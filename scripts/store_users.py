#!/usr/bin/env python3
"""Dedicated store/test accounts: one per screenshot locale + App Review copy of EN.

Usage:
  python3 scripts/store_users.py provision          # register once, write users.yaml
  python3 scripts/store_users.py login ru|en|app-store-review
  python3 scripts/store_users.py prepare-discover ru|en [--token BEARER]
  python3 scripts/store_users.py show
"""

from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
USERS_PATH = ROOT / "store" / "fixtures" / "users.yaml"
DEFAULT_API = "https://recipe-scaler.ru"

USER_SPECS = (
    {
        "key": "ru",
        "role": "screenshot",
        "locale": "ru",
        "label": "Store screenshots RU",
        "deviceId": "store-screenshot-ru",
        "archive": "store/fixtures/recipes-ru.zip",
        "notes": "Persistent screenshot library (Russian content).",
    },
    {
        "key": "en",
        "role": "screenshot",
        "locale": "en",
        "label": "Store screenshots EN",
        "deviceId": "store-screenshot-en",
        "archive": "store/fixtures/recipes-en.zip",
        "notes": "Persistent screenshot library (English content).",
    },
    {
        "key": "app-store-review",
        "role": "app-store-review",
        "locale": "en",
        "label": "App Store Review (EN library copy)",
        "deviceId": "store-app-review",
        "archive": "store/fixtures/recipes-en.zip",
        "notes": "Give this seed to App Review in ASC. Same EN fixture as screenshots, separate account.",
    },
)


def api_base() -> str:
    return (__import__("os").environ.get("E2E_API_BASE") or DEFAULT_API).rstrip("/")


def request_json(method: str, path: str, body: dict | None, timeout: int = 25, *, token: str | None = None) -> dict:
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        api_base() + path,
        data=data,
        headers=headers,
        method=method,
    )
    last_error: Exception | None = None
    for attempt in range(1, 8):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return json.load(resp)
        except urllib.error.HTTPError as exc:
            if exc.code == 429 and attempt < 7:
                time.sleep(min(attempt * 5, 30))
                last_error = exc
                continue
            raise SystemExit(f"{method} {path} failed: HTTP {exc.code}: {exc.reason}") from exc
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
            last_error = exc
            time.sleep(min(attempt * 2, 15))
    raise SystemExit(f"{method} {path} failed: {last_error}")


def parse_users_yaml(text: str) -> dict:
    """Minimal YAML subset used by this file (no external PyYAML dependency)."""
    users: dict[str, dict[str, str]] = {}
    current: str | None = None
    api = DEFAULT_API
    for raw in text.splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        if raw.startswith("apiBase:"):
            api = raw.split(":", 1)[1].strip().strip('"').strip("'")
            continue
        if raw.startswith("users:"):
            continue
        if raw.startswith("  ") and not raw.startswith("    ") and raw.rstrip().endswith(":"):
            current = raw.strip().rstrip(":")
            users[current] = {}
            continue
        if current and raw.startswith("    "):
            key, _, value = raw.strip().partition(":")
            users[current][key.strip()] = value.strip().strip('"').strip("'")
    return {"apiBase": api, "users": users}


def dump_users_yaml(payload: dict) -> str:
    lines = [
        "# Dedicated Recipe Scaler accounts for screenshots and App Review.",
        "# Not personal identities. app-store-review seed is given to Apple.",
        "# Recreate (new accounts): python3 scripts/store_users.py provision --force",
        f"apiBase: {payload.get('apiBase') or DEFAULT_API}",
        "users:",
    ]
    for spec in USER_SPECS:
        user = payload["users"][spec["key"]]
        lines.append(f"  {spec['key']}:")
        for field in (
            "role",
            "locale",
            "label",
            "userId",
            "seedPhrase",
            "deviceId",
            "username",
            "archive",
            "createdAt",
            "notes",
        ):
            value = user.get(field, spec.get(field, ""))
            if value == "":
                continue
            if field == "seedPhrase" or " " in str(value) or ":" in str(value):
                lines.append(f'    {field}: "{value}"')
            else:
                lines.append(f"    {field}: {value}")
    lines.append("")
    return "\n".join(lines)


def load_users() -> dict:
    if not USERS_PATH.is_file():
        raise SystemExit(f"missing {USERS_PATH}; run: python3 scripts/store_users.py provision")
    return parse_users_yaml(USERS_PATH.read_text())


def register_auto(device_id: str, language: str) -> tuple[str, str, str]:
    payload = request_json(
        "POST",
        "/api/auth/register-auto",
        {
            "device_id": device_id,
            "platform": "ios",
            "user_agent": "store-user-provision",
            "language": language,
        },
    )
    data = payload["data"]
    return data["user"]["id"], data["device_token"], data["seed_phrase"]


def login_with_seed(seed_phrase: str, device_id: str, language: str) -> tuple[str, str]:
    payload = request_json(
        "POST",
        "/api/auth/login-with-seed",
        {
            "seed_phrase": seed_phrase,
            "device_id": device_id,
            "platform": "ios",
            "user_agent": "store-screenshot-capture",
            "language": language,
        },
    )
    data = payload["data"]
    return data["user"]["id"], data["device_token"]


