#!/bin/bash
# Install ogg2mp3 to ~/.local/bin so Agents (Claude Code, Codex, etc.) and humans
# can invoke it as plain `ogg2mp3 <command>` without a path prefix.
#
# Idempotent: re-running replaces the existing symlink.
# Refuses to run as root — a root-owned symlink in ~/.local/bin would force
# subsequent invocations to need sudo, defeating the point.

set -eo pipefail

if [[ "$(id -u)" -eq 0 ]]; then
    echo "error: must not run as root; rerun without sudo" >&2
    exit 3
fi

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)
SOURCE="$REPO_ROOT/ogg2mp3.sh"
BIN_DIR="$HOME/.local/bin"
TARGET="$BIN_DIR/ogg2mp3"

if [[ ! -f "$SOURCE" ]]; then
    echo "error: source script not found: $SOURCE" >&2
    exit 1
fi
if [[ ! -x "$SOURCE" ]]; then
    echo "warning: $SOURCE is not executable; fixing chmod +x" >&2
    chmod +x "$SOURCE"
fi

mkdir -p "$BIN_DIR"

# Refuse to clobber a non-symlink (could be the user's own binary).
if [[ -e "$TARGET" && ! -L "$TARGET" ]]; then
    echo "error: $TARGET exists and is not a symlink; refusing to overwrite" >&2
    echo "       move or delete it manually, then re-run" >&2
    exit 1
fi

ln -sfn "$SOURCE" "$TARGET"

VERSION=$("$TARGET" version 2>/dev/null | awk '{print $2}')
echo "installed: $TARGET -> $SOURCE"
echo "version:   ${VERSION:-unknown}"

# PATH check
case ":$PATH:" in
    *":$BIN_DIR:"*)
        echo "PATH:      ok ($BIN_DIR is on PATH)"
        ;;
    *)
        echo "PATH:      WARNING — $BIN_DIR is not on PATH"
        echo "           add this to your shell rc:"
        echo "             export PATH=\"\$HOME/.local/bin:\$PATH\""
        ;;
esac

echo
echo "try:  ogg2mp3 doctor"
