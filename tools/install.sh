#!/usr/bin/env sh
set -eu

REPOSITORY="RecurLoop/RecurLoop"
ARCHIVE_BASE="recurloop-linux-x86_64.tar.gz"
LATEST_URL="https://github.com/${REPOSITORY}/releases/latest"
DOWNLOAD_BASE="https://github.com/${REPOSITORY}/releases/latest/download"

case "$(uname -s)" in
  Linux) ;;
  *)
    echo "RecurLoop release installer currently supports Linux only." >&2
    exit 1
    ;;
esac

case "$(uname -m)" in
  x86_64|amd64) ;;
  *)
    echo "RecurLoop release installer currently supports x86-64 only." >&2
    exit 1
    ;;
esac

if [ -n "${RECURLOOP_PREFIX:-}" ]; then
  PREFIX="$RECURLOOP_PREFIX"
elif [ "$(id -u)" -eq 0 ]; then
  PREFIX="/usr/local"
else
  PREFIX="${HOME}/.local"
fi

for command in curl tar sha256sum awk mktemp; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Required command not found: $command" >&2
    exit 1
  fi
done

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM HUP

ARCHIVE="$TMP_DIR/$ARCHIVE_BASE"
CHECKSUM="$TMP_DIR/$ARCHIVE_BASE.sha256"

# New releases publish a stable asset name so this URL never changes.
# Fall back to the historical versioned asset name for older releases.
if ! curl -fL --retry 3 --connect-timeout 15 \
    "$DOWNLOAD_BASE/$ARCHIVE_BASE" -o "$ARCHIVE"; then
  LATEST_EFFECTIVE_URL="$(curl -fsSL -o /dev/null -w '%{url_effective}' "$LATEST_URL")"
  TAG="${LATEST_EFFECTIVE_URL##*/}"
  VERSION="${TAG#v}"
  if [ -z "$VERSION" ] || [ "$VERSION" = "$TAG" ]; then
    echo "Could not determine the latest RecurLoop release tag." >&2
    exit 1
  fi
  ARCHIVE_BASE="recurloop-${VERSION}-linux-x86_64.tar.gz"
  ARCHIVE="$TMP_DIR/$ARCHIVE_BASE"
  CHECKSUM="$TMP_DIR/$ARCHIVE_BASE.sha256"
  curl -fL --retry 3 --connect-timeout 15 \
    "https://github.com/${REPOSITORY}/releases/download/${TAG}/${ARCHIVE_BASE}" \
    -o "$ARCHIVE"
  curl -fL --retry 3 --connect-timeout 15 \
    "https://github.com/${REPOSITORY}/releases/download/${TAG}/${ARCHIVE_BASE}.sha256" \
    -o "$CHECKSUM"
else
  curl -fL --retry 3 --connect-timeout 15 \
    "$DOWNLOAD_BASE/$ARCHIVE_BASE.sha256" -o "$CHECKSUM"
fi

EXPECTED="$(awk 'NR == 1 { print $1 }' "$CHECKSUM")"
ACTUAL="$(sha256sum "$ARCHIVE" | awk '{ print $1 }')"
if [ -z "$EXPECTED" ] || [ "$EXPECTED" != "$ACTUAL" ]; then
  echo "RecurLoop release checksum verification failed." >&2
  exit 1
fi

mkdir -p "$PREFIX"
tar -xzf "$ARCHIVE" -C "$PREFIX" --strip-components=1

BINARY="$PREFIX/bin/recurloop"
if [ ! -x "$BINARY" ]; then
  echo "Installation failed: $BINARY was not installed." >&2
  exit 1
fi

for library in language-kit shell inferred http; do
  if [ ! -s "$PREFIX/share/recurloop/libraries/${library}.rli" ]; then
    echo "Installation failed: missing ${library}.rli" >&2
    exit 1
  fi
done

echo "Installed RecurLoop to $PREFIX"
echo "  binary:    $PREFIX/bin/recurloop"
echo "  libraries: $PREFIX/share/recurloop/libraries"

case ":${PATH}:" in
  *":$PREFIX/bin:"*) ;;
  *)
    echo
    echo "$PREFIX/bin is not currently in PATH."
    echo "Add it to your shell configuration, for example:"
    echo "  export PATH=\"$PREFIX/bin:\$PATH\""
    ;;
esac
