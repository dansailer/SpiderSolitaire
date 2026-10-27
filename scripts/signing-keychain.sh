#!/usr/bin/env bash
# Temporary keychain for signing in CI (the Release workflow).
#
#   KEYCHAIN=<path> CERT_P12_BASE64=<base64 .p12> CERT_PASSWORD=<pw> scripts/signing-keychain.sh create
#   KEYCHAIN=<path> scripts/signing-keychain.sh delete
#
# create: makes KEYCHAIN with a random password, imports the .p12 (only codesign may use the key),
# sets the key partition list so codesign can use it without a prompt, and adds the keychain to the
# user search list (needed by codesign's certificate chain lookup). delete: removes it again.
# Nothing secret is printed.
set -euo pipefail

: "${KEYCHAIN:?KEYCHAIN is not set}"

case "${1:-}" in
    create)
        : "${CERT_P12_BASE64:?CERT_P12_BASE64 is not set}"
        : "${CERT_PASSWORD:?CERT_PASSWORD is not set}"
        umask 077
        work="$(mktemp -d)"
        trap 'rm -rf "$work"' EXIT
        password="$(openssl rand -hex 32)"
        if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
            echo "::add-mask::$password"
        fi
        printf '%s' "$CERT_P12_BASE64" | base64 --decode > "$work/cert.p12"
        security create-keychain -p "$password" "$KEYCHAIN"
        security set-keychain-settings -lut 3600 "$KEYCHAIN"
        security unlock-keychain -p "$password" "$KEYCHAIN"
        security import "$work/cert.p12" -k "$KEYCHAIN" -f pkcs12 -P "$CERT_PASSWORD" -T /usr/bin/codesign
        security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$KEYCHAIN" >/dev/null
        existing=()
        while IFS= read -r line; do
            line="${line#"${line%%[![:space:]]*}"}"
            line="${line%\"}"
            existing+=("${line#\"}")
        done < <(security list-keychains -d user)
        security list-keychains -d user -s "$KEYCHAIN" ${existing[@]+"${existing[@]}"}
        security find-identity -v -p codesigning "$KEYCHAIN"
        ;;
    delete)
        if [[ -f "$KEYCHAIN" ]]; then
            security delete-keychain "$KEYCHAIN" || rm -f "$KEYCHAIN"
        fi
        ;;
    *)
        echo "usage: KEYCHAIN=<path> scripts/signing-keychain.sh create|delete" >&2
        exit 2
        ;;
esac
