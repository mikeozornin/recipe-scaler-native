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

  # new texts from a drafts folder: name and subtitle (app info) plus description,
  # keywords, promotional text and URLs (version), one <locale>.json per locale
  python3 scripts/asc-push-app-store-version-metadata.py \\
    --version 1.0.15 --listing store/listing-drafts/1.0.15 --dry-run

  # length and keyword checks only, without ASC
  python3 scripts/asc-push-app-store-version-metadata.py --listing store/listing-drafts/1.0.15 --check
"""

from __future__ import annotations

import argparse
import json
import os
import re
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
APP_INFO_FIELDS = ("name", "subtitle", "privacyPolicyUrl")
LISTING_LIMITS = {
    "name": 30,
    "subtitle": 30,
    "keywords": 100,
    "promotionalText": 170,
    "description": 4000,
}
# Name and subtitle can only change on an appInfo in one of these states,
# that is after the new version is created in ASC.
EDITABLE_APP_INFO_STATES = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED"}


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


def load_listing(listing_dir: Path) -> dict[str, dict[str, Any]]:
    if not listing_dir.is_dir():
        die(f"listing dir not found: {listing_dir}")
    out: dict[str, dict[str, Any]] = {}
    for path in sorted(listing_dir.glob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        if data.get("locale") != path.stem:
            die(f"{path}: locale {data.get('locale')!r} does not match the file name")
        out[path.stem] = data
    if not out:
        die(f"no <locale>.json files in {listing_dir}")
    return out


def words(text: str) -> set[str]:
    return {w for w in re.split(r"\W+", text.casefold().replace("ё", "е")) if w}


def lint_listing(listing: dict[str, dict[str, Any]]) -> list[str]:
    """Limits from ASC plus keyword waste: App Store already indexes every word
    of the name and subtitle, so repeating them in keywords spends characters."""
    errors: list[str] = []
    for locale, data in listing.items():
        for field, limit in LISTING_LIMITS.items():
            length = len(data.get(field) or "")
            if length > limit:
                errors.append(f"{locale}: {field} is {length} chars, limit {limit}")
        terms = (data.get("keywords") or "").split(",")
        if any(not term or term != term.strip() for term in terms):
            errors.append(f"{locale}: keywords need commas without spaces and no empty terms")
        title_words = words(f"{data.get('name') or ''} {data.get('subtitle') or ''}")
        seen: set[str] = set()
        for word in (w for term in terms for w in sorted(words(term))):
            if word in seen:
                errors.append(f"{locale}: keyword word {word!r} repeats")
            if word in title_words:
                errors.append(f"{locale}: keyword word {word!r} is already in the name or subtitle")
            seen.add(word)
    return errors


def app_info_localization_map(client: AscClient, app_info_id: str) -> dict[str, dict[str, Any]]:
    locs = client.get_json(f"/v1/appInfos/{app_info_id}/appInfoLocalizations", {"limit": "200"})
    out: dict[str, dict[str, Any]] = {}
    for loc in locs.get("data") or []:
        locale = (loc.get("attributes") or {}).get("locale")
        if locale:
            out[locale] = loc
    return out


def changed_fields(
    wanted: dict[str, Any], current: dict[str, Any], fields: tuple[str, ...]
) -> dict[str, Any]:
    return {f: wanted[f] for f in fields if f in wanted and wanted[f] != current.get(f)}


def upsert_localization(
    client: AscClient,
    kind: str,
    parent: tuple[str, str, str],
    existing: dict[str, Any] | None,
    locale: str,
    wanted: dict[str, Any],
    fields: tuple[str, ...],
    dry_run: bool,
) -> bool:
    relationship, parent_type, parent_id = parent
    if existing is None:
        attrs = {f: wanted[f] for f in fields if wanted.get(f) not in (None, "")}
        print(f"create {kind} {locale}: {sorted(attrs)}")
        if not dry_run:
            client.post_json(
                f"/v1/{kind}",
                {
                    "data": {
                        "type": kind,
                        "attributes": {"locale": locale, **attrs},
                        "relationships": {
                            relationship: {"data": {"type": parent_type, "id": parent_id}}
                        },
                    }
                },
            )
        return True
    attrs = changed_fields(wanted, existing.get("attributes") or {}, fields)
    if not attrs:
        print(f"skip {kind} {locale}: already up to date")
        return False
    print(f"patch {kind} {locale}: {sorted(attrs)}")
    if not dry_run:
        client.patch_json(
            f"/v1/{kind}/{existing['id']}",
            {"data": {"type": kind, "id": existing["id"], "attributes": attrs}},
        )
    return True


def push_listing(
    client: AscClient,
    app_id: str,
    target_ver: dict[str, Any],
    listing: dict[str, dict[str, Any]],
    whats_new: dict[str, str],
    dry_run: bool,
) -> int:
    infos = client.get_json(f"/v1/apps/{app_id}/appInfos", {"limit": "10"}).get("data") or []
    editable = next(
        (i for i in infos if (i.get("attributes") or {}).get("state") in EDITABLE_APP_INFO_STATES),
        None,
    )
    info = editable or (infos[0] if infos else None)
    if info is None:
        die("app has no appInfo")
    info_locs = app_info_localization_map(client, info["id"])
    version_locs = localization_map(client, target_ver["id"])
    version_string = (target_ver.get("attributes") or {}).get("versionString")
    updated = 0
    for locale, data in listing.items():
        wanted = dict(data)
        if locale in whats_new:
            wanted["whatsNew"] = whats_new[locale]
        current_info = info_locs.get(locale)
        if editable is None:
            if current_info is None or changed_fields(
                wanted, current_info.get("attributes") or {}, APP_INFO_FIELDS
            ):
                die(
                    f"{locale}: name or subtitle differ from ASC, but no appInfo is editable; "
                    f"create version {version_string} in ASC first"
                )
        else:
            updated += upsert_localization(
                client,
                "appInfoLocalizations",
                ("appInfo", "appInfos", info["id"]),
                current_info,
                locale,
                wanted,
                APP_INFO_FIELDS,
                dry_run,
            )
        version_fields = VERSION_COPY_FIELDS + (("whatsNew",) if "whatsNew" in wanted else ())
        updated += upsert_localization(
            client,
            "appStoreVersionLocalizations",
            ("appStoreVersion", "appStoreVersions", target_ver["id"]),
            version_locs.get(locale),
            locale,
            wanted,
            version_fields,
            dry_run,
        )
    return updated


def main() -> None:
    parser = argparse.ArgumentParser(description="Push ASC version localization metadata")
    parser.add_argument("--bundle-id", default=DEFAULT_BUNDLE)
    parser.add_argument("--out", type=Path, default=Path(DEFAULT_OUT))
    parser.add_argument("--version", help="target version, e.g. 1.0.9")
    parser.add_argument(
        "--from-version",
        help="source version to copy empty fields from (not used with --listing)",
    )
    parser.add_argument(
        "--listing",
        type=Path,
        metavar="DIR",
        help="push name, subtitle and version texts from DIR/<locale>.json",
    )
    parser.add_argument("--check", action="store_true", help="with --listing: only lint, no ASC")
    parser.add_argument(
        "--whats-new",
        action="append",
        default=[],
        metavar="LOCALE=PATH",
        help="What's New text file per locale (repeatable)",
    )
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    listing = None
    if args.listing:
        listing = load_listing(args.listing)
        errors = lint_listing(listing)
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        if errors:
            raise SystemExit(1)
        if args.check:
            print(f"ok: {', '.join(listing)}")
            return
    elif args.check:
        die("--check needs --listing")
    if not args.version:
        die("--version is required")
    if listing is None and not args.from_version:
        die("--from-version is required without --listing")

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
    target_ver = versions.get(args.version)
    if listing is not None:
        if not target_ver:
            die(f"target version {args.version!r} not found in ASC")
        whats_new = {}
        for locale, path in whats_new_by_locale.items():
            if not path.is_file():
                die(f"missing what's new file: {path}")
            whats_new[locale] = path.read_text(encoding="utf-8").strip()
        updated = push_listing(client, app["id"], target_ver, listing, whats_new, args.dry_run)
        if not args.dry_run and updated:
            print(f"updated {updated} localization(s); re-run asc-pull-app-store-metadata.py to refresh store/")
        return

    source_ver = versions.get(args.from_version)
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
