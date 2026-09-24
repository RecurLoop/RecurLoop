#!/usr/bin/env sh
set -eu

REPOSITORY="RecurLoop/RecurLoop"
LATEST_URL="https://github.com/${REPOSITORY}/releases/latest"

case "$(uname -s)" in
  Linux) ;;
  *)
    echo "RecurLoop binary releases currently support Linux only." >&2
    exit 1
    ;;
esac

case "$(uname -m)" in
  x86_64|amd64) ;;
  *)
    echo "RecurLoop binary releases currently support Linux x86-64 only." >&2
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

for command in curl tar sha256sum awk mktemp getconf; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Required command not found: $command" >&2
    exit 1
  fi
done

if ! getconf GNU_LIBC_VERSION >/dev/null 2>&1; then
  echo "The current binary release requires glibc; musl-based systems need a separate future artifact." >&2
  exit 1
fi
GLIBC_VERSION="$(getconf GNU_LIBC_VERSION | awk '{ print $2 }')"
if ! awk -v version="$GLIBC_VERSION" 'BEGIN { split(version, v, "."); exit !(v[1] > 2 || (v[1] == 2 && v[2] >= 35)) }'; then
  echo "This release requires glibc >= 2.35 (found $GLIBC_VERSION)." >&2
  exit 1
fi

if [ -n "${RECURLOOP_VERSION:-}" ]; then
  VERSION="${RECURLOOP_VERSION#v}"
  TAG="v${VERSION}"
else
  LATEST_EFFECTIVE_URL="$(curl -fsSL --retry 3 --connect-timeout 15 -o /dev/null -w '%{url_effective}' "$LATEST_URL")"
  TAG="${LATEST_EFFECTIVE_URL##*/}"
  VERSION="${TAG#v}"
fi
if ! printf '%s\n' "$VERSION" | awk -F. '
  NF != 3 { exit 1 }
  $1 !~ /^[0-9]+$/ || $2 !~ /^[0-9]+$/ || $3 !~ /^[0-9]+$/ { exit 1 }
'; then
  echo "Could not determine a valid RecurLoop release version (got '$VERSION')." >&2
  exit 1
fi

ARCHIVE_BASE="recurloop-${VERSION}-linux-x86_64.tar.gz"
DOWNLOAD_BASE="https://github.com/${REPOSITORY}/releases/download/${TAG}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM HUP
ARCHIVE="$TMP_DIR/$ARCHIVE_BASE"
CHECKSUM="$TMP_DIR/$ARCHIVE_BASE.sha256"

curl -fL --retry 3 --connect-timeout 15 "$DOWNLOAD_BASE/$ARCHIVE_BASE" -o "$ARCHIVE"
curl -fL --retry 3 --connect-timeout 15 "$DOWNLOAD_BASE/$ARCHIVE_BASE.sha256" -o "$CHECKSUM"
EXPECTED="$(awk 'NR == 1 { print $1 }' "$CHECKSUM")"
CHECKSUM_NAME="$(awk 'NR == 1 { name=$2; sub(/^\*/, "", name); print name }' "$CHECKSUM")"
ACTUAL="$(sha256sum "$ARCHIVE" | awk '{ print $1 }')"
if [ -z "$EXPECTED" ] || [ "$CHECKSUM_NAME" != "$ARCHIVE_BASE" ] || [ "$EXPECTED" != "$ACTUAL" ]; then
  echo "RecurLoop release checksum verification failed." >&2
  exit 1
fi

PACKAGE_ROOT="recurloop-${VERSION}-linux-x86_64"
if ! tar -tzf "$ARCHIVE" | awk -v root="$PACKAGE_ROOT" '
  /^\// || /(^|\/)\.\.(\/|$)/ || /(^|\/)\.(\/|$)/ { bad = 1; next }
  $0 == root || $0 == root "/" || index($0, root "/") == 1 { next }
  { bad = 1 }
  END { exit bad }
'; then
  echo "Release archive contains paths outside the expected package root." >&2
  exit 1
fi

EXTRACT_DIR="$TMP_DIR/extracted"
mkdir -p "$EXTRACT_DIR"
tar -xzf "$ARCHIVE" -C "$EXTRACT_DIR"
STAGED="$EXTRACT_DIR/$PACKAGE_ROOT"
if [ ! -f "$STAGED/share/recurloop/PACKAGE-MANIFEST.sha256" ]; then
  echo "Release package has no internal integrity manifest." >&2
  exit 1
fi
(
  cd "$STAGED"
  sha256sum -c share/recurloop/PACKAGE-MANIFEST.sha256 >/dev/null
)

mkdir -p "$PREFIX"
# Validate completely before touching the destination. The tar-to-tar copy
# preserves the package's executable bits without depending on GNU cp.
tar -C "$STAGED" -cf - . | tar -C "$PREFIX" -xf -
(
  cd "$PREFIX"
  sha256sum -c share/recurloop/PACKAGE-MANIFEST.sha256 >/dev/null
)

BINARY="$PREFIX/bin/recurloop"
if [ ! -x "$BINARY" ]; then
  echo "Installation failed: $BINARY was not installed." >&2
  exit 1
fi
for library in language-kit shell inferred http gui ide project embed; do
  if [ ! -s "$PREFIX/share/recurloop/libraries/${library}.rli" ]; then
    echo "Installation failed: missing ${library}.rli" >&2
    exit 1
  fi
done
"$BINARY" --version
if command -v ldd >/dev/null 2>&1; then
  missing_runtime="$(ldd "$BINARY" 2>/dev/null | awk '/not found/ { print $1 }')"
  if [ -n "$missing_runtime" ]; then
    echo "Installation is missing required runtime libraries:" >&2
    printf '  %s\n' $missing_runtime >&2
    echo "Install the corresponding packages from your Linux distribution." >&2
    exit 1
  fi
fi

echo "Installed RecurLoop $VERSION to $PREFIX"
echo "  binary:    $PREFIX/bin/recurloop"
echo "  libraries: $PREFIX/share/recurloop/libraries"

# The LLVM JIT/backend itself is linked into RecurLoop. Native file output uses
# host tools: LLD for objects, and Clang+LLD for executables.
missing_native_tools=0
if ! command -v ld.lld-22 >/dev/null 2>&1 && ! command -v ld.lld >/dev/null 2>&1; then
  missing_native_tools=1
fi
if ! command -v clang-22 >/dev/null 2>&1 && ! command -v clang >/dev/null 2>&1; then
  missing_native_tools=1
fi
if [ "$missing_native_tools" -ne 0 ]; then
  echo
  echo "Optional native file-output tools were not found."
  echo "On Debian/Ubuntu install them with:"
  echo "  sudo apt install clang-22 lld-22"
fi

case ":${PATH}:" in
  *":$PREFIX/bin:"*) ;;
  *)
    echo
    echo "$PREFIX/bin is not currently in PATH."
    echo "Add it to your shell configuration, for example:"
    echo "  export PATH=\"$PREFIX/bin:\$PATH\""
    ;;
esac
