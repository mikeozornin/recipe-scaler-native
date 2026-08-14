#!/usr/bin/env bash
#
# Read-only inventory of App Store Connect in-app purchases and subscriptions.
#
# Requires: ASC_KEY_ID, ASC_ISSUER_ID, ASC_P8_PATH (or defaults below).
# Only GET requests — no mutations. See docs/AGENT-WORKFLOW.md for verify
# script contract; this is a diagnostics helper, not a verify script.
#
set -euo pipefail

ASC_KEY_ID="${ASC_KEY_ID:?ASC_KEY_ID (10 chars) required}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:?ASC_ISSUER_ID (uuid) required}"
ASC_P8_PATH="${ASC_P8_PATH:-/Users/mike/work/git-repos/projects/recipe-scaler/recipe-scaler-apple-api-connect-app-manager.p8}"
export ASC_KEY_ID ASC_ISSUER_ID ASC_P8_PATH

API="https://api.appstoreconnect.apple.com"

# --- JWT (ES256), pure ruby + openssl ---
JWT="$(
  ruby -rbase64 -ropenssl -e '
    key_id     = ENV.fetch("ASC_KEY_ID")
    issuer_id  = ENV.fetch("ASC_ISSUER_ID")
    p8_path    = ENV.fetch("ASC_P8_PATH")

    to_json = ->(h) {
      "{" + h.map { |k, v| "\"#{k}\":#{v.is_a?(String) ? "\"#{v}\"" : v}" }.join(",") + "}"
    }

    ec_key = OpenSSL::PKey::EC.new(File.read(p8_path))
    now    = Time.now.to_i

    header  = to_json.call({ "alg" => "ES256", "kid" => key_id, "typ" => "JWT" })
    payload = to_json.call({ "iss" => issuer_id, "iat" => now, "exp" => now + 1200, "aud" => "appstoreconnect-v1" })

    b64url = ->(s) { Base64.urlsafe_encode64(s, padding: false) }
    signing_input = "#{b64url.call(header)}.#{b64url.call(payload)}"

    der_sig = ec_key.sign(OpenSSL::Digest::SHA256.new, signing_input)
    # DER -> raw r||s (64 bytes)
    asn = OpenSSL::ASN1.decode(der_sig)
    r = asn.value[0].value.to_s(2).rjust(32, "\x00")
    s = asn.value[1].value.to_s(2).rjust(32, "\x00")
    puts "#{signing_input}.#{b64url.call(r + s)}"
  ')" 
export JWT

api_get() {
  local path="$1" tmp status
  tmp="$(mktemp)"
  status="$(curl -sS -o "$tmp" -w "%{http_code}" -H "Authorization: Bearer $JWT" "$API$path")" || status="curl_error"
  if [[ "$status" != 2* ]]; then
    echo "HTTP $status from $path" >> /dev/stderr
    head -c 2000 "$tmp" >> /dev/stderr
    echo >> /dev/stderr
  fi
  cat "$tmp"; rm -f "$tmp"
}

echo "== Apps in account =="
APPS_JSON="$(api_get "/v1/apps?limit=200&fields%5Bapps%5D=name,bundleId")"
jq -r '.data[] | "\(.id)\t\(.attributes.bundleId)\t\(.attributes.name)"' <<<"$APPS_JSON" | column -t -s $'\t'

echo
echo "== Subscription groups / subscriptions =="
# Subscription groups: need app id — listed per app below after we know ids.
echo "(fetched per-app below)"

echo
echo "== Per-app IAP + subscriptions =="
while IFS=$'\t' read -r app_id bundle app_name; do
  [ -z "$app_id" ] && continue
  echo "--- $app_name ($bundle, id=$app_id) ---"

  echo "  [inAppPurchases v2]"
  api_get "/v2/inAppPurchases?filter%5Bapp%5D=$app_id&limit=200" \
    | jq -r '.data[]? | "    \(.id)\t\(.attributes.state // "?")\t\(.type)\t\(.attributes.productId // .attributes.name // "?")"' \
    | column -t -s $'\t' || echo "    (none or not accessible)"

  echo "  [subscriptionGroups]"
  api_get "/v1/subscriptionGroups?filter%5Bapp%5D=$app_id&limit=100&fields%5BsubscriptionGroups%5D=referenceName" \
    | jq -r '.data[]? | "    group \(.id)\t\(.attributes.referenceName)"' \
    | column -t -s $'\t' || echo "    (none)"

  for group_id in $(api_get "/v1/subscriptionGroups?filter%5Bapp%5D=$app_id&limit=100" | jq -r '.data[]?.id'); do
    echo "  [subscriptions in group $group_id]"
    api_get "/v1/subscriptionGroups/$group_id/subscriptions?limit=100&fields%5Bsubscriptions%5D=name,productId,state" \
      | jq -r '.data[]? | "    \(.id)\t\(.attributes.state // "?")\t\(.attributes.productId // "?")\t\(.attributes.name // "?")"' \
      | column -t -s $'\t' || echo "    (none)"
  done
done < <(jq -r '.data[] | "\(.id)\t\(.attributes.bundleId)\t\(.attributes.name)"' <<<"$APPS_JSON")

echo
echo "== Current app versions (review state) =="
while IFS=$'\t' read -r app_id bundle app_name; do
  [ -z "$app_id" ] && continue
  echo "--- $app_name (id=$app_id) ---"
  api_get "/v1/apps/$app_id/appStoreVersions?filter%5BappStoreState%5D=READY_FOR_SALE,PROCESSING_FOR_APP_STORE,DEVELOPER_REMOVED_FROM_SALE,PENDING_DEVELOPER_RELEASE&limit=10&fields%5BappStoreVersions%5D=versionString,appStoreState" \
    | jq -r '.data[]? | "    \(.attributes.versionString)\t\(.attributes.appStoreState)"' \
    | column -t -s $'\t' || true
  echo "  [in-review / waiting]"
  api_get "/v1/apps/$app_id/appStoreVersions?filter%5BappStoreState%5D=WAITING_FOR_REVIEW,IN_REVIEW,PENDING_APPLE_RELEASE&limit=10&fields%5BappStoreVersions%5D=versionString,appStoreState" \
    | jq -r '.data[]? | "    \(.attributes.versionString)\t\(.attributes.appStoreState)"' \
    | column -t -s $'\t' || true
done < <(jq -r '.data[] | "\(.id)\t\(.attributes.bundleId)\t\(.attributes.name)"' <<<"$APPS_JSON")

echo
echo "DONE (read-only inventory)"
