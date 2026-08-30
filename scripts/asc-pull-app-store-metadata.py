#!/usr/bin/env python3
"""
Pull App Store Connect listing metadata into store/ (read-only).

Requires env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_P8_PATH
(or store/asc.env.local — see asc.env.example).

Usage:
  python3 scripts/asc-pull-app-store-metadata.py [--bundle-id ru.recipescaler.RecipeScaler] [--out store]
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

API = "https://api.appstoreconnect.apple.com"
DEFAULT_BUNDLE = "ru.recipescaler.RecipeScaler"
DEFAULT_OUT = "store"
ASC_ENV_FILE = Path(__file__).resolve().parent.parent / "store" / "asc.env.local"


def load_asc_env() -> None:
    """Load store/asc.env.local without overriding existing env vars."""
    if not ASC_ENV_FILE.is_file():
        return
    for raw in ASC_ENV_FILE.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, _, val = line.partition("=")
        key = key.strip()
        val = val.strip()
        if key and key not in os.environ:
            os.environ[key] = val

APP_INFO_FIELDS = (
    "locale",
    "name",
    "subtitle",
    "privacyPolicyUrl",
    "privacyChoicesUrl",
    "privacyPolicyText",
)

VERSION_LOC_FIELDS = (
    "locale",
    "description",
    "keywords",
    "marketingUrl",
    "promotionalText",
    "supportUrl",
    "whatsNew",
)


def die(msg: str, code: int = 1) -> None:
    print(f"error: {msg}", file=sys.stderr)
    raise SystemExit(code)


def asc_jwt() -> str:
    for var in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_P8_PATH"):
        if not os.environ.get(var):
            die(f"{var} is required (see scripts/asc-iap-inventory.sh)")
    ruby = r"""
    key_id=ENV.fetch("ASC_KEY_ID"); issuer_id=ENV.fetch("ASC_ISSUER_ID"); p8_path=ENV.fetch("ASC_P8_PATH")
    to_json=->(h){"{"+h.map{|k,v|"\"#{k}\":#{v.is_a?(String)?"\"#{v}\"":v}"}.join(",")+"}"}
    ec_key=OpenSSL::PKey::EC.new(File.read(p8_path)); now=Time.now.to_i
    header=to_json.call({"alg"=>"ES256","kid"=>key_id,"typ"=>"JWT"})
    payload=to_json.call({"iss"=>issuer_id,"iat"=>now,"exp"=>now+1200,"aud"=>"appstoreconnect-v1"})
    b64url=->(s){Base64.urlsafe_encode64(s,padding:false)}
    signing_input="#{b64url.call(header)}.#{b64url.call(payload)}"
    der_sig=ec_key.sign(OpenSSL::Digest::SHA256.new,signing_input)
    asn=OpenSSL::ASN1.decode(der_sig); r=asn.value[0].value.to_s(2).rjust(32,"\x00"); s=asn.value[1].value.to_s(2).rjust(32,"\x00")
    puts "#{signing_input}.#{b64url.call(r+s)}"
    """
    proc = subprocess.run(
        ["ruby", "-rbase64", "-ropenssl", "-e", ruby],
        check=True,
        capture_output=True,
        text=True,
        env=os.environ.copy(),
    )
    token = proc.stdout.strip()
    if not token:
        die("failed to generate ASC JWT")
    return token


class AscClient:
    def __init__(self, token: str) -> None:
        self.token = token

    def get_json(self, path: str, params: dict[str, str] | None = None) -> dict[str, Any]:
        url = API + path
        if params:
            url += "?" + urllib.parse.urlencode(params, safe=",")
        req = urllib.request.Request(
            url,
            headers={"Authorization": f"Bearer {self.token}", "Accept": "application/json"},
        )
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                return json.load(resp)
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")[:2000]
            die(f"HTTP {exc.code} GET {path}: {body}")


def pick_attrs(data: dict[str, Any], fields: tuple[str, ...]) -> dict[str, Any]:
    attrs = data.get("attributes") or {}
    return {k: attrs.get(k) for k in fields}


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description="Pull ASC listing metadata into store/")
    parser.add_argument("--bundle-id", default=DEFAULT_BUNDLE)
    parser.add_argument("--out", type=Path, default=Path(DEFAULT_OUT))
    args = parser.parse_args()

    load_asc_env()
    client = AscClient(asc_jwt())
    out_root: Path = args.out

    apps = client.get_json(
        "/v1/apps",
        {"filter[bundleId]": args.bundle_id, "limit": "1", "fields[apps]": "name,bundleId,primaryLocale,sku"},
    )
    app = (apps.get("data") or [None])[0]
    if not app:
        die(f"app not found for bundle id {args.bundle_id}")

    app_id = app["id"]
    app_attrs = app.get("attributes") or {}

    app_detail = client.get_json(
        f"/v1/apps/{app_id}",
        {"include": "appInfos", "fields[apps]": "name,bundleId,primaryLocale,sku"},
    )
    included = app_detail.get("included") or []
    app_infos = [x for x in included if x.get("type") == "appInfos"]
    if not app_infos:
        die("no appInfos on app")

    app_info_id = app_infos[0]["id"]

    app_info_locs = client.get_json(
        f"/v1/appInfos/{app_info_id}/appInfoLocalizations",
        {"limit": "200"},
    )

    versions = client.get_json(
        f"/v1/apps/{app_id}/appStoreVersions",
        {
            "limit": "200",
            "fields[appStoreVersions]": "versionString,appStoreState,platform,createdDate",
        },
    )

    pulled_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    manifest = {
        "source": "app-store-connect-api",
        "pulledAt": pulled_at,
        "appId": app_id,
        "bundleId": app_attrs.get("bundleId"),
        "name": app_attrs.get("name"),
        "sku": app_attrs.get("sku"),
        "primaryLocale": app_attrs.get("primaryLocale"),
        "masterLocale": app_attrs.get("primaryLocale"),
        "appInfoId": app_info_id,
    }
    write_json(out_root / "manifest.json", manifest)

    listing_root = out_root / "listing"
    for loc in app_info_locs.get("data") or []:
        locale = (loc.get("attributes") or {}).get("locale")
        if not locale:
            continue
        payload = pick_attrs(loc, APP_INFO_FIELDS)
        write_json(listing_root / "app-info" / f"{locale}.json", payload)

    versions_root = listing_root / "versions"
    version_summaries: list[dict[str, Any]] = []
    for ver in versions.get("data") or []:
        ver_id = ver["id"]
        ver_attrs = ver.get("attributes") or {}
        version_string = ver_attrs.get("versionString") or "unknown"
        version_summaries.append(
            {
                "id": ver_id,
                "version": version_string,
                "state": ver_attrs.get("appStoreState"),
                "platform": ver_attrs.get("platform"),
            }
        )

        locs = client.get_json(
            f"/v1/appStoreVersions/{ver_id}/appStoreVersionLocalizations",
            {"limit": "200"},
        )
        for loc in locs.get("data") or []:
            locale = (loc.get("attributes") or {}).get("locale")
            if not locale:
                continue
            payload = pick_attrs(loc, VERSION_LOC_FIELDS)
            write_json(versions_root / version_string / f"{locale}.json", payload)

    write_json(out_root / "versions-index.json", version_summaries)

    locales = sorted({p.stem for p in (listing_root / "app-info").glob("*.json")})
    print(f"pulled app-store metadata for {args.bundle_id}")
    print(f"  out: {out_root.resolve()}")
    print(f"  primary locale: {app_attrs.get('primaryLocale')}")
    print(f"  app-info locales: {', '.join(locales) or '(none)'}")
    print(f"  versions: {', '.join(v['version'] for v in version_summaries) or '(none)'}")


if __name__ == "__main__":
    main()
