#!/usr/bin/env bash
# Baran installer:
#   curl -fsSL https://raw.githubusercontent.com/keravyn-ops/baran/main/install.sh | bash
set -euo pipefail

REPO="${BARAN_REPO:-keravyn-ops/baran}"
REF="${BARAN_REF:-main}"
BIN_DIR="${BARAN_BIN_DIR:-$HOME/.local/bin}"
URL="https://raw.githubusercontent.com/$REPO/$REF/baran"

[[ $EUID -eq 0 ]] && { echo "install.sh: run as your normal user, not root" >&2; exit 1; }
command -v curl >/dev/null || { echo "install.sh: curl is missing" >&2; exit 1; }
command -v python3 >/dev/null || { echo "install.sh: python3 is missing" >&2; exit 1; }

tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
echo "baran: downloading $REF from $REPO"
curl -fsSL "$URL" -o "$tmp"
head -n1 "$tmp" | grep -q '^#!/usr/bin/env python3' || { echo "install.sh: unexpected download" >&2; exit 1; }
python3 -m py_compile "$tmp" || { echo "install.sh: syntax check failed" >&2; exit 1; }

mkdir -p "$BIN_DIR"
install -m 755 "$tmp" "$BIN_DIR/baran"
echo "baran: installed to $BIN_DIR/baran"
"$BIN_DIR/baran" --version

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo; echo "Note: $BIN_DIR is not in PATH. Add to your shell profile:";
     echo '  export PATH="$HOME/.local/bin:$PATH"' ;;
esac
echo
echo "Next:  baran gui     (or: baran doctor)"
