#!/usr/bin/env bash
# Downloads the pinned SwiftLint release binary into .build/tools, checks its SHA-256 and prints the
# path of the executable. Used by scripts/lint.sh and CI, so both run exactly the same version.
# To upgrade: change VERSION and the checksums (from the release's asset digests:
#   gh release view <version> -R realm/SwiftLint --json assets -q '.assets[]|.name+" "+.digest').
set -euo pipefail

VERSION=0.65.1
case "$(uname -s)-$(uname -m)" in
    Darwin-*)
        ASSET=portable_swiftlint.zip
        SHA256=c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0
        BINARY=swiftlint
        ;;
    Linux-x86_64)
        ASSET=swiftlint_linux_amd64.zip
        SHA256=caeed6f4a679c35539ffaf124f6c4ab4a8416917f7d8796279dc52b74026059d
        BINARY=swiftlint-static
        ;;
    Linux-aarch64 | Linux-arm64)
        ASSET=swiftlint_linux_arm64.zip
        SHA256=9ffa52f478e6d8eb485d37d14715ffac90abc81c58f3370d598bf75be05605f8
        BINARY=swiftlint-static
        ;;
    *)
        echo "install-swiftlint: unsupported platform $(uname -s)-$(uname -m)" >&2
        exit 1
        ;;
esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$ROOT/.build/tools/swiftlint-$VERSION"
EXE="$DIR/$BINARY"

if [[ ! -x "$EXE" ]]; then
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
        --output "$TMP/$ASSET" \
        "https://github.com/realm/SwiftLint/releases/download/$VERSION/$ASSET"
    if command -v sha256sum >/dev/null; then
        ACTUAL="$(sha256sum "$TMP/$ASSET" | cut -d' ' -f1)"
    else
        ACTUAL="$(shasum -a 256 "$TMP/$ASSET" | cut -d' ' -f1)"
    fi
    if [[ "$ACTUAL" != "$SHA256" ]]; then
        echo "install-swiftlint: checksum mismatch for $ASSET (expected $SHA256, got $ACTUAL)" >&2
        exit 1
    fi
    mkdir -p "$DIR"
    unzip -q -o "$TMP/$ASSET" "$BINARY" -d "$DIR"
    chmod +x "$EXE"
fi

ACTUAL_VERSION="$("$EXE" version)"
if [[ "$ACTUAL_VERSION" != "$VERSION" ]]; then
    echo "install-swiftlint: $EXE reports $ACTUAL_VERSION, expected $VERSION" >&2
    exit 1
fi
echo "$EXE"
