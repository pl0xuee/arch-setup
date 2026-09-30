#!/usr/bin/env bash
#
# One-liner entry point. On a fresh CachyOS or Omarchy box:
#
#   curl -fsSL https://raw.githubusercontent.com/pl0xuee/arch-setup/master/bootstrap.sh | bash
#
# It clones the repo and runs install.sh. It has to clone rather than just pipe
# install.sh into bash, because install.sh reads its package lists from
# packages/*.txt — piping the script alone would give you a script with nothing
# to install.
#
# Piping a script from the internet into bash means running whatever is at that
# URL, sight unseen. If you'd rather look first (you should):
#
#   git clone https://github.com/pl0xuee/arch-setup.git
#   cd arch-setup
#   less install.sh
#   ./install.sh --dry-run
#   ./install.sh
#
# Any arguments are passed straight through, so the one-liner takes install.sh's
# options too — `... | bash -s -- --dry-run`, or `--desktop omarchy` if the
# desktop guess is wrong.
#
set -euo pipefail

REPO_URL="https://github.com/pl0xuee/arch-setup.git"
DEST="${SETUP_DIR:-$HOME/Documents/Projects/arch-setup}"

command -v git >/dev/null 2>&1 || {
    echo "error: git is required. Install it with: sudo pacman -S git" >&2
    exit 1
}

if [[ -d "$DEST/.git" ]]; then
    echo "Updating $DEST..."
    # Stop rather than quietly running an old install.sh: a checkout with local
    # edits or a diverged branch can't fast-forward, and the one line saying so
    # would scroll away under the whole run.
    if ! git -C "$DEST" pull --ff-only; then
        echo "error: couldn't update $DEST to the latest version (local changes, or" >&2
        echo "       a branch that has diverged). Sort that out with git, or run" >&2
        echo "       $DEST/install.sh directly to use the copy that's there." >&2
        exit 1
    fi
else
    echo "Cloning into $DEST..."
    mkdir -p "$(dirname "$DEST")"
    git clone --quiet "$REPO_URL" "$DEST"
fi

chmod +x "$DEST/install.sh"

# When this script is itself being piped from curl, our stdin IS that pipe, and
# it's at EOF. Hand install.sh the real terminal instead, so sudo can prompt for
# a password and the run doesn't die at the first hurdle. Opening it is the
# test, not -e: the node exists even with no controlling terminal (ssh without
# -t, CI), and there the redirect would fail and take the exec with it.
if { : </dev/tty; } 2>/dev/null; then
    exec "$DEST/install.sh" "$@" < /dev/tty
else
    exec "$DEST/install.sh" "$@"
fi
