#!/usr/bin/env python3
"""
Push App Store Connect version localization metadata from store/listing/ + drafts.

Requires env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_P8_PATH (or store/asc.env.local).

Usage:
  python3 scripts/asc-push-app-store-version-metadata.py \\
    --version 1.0.9 \\
    --from-version 1.0 \\
    --whats-new en-GB=store/drafts/whats-new-1.0.9-en.txt

  # dry-run
  python3 scripts/asc-push-app-store-version-metadata.py --version 1.0.9 --from-version 1.0 --dry-run
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
from pathlib import Path
from typing import Any

API = "https://api.appstoreconnect.apple.com"
DEFAULT_BUNDLE = "ru.recipescaler.RecipeScaler"
DEFAULT_OUT = "store"
ASC_ENV_FILE = Path(__file__).resolve().parent.parent / "store" / "asc.env.local"

VERSION_COPY_FIELDS = (
    "description",
    "keywords",
    "marketingUrl",
    "promotionalText",
    "supportUrl",
)


def load_asc_env() -> None:
    if not ASC_ENV_FILE.is_file():
        return
    for raw in ASC_ENV_FILE.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, val = line.partition("=")
        key = key.strip()
        val = val.strip()
        if key and key not in os.environ:
            os.environ[key] = val


def die(msg: str, code: int = 1) -> None:
    print(f"error: {msg}", file=sys.stderr)
    raise SystemExit(code)


def asc_jwt() -> str:
    for var in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_P8_PATH"):
        if not os.environ.get(var):
            die(f"{var} is required (see store/asc.env.example)")
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

    def request(
        self,
        method: str,
        path: str,
        *,
        params: dict[str, str] | None = None,
        body: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        url = API + path
        if params:
            url += "?" + urllib.parse.urlencode(params, safe=",")
        data = None
        headers = {
            "Authorization": f"Bearer {self.token}",
            "Accept": "application/json",
        }
        if body is not None:
            data = json.dumps(body).encode("utf-8")
            headers["Content-Type"] = "application/json"
        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                raw = resp.read().decode("utf-8")
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as exc:
            body_text = exc.read().decode("utf-8", errors="replace")[:2000]
            die(f"HTTP {exc.code} {method} {path}: {body_text}")

    def get_json(self, path: str, params: dict[str, str] | None = None) -> dict[str, Any]:
        return self.request("GET", path, params=params)

    def patch_json(self, path: str, body: dict[str, Any]) -> dict[str, Any]:
        return self.request("PATCH", path, body=body)

    def post_json(self, path: str, body: dict[str, Any]) -> dict[str, Any]:
        return self.request("POST", path, body=body)


def version_map(client: AscClient, app_id: str) -> dict[str, dict[str, Any]]:
    versions = client.get_json(
        f"/v1/apps/{app_id}/appStoreVersions",
        {"limit": "200", "fields[appStoreVersions]": "versionString,appStoreState"},
    )
    out: dict[str, dict[str, Any]] = {}
    for ver in versions.get("data") or []:
        version_string = (ver.get("attributes") or {}).get("versionString")
        if version_string:
            out[version_string] = ver
    return out


def localization_map(client: AscClient, version_id: str) -> dict[str, dict[str, Any]]:
    locs = client.get_json(
        f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations",
        {"limit": "200"},
    )
    out: dict[str, dict[str, Any]] = {}
    for loc in locs.get("data") or []:
        locale = (loc.get("attributes") or {}).get("locale")
        if locale:
            out[locale] = loc
    return out


def parse_whats_new_specs(specs: list[str]) -> dict[str, Path]:
    out: dict[str, Path] = {}
    for spec in specs:
        if "=" not in spec:
            die(f"invalid --whats-new value {spec!r}; use locale=path")
        locale, _, path = spec.partition("=")
        locale = locale.strip()
        path = path.strip()
        if not locale or not path:
            die(f"invalid --whats-new value {spec!r}")
        out[locale] = Path(path)
    return out


def merge_attrs(
    source_attrs: dict[str, Any],
    target_attrs: dict[str, Any],
    whats_new: str | None,
) -> dict[str, Any]:
    merged: dict[str, Any] = {}
    for field in VERSION_COPY_FIELDS:
        target_val = target_attrs.get(field)
        source_val = source_attrs.get(field)
        if target_val in (None, "") and source_val not in (None, ""):
            merged[field] = source_val
    if whats_new is not None:
        merged["whatsNew"] = whats_new
    return merged


def main() -> None:
    parser = argparse.ArgumentParser(description="Push ASC version localization metadata")
    parser.add_argument("--bundle-id", default=DEFAULT_BUNDLE)
    parser.add_argument("--out", type=Path, default=Path(DEFAULT_OUT))
    parser.add_argument("--version", required=True, help="target version, e.g. 1.0.9")
    parser.add_argument("--from-version", required=True, help="source version to copy empty fields from")
    parser.add_argument(
        "--whats-new",
        action="append",
        default=[],
        metavar="LOCALE=PATH",
        help="What's New text file per locale (repeatable)",
    )
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    load_asc_env()
    client = AscClient(asc_jwt())
    whats_new_by_locale = parse_whats_new_specs(args.whats_new)

    apps = client.get_json(
        "/v1/apps",
        {"filter[bundleId]": args.bundle_id, "limit": "1", "fields[apps]": "name,bundleId"},
    )
    app = (apps.get("data") or [None])[0]
    if not app:
        die(f"app not found for bundle id {args.bundle_id}")

    versions = version_map(client, app["id"])
    source_ver = versions.get(args.from_version)
    target_ver = versions.get(args.version)
    if not source_ver:
        die(f"source version {args.from_version!r} not found in ASC")
    if not target_ver:
        die(f"target version {args.version!r} not found in ASC")

    source_locs = localization_map(client, source_ver["id"])
    target_locs = localization_map(client, target_ver["id"])
    if not source_locs:
        die(f"no localizations on source version {args.from_version}")
    if not target_locs:
        die(f"no localizations on target version {args.version}")

    locales = sorted(set(source_locs) | set(target_locs) | set(whats_new_by_locale))
    updated = 0
    for locale in locales:
        target_loc = target_locs.get(locale)
        source_loc = source_locs.get(locale)
        whats_new_path = whats_new_by_locale.get(locale)
        whats_new_text = None
        if whats_new_path is not None:
            if not whats_new_path.is_file():
                die(f"missing what's new file: {whats_new_path}")
            whats_new_text = whats_new_path.read_text(encoding="utf-8").strip()

        if target_loc is None:
            if source_loc is None:
                print(f"skip {locale}: no source localization to create from")
                continue
            source_attrs = source_loc.get("attributes") or {}
            attrs = {field: source_attrs.get(field) for field in VERSION_COPY_FIELDS}
            attrs = {k: v for k, v in attrs.items() if v not in (None, "")}
            if whats_new_text is not None:
                attrs["whatsNew"] = whats_new_text
            if not attrs:
                print(f"skip {locale}: nothing to create")
                continue
            print(f"create {locale}: {sorted(attrs)}")
            if args.dry_run:
                continue
            client.post_json(
                "/v1/appStoreVersionLocalizations",
                {
                    "data": {
                        "type": "appStoreVersionLocalizations",
                        "attributes": {"locale": locale, **attrs},
                        "relationships": {
                            "appStoreVersion": {
                                "data": {"type": "appStoreVersions", "id": target_ver["id"]}
                            }
                        },
                    }
                },
            )
            updated += 1
            continue

        source_attrs = (source_loc or {}).get("attributes") or {}
        target_attrs = target_loc.get("attributes") or {}
        patch_attrs = merge_attrs(source_attrs, target_attrs, whats_new_text)
        if not patch_attrs:
            print(f"skip {locale}: already up to date")
            continue
        print(f"patch {locale}: {sorted(patch_attrs)}")
        if args.dry_run:
            continue
        client.patch_json(
            f"/v1/appStoreVersionLocalizations/{target_loc['id']}",
            {
                "data": {
                    "type": "appStoreVersionLocalizations",
                    "id": target_loc["id"],
                    "attributes": patch_attrs,
                }
            },
        )
        updated += 1

    if not args.dry_run and updated:
        print(f"updated {updated} localization(s); re-run asc-pull-app-store-metadata.py to refresh store/")


if __name__ == "__main__":
    main()