def cmd_provision(force: bool) -> int:
    existing = parse_users_yaml(USERS_PATH.read_text()) if USERS_PATH.is_file() else {"users": {}}
    users: dict[str, dict[str, str]] = {}
    for spec in USER_SPECS:
        key = spec["key"]
        prev = existing.get("users", {}).get(key, {})
        if prev.get("seedPhrase") and prev.get("userId") and not force:
            print(f"keep {key}: {prev['userId']}", flush=True)
            users[key] = {**spec, **prev}
            continue
        print(f"register {key}…", flush=True)
        user_id, _token, seed = register_auto(spec["deviceId"], spec["locale"])
        users[key] = {
            **spec,
            "userId": user_id,
            "seedPhrase": seed,
            "createdAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        }
        print(f"  userId={user_id}", flush=True)
    payload = {"apiBase": api_base(), "users": users}
    USERS_PATH.parent.mkdir(parents=True, exist_ok=True)
    USERS_PATH.write_text(dump_users_yaml(payload))
    print(f"wrote {USERS_PATH}", flush=True)
    return 0


def cmd_login(key: str) -> int:
    payload = load_users()
    user = payload["users"].get(key)
    if not user:
        raise SystemExit(f"unknown user key {key!r}; expected ru|en|app-store-review")
    if not user.get("seedPhrase") or not user.get("userId"):
        raise SystemExit(f"{key} has no seed yet; run: python3 scripts/store_users.py provision")
    user_id, token = login_with_seed(user["seedPhrase"], user["deviceId"], user.get("locale") or "en")
    print(user_id)
    print(token)
    print(user["seedPhrase"])
    return 0


def _ensure_store_username(user: dict[str, str], token: str) -> str | None:
    desired = (user.get("username") or "").strip().lower()
    if not desired:
        return None
    settings = request_json("GET", "/api/users/sharing-settings", None, token=token)
    current = (settings.get("data") or {}).get("username")
    if current and current.lower() == desired:
        return current
    request_json("PUT", "/api/users/username", {"username": desired}, token=token)
    return desired


def cmd_prepare_discover(key: str, token: str | None = None) -> int:
    """Enable public profile for the store user and print their @username for discover shots."""
    if key not in {"ru", "en"}:
        raise SystemExit("prepare-discover supports ru|en screenshot users only")
    payload = load_users()
    user = payload["users"].get(key)
    if not user:
        raise SystemExit(f"unknown user key {key!r}")
    if not user.get("seedPhrase") or not user.get("deviceId"):
        raise SystemExit(f"{key} has no seed yet; run: python3 scripts/store_users.py provision")
    # Reusing the capture login token is mandatory: login-with-seed rotates the
    # device hash, and a second login here would invalidate the Bearer already
    # handed to the simulator (empty library / socket unauthorized).
    resolved_token = token
    if not resolved_token:
        _user_id, resolved_token = login_with_seed(
            user["seedPhrase"], user["deviceId"], user.get("locale") or "en"
        )
    _ensure_store_username(user, resolved_token)
    request_json(
        "PATCH",
        "/api/users/sharing-settings",
        {"publicProfileEnabled": True, "shareMode": "all"},
        token=resolved_token,
    )
    settings = request_json("GET", "/api/users/sharing-settings", None, token=resolved_token)
    data = settings.get("data") or {}
    username = (data.get("username") or user.get("username") or "").strip().lower()
    if not username:
        raise SystemExit(f"{key}: public profile enabled but username is missing in users.yaml and API")
    if data.get("publicProfileEnabled") is not True:
        raise SystemExit(f"{key}: failed to enable public profile (API returned disabled)")
    print(username)
    return 0


def cmd_show() -> int:
    payload = load_users()
    for spec in USER_SPECS:
        user = payload["users"].get(spec["key"], {})
        print(f"{spec['key']}:")
        print(f"  role:        {user.get('role', spec['role'])}")
        print(f"  locale:      {user.get('locale', spec['locale'])}")
        print(f"  userId:      {user.get('userId', '(missing)')}")
        print(f"  seedPhrase:  {user.get('seedPhrase', '(missing)')}")
        print(f"  notes:       {user.get('notes', spec['notes'])}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="cmd", required=True)
    p_prov = sub.add_parser("provision")
    p_prov.add_argument("--force", action="store_true")
    p_login = sub.add_parser("login")
    p_login.add_argument("key", choices=[spec["key"] for spec in USER_SPECS])
    p_prep = sub.add_parser("prepare-discover")
    p_prep.add_argument("key", choices=["ru", "en"])
    p_prep.add_argument(
        "--token",
        default=None,
        help="Reuse an existing Bearer instead of login-with-seed (avoids rotating capture tokens)",
    )
    sub.add_parser("show")
    args = parser.parse_args()
    if args.cmd == "provision":
        return cmd_provision(force=args.force)
    if args.cmd == "login":
        return cmd_login(args.key)
    if args.cmd == "prepare-discover":
        return cmd_prepare_discover(args.key, token=args.token)
    if args.cmd == "show":
        return cmd_show()
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
