#!/usr/bin/env bash
# Notarizes and staples "build/Spider Solitaire.app" (already Developer ID signed by package.sh),
# then rebuilds build/SpiderSolitaire.zip from the stapled app and verifies it with Gatekeeper.
#
# Credentials, either set (the API key wins when both are complete):
#   App Store Connect API key: ASC_KEY_FILE=<AuthKey .p8> ASC_KEY_ID=<key id> ASC_ISSUER_ID=<issuer id>
#   Apple ID: APPLE_ID=<email> APPLE_APP_PASSWORD=<app-specific password> APPLE_TEAM_ID=<team id>
#
# On a rejected submission it prints the notary log and fails. Nothing secret is printed.
set -euo pipefail

if [[ -n "${ASC_KEY_FILE:-}" && -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]]; then
    echo "==> Notary credentials: App Store Connect API key"
    AUTH=(--key "$ASC_KEY_FILE" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID")
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
    echo "==> Notary credentials: Apple ID"
    AUTH=(--apple-id "$APPLE_ID" --password "$APPLE_APP_PASSWORD" --team-id "$APPLE_TEAM_ID")
else
    echo "error: set ASC_KEY_FILE, ASC_KEY_ID and ASC_ISSUER_ID, or APPLE_ID, APPLE_APP_PASSWORD and APPLE_TEAM_ID" >&2
    exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Spider Solitaire.app"
ZIP="$ROOT/build/SpiderSolitaire.zip"
SUBMIT_ZIP="$ROOT/build/SpiderSolitaire-notarize.zip"

echo "==> Submitting for notarization"
rm -f "$SUBMIT_ZIP"
ditto -c -k --keepParent "$APP" "$SUBMIT_ZIP"
result="$(xcrun notarytool submit "$SUBMIT_ZIP" "${AUTH[@]}" --wait --timeout 30m --output-format json)" || true
rm -f "$SUBMIT_ZIP"
echo "$result"
id="$(plutil -extract id raw -o - - <<<"$result" 2>/dev/null || true)"
status="$(plutil -extract status raw -o - - <<<"$result" 2>/dev/null || true)"
if [[ "$status" != "Accepted" ]]; then
    echo "error: notarization status '${status:-unknown}'" >&2
    if [[ -n "$id" ]]; then
        xcrun notarytool log "$id" "${AUTH[@]}" || true
    fi
    exit 1
fi

echo "==> Stapling"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "==> Verifying"
codesign --verify --strict --deep --verbose=2 "$APP"
spctl --assess --verbose=4 --type execute "$APP"

echo "==> Zipping the stapled app"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "==> Done: $ZIP"
