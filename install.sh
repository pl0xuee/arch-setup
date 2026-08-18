#!/usr/bin/env bash
#
# Post-install setup for a fresh CachyOS or Omarchy box.
#
# Both ship a full desktop already, so this only installs the delta:
# the apps that aren't on the ISO, plus two programs of mine that aren't
# packaged anywhere and have to be built or fetched from GitHub.
#
# The desktop is detected at the start of the run and the steps that only exist
# on one of them are gated on it — see detect_desktop() and the README. Nothing
# is ever skipped silently.
#
# Everything here is idempotent — re-run it any time.
#
#   ./install.sh              # everything
#   ./install.sh --dry-run    # show what it would do, change nothing
#   ./install.sh --help       # options
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$REPO_DIR/packages"

# Where AgentTileCLI gets cloned. It has a built-in "check for updates" that
# pulls and rebuilds from its own clone, so this must be a permanent path you
# don't mind keeping — not a temp dir.
PROJECTS_DIR="${PROJECTS_DIR:-$HOME/Documents/Projects}"

# StreamHub self-updates by overwriting its own AppImage in place, so it has to
# live somewhere your user can write. Anywhere root-owned (/opt, /usr/local/bin)
# would break that.
BIN_DIR="$HOME/.local/bin"
APPS_DIR="$HOME/.local/share/applications"
STREAMHUB_DIR="$HOME/.local/share/streamhub"
STREAMHUB_APPIMAGE="$BIN_DIR/StreamHub.AppImage"   # unversioned name is deliberate; see StreamHub's README
STREAMHUB_REPO="pl0xuee/StreamHub"
AGENTTILE_REPO="https://github.com/pl0xuee/agenttilecli.git"

# ConsoleVault is a Tauri app with the updater turned on, so like StreamHub it
# replaces its own AppImage in place — same reason it lives under ~/.local/bin.
# The release ships a versioned filename (ConsoleVault_x.y.z_amd64.AppImage); we
# install it under a stable name because Tauri's updater overwrites whatever path
# it's running from, and the .desktop launcher needs a filename that won't move.
CONSOLEVAULT_DIR="$HOME/.local/share/consolevault"
CONSOLEVAULT_APPIMAGE="$BIN_DIR/ConsoleVault.AppImage"
CONSOLEVAULT_REPO="pl0xuee/ConsoleVault"
# minisign public key, verbatim from the app's src-tauri/tauri.conf.json. It's
# hard-coded rather than fetched at runtime on purpose: pulling the key from the
# same GitHub release as the binary would "verify" a tampered download against a
# tampered key, which is no verification at all. Bump this only if the app rotates
# its signing key (and only from a source you trust, not the release page).
CONSOLEVAULT_PUBKEY="RWRWvWU0rorx3lM6O7xZd/SBN3UzFI5a/fPThO4FQVe3iad5QNfwVo2J"

# Disc Ripper is a PySide6/Qt AppImage that auto-rips DVDs/Blu-rays to H.265. Like
# the other two it's fetched from GitHub Releases under a stable filename and lives
# in ~/.local/bin. Unlike them the release publishes no signature or checksum asset
# — only the AppImage and its .zsync — so the download is verified against the
# full-file SHA-1 and length carried in that .zsync header. That's an integrity
# check, not a signature: the .zsync rides in the same release, so it catches a
# corrupt or truncated download, not a maliciously swapped release. It's the
# strongest check the release offers, and still beats running the binary unchecked.
DISCRIPPER_DIR="$HOME/.local/share/discripper"
DISCRIPPER_APPIMAGE="$BIN_DIR/DiscRipper.AppImage"
DISCRIPPER_REPO="pl0xuee/discripper"

# GridDown is a Tauri app (offline US maps — streets, forest roads, trails), so it
# follows ConsoleVault exactly: updater enabled, replaces its own AppImage in place,
# release ships a versioned name (GridDown_x.y.z_amd64.AppImage) that we install
# under a stable one. Note the repo's default branch is master, not main.
GRIDDOWN_DIR="$HOME/.local/share/griddown"
GRIDDOWN_APPIMAGE="$BIN_DIR/GridDown.AppImage"
GRIDDOWN_REPO="pl0xuee/griddown"
GRIDDOWN_BRANCH="master"
# minisign public key from the app's src-tauri/tauri.conf.json. Tauri stores it
# there base64-encoded (the whole key *file*); this is the decoded key line, which
# is what `minisign -P` wants. Hard-coded for the same reason as ConsoleVault's:
# a key fetched from the release it's meant to vouch for proves nothing.
GRIDDOWN_PUBKEY="RWR4H5doHqJ0FJLVbBQvbrbWfmA74M7CFZWb4R7gejBvNR3iwMMe28Je"

# Stalker GAMMA GUI is an Avalonia/.NET AppImage that downloads, installs,
# updates and launches S.T.A.L.K.E.R. GAMMA through Steam/Proton. Unlike the
# Tauri/Electron apps above it has NO self-updater — re-running this script is
# how it updates, which the version stamp makes cheap. Its CI names the asset
# unversioned already, and publishes no signature or checksum file; the only
# digest anywhere is the per-asset sha256 the GitHub releases API reports, so
# the download is checked against that. Same caveat as Disc Ripper's .zsync:
# the digest comes from the same host as the binary, so it catches a corrupt
# or truncated download, not a swapped release — still the strongest check the
# release offers.
GAMMAGUI_DIR="$HOME/.local/share/stalkergammagui"
GAMMAGUI_APPIMAGE="$BIN_DIR/StalkerGammaGui.AppImage"
GAMMAGUI_REPO="pl0xuee/stalker-gamma-linux-gui"
GAMMAGUI_ASSET="StalkerGammaGui-x86_64.AppImage"

# LoreRim Autoinstall is an Avalonia/.NET AppImage that installs the LoreRim
# Wabbajack modlist for Skyrim — Steam, Proton and Nexus handled automatically.
# Same shape as Stalker GAMMA GUI in every way that matters here: NO
# self-updater (re-running this script is the update path, via the version
# stamp), CI already names the asset unversioned, and the release publishes no
# signature or checksum file — the only digest anywhere is the per-asset sha256
# the GitHub releases API reports, so the download is checked against that.
# Same caveat as the others: the digest comes from the same host as the binary,
# so it catches a corrupt or truncated download, not a swapped release.
LORERIM_DIR="$HOME/.local/share/lorerim-autoinstall"
LORERIM_APPIMAGE="$BIN_DIR/LorerimAutoinstall.AppImage"
LORERIM_REPO="pl0xuee/lorerim-autoinstall"
LORERIM_ASSET="LorerimAutoinstall-x86_64.AppImage"

# WotLK Autoinstall is an Avalonia/.NET AppImage that installs a World of
# Warcraft 3.3.5a client for a local server — realmlist, addons, and a Steam
# shortcut under Proton. Same no-self-updater shape as Stalker GAMMA GUI and
# LoreRim (the version stamp is the update path, CI already names the asset
# unversioned), with one difference that's worth the extra code below: this
# release is the first here to publish a real checksum FILE (SHA256SUMS)
# alongside the binary, so that — not just the API's per-asset digest — is what
# the download is checked against. Both still come from the same host as the
# binary, so this is integrity, not authenticity: it catches a corrupt,
# truncated or re-uploaded asset, not a maliciously cut release.
WOTLK_DIR="$HOME/.local/share/wow-wotlk-autoinstall"
WOTLK_APPIMAGE="$BIN_DIR/WowWotlkAutoinstall.AppImage"
WOTLK_REPO="pl0xuee/wow-wotlk-autoinstall"
WOTLK_ASSET="WowWotlkAutoinstall-x86_64.AppImage"
WOTLK_SUMS="SHA256SUMS"

# Music AI Player is a Tauri music player for long coding sessions — SQLite
# library, crossfade, shuffle, playlists, visualizer — filled from a yt-dlp
# importer, a folder scan, or a local ACE-Step generator. Back to the
# ConsoleVault/GridDown shape after the last three: the Tauri updater IS enabled
# here (the release ships latest.json and a minisign .sig), so it replaces its
# own AppImage in place and the version stamp only matters for the first run
# after a release the app hasn't picked up itself. Versioned asset name
# (Music.AI.Player_x.y.z_amd64.AppImage) installed under a stable one, for the
# same reason as the other Tauri apps: the updater overwrites whatever path it
# is running from, and the launcher needs a filename that won't move. Default
# branch is master, not main.
MUSICAI_DIR="$HOME/.local/share/music-ai-player"
MUSICAI_APPIMAGE="$BIN_DIR/MusicAIPlayer.AppImage"
MUSICAI_REPO="pl0xuee/music-ai-player"
MUSICAI_BRANCH="master"
# minisign public key from the app's src-tauri/tauri.conf.json. Tauri stores it
# there base64-encoded (the whole key *file*); this is the decoded key line, the
# form `minisign -P` wants — same as GridDown's. Hard-coded for the same reason
# as the others: a key fetched from the release it vouches for proves nothing.
MUSICAI_PUBKEY="RWQAo9xTlRVM+fTKa7sSVc0P+nIEuLCEDbEOtfEK10uMzI0sbx7BAO/S"

# CPU power profile. power-profiles-daemon forgets this on reboot, so the config
# step also installs a user service that reapplies it at login.
POWER_PROFILE="performance"

# KDE's Power Management page (System Settings → Power Management).
#
# Only the "AC" profile is set: a desktop has no other one. On a laptop the
# Battery and Low Battery profiles are left at their defaults, which is what you
# want — never suspending on battery is a good way to find a flat machine.
SCREEN_OFF_MINS=10          # turn the screen off after this long idle
SCREEN_OFF_LOCKED_MINS=1    # ...and this long after the session locks

# Panel tweaks, taken from the real machine's plasma config rather than guessed.
# A stock CachyOS panel is otherwise identical, so these are the only deltas.

# Panel height in pixels. Plasma's default is 30. Note this lives in
# plasmashellrc, NOT the appletsrc where everything else about the panel is.
PANEL_HEIGHT=40

# Brave's homepage (the Home button), set via enterprise policy. Being policy,
# Brave marks it "managed by your organisation" and greys it out in Settings —
# to change it, edit this and re-run, or delete the policy file.
BRAVE_HOMEPAGE="https://pl0xuee.com"

# Brave filter lists to switch on, by UUID (brave://settings/shields/filters).
# These are NOT settable via enterprise policy — they live in Brave's own
# "Local State" file, so the script seeds them there instead.
BRAVE_FILTER_LISTS=(
    564C3B75-8731-404C-AD7C-5683258BA0B0    # Brave Experimental Adblock Rules
)

# Widgets to remove from the panel entirely.
PANEL_REMOVE=(
    org.kde.plasma.showdesktop      # "Peek at Desktop"
)

# System-tray items to tuck behind the expander arrow instead of showing inline.
TRAY_HIDDEN=(
    org.kde.plasma.brightness       # Brightness and Color
    org.kde.plasma.clipboard
    org.kde.plasma.battery
    org.kde.plasma.keyboardindicator
)

# ── Omarchy desktop ───────────────────────────────────────────────────────────
#
# Omarchy-only settings, applied by configure_omarchy() and skipped on every
# other desktop. Taken from the real machine rather than guessed.

# Shell text size in px — the bar included, because the bar's height scales from
# it ([bar] scale-with-font defaults to true). Omarchy's default is 12. This is
# written to ~/.config/omarchy/shell.toml as [font] base-size, which moves the
# shell alone: `omarchy display text size` writes the same key but drags GTK's
# text-scaling-factor and every terminal's font size along with it.
OMARCHY_SHELL_FONT_PX=16

# Theme, and which of its backgrounds to select. The background is a filename
# inside omarchy/backgrounds/<theme>/ in this repo — leave it empty to install
# the wallpapers without picking one.
OMARCHY_THEME=solitude
OMARCHY_BACKGROUND=1308922.jpg

# foot's font size, in points. Omarchy ships 9, which is small on a 3440x1440.
FOOT_FONT_SIZE=11

# Clock widget formats. Qt date-format strings, not strftime.
OMARCHY_CLOCK_FORMAT="ddd d MMM h:mm AP"
OMARCHY_CLOCK_FORMAT_VERTICAL=$'h\n—\nmm\nAP'

# Which monitors get a bar, by connector name (`hyprctl monitors` — DP-1,
# HDMI-A-1). Empty means every monitor, which is stock Omarchy's behaviour. Only
# the patched bar clone honours this; a name that matches nothing on the box
# falls back to every monitor, so a machine with different displays still gets a
# bar rather than none.
OMARCHY_BAR_MONITORS=(
    DP-1                    # the ultrawide — the other two are secondary
)

# Bar widgets added to the right section, in order, directly after the tray.
OMARCHY_BAR_RIGHT_EXTRA=(
    omarchy.dropbox         # the Dropbox flatpak this script installs
    crmne.hyprmoncfg        # multi-monitor layout switcher (the plugin below)
)

# Third-party shell plugins, installed with `omarchy plugin add`.
OMARCHY_PLUGINS_GIT=(
    https://github.com/crmne/omarchy-hyprmoncfg.git
)

# Which AI agent Omarchy's menu and keybindings launch. Empty leaves it unset.
OMARCHY_DEFAULT_AGENT=claude

# sha256 of the two upstream files our QML patches were generated against
# (Omarchy 4.0.0-1). A mismatch doesn't stop the patch being tried — it just
# means the warning fires first, so a bar that comes back stock after an
# `omarchy update` has an obvious explanation in the run log.
OMARCHY_BAR_BASELINE_SHA=8bbe27ad7c617da1a3770fd5731b8cc79935ac34f04873c3933f7ff581a7cb15
OMARCHY_TRAY_BASELINE_SHA=36d26f81d8e37561cdd4addc3ccd0df0490415d196d518ead88ea95af0d02466

SKIP_UPGRADE=0
DRY_RUN=0
ONLY=""

# Which desktop this box runs, filled in by detect_desktop() during preflight:
#
#   kde      Plasma — CachyOS's default, and what this script was written for
#   omarchy  Omarchy (Arch + Hyprland). No Plasma panel, no powerdevil, and the
#            CachyOS repos aren't there either
#   other    anything else — the desktop-specific steps skip, the rest runs
#
# DESKTOP_FORCED is --desktop, for when the guess is wrong (or to test the other
# path from this machine).
DESKTOP=""
DESKTOP_FORCED=""

# ── output ────────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    BOLD=$'\e[1m'; DIM=$'\e[2m'; RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; BLUE=$'\e[34m'; RESET=$'\e[0m'
else
    BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; RESET=""
fi
STEP_N=0
STEP_TOTAL=14    # preflight + 13 steps; recalculated below if --only is used

step() {
    STEP_N=$((STEP_N + 1))
    printf '\n%s┌─ %s[%d/%d]%s %s%s%s\n' \
        "$BLUE" "$DIM" "$STEP_N" "$STEP_TOTAL" "$RESET$BLUE" "$BOLD$*" "$RESET" ""
}
info() { printf '   %s\n' "$*"; }
ok()   { printf '   %s✓%s %s\n' "$GREEN" "$RESET" "$*"; }
skip() { printf '   %s·%s %s%s%s\n' "$DIM" "$RESET" "$DIM" "$*" "$RESET"; }
# Warnings are also collected and reprinted at the end. During a ten-minute run
# a warning at minute two has long scrolled off the screen by the time it
# matters, which is the same as never having printed it.
WARNINGS=()
warn() {
    WARNINGS+=("$*")
    printf '   %s▲%s %s\n' "$YELLOW" "$RESET" "$*" >&2
}
die()  { printf '\n %s✗ error:%s %s\n\n' "$RED$BOLD" "$RESET" "$*" >&2; exit 1; }

# GitHub gives unauthenticated callers 60 API requests an hour per IP. Every
# AppImage step here spends one, so a couple of re-runs can empty the budget —
# and GitHub answers a spent budget with 403, not 429, which reads exactly like
# a permissions or network fault. Send a token when one is around (5000 an
# hour), and when we are refused, say which refusal it actually was.
github_token() {
    local t=""
    if   [[ -n "${GH_TOKEN:-}" ]];     then t="$GH_TOKEN"
    elif [[ -n "${GITHUB_TOKEN:-}" ]]; then t="$GITHUB_TOKEN"
    elif have gh; then
        # `gh` is not always the gh binary. Omarchy generates a wrapper in
        # ~/.local/bin for every mise-managed tool, and each one runs
        # `mise use -g <tool>` first — which prints "mise <config> tools: ..."
        # to STDOUT, ahead of the command's real output. Take the token out of
        # whatever else landed on the pipe: a token is one unbroken word, and a
        # status banner is a sentence. Matching on "has no whitespace" rather
        # than on a token prefix keeps classic PATs, fine-grained tokens and
        # whatever GitHub ships next all working.
        #
        # Not cosmetic. Stripping the newline and keeping both (what this used
        # to do) glues the banner onto a perfectly good token, and GitHub
        # answers that with 401 — which this script then reports as "the token
        # was rejected", sending you to check a token that was never the
        # problem.
        t="$(gh auth token 2>/dev/null | grep -xE '[^[:space:]]+' | tail -n1 || true)"
    fi
    # An explicit GH_TOKEN/GITHUB_TOKEN is passed through as the user set it —
    # classic PATs are 40 bare hex characters and enterprise tokens carry their
    # own shapes, so there is nothing safe to validate against. Only the stray
    # newline goes, which would otherwise terminate the header early.
    printf '%s' "${t//[$'\n\r']/}"
}

# Turn a failed response into a sentence naming the actual cause. Separate from
# the request so it can be tested without spending the very budget it reports on.
github_api_diagnose() {
    local code="$1" body="$2" had_token="$3" reset="" when=""

    if [[ "$code" == 403 || "$code" == 429 ]] && [[ "$body" == *"rate limit exceeded"* ]]; then
        # /rate_limit is free — it doesn't spend a request from the budget it reports.
        reset="$(curl -sS https://api.github.com/rate_limit 2>/dev/null \
                 | python -c 'import json,sys; print(json.load(sys.stdin)["resources"]["core"]["reset"])' \
                   2>/dev/null || true)"
        [[ -n "$reset" ]] && when="$(date -d "@$reset" '+%H:%M' 2>/dev/null || true)"

        if [[ "$had_token" -eq 1 ]]; then
            printf 'GitHub API rate limit exhausted for this token%s.' "${when:+ — resets at $when}"
        else
            printf 'GitHub API rate limit exhausted — 60 requests an hour, per IP, unauthenticated%s.\n' \
                   "${when:+; resets at $when}"
            printf '   Set GH_TOKEN (or run `gh auth login`) for 5000 an hour.'
        fi
        return 0
    fi

    case "$code" in
        404) printf 'GitHub returned 404 — no such repository, or it has no published release yet.' ;;
        401) printf 'GitHub returned 401 — the token was rejected. Check GH_TOKEN, or run `gh auth status`.' ;;
        000) printf "couldn't reach the GitHub API at all — network down, or a DNS/TLS failure." ;;
        *)   printf 'GitHub API request failed with HTTP %s.' "$code" ;;
    esac
}

# Authenticated GET, printing the body with the status appended on its own last
# line. Callers that need to tell one failure from another — GridDown treats a
# 404 as "no release cut yet" rather than an error — split that off themselves.
github_api_raw() {
    local url="$1" token auth=()
    token="$(github_token)"
    [[ -n "$token" ]] && auth=(-H "Authorization: Bearer $token")

    local out
    out="$(curl -sSL -w $'\n%{http_code}' \
                -H "Accept: application/vnd.github+json" \
                "${auth[@]}" "$url" 2>/dev/null)" || true
    # curl writes the status line even when the transfer fails, so only stand one
    # in when it wrote nothing at all — appending unconditionally leaves two, and
    # the body then parses as "\n000" rather than empty.
    [[ -n "$out" ]] || out=$'\n000'
    printf '%s' "$out"
}

# Whether the request carried a token, so a diagnosis can tell "your 60 are
# gone" from "your token's budget is gone" without re-deriving it.
github_had_token() { [[ -n "$(github_token)" ]] && printf '1' || printf '0'; }

# Fetch a GitHub API URL, printing the body on success. On failure the reason
# goes to stderr and the caller decides whether that is fatal.
github_api() {
    local url="$1" response body code
    response="$(github_api_raw "$url")"
    code="${response##*$'\n'}"
    body="${response%$'\n'*}"

    [[ "$code" == 200 ]] && { printf '%s' "$body"; return 0; }

    printf '   %s▲%s %s\n' "$YELLOW" "$RESET" \
           "$(github_api_diagnose "$code" "$body" "$(github_had_token)")" >&2
    return 1
}

BOX_W=52

# Draw a box around some lines. Built rather than hand-drawn: counting box
# characters by eye is how you end up with a border that's one column out.
box() {
    local colour="$1"; shift
    local line pad rule=""
    local i
    for (( i = 0; i < BOX_W; i++ )); do rule+="─"; done

    printf '\n%s╭%s╮%s\n' "$colour" "$rule" "$RESET"
    for line in "$@"; do
        # Width in characters, not bytes — the text may contain non-ASCII.
        pad=$(( BOX_W - 2 - ${#line} ))
        (( pad < 0 )) && pad=0
        printf '%s│%s  %s%*s%s│%s\n' "$colour" "$RESET" "$line" "$pad" "" "$colour" "$RESET"
    done
    printf '%s╰%s╯%s\n' "$colour" "$rule" "$RESET"
}

banner() {
    box "$BOLD$BLUE" \
        "CachyOS / Omarchy post-install setup" \
        "everything that isn't on the ISO"
}

have() { command -v "$1" >/dev/null 2>&1; }

# ── what are we running on ────────────────────────────────────────────────────
#
# Two questions, and they are NOT the same question:
#
#   detect_desktop()    which desktop is on screen — decides whether the Plasma
#                       panel and powerdevil steps have anything to configure
#   has_cachyos_repos() whether the CachyOS repos are enabled — decides which
#                       packages can be installed at all
#
# Omarchy answers "hyprland" and "no" to those; CachyOS answers "kde" and "yes".
# They are still asked separately, because CachyOS-with-something-else and
# Arch-with-the-CachyOS-repos-added are both real machines, and a single
# "is this CachyOS?" flag would get one of them wrong.
# Whether Omarchy is on this box at all — which is a different question from
# whether it is what the user is looking at.
#
# Omarchy 4.x is packaged: it lives in /usr/share/omarchy and exports
# OMARCHY_PATH from /etc/profile.d/omarchy.sh. Earlier releases were a git clone
# under ~/.local/share/omarchy. The paths are checked as well as the env var,
# because the env var only reaches us from a login shell inside the session —
# not over SSH with a command, and not from a TTY.
#
# Its own function so the suite can stub it. A test can fake XDG_CURRENT_DESKTOP
# and HOME, but it cannot make /usr/share/omarchy stop existing on the machine
# running the tests, and "a CachyOS box with bare Hyprland on it" is a case that
# has to be testable from an Omarchy box.
omarchy_installed() {
    [[ -n "${OMARCHY_PATH:-}" ]] \
        || [[ -d /usr/share/omarchy ]] \
        || [[ -d "$HOME/.local/share/omarchy" ]] \
        || have omarchy-version
}

detect_desktop() {
    if [[ -n "$DESKTOP_FORCED" ]]; then
        DESKTOP="$DESKTOP_FORCED"
        return
    fi

    # The running session wins whenever there is one: XDG_CURRENT_DESKTOP is set
    # by the session itself, so it says what is actually on screen rather than
    # what happens to be installed. That matters on a box carrying both — an
    # Omarchy install layered onto CachyOS, or the reverse — where the installed
    # markers are all true at once and only the session distinguishes them.
    local session="${XDG_CURRENT_DESKTOP:-}:${DESKTOP_SESSION:-}"
    session="${session,,}"
    if [[ "$session" == *kde* || "$session" == *plasma* ]]; then
        DESKTOP=kde
        return
    fi

    if [[ -n "${XDG_CURRENT_DESKTOP:-}${DESKTOP_SESSION:-}" ]]; then
        # Omarchy IS a Hyprland session — it sets XDG_CURRENT_DESKTOP=Hyprland
        # and nothing more specific — so the session name alone can't tell it
        # apart from bare Hyprland. Both together can: Hyprland on a box that
        # also has Omarchy installed is Omarchy.
        if [[ "$session" == *hyprland* || "$session" == *omarchy* ]] && omarchy_installed; then
            DESKTOP=omarchy
            return
        fi

        # A session that is set and is none of the above is the answer, and the
        # installed-package fallback below must not get to overrule it. A
        # CachyOS box whose owner added GNOME and logged into THAT still has
        # plasmashell sitting on disk; without this the fallback would call it
        # kde and go configure a panel nobody is looking at. The same holds for
        # a machine that has Omarchy installed but is running something else.
        DESKTOP=other
        return
    fi

    # No session environment at all — an SSH command, or a TTY — so there is
    # nothing to go on but what's installed.
    if omarchy_installed; then
        DESKTOP=omarchy
        return
    fi

    # plasmashell, NOT kwriteconfig6: the latter ships in kconfig, which rides
    # in behind any single KDE application on any desktop (Omarchy's own package
    # list includes kdenlive), and would call half the world KDE.
    if have plasmashell; then
        DESKTOP=kde
        return
    fi

    DESKTOP=other
}

# For messages. Kept separate from $DESKTOP so the value stays a bare word that
# is safe to compare against.
desktop_label() {
    case "$DESKTOP" in
        kde)     printf 'KDE Plasma' ;;
        omarchy) printf 'Omarchy (Hyprland)' ;;
        # Name what was found, so an unexpected 'other' is debuggable from the
        # one line of output. Not when it was forced, though — there the session
        # is exactly what the user chose to overrule, and printing it reads as a
        # contradiction ("other (KDE)").
        *)       if [[ -n "$DESKTOP_FORCED" ]]; then
                     printf 'other'
                 else
                     printf 'other (%s)' "${XDG_CURRENT_DESKTOP:-unknown}"
                 fi ;;
    esac
}

# Whether the CachyOS repos are enabled. That — not the distro's name — is what
# decides package availability, and it is worth being exact about: pacman fails
# the WHOLE transaction on one unknown package, so a single cachyos-only name in
# the list is the difference between "everything installed" and "nothing did,
# and set -e killed the run before any of the other steps".
CACHYOS_REPOS=""
has_cachyos_repos() {
    if [[ -z "$CACHYOS_REPOS" ]]; then
        local repos=""
        # pacman-conf resolves Includes and honours commented-out sections, so
        # it is the right answer; the grep is only there for a pacman old enough
        # not to ship it, where a section header in the file is the best we have.
        if have pacman-conf; then
            repos="$(pacman-conf --repo-list 2>/dev/null || true)"
        else
            repos="$(sed -n 's/^\[\([^]]*\)\].*/\1/p' /etc/pacman.conf 2>/dev/null || true)"
        fi
        if grep -q '^cachyos' <<<"$repos"; then CACHYOS_REPOS=1; else CACHYOS_REPOS=0; fi
    fi
    [[ "$CACHYOS_REPOS" == 1 ]]
}

# Set one key in one group of a Qt/KDE-style INI file, creating the file and the
# group if they aren't there.
#
# kwriteconfig6 is the right tool and is used whenever it exists. It doesn't
# always: it ships in kconfig, which is KDE Frameworks, and a machine that isn't
# running Plasma has no reason to have it. The python fallback exists so a
# setting that has nothing to do with KDE (KeePassXC's browser integration, say)
# still lands there rather than taking the run down with a command-not-found.
#
# RawConfigParser, not ConfigParser: Qt writes values containing % — a
# percent-encoded path, a format string — and ConfigParser would try to
# interpolate them and raise. optionxform is overridden because the default
# lowercases every key, and Qt's are CamelCase.
ini_set() {
    local file="$1" group="$2" key="$3" value="$4"

    if have kwriteconfig6; then
        kwriteconfig6 --file "$file" --group "$group" --key "$key" "$value"
        return
    fi

    INI_FILE="$file" INI_GROUP="$group" INI_KEY="$key" INI_VALUE="$value" python - <<'INI'
import configparser, os

path = os.environ["INI_FILE"]

cp = configparser.RawConfigParser(strict=False)
cp.optionxform = str
cp.read(path)

group = os.environ["INI_GROUP"]
if not cp.has_section(group):
    cp.add_section(group)
cp.set(group, os.environ["INI_KEY"], os.environ["INI_VALUE"])

with open(path, "w") as f:
    cp.write(f, space_around_delimiters=False)
INI
}

# Collected as the run goes, printed as a report at the end. Steps record what
# they actually did, not what they intended to do.
SUMMARY=()
report() { SUMMARY+=("$(printf '%-14s %s' "$1" "$2")"); }

# Every mutating command goes through this, so --dry-run is honest: if it isn't
# wrapped in run(), it doesn't change anything.
run() {
    if [[ $DRY_RUN -eq 1 ]]; then
        printf '   %s[dry-run]%s %s\n' "$YELLOW" "$RESET" "$*"
    else
        "$@"
    fi
}

usage() {
    cat <<EOF
Post-install setup for a fresh CachyOS or Omarchy box.

Usage: ./install.sh [options]

Options:
  --dry-run       Print every command that would run, change nothing
  --only STEP     Run one step only:
                    packages | flatpak | agenttilecli | streamhub | consolevault
                    discripper | griddown | gammagui | lorerim | wotlk
                    musicai | config | omarchy
  --skip-upgrade  Don't run 'pacman -Syu' first (not recommended — see below)
  --desktop D     Force the desktop instead of detecting it:
                    kde | omarchy | other
  -h, --help      This message

Steps:
  config          Enables the LACT daemon and puts ~/.local/bin on PATH. Both
                  are needed for a working setup, so they run by default —
                  there is nothing to do by hand after this script.
  omarchy         The Omarchy desktop: shell text size, bar layout and widgets,
                  the patched bar/tray plugins, theme and wallpaper, Hyprland
                  window rules, monitors and input. Skipped on any other
                  desktop.

Desktops:
  The desktop is detected, and the steps that only exist on one of them are
  gated on it. On KDE Plasma the Plasma panel and powerdevil steps run and the
  omarchy step is skipped. On Omarchy (Arch + Hyprland) it is the other way
  round — there is no Plasma panel to pin to, and powerdevil is not what
  handles idle there. Everything else is common to both: the signed [cachyos]
  repo is added on either (below Arch's, so Arch still wins every name
  collision) and the CachyOS-only packages install as they do anywhere. No AUR
  helper is used, or needed.

Notes:
  A full system upgrade runs first by default. On Arch-based systems that
  isn't optional busywork: installing a new package against a stale package
  database is a partial upgrade, and partial upgrades break things. Skip it
  only if you just upgraded.

Env:
  PROJECTS_DIR    Where to clone AgentTileCLI
                  (default: ~/Documents/Projects)
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)      DRY_RUN=1; shift ;;
        # Guard the arg count first: `shift 2` with only one argument left
        # returns non-zero, and set -e would then exit silently — no usage, no
        # error, nothing. `./install.sh --only` would just print nothing and fail.
        --only)         [[ $# -ge 2 ]] || die "--only needs a step (packages | flatpak | agenttilecli | streamhub | consolevault | discripper | griddown | gammagui | lorerim | wotlk | musicai | config | omarchy)"
                        ONLY="$2"; shift 2 ;;
        --skip-upgrade) SKIP_UPGRADE=1; shift ;;
        # Same arg-count guard as --only, for the same reason: `shift 2` with
        # one argument left returns non-zero, and set -e would then exit with
        # nothing printed at all.
        --desktop)      [[ $# -ge 2 ]] || die "--desktop needs one of: kde | omarchy | other"
                        DESKTOP_FORCED="$2"; shift 2 ;;
        -h|--help)      usage; exit 0 ;;
        *)              die "unknown option: $1 (try --help)" ;;
    esac
done

if [[ -n "$ONLY" ]]; then
    case "$ONLY" in
        packages|flatpak|agenttilecli|streamhub|consolevault|discripper|griddown|gammagui|lorerim|wotlk|musicai|config|omarchy) ;;
        *) die "--only takes: packages | flatpak | agenttilecli | streamhub | consolevault | discripper | griddown | gammagui | lorerim | wotlk | musicai | config | omarchy" ;;
    esac
fi
if [[ -n "$DESKTOP_FORCED" ]]; then
    case "$DESKTOP_FORCED" in
        kde|omarchy|other) ;;
        *) die "--desktop takes: kde | omarchy | other" ;;
    esac
fi
wanted() { [[ -z "$ONLY" || "$ONLY" == "$1" ]]; }
[[ -n "$ONLY" ]] && STEP_TOTAL=2      # preflight + the one requested step

# Strip inline #-comments, trailing whitespace and blank lines from a list file.
# Callers must check the file exists first — this runs inside a process
# substitution, where a die() here could not abort the parent shell.
read_list() {
    sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^$/d' "$1"
}

# ── preflight ─────────────────────────────────────────────────────────────────
preflight() {
    step "Preflight"

    [[ $EUID -ne 0 ]] || die "don't run this as root — it installs into your home dir. It'll ask for sudo when it needs it."
    have pacman || die "no pacman — this script is for Arch/CachyOS."
    have curl   || die "curl is not installed."
    have sudo   || die "sudo is not installed."
    # Used to verify StreamHub's sha512 and to merge Brave's Local State JSON.
    # It's part of the CachyOS base install, so this should never fire — but a
    # missing python would otherwise surface as a confusing checksum failure.
    have python || die "python is not installed (needed for checksum + JSON handling)."

    for f in "$PKG_DIR/pacman.txt" "$PKG_DIR/flatpak.txt"; do
        [[ -f "$f" ]] || die "missing package list: $f"
    done

    curl -fsS --max-time 10 -o /dev/null https://archlinux.org 2>/dev/null \
        || die "no network (couldn't reach archlinux.org)."
    ok "root check, pacman, curl, sudo, package lists, network"

    # Everything after this point asks "which desktop?" and "which repos?", so
    # settle both here — once, out loud, before the first thing is installed.
    # A run that quietly skipped the panel step because it guessed Omarchy on a
    # Plasma box would be a mystery; this line is what makes it not one.
    detect_desktop
    local repos
    if has_cachyos_repos; then repos="CachyOS repos"; else repos="Arch repos only"; fi
    if [[ -n "$DESKTOP_FORCED" ]]; then
        ok "desktop: $(desktop_label) (forced with --desktop) · $repos"
    else
        ok "desktop: $(desktop_label) · $repos"
    fi
    report "Detected" "$(desktop_label), $repos"
    if [[ "$DESKTOP" != kde ]]; then
        info "The Plasma panel and powerdevil steps will be skipped — nothing here to configure."
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        skip "dry run — no sudo needed, nothing will be changed"
        return
    fi

    # Grab sudo once up front so the script doesn't stall on a password prompt
    # 20 minutes in, then hold the timestamp open while the long builds run.
    #
    # Only prompt if sudo actually needs it. 'sudo -v' insists on a terminal
    # even when the user is NOPASSWD, which would make this script impossible to
    # run over SSH or from any non-interactive context — the -n probe first means
    # a passwordless or already-cached sudo sails straight through.
    if sudo -n true 2>/dev/null; then
        ok "sudo already available without a password"
    else
        info "Asking for sudo up front so nothing blocks later..."
        sudo -v || die "sudo failed (no terminal to prompt on? run this from a shell, or configure NOPASSWD)."
        ok "sudo cached"
    fi
    while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done 2>/dev/null &
    SUDO_KEEPALIVE=$!
    trap cleanup EXIT
}

# Runs however the script ends, including a crash.
cleanup() {
    [[ -n "${SUDO_KEEPALIVE:-}" ]] && kill "$SUDO_KEEPALIVE" 2>/dev/null

    # The taskbar step stops plasmashell so it can't overwrite the config we're
    # writing. If anything failed in between, the user is staring at a desktop
    # with NO PANEL and no obvious way to get it back. Always put it back.
    if [[ "${PLASMA_STOPPED:-0}" -eq 1 ]] && ! pgrep -x plasmashell >/dev/null 2>&1; then
        printf '   %s!%s restoring plasmashell after an error...\n' "$YELLOW" "$RESET" >&2
        systemctl --user start plasma-plasmashell.service 2>/dev/null \
            || { setsid plasmashell > /dev/null 2>&1 & }
    fi
    return 0
}

# ── 1. pacman packages ────────────────────────────────────────────────────────
install_packages() {
    step "Repo packages"

    if [[ $SKIP_UPGRADE -eq 1 ]]; then
        skip "system upgrade skipped (--skip-upgrade)"
    else
        info "Full system upgrade (avoids a partial-upgrade break)..."
        run sudo pacman -Syu --noconfirm
    fi

    ensure_cachyos_repo

    local pkgs=() extra=()
    mapfile -t pkgs < <(read_list "$PKG_DIR/pacman.txt")

    # The conditional lists. Both are additive: everything in pacman.txt goes on
    # every machine, and these only widen it. Skipping is a normal outcome and
    # is said out loud, because "Steam never got installed" is otherwise a very
    # quiet failure to notice three weeks later.
    if [[ ! -f "$PKG_DIR/pacman-cachyos.txt" ]]; then
        warn "missing $PKG_DIR/pacman-cachyos.txt — Brave, Vesktop and the gaming packages will NOT be installed"
    else
        mapfile -t extra < <(read_list "$PKG_DIR/pacman-cachyos.txt")
        if [[ ${#extra[@]} -gt 0 ]]; then
            if has_cachyos_repos; then
                pkgs+=("${extra[@]}")
            else
                # Only reachable when ensure_cachyos_repo could not add the repo
                # — it already said why, so this just records the consequence.
                skip "no CachyOS repos — skipping ${#extra[@]} CachyOS-only packages"
                report "Packages" "skipped (CachyOS repo unavailable): ${extra[*]}"
            fi
        fi
    fi

    if [[ ! -f "$PKG_DIR/pacman-kde.txt" ]]; then
        warn "missing $PKG_DIR/pacman-kde.txt — the Plasma-only packages will NOT be installed"
    else
        mapfile -t extra < <(read_list "$PKG_DIR/pacman-kde.txt")
        if [[ ${#extra[@]} -gt 0 ]]; then
            if [[ "$DESKTOP" == kde ]]; then
                pkgs+=("${extra[@]}")
            else
                skip "not KDE — skipping ${#extra[@]} Plasma-only packages"
                report "Packages" "skipped (not KDE): ${extra[*]}"
            fi
        fi
    fi

    [[ ${#pkgs[@]} -gt 0 ]] || { skip "no packages listed"; return; }

    # --needed makes this a no-op for anything already present, so most of
    # these get skipped on a CachyOS box that already ships them.
    info "Installing ${#pkgs[@]} packages (already-present ones are skipped)..."

    if [[ $DRY_RUN -eq 1 ]]; then
        run sudo pacman -S --needed --noconfirm "${pkgs[@]}"
        return 0
    fi

    # Diff the installed set around the transaction rather than parsing pacman's
    # output — that way the report says what actually landed, including the
    # dependencies pulled in behind the packages we asked for.
    local before after
    before="$(pacman -Qq | sort)"
    sudo pacman -S --needed --noconfirm "${pkgs[@]}"
    after="$(pacman -Qq | sort)"

    local new_all=() new_wanted=()
    mapfile -t new_all < <(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after"))

    local p
    for p in "${pkgs[@]}"; do
        printf '%s\n' "${new_all[@]}" | grep -qx "$p" && new_wanted+=("$p")
    done

    ok "repo packages installed"

    if [[ ${#new_all[@]} -eq 0 ]]; then
        report "Packages" "all ${#pkgs[@]} already present — nothing to do"
    else
        local deps=$(( ${#new_all[@]} - ${#new_wanted[@]} ))
        report "Packages" "${#new_wanted[@]} of ${#pkgs[@]} newly installed, plus $deps dependencies"
        # NOT `[[ ... ]] && report ...`. As the last command of the function that
        # would return 1 whenever new_wanted is empty (packages upgraded rather
        # than newly installed, say), and `set -e` would then kill the whole run
        # right here — no flatpaks, no apps, no config, no summary, no message.
        if [[ ${#new_wanted[@]} -gt 0 ]]; then
            report "" "${new_wanted[*]}"
        fi
    fi

    return 0
}

# CachyOS's signing key and repo, for boxes that don't have them — Omarchy is
# plain Arch, so `pacman -S cachyos-gaming-meta` there has nothing to install
# from. Adding the repo is what makes the CachyOS-only list work everywhere,
# and it is the whole reason there is no AUR list here: everything those five
# packages need is in a signed binary repo, which beats building from unreviewed
# PKGBUILDs.
#
# The key detail is WHERE the repo goes, and it is worth being emphatic about.
#
# CachyOS's own cachyos-repo.sh inserts [cachyos] ABOVE core/extra/multilib (and
# switches Architecture to auto, pulling the v3/v4 repos as well). That is right
# for CachyOS, where the optimised rebuilds are the entire point. It is very
# wrong here: the cachyos repo shares 90 package names with Arch's, among them
# pacman, mesa, linux-firmware, mkinitcpio, sddm, xz and zstd. Ordered first, the
# next `pacman -Syu` — which omarchy-update runs on its own — starts replacing
# Omarchy's base system with CachyOS builds. That is a conversion, not a package
# source, and nobody asked for it.
#
# So the section is APPENDED, landing after every existing repo. Pacman resolves
# a name from the first repo that has it, so Arch wins every one of those 90
# collisions and the only things that come from here are the ones Arch does not
# carry at all: the two gaming metapackages, brave-origin-bin, vesktop,
# protonup-qt, and the proton/wine/heroic builds they depend on.
CACHYOS_KEY="F3B607488DB35A47"
CACHYOS_KEYSERVER="keyserver.ubuntu.com"
CACHYOS_MIRROR='https://cdn77.cachyos.org/repo/$arch/$repo'
ensure_cachyos_repo() {
    has_cachyos_repos && { skip "CachyOS repos already configured"; return 0; }

    local conf="/etc/pacman.conf"
    local mirrorlist="/etc/pacman.d/cachyos-mirrorlist"

    info "No CachyOS repos — adding them so the CachyOS-only packages can install..."

    if [[ $DRY_RUN -eq 1 ]]; then
        run "sudo pacman-key --recv-keys $CACHYOS_KEY --keyserver $CACHYOS_KEYSERVER"
        run "sudo pacman-key --lsign-key $CACHYOS_KEY"
        run "sudo write $mirrorlist"
        run "sudo append [cachyos] to $conf (AFTER core/extra/multilib, so Arch wins every name collision)"
        run "sudo pacman -Sy"
        report "CachyOS repo" "would add the signed [cachyos] repo, ordered below Arch's"
        # A dry run has to predict the real run. Without this the CachyOS-only
        # list is reported as skipped — true of the dry run, which changed
        # nothing, but the opposite of what a real run does two lines later.
        CACHYOS_REPOS=1
        return 0
    fi

    # The key first. If this fails nothing has been touched yet, which is the
    # point of doing it first: a pacman.conf naming a repo whose packages can't
    # be verified makes every later pacman call fail, including the ones that
    # would fix it.
    if ! sudo pacman-key --recv-keys "$CACHYOS_KEY" --keyserver "$CACHYOS_KEYSERVER" >/dev/null 2>&1; then
        warn "couldn't fetch CachyOS's signing key from $CACHYOS_KEYSERVER — leaving pacman.conf alone"
        report "CachyOS repo" "FAILED (no signing key) — the CachyOS-only packages will be skipped"
        return 0
    fi
    if ! sudo pacman-key --lsign-key "$CACHYOS_KEY" >/dev/null 2>&1; then
        warn "couldn't locally sign CachyOS's key — leaving pacman.conf alone"
        report "CachyOS repo" "FAILED (key not signed) — the CachyOS-only packages will be skipped"
        return 0
    fi

    # One mirror, not the full generated list. This is a bootstrap: the real
    # cachyos-mirrorlist package is installed from the repo below and overwrites
    # this file with the maintained list.
    printf '# Bootstrapped by arch-setup; replaced by the cachyos-mirrorlist package.\nServer = %s\n' \
        "$CACHYOS_MIRROR" | sudo tee "$mirrorlist" >/dev/null

    # Keeps the old name after the repo was renamed to arch-setup: machines
    # provisioned before the rename already have this file, and the README's
    # undo instructions point at it. A new name would just orphan both.
    sudo cp -n "$conf" "$conf.before-cachyos-setup" 2>/dev/null || true

    # multilib before cachyos, because cachyos-gaming-applications pulls steam
    # and lib32-mangohud and pacman fails the whole transaction without them.
    # Uncommented in place, so it keeps its position above the appended section.
    if ! pacman-conf --repo-list 2>/dev/null | grep -qx multilib; then
        info "Enabling the multilib repo (Steam and the lib32 packages live there)..."
        sudo sed -i 's/^#\[multilib\]$/[multilib]/; /^\[multilib\]$/{n; s|^#Include = /etc/pacman.d/mirrorlist$|Include = /etc/pacman.d/mirrorlist|}' "$conf"
        pacman-conf --repo-list 2>/dev/null | grep -qx multilib \
            || warn "couldn't enable multilib — Steam and the lib32 packages will be skipped"
    fi

    printf '\n# Added by arch-setup. Deliberately LAST: pacman takes a package from the\n# first repo that has it, so every name Arch also carries still comes from Arch.\n[cachyos]\nInclude = %s\n' \
        "$mirrorlist" | sudo tee -a "$conf" >/dev/null

    if ! sudo pacman -Sy >/dev/null 2>&1; then
        warn "pacman couldn't sync the new CachyOS repo — restoring $conf"
        sudo cp "$conf.before-cachyos-setup" "$conf" 2>/dev/null || true
        report "CachyOS repo" "FAILED (sync) — pacman.conf restored"
        CACHYOS_REPOS=""
        return 0
    fi

    # Hand the mirrorlist and keyring over to their real packages, so they are
    # tracked and updated like anything else rather than frozen at whatever this
    # script wrote today.
    sudo pacman -S --needed --noconfirm cachyos-keyring cachyos-mirrorlist >/dev/null 2>&1 \
        || warn "couldn't install cachyos-keyring/cachyos-mirrorlist — the repo works, but won't self-update"

    CACHYOS_REPOS=""          # re-detect: has_cachyos_repos cached the old answer
    if has_cachyos_repos; then
        ok "CachyOS repo added, ordered below Arch's (Arch wins every name collision)"
        report "CachyOS repo" "[cachyos] added below core/extra/multilib"
    else
        warn "added [cachyos] but pacman still doesn't list it — check $conf"
        report "CachyOS repo" "added but not visible to pacman — check $conf"
    fi
    return 0
}

# ── 2. flatpaks ───────────────────────────────────────────────────────────────
install_flatpaks() {
    step "Flatpaks"

    # flatpak is NOT on a stock CachyOS install, so pacman.txt installs it. If
    # it's missing here, the package step was skipped (--only flatpak) rather
    # than anything being broken.
    have flatpak || die "flatpak is not installed — run the packages step first (it's in packages/pacman.txt)."

    local apps_dry=()
    if [[ $DRY_RUN -eq 1 ]]; then
        # Even read-only flatpak queries ('remotes', 'info') scaffold
        # ~/.local/share/flatpak and ~/.cache/flatpak on first use. That's a
        # filesystem change, and a dry run promises not to make any — so in dry
        # mode we don't invoke flatpak at all, we just say what we'd do.
        run sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
        mapfile -t apps_dry < <(read_list "$PKG_DIR/flatpak.txt")
        local a
        for a in "${apps_dry[@]}"; do
            run sudo flatpak install -y --noninteractive flathub "$a"
        done
        return
    fi

    # --system, not the default (which lists user AND system remotes). We install
    # system-wide, so a Flathub remote that exists only in the *user* scope — as
    # Discover tends to add it — would satisfy an unscoped check while the system
    # install still fails with "Remote 'flathub' not found".
    #
    # remote-add --if-not-exists is idempotent anyway; the check is only here so
    # a re-run can say "already configured" instead of silently doing nothing.
    if flatpak remotes --system --columns=name 2>/dev/null | grep -qx flathub; then
        skip "Flathub remote already configured"
    else
        info "Adding Flathub remote..."
        run sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    fi

    local apps=()
    mapfile -t apps < <(read_list "$PKG_DIR/flatpak.txt")
    [[ ${#apps[@]} -gt 0 ]] || { skip "no flatpaks listed"; return; }

    local app installed=() already=()
    for app in "${apps[@]}"; do
        if flatpak info "$app" >/dev/null 2>&1; then
            skip "$app (already installed)"
            already+=("$app")
        else
            info "Installing $app..."
            installed+=("$app")
            # As root, deliberately. A system-scope install is a privileged
            # operation that flatpak routes through polkit, and polkit needs an
            # interactive agent — so an unprivileged 'flatpak install' dies with
            # "Deploy not allowed for user" over SSH, and pops an auth dialog
            # mid-run on a desktop. sudo sidesteps both.
            run sudo flatpak install -y --noninteractive flathub "$app"
            ok "$app"
        fi
    done

    if [[ ${#installed[@]} -gt 0 ]]; then
        report "Flatpaks" "installed ${installed[*]}"
    else
        report "Flatpaks" "already present (${already[*]})"
    fi
}

# ── 3. AgentTileCLI (build from source) ───────────────────────────────────────
# Rust + GTK4/VTE4. Its own install.sh builds the release binary and drops a
# .desktop file + icon into ~/.local. We clone to a permanent path because the
# app's "check for updates" pulls and rebuilds from this same clone.
install_agenttilecli() {
    step "AgentTileCLI"

    ensure_claude_cli
    ensure_codex_cli

    local dir="$PROJECTS_DIR/agenttilecli"
    run mkdir -p "$PROJECTS_DIR"

    if [[ -d "$dir/.git" ]]; then
        info "Clone exists — pulling latest..."
        # Fast-forward only. Local commits, a dev branch or uncommitted work
        # make this refuse rather than clobber anything.
        if ! run git -C "$dir" pull --ff-only; then
            warn "couldn't fast-forward $dir (local changes or a dev branch?) — building what's already there"
        fi
    else
        info "Cloning into $dir..."
        run git clone "$AGENTTILE_REPO" "$dir"
    fi

    info "Building (cargo release build — takes a few minutes)..."
    # Its install.sh checks for cargo/gtk4/vte4 itself and reports what's missing.
    #
    # stdin from /dev/null on purpose. That script offers to install the `claude`
    # CLI when it's absent, and only prompts if stdin is a terminal — so it sails
    # through a piped/SSH run but BLOCKS FOREVER when a human runs this from a
    # real shell, which is the normal case. ensure_claude_cli above means the
    # prompt shouldn't fire at all; </dev/null guarantees that neither it nor any
    # prompt it grows later can ever hang an unattended install.
    if [[ $DRY_RUN -eq 1 ]]; then
        run "(cd $dir && ./install.sh)"
    else
        ( cd "$dir" && ./install.sh < /dev/null )
    fi
    ok "AgentTileCLI installed to $BIN_DIR/agenttilecli"

    local commit="unknown"
    [[ $DRY_RUN -eq 0 ]] && commit="$(git -C "$dir" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    report "AgentTileCLI" "built from source ($commit) → $BIN_DIR/agenttilecli"
    report "" "clone kept at $dir (its updater rebuilds from here)"
}

# Find the applet id declaring a given plugin inside a containment.
#
# Uses index() rather than a regex: the group headers are full of [ ] and awk -v
# runs its OWN escape processing over -v values, so a "\[" written here arrives
# at awk as a bare "[" and the regex blows up as an unbalanced bracket. Plain
# string matching sidesteps the whole problem.
applet_id_for() {
    local conf="$1" cont="$2" plugin="$3"
    awk -v pfx="[Containments][$cont][Applets][" -v want="plugin=$plugin" '
        /^\[/ {
            a = ""
            if (index($0, pfx) == 1) {
                rest = substr($0, length(pfx) + 1)
                # Only a direct applet group, e.g. "[...][Applets][39]" — not a
                # sub-group like "[...][Applets][39][Configuration]".
                if (rest ~ /^[0-9]+\]$/) { sub(/\]$/, "", rest); a = rest }
            }
            next
        }
        a != "" && $0 == want { print a; exit }
    ' "$conf"
}

# Delete the widgets in PANEL_REMOVE from the panel.
#
# An applet lives in a group plus any number of sub-groups, and its id is also
# listed in the containment's AppletOrder — leave the id in AppletOrder after
# deleting the group and Plasma logs an error and can drop the panel. Both have
# to go.
panel_remove_widgets() {
    local conf="$1" cont="$2"
    [[ ${#PANEL_REMOVE[@]} -gt 0 ]] || return 0

    local plug id order removed=()
    for plug in "${PANEL_REMOVE[@]}"; do
        id="$(applet_id_for "$conf" "$cont" "$plug")"
        [[ -n "$id" ]] || continue

        # Rewrite AppletOrder FIRST, then delete the group.
        #
        # Order matters: an id left in AppletOrder whose group no longer exists is
        # the state that makes Plasma log an error and drop the panel. If we die
        # between the two operations, better to have an unused id still listed
        # (harmless — Plasma ignores it) than a dangling reference.
        order="$(kreadconfig6 --file "$conf" --group Containments --group "$cont" \
                    --group General --key AppletOrder 2>/dev/null || true)"
        if [[ -n "$order" ]]; then
            # `|| true`: grep -v exits 1 when it filters out EVERY line, which
            # happens when this applet is the only one in the list. Under pipefail
            # that would kill the script mid-surgery.
            order="$(tr ';' '\n' <<<"$order" | grep -vx "$id" | paste -sd';' - || true)"
            kwriteconfig6 --file "$conf" --group Containments --group "$cont" \
                --group General --key AppletOrder "$order"
        fi

        # Now drop the applet's group and every sub-group of it.
        #
        # mktemp INSIDE the config's own directory, not /tmp: /tmp is tmpfs and
        # $HOME is btrfs here, so `mv` across them is a copy+unlink rather than an
        # atomic rename(2) — an interrupt mid-copy would leave the Plasma config
        # truncated, at the exact moment plasmashell is stopped and can't help.
        # Same-filesystem mv is atomic. chmod --reference keeps the original 644
        # rather than mktemp's 600.
        local tmp
        tmp="$(mktemp "$conf.XXXXXX")" || { warn "couldn't create a temp file — skipping widget removal"; return 0; }
        if awk -v pfx="[Containments][$cont][Applets][$id]" '
                /^\[/ { skip = (index($0, pfx) == 1) }
                !skip
            ' "$conf" > "$tmp"
        then
            chmod --reference="$conf" "$tmp" 2>/dev/null || true
            mv -f "$tmp" "$conf"
            removed+=("$plug")
        else
            rm -f "$tmp"
            warn "couldn't rewrite the Plasma config — left $plug in place"
        fi
    done

    [[ ${#removed[@]} -gt 0 ]] && ok "removed from panel: ${removed[*]##*.}"
    return 0
}

# Tuck TRAY_HIDDEN items behind the system tray's expander arrow.
tray_hide_items() {
    local conf="$1" cont="$2"
    [[ ${#TRAY_HIDDEN[@]} -gt 0 ]] || return 0

    # The system tray is itself an applet of the panel.
    local tray
    tray="$(applet_id_for "$conf" "$cont" org.kde.plasma.systemtray)"
    [[ -n "$tray" ]] || { warn "no system tray applet found — not hiding tray items"; return 0; }

    local hidden
    hidden="$(IFS=,; echo "${TRAY_HIDDEN[*]}")"

    # Note the group is [...][Applets][N][General], NOT [Configuration][General]
    # like most applets — the system tray is a containment in its own right.
    kwriteconfig6 --file "$conf" \
        --group Containments --group "$cont" \
        --group Applets --group "$tray" \
        --group General \
        --key hiddenItems "$hidden"

    ok "hidden in system tray: ${TRAY_HIDDEN[*]##*.}"
    return 0
}

# AgentTileCLI launches `claude` in every pane, so without it the app opens to a
# grid of "command not found". Install it up front rather than letting
# AgentTileCLI's own installer stop and ask.
ensure_claude_cli() {
    if have claude; then
        skip "claude CLI already installed"
        return
    fi

    info "Installing the claude CLI (AgentTileCLI runs it in every pane)..."
    if [[ $DRY_RUN -eq 1 ]]; then
        run "curl -fsSL https://claude.ai/install.sh | bash"
        return
    fi

    if curl -fsSL https://claude.ai/install.sh | bash; then
        # It installs to ~/.local/bin, which isn't on PATH yet this early in the
        # run — export it so the AgentTileCLI installer's own `have claude` check
        # finds it and stays quiet.
        export PATH="$BIN_DIR:$PATH"
        ok "claude CLI installed"
    else
        warn "claude CLI install failed — AgentTileCLI's panes won't work until you run:"
        warn "    curl -fsSL https://claude.ai/install.sh | bash"
    fi
}

# Keep Codex available alongside Claude.  It is not required to build
# AgentTileCLI, but it is part of the developer-tool setup this script provides.
ensure_codex_cli() {
    if have codex; then
        skip "Codex CLI already installed"
        return
    fi

    info "Installing the Codex CLI..."
    if [[ $DRY_RUN -eq 1 ]]; then
        run "curl -fsSL https://chatgpt.com/codex/install.sh | sh"
        return
    fi

    if curl -fsSL https://chatgpt.com/codex/install.sh | sh; then
        # Like Claude, Codex installs to ~/.local/bin. It is not on PATH yet this
        # early in the run, so make the command available to the remaining steps.
        export PATH="$BIN_DIR:$PATH"
        ok "Codex CLI installed"
    else
        warn "Codex CLI install failed — install it later with:"
        warn "    curl -fsSL https://chatgpt.com/codex/install.sh | sh"
    fi
}

# ── 4. StreamHub (prebuilt AppImage) ──────────────────────────────────────────
# Fetched from GitHub Releases rather than built: the release AppImage bundles
# castLabs Electron (Widevine), which is what makes Netflix/Prime actually play.
# The app updates itself in place afterwards, so this normally runs once — but
# it's version-stamped, so a re-run still picks up a newer release if there is one.
install_streamhub() {
    step "StreamHub"

    local stamp="$STREAMHUB_DIR/.version"
    local release tag url

    info "Checking latest release..."
    release="$(github_api "https://api.github.com/repos/$STREAMHUB_REPO/releases/latest")" \
        || die "couldn't fetch the latest release from GitHub."
    # `|| true` is load-bearing. grep exits 1 when it matches nothing, pipefail
    # propagates that to the assignment, and set -e then kills the script BEFORE
    # the checks below can run — so a renamed or pulled asset would exit 1 with
    # no diagnostic at all, instead of the clear message we wrote for exactly
    # that case.
    tag="$(printf '%s' "$release" | grep -m1 '"tag_name"' | cut -d'"' -f4 || true)"
    url="$(printf '%s' "$release" | grep -o 'https://[^"]*/StreamHub\.AppImage' | head -1 || true)"

    [[ -n "$tag" ]] || die "couldn't read a tag from the latest release."
    [[ -n "$url" ]] || die "no StreamHub.AppImage asset in release $tag."

    if [[ -f "$STREAMHUB_APPIMAGE" && -f "$stamp" ]] && [[ "$(cat "$stamp")" == "$tag" ]]; then
        skip "StreamHub $tag already installed (it self-updates from here on)"

        # Don't just return — repair the launcher if it's gone. Otherwise deleting
        # the .desktop file (or having the icon fetch fail on an earlier run)
        # leaves you permanently unable to get it back: the version stamp still
        # matches, so every future run skips straight past this.
        if [[ ! -f "$APPS_DIR/com.streamhub.app.desktop" || ! -f "$STREAMHUB_DIR/icon.png" ]]; then
            info "Launcher missing — recreating it..."
            mkdir -p "$APPS_DIR" "$STREAMHUB_DIR"
            [[ -f "$STREAMHUB_DIR/icon.png" ]] || curl -fsSL -o "$STREAMHUB_DIR/icon.png" \
                "https://raw.githubusercontent.com/$STREAMHUB_REPO/master/assets/icon.png" \
                || warn "couldn't fetch the icon"
            write_streamhub_desktop
            refresh_desktop_db
            ok "launcher recreated"
        fi

        # Outside the repair branch above on purpose: that only fires when ours
        # is missing or stale, and a stray can sit beside a perfectly good one.
        prune_competing_launchers "com.streamhub.app.desktop"

        report "StreamHub" "$tag already installed"
        return
    fi

    run mkdir -p "$BIN_DIR" "$STREAMHUB_DIR" "$APPS_DIR"

    info "Downloading StreamHub $tag..."
    # Download to a temp file beside the target, then move into place, so an
    # interrupted download can't leave a half-written AppImage that still looks
    # runnable — and so a failed update can't destroy a working install.
    local tmp="$STREAMHUB_APPIMAGE.partial"
    if [[ $DRY_RUN -eq 1 ]]; then
        run curl -fL --progress-bar -o "$tmp" "$url"
        run "verify sha512 against the release's latest-linux.yml"
        run chmod +x "$tmp"
        run mv -f "$tmp" "$STREAMHUB_APPIMAGE"
        run curl -fsSL -o "$STREAMHUB_DIR/icon.png" "https://raw.githubusercontent.com/$STREAMHUB_REPO/master/assets/icon.png"
        run "write $APPS_DIR/com.streamhub.app.desktop"
        prune_competing_launchers "com.streamhub.app.desktop"
        run "stamp version $tag"
    else
        curl -fL --progress-bar -o "$tmp" "$url" || { rm -f "$tmp"; die "download failed."; }

        # Verify before making it executable.
        #
        # This is a 130MB binary fetched off the internet and then run with your
        # user's full privileges. electron-builder publishes a sha512 for it in
        # latest-linux.yml alongside the release, so there is no good reason to
        # take the download on trust. A mismatch means a corrupt download or a
        # tampered asset; either way we stop rather than chmod +x it.
        verify_streamhub "$tmp" "$tag" || { rm -f "$tmp"; die "StreamHub download could not be verified — refusing to install it."; }

        chmod +x "$tmp"
        mv -f "$tmp" "$STREAMHUB_APPIMAGE"

        curl -fsSL -o "$STREAMHUB_DIR/icon.png" \
            "https://raw.githubusercontent.com/$STREAMHUB_REPO/master/assets/icon.png" \
            || warn "couldn't fetch the icon — the launcher entry will fall back to a generic one"

        write_streamhub_desktop
        prune_competing_launchers "com.streamhub.app.desktop"
        printf '%s\n' "$tag" > "$stamp"
        refresh_desktop_db
    fi

    ok "StreamHub $tag installed to $STREAMHUB_APPIMAGE"
    report "StreamHub" "$tag (prebuilt AppImage) → $STREAMHUB_APPIMAGE"
}

# Check the downloaded AppImage against the sha512 the release publishes in
# latest-linux.yml. Returns non-zero if it doesn't match, or if the checksum
# can't be fetched at all — "couldn't verify" is not the same as "verified", and
# is not a good enough reason to run the binary anyway.
verify_streamhub() {
    local file="$1" tag="$2"
    local yml expected

    yml="$(curl -fsSL "https://github.com/$STREAMHUB_REPO/releases/download/$tag/latest-linux.yml" 2>/dev/null)" \
        || { warn "couldn't fetch latest-linux.yml — cannot verify the download"; return 1; }

    # The sha512 is base64, not hex, which is what electron-builder emits.
    expected="$(grep -m1 '^sha512:' <<<"$yml" | awk '{print $2}')"
    [[ -n "$expected" ]] || { warn "no sha512 in latest-linux.yml"; return 1; }

    local actual
    actual="$(python - "$file" <<'PY'
import base64, hashlib, sys
h = hashlib.sha512()
with open(sys.argv[1], "rb") as f:
    for chunk in iter(lambda: f.read(1 << 20), b""):
        h.update(chunk)
print(base64.b64encode(h.digest()).decode())
PY
)" || { warn "couldn't compute the checksum"; return 1; }

    if [[ "$actual" == "$expected" ]]; then
        ok "checksum verified (sha512)"
        return 0
    fi

    warn "CHECKSUM MISMATCH — the download does not match the published sha512"
    warn "  expected: $expected"
    warn "  got:      $actual"
    return 1
}

# Icon is referenced by absolute path rather than a themed name, which sidesteps
# having to guess which hicolor size directory the source PNG belongs in.
write_streamhub_desktop() {
    cat > "$APPS_DIR/com.streamhub.app.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=StreamHub
Comment=Netflix, Prime Video, Disney+, Max, Hulu and YouTube in one app
Exec=$STREAMHUB_APPIMAGE
Icon=$STREAMHUB_DIR/icon.png
Terminal=false
Categories=AudioVideo;Video;Player;
StartupNotify=true
StartupWMClass=StreamHub
EOF
}

# KDE keeps its own application-menu index; without kbuildsycoca a new .desktop
# file may not appear in the menu or KRunner until the next login.
refresh_desktop_db() {
    have update-desktop-database && update-desktop-database "$APPS_DIR" >/dev/null 2>&1 || true
    have kbuildsycoca6           && kbuildsycoca6 >/dev/null 2>&1 || true
    return 0
}

# KDE binds a window to a launcher by StartupWMClass. A .desktop left behind by
# a manual install of the same app claims the class we write, and the taskbar
# takes whichever it finds first — when that's the stray, the pinned icon never
# lights up and the app opens a second entry beside it. Ours is the one the
# panel is pinned to and the one that tracks the AppImage this script manages,
# so any other launcher claiming the class goes.
prune_competing_launchers() {
    local keep="$1" f removed=0 wmclass
    [[ -d "$APPS_DIR" ]] || return 0

    # Read the class off the launcher being kept rather than repeating the
    # literal at all seven call sites. 63b72a5 is the standing reminder that
    # these drift: GridDown's went from GridDown to griddown, and a call site
    # left on the old value would delete the very launcher it means to protect.
    # No launcher, or one carrying no class, means nothing to compare against —
    # prune nothing rather than let an empty class match loosely.
    #
    # The -f test has to come first, not just be implied by an empty $wmclass:
    # sed exits 2 on a missing file, pipefail hands that to the assignment, and
    # set -e kills the whole run before the -n check below is ever reached. That
    # is exactly the dry-run path — nothing writes the launcher, so it is always
    # missing — on any box where $APPS_DIR itself exists, which is every box that
    # has run this script once. Every app here calls this, so it took until one
    # of them was new on an already-set-up machine for it to show.
    [[ -f "$APPS_DIR/$keep" ]] || return 0
    wmclass="$(sed -n 's/^StartupWMClass=//p' "$APPS_DIR/$keep" 2>/dev/null | head -1)"
    [[ -n "$wmclass" ]] || return 0

    for f in "$APPS_DIR"/*.desktop; do
        [[ -f "$f" ]] || continue                       # no match — the glob stayed literal
        [[ "${f##*/}" == "$keep" ]] && continue
        # -F: every class here contains a dot, and an unescaped dot in a regex
        # matches any character — enough to delete a different app's launcher.
        grep -qxF "StartupWMClass=$wmclass" "$f" || continue
        if [[ $DRY_RUN -eq 1 ]]; then
            run "rm $f (claims StartupWMClass=$wmclass — splits the taskbar icon with $keep)"
        elif rm -f "$f"; then
            removed=1
            warn "removed ${f##*/} — it claimed the same window class as $keep, which split the taskbar icon"
        else
            warn "couldn't remove ${f##*/} — it claims the same window class as $keep, so the taskbar icon may still split"
        fi
    done
    [[ $removed -eq 1 ]] && refresh_desktop_db
    return 0
}

# ── 5. ConsoleVault (prebuilt AppImage) ───────────────────────────────────────
# A Tauri launcher for a physical ROM collection (SNES/N64/PS1/PS2/PS3). Like
# StreamHub it's a self-updating AppImage fetched from GitHub Releases, so this
# normally runs once but is version-stamped to pick up a newer release on re-run.
install_consolevault() {
    step "ConsoleVault"

    local stamp="$CONSOLEVAULT_DIR/.version"
    local release tag url

    info "Checking latest release..."
    release="$(github_api "https://api.github.com/repos/$CONSOLEVAULT_REPO/releases/latest")" \
        || die "couldn't fetch the latest release from GitHub."
    # `|| true` guards against grep's exit-1-on-no-match tripping pipefail+set -e
    # before we can print the clear message below — same reasoning as StreamHub.
    tag="$(printf '%s' "$release" | grep -m1 '"tag_name"' | cut -d'"' -f4 || true)"
    # The trailing `"` in the pattern is what keeps this from also matching the
    # sibling `..._amd64.AppImage.sig` asset URL.
    url="$(printf '%s' "$release" | grep -o 'https://[^"]*_amd64\.AppImage"' | head -1 | tr -d '"' || true)"

    [[ -n "$tag" ]] || die "couldn't read a tag from the latest release."
    [[ -n "$url" ]] || die "no ConsoleVault _amd64.AppImage asset in release $tag."

    if [[ -f "$CONSOLEVAULT_APPIMAGE" && -f "$stamp" ]] && [[ "$(cat "$stamp")" == "$tag" ]]; then
        skip "ConsoleVault $tag already installed (it self-updates from here on)"

        # Same launcher-repair logic as StreamHub: a matching version stamp would
        # otherwise skip this step forever, stranding a deleted .desktop/icon.
        if [[ ! -f "$APPS_DIR/com.consolevault.app.desktop" || ! -f "$CONSOLEVAULT_DIR/icon.png" ]]; then
            info "Launcher missing — recreating it..."
            mkdir -p "$APPS_DIR" "$CONSOLEVAULT_DIR"
            [[ -f "$CONSOLEVAULT_DIR/icon.png" ]] || curl -fsSL -o "$CONSOLEVAULT_DIR/icon.png" \
                "https://raw.githubusercontent.com/$CONSOLEVAULT_REPO/main/src-tauri/icons/icon.png" \
                || warn "couldn't fetch the icon"
            write_consolevault_desktop
            refresh_desktop_db
            ok "launcher recreated"
        fi

        # Outside the repair branch above on purpose: that only fires when ours
        # is missing or stale, and a stray can sit beside a perfectly good one.
        prune_competing_launchers "com.consolevault.app.desktop"

        report "ConsoleVault" "$tag already installed"
        return
    fi

    run mkdir -p "$BIN_DIR" "$CONSOLEVAULT_DIR" "$APPS_DIR"

    info "Downloading ConsoleVault $tag..."
    # Temp file beside the target, moved into place only after it verifies — an
    # interrupted download or a failed update never leaves a half-written or
    # unverified AppImage where a runnable one used to be.
    local tmp="$CONSOLEVAULT_APPIMAGE.partial"
    if [[ $DRY_RUN -eq 1 ]]; then
        run curl -fL --progress-bar -o "$tmp" "$url"
        run "verify minisign signature against the embedded public key"
        run chmod +x "$tmp"
        run mv -f "$tmp" "$CONSOLEVAULT_APPIMAGE"
        run curl -fsSL -o "$CONSOLEVAULT_DIR/icon.png" "https://raw.githubusercontent.com/$CONSOLEVAULT_REPO/main/src-tauri/icons/icon.png"
        run "write $APPS_DIR/com.consolevault.app.desktop"
        prune_competing_launchers "com.consolevault.app.desktop"
        run "stamp version $tag"
    else
        curl -fL --progress-bar -o "$tmp" "$url" || { rm -f "$tmp"; die "download failed."; }

        # Verify before making it executable. This is an 80MB binary pulled off
        # the internet and then run with your user's full privileges. Tauri signs
        # every release with minisign and embeds the matching public key in the
        # app source, so there's no reason to trust the download blind. A bad
        # signature means a corrupt or tampered asset — we stop, we don't chmod it.
        verify_consolevault "$tmp" "$url" || { rm -f "$tmp"; die "ConsoleVault download could not be verified — refusing to install it."; }

        chmod +x "$tmp"
        mv -f "$tmp" "$CONSOLEVAULT_APPIMAGE"

        curl -fsSL -o "$CONSOLEVAULT_DIR/icon.png" \
            "https://raw.githubusercontent.com/$CONSOLEVAULT_REPO/main/src-tauri/icons/icon.png" \
            || warn "couldn't fetch the icon — the launcher entry will fall back to a generic one"

        write_consolevault_desktop
        prune_competing_launchers "com.consolevault.app.desktop"
        printf '%s\n' "$tag" > "$stamp"
        refresh_desktop_db
    fi

    ok "ConsoleVault $tag installed to $CONSOLEVAULT_APPIMAGE"
    report "ConsoleVault" "$tag (prebuilt AppImage) → $CONSOLEVAULT_APPIMAGE"
}

# Verify the AppImage against the minisign signature the release publishes next to
# it (…AppImage.sig), using the public key baked into this script. Returns
# non-zero if the signature is missing, malformed, or doesn't match — "couldn't
# check" is treated exactly like "failed", never like "passed".
verify_consolevault() {
    local file="$1" url="$2"

    # minisign isn't in the CachyOS base install. It's listed in packages/pacman.txt
    # so a normal run already has it, but `--only consolevault` can reach here
    # without the packages step, so pull it in on the fly rather than failing.
    if ! have minisign; then
        info "Installing minisign (needed to verify the download)..."
        run sudo pacman -S --needed --noconfirm minisign \
            || { warn "couldn't install minisign — cannot verify the download"; return 1; }
    fi

    # Tauri publishes the .sig as base64 of the actual minisign signature file, so
    # it has to be decoded before minisign will read it.
    local sig="$file.minisig"
    curl -fsSL "$url.sig" 2>/dev/null | base64 -d > "$sig" 2>/dev/null \
        || { warn "couldn't fetch/decode the .sig — cannot verify the download"; rm -f "$sig"; return 1; }
    [[ -s "$sig" ]] || { warn "empty signature — cannot verify the download"; rm -f "$sig"; return 1; }

    # -P takes the public key string directly, so there's no temp keyfile to clean
    # up. minisign auto-detects the prehashed (Tauri) signature format.
    if minisign -Vm "$file" -x "$sig" -P "$CONSOLEVAULT_PUBKEY" >/dev/null 2>&1; then
        rm -f "$sig"
        ok "signature verified (minisign)"
        return 0
    fi

    rm -f "$sig"
    warn "SIGNATURE MISMATCH — the download does not match the published minisign signature"
    return 1
}

write_consolevault_desktop() {
    cat > "$APPS_DIR/com.consolevault.app.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=ConsoleVault
Comment=Launcher for your own physical ROM collection (SNES, N64, PS1, PS2, PS3)
Exec=$CONSOLEVAULT_APPIMAGE
Icon=$CONSOLEVAULT_DIR/icon.png
Terminal=false
Categories=Game;Emulator;
StartupNotify=true
StartupWMClass=ConsoleVault
EOF
}

# ── 6. Disc Ripper (prebuilt AppImage) ────────────────────────────────────────
# A PySide6/Qt app that auto-detects a disc, rips it to H.265 and names the output
# for Plex/Jellyfin. Same shape as StreamHub/ConsoleVault — a GitHub-Releases
# AppImage under a stable name — but its release ships no signature or checksum, so
# it's verified against the SHA-1/length in the sibling .zsync (integrity, not a
# signature; see the note by DISCRIPPER_* above). Version-stamped so a re-run picks
# up a newer release.
install_discripper() {
    step "Disc Ripper"

    local stamp="$DISCRIPPER_DIR/.version"
    local release tag url

    info "Checking latest release..."
    release="$(github_api "https://api.github.com/repos/$DISCRIPPER_REPO/releases/latest")" \
        || die "couldn't fetch the latest release from GitHub."
    # `|| true` guards against grep's exit-1-on-no-match tripping pipefail+set -e
    # before the clear messages below can run — same reasoning as StreamHub.
    tag="$(printf '%s' "$release" | grep -m1 '"tag_name"' | cut -d'"' -f4 || true)"
    # The trailing `"` keeps this from also matching the sibling ...AppImage.zsync
    # asset URL, whose value continues past `.AppImage` before its closing quote.
    url="$(printf '%s' "$release" | grep -o 'https://[^"]*/DiscRipper\.AppImage"' | head -1 | tr -d '"' || true)"

    [[ -n "$tag" ]] || die "couldn't read a tag from the latest release."
    [[ -n "$url" ]] || die "no DiscRipper.AppImage asset in release $tag."

    if [[ -f "$DISCRIPPER_APPIMAGE" && -f "$stamp" ]] && [[ "$(cat "$stamp")" == "$tag" ]]; then
        skip "Disc Ripper $tag already installed"

        # Same launcher-repair path as the others: a matching stamp would otherwise
        # skip this step forever, stranding a deleted .desktop or icon.
        if [[ ! -f "$APPS_DIR/com.discripper.app.desktop" || ! -f "$DISCRIPPER_DIR/icon.png" ]]; then
            info "Launcher missing — recreating it..."
            mkdir -p "$APPS_DIR" "$DISCRIPPER_DIR"
            [[ -f "$DISCRIPPER_DIR/icon.png" ]] || curl -fsSL -o "$DISCRIPPER_DIR/icon.png" \
                "https://raw.githubusercontent.com/$DISCRIPPER_REPO/main/src/discripper/resources/icon.png" \
                || warn "couldn't fetch the icon"
            write_discripper_desktop
            refresh_desktop_db
            ok "launcher recreated"
        fi

        # Outside the repair branch above on purpose: that only fires when ours
        # is missing or stale, and a stray can sit beside a perfectly good one.
        prune_competing_launchers "com.discripper.app.desktop"

        report "Disc Ripper" "$tag already installed"
        return
    fi

    run mkdir -p "$BIN_DIR" "$DISCRIPPER_DIR" "$APPS_DIR"

    info "Downloading Disc Ripper $tag..."
    # Temp file beside the target, moved into place only after it verifies — an
    # interrupted download never leaves a half-written AppImage where a runnable
    # one used to be.
    local tmp="$DISCRIPPER_APPIMAGE.partial"
    if [[ $DRY_RUN -eq 1 ]]; then
        run curl -fL --progress-bar -o "$tmp" "$url"
        run "verify sha1/length against the release's DiscRipper.AppImage.zsync"
        run chmod +x "$tmp"
        run mv -f "$tmp" "$DISCRIPPER_APPIMAGE"
        run curl -fsSL -o "$DISCRIPPER_DIR/icon.png" "https://raw.githubusercontent.com/$DISCRIPPER_REPO/main/src/discripper/resources/icon.png"
        run "write $APPS_DIR/com.discripper.app.desktop"
        prune_competing_launchers "com.discripper.app.desktop"
        run "stamp version $tag"
    else
        curl -fL --progress-bar -o "$tmp" "$url" || { rm -f "$tmp"; die "download failed."; }

        # Verify before making it executable. This is an 80MB binary pulled off the
        # internet and then run with your user's full privileges. The release has no
        # signature to check, but the .zsync header records the full file's SHA-1
        # and length; a mismatch means a corrupt or truncated download and we stop
        # rather than chmod it. (This does not defend against a swapped release —
        # the .zsync comes from the same one — only against a broken transfer.)
        verify_discripper "$tmp" "$tag" || { rm -f "$tmp"; die "Disc Ripper download could not be verified — refusing to install it."; }

        chmod +x "$tmp"
        mv -f "$tmp" "$DISCRIPPER_APPIMAGE"

        curl -fsSL -o "$DISCRIPPER_DIR/icon.png" \
            "https://raw.githubusercontent.com/$DISCRIPPER_REPO/main/src/discripper/resources/icon.png" \
            || warn "couldn't fetch the icon — the launcher entry will fall back to a generic one"

        write_discripper_desktop
        prune_competing_launchers "com.discripper.app.desktop"
        printf '%s\n' "$tag" > "$stamp"
        refresh_desktop_db
    fi

    ok "Disc Ripper $tag installed to $DISCRIPPER_APPIMAGE"
    report "Disc Ripper" "$tag (prebuilt AppImage) → $DISCRIPPER_APPIMAGE"
}

# Verify the AppImage against the SHA-1 and length recorded in its sibling .zsync
# header (the release ships no .sig or checksum file). Returns non-zero if the
# .zsync can't be fetched or the digest doesn't match — "couldn't check" is treated
# as "failed", never as "passed".
verify_discripper() {
    local file="$1" tag="$2"
    local zsync="$file.zsync" header expected_sha expected_len actual_sha actual_len

    curl -fsSL -o "$zsync" \
        "https://github.com/$DISCRIPPER_REPO/releases/download/$tag/DiscRipper.AppImage.zsync" 2>/dev/null \
        || { warn "couldn't fetch the .zsync — cannot verify the download"; rm -f "$zsync"; return 1; }

    # The .zsync is plain-text header lines, then a blank line, then a binary block.
    # sed quits at that blank line so the binary is never fed into the field parse.
    header="$(sed '/^$/q' "$zsync")"
    rm -f "$zsync"

    expected_sha="$(printf '%s\n' "$header" | grep -m1 '^SHA-1:' | awk '{print $2}')"
    expected_len="$(printf '%s\n' "$header" | grep -m1 '^Length:' | awk '{print $2}')"
    [[ -n "$expected_sha" ]] || { warn "no SHA-1 in the .zsync header — cannot verify"; return 1; }

    actual_sha="$(sha1sum "$file" | awk '{print $1}')"
    actual_len="$(stat -c%s "$file")"

    if [[ "$actual_sha" == "$expected_sha" && "$actual_len" == "$expected_len" ]]; then
        ok "checksum verified (sha1, from .zsync)"
        return 0
    fi

    warn "CHECKSUM MISMATCH — the download does not match the .zsync header"
    warn "  expected: $expected_sha ($expected_len bytes)"
    warn "  got:      $actual_sha ($actual_len bytes)"
    return 1
}

write_discripper_desktop() {
    cat > "$APPS_DIR/com.discripper.app.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Disc Ripper
Comment=Auto-rip DVDs/Blu-rays to H.265 with Plex/Jellyfin naming
Exec=$DISCRIPPER_APPIMAGE
Icon=$DISCRIPPER_DIR/icon.png
Terminal=false
Categories=AudioVideo;Video;
StartupNotify=true
StartupWMClass=discripper
EOF
}

# ── 7. GridDown (prebuilt AppImage) ───────────────────────────────────────────
# Offline US maps — streets, forest service roads, trails and terrain that work with
# no internet. Same shape as ConsoleVault (Tauri, updater on, minisign-signed
# release), so the download is checked against the embedded public key before it's
# made executable. Version-stamped so a re-run picks up a newer release.
install_griddown() {
    step "GridDown"

    local stamp="$GRIDDOWN_DIR/.version"
    local release tag url http

    info "Checking latest release..."
    # The raw helper appends the status on its own line so "no releases published
    # yet" (404) can be told apart from a genuine failure. Without that split, -f
    # collapses both into one exit code and the step below can't react.
    release="$(github_api_raw "https://api.github.com/repos/$GRIDDOWN_REPO/releases/latest")"
    http="${release##*$'\n'}"
    release="${release%$'\n'*}"

    # GridDown is the newest of these apps and may not have cut its first release
    # yet. That's a "not ready", not a "something is broken" — warn and move on so
    # the remaining steps (including system config) still run. Every other failure
    # below, including a release whose asset is missing or unverifiable, still dies.
    if [[ "$http" == "404" ]]; then
        warn "GridDown has no published release yet — skipping (re-run this later to pick it up)"
        report "GridDown" "skipped — no published release yet"
        return 0
    fi
    [[ "$http" == "200" ]] || die "$(github_api_diagnose "$http" "$release" "$(github_had_token)")"
    # `|| true` guards against grep's exit-1-on-no-match tripping pipefail+set -e
    # before the clear messages below can run — same reasoning as StreamHub.
    tag="$(printf '%s' "$release" | grep -m1 '"tag_name"' | cut -d'"' -f4 || true)"
    # The trailing `"` is what keeps this from also matching the sibling
    # ..._amd64.AppImage.sig asset URL.
    url="$(printf '%s' "$release" | grep -o 'https://[^"]*_amd64\.AppImage"' | head -1 | tr -d '"' || true)"

    [[ -n "$tag" ]] || die "couldn't read a tag from the latest release."
    [[ -n "$url" ]] || die "no GridDown _amd64.AppImage asset in release $tag."

    if [[ -f "$GRIDDOWN_APPIMAGE" && -f "$stamp" ]] && [[ "$(cat "$stamp")" == "$tag" ]]; then
        skip "GridDown $tag already installed (it self-updates from here on)"

        # Same launcher-repair path as the others: a matching stamp would otherwise
        # skip this step forever, stranding a deleted .desktop or icon.
        # ...and a launcher written by an older version of this script can carry a
        # stale StartupWMClass, which leaves a duplicate taskbar icon, so rewrite
        # it whenever it doesn't match what write_griddown_desktop produces now.
        if [[ ! -f "$APPS_DIR/com.griddown.app.desktop" || ! -f "$GRIDDOWN_DIR/icon.png" ]] \
            || ! grep -qx 'StartupWMClass=griddown' "$APPS_DIR/com.griddown.app.desktop"; then
            info "Launcher missing or out of date — recreating it..."
            mkdir -p "$APPS_DIR" "$GRIDDOWN_DIR"
            [[ -f "$GRIDDOWN_DIR/icon.png" ]] || curl -fsSL -o "$GRIDDOWN_DIR/icon.png" \
                "https://raw.githubusercontent.com/$GRIDDOWN_REPO/$GRIDDOWN_BRANCH/src-tauri/icons/icon.png" \
                || warn "couldn't fetch the icon"
            write_griddown_desktop
            refresh_desktop_db
            ok "launcher recreated"
        fi

        # Outside the repair branch above on purpose: that only fires when ours
        # is missing or stale, and a stray can sit beside a perfectly good one.
        prune_competing_launchers "com.griddown.app.desktop"

        report "GridDown" "$tag already installed"
        return
    fi

    run mkdir -p "$BIN_DIR" "$GRIDDOWN_DIR" "$APPS_DIR"

    info "Downloading GridDown $tag..."
    # Temp file beside the target, moved into place only after it verifies — an
    # interrupted or unverifiable download never replaces a working AppImage.
    local tmp="$GRIDDOWN_APPIMAGE.partial"
    if [[ $DRY_RUN -eq 1 ]]; then
        run curl -fL --progress-bar -o "$tmp" "$url"
        run "verify minisign signature against the embedded public key"
        run chmod +x "$tmp"
        run mv -f "$tmp" "$GRIDDOWN_APPIMAGE"
        run curl -fsSL -o "$GRIDDOWN_DIR/icon.png" "https://raw.githubusercontent.com/$GRIDDOWN_REPO/$GRIDDOWN_BRANCH/src-tauri/icons/icon.png"
        run "write $APPS_DIR/com.griddown.app.desktop"
        prune_competing_launchers "com.griddown.app.desktop"
        run "stamp version $tag"
    else
        curl -fL --progress-bar -o "$tmp" "$url" || { rm -f "$tmp"; die "download failed."; }

        # Verify before making it executable — same stance as ConsoleVault: this is
        # a binary off the internet about to run with your user's privileges, and
        # Tauri signs every release, so there's no reason to trust it blind.
        verify_griddown "$tmp" "$url" || { rm -f "$tmp"; die "GridDown download could not be verified — refusing to install it."; }

        chmod +x "$tmp"
        mv -f "$tmp" "$GRIDDOWN_APPIMAGE"

        curl -fsSL -o "$GRIDDOWN_DIR/icon.png" \
            "https://raw.githubusercontent.com/$GRIDDOWN_REPO/$GRIDDOWN_BRANCH/src-tauri/icons/icon.png" \
            || warn "couldn't fetch the icon — the launcher entry will fall back to a generic one"

        write_griddown_desktop
        prune_competing_launchers "com.griddown.app.desktop"
        printf '%s\n' "$tag" > "$stamp"
        refresh_desktop_db
    fi

    ok "GridDown $tag installed to $GRIDDOWN_APPIMAGE"
    report "GridDown" "$tag (prebuilt AppImage) → $GRIDDOWN_APPIMAGE"
}

# Verify the AppImage against the minisign signature published beside it
# (…AppImage.sig), using the key baked into this script. Returns non-zero if the
# signature is missing, malformed or doesn't match — "couldn't check" is treated
# exactly like "failed", never like "passed".
verify_griddown() {
    local file="$1" url="$2"

    # minisign is in packages/pacman.txt (for ConsoleVault), but `--only griddown`
    # can reach here without the packages step, so pull it in rather than failing.
    if ! have minisign; then
        info "Installing minisign (needed to verify the download)..."
        run sudo pacman -S --needed --noconfirm minisign \
            || { warn "couldn't install minisign — cannot verify the download"; return 1; }
    fi

    # Tauri publishes the .sig as base64 of the actual minisign signature file, so
    # it has to be decoded before minisign will read it.
    local sig="$file.minisig"
    curl -fsSL "$url.sig" 2>/dev/null | base64 -d > "$sig" 2>/dev/null \
        || { warn "couldn't fetch/decode the .sig — cannot verify the download"; rm -f "$sig"; return 1; }
    [[ -s "$sig" ]] || { warn "empty signature — cannot verify the download"; rm -f "$sig"; return 1; }

    if minisign -Vm "$file" -x "$sig" -P "$GRIDDOWN_PUBKEY" >/dev/null 2>&1; then
        rm -f "$sig"
        ok "signature verified (minisign)"
        return 0
    fi

    rm -f "$sig"
    warn "SIGNATURE MISMATCH — the download does not match the published minisign signature"
    return 1
}

# StartupWMClass has to match the window's WM_CLASS or the taskbar shows the
# running window as a second, unmatched app next to this icon. Tauri takes that
# from the crate name, not productName, so it was "tauri-app" through v0.1.3;
# griddown renamed the crate after that release, and the app self-updates, so
# this tracks the new name. Anything still on <=v0.1.3 keeps the duplicate icon
# until it updates.
write_griddown_desktop() {
    cat > "$APPS_DIR/com.griddown.app.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=GridDown
Comment=Offline US maps — streets, forest service roads, trails and terrain
Exec=$GRIDDOWN_APPIMAGE
Icon=$GRIDDOWN_DIR/icon.png
Terminal=false
Categories=Utility;Maps;Education;
StartupNotify=true
StartupWMClass=griddown
EOF
}

# ── 8. Stalker GAMMA GUI (prebuilt AppImage) ──────────────────────────────────
# An Avalonia/.NET GUI that downloads, installs, updates and launches
# S.T.A.L.K.E.R. GAMMA via Steam/Proton. Same GitHub-Releases-AppImage shape as
# the others but with no in-app updater: the version stamp is what picks up a
# newer release, on re-run, rather than being a once-only convenience. The
# release ships no signature or checksum asset, so the download is verified
# against the sha256 digest the releases API reports for the asset (integrity,
# not a signature — see the note by GAMMAGUI_* above).
install_gammagui() {
    step "Stalker GAMMA GUI"

    local stamp="$GAMMAGUI_DIR/.version"
    local release tag url digest

    info "Checking latest release..."
    release="$(github_api "https://api.github.com/repos/$GAMMAGUI_REPO/releases/latest")" \
        || die "couldn't fetch the latest release from GitHub."
    # `|| true` guards against grep's exit-1-on-no-match tripping pipefail+set -e
    # before the clear messages below can run — same reasoning as StreamHub.
    tag="$(printf '%s' "$release" | grep -m1 '"tag_name"' | cut -d'"' -f4 || true)"
    # The asset name is already stable/unversioned. The trailing `"` keeps the
    # match off any sibling asset URL that continues past `.AppImage`.
    url="$(printf '%s' "$release" | grep -o 'https://[^"]*/StalkerGammaGui-x86_64\.AppImage"' | head -1 | tr -d '"' || true)"

    [[ -n "$tag" ]] || die "couldn't read a tag from the latest release."
    [[ -n "$url" ]] || die "no $GAMMAGUI_ASSET asset in release $tag."

    # The releases API reports each asset's sha256 in a `digest` field — the only
    # checksum this release publishes anywhere. Matched to the asset by NAME via
    # a real JSON parse, not a blind grep: a second asset added to some future
    # release must not be able to swap its digest in for the AppImage's.
    digest="$(printf '%s' "$release" | GAMMAGUI_ASSET="$GAMMAGUI_ASSET" python -c '
import json, os, sys
for a in json.load(sys.stdin).get("assets", []):
    if a.get("name") == os.environ["GAMMAGUI_ASSET"]:
        d = a.get("digest") or ""
        if d.startswith("sha256:"):
            print(d[len("sha256:"):])
        break
' 2>/dev/null || true)"

    if [[ -f "$GAMMAGUI_APPIMAGE" && -f "$stamp" ]] && [[ "$(cat "$stamp")" == "$tag" ]]; then
        skip "Stalker GAMMA GUI $tag already installed (no self-updater — a re-run picks up new releases)"

        # Same launcher-repair path as the others: a matching stamp would otherwise
        # skip this step forever, stranding a deleted .desktop or icon.
        if [[ ! -f "$APPS_DIR/com.stalkergamma.gui.desktop" || ! -f "$GAMMAGUI_DIR/icon.png" ]]; then
            info "Launcher missing — recreating it..."
            mkdir -p "$APPS_DIR" "$GAMMAGUI_DIR"
            [[ -f "$GAMMAGUI_DIR/icon.png" ]] || curl -fsSL -o "$GAMMAGUI_DIR/icon.png" \
                "https://raw.githubusercontent.com/$GAMMAGUI_REPO/main/packaging/icon-256.png" \
                || warn "couldn't fetch the icon"
            write_gammagui_desktop
            refresh_desktop_db
            ok "launcher recreated"
        fi

        # Outside that branch on purpose: a stray launcher can sit beside a
        # perfectly good one of ours, and the repair above only fires when ours
        # is missing or stale.
        prune_competing_launchers "com.stalkergamma.gui.desktop"

        report "Stalker GAMMA GUI" "$tag already installed"
        return
    fi

    run mkdir -p "$BIN_DIR" "$GAMMAGUI_DIR" "$APPS_DIR"

    info "Downloading Stalker GAMMA GUI $tag..."
    # Temp file beside the target, moved into place only after it verifies — an
    # interrupted download never leaves a half-written AppImage where a runnable
    # one used to be.
    local tmp="$GAMMAGUI_APPIMAGE.partial"
    if [[ $DRY_RUN -eq 1 ]]; then
        run curl -fL --progress-bar -o "$tmp" "$url"
        run "verify sha256 against the digest in the release's API record"
        run chmod +x "$tmp"
        run mv -f "$tmp" "$GAMMAGUI_APPIMAGE"
        run curl -fsSL -o "$GAMMAGUI_DIR/icon.png" "https://raw.githubusercontent.com/$GAMMAGUI_REPO/main/packaging/icon-256.png"
        run "write $APPS_DIR/com.stalkergamma.gui.desktop"
        prune_competing_launchers "com.stalkergamma.gui.desktop"
        run "stamp version $tag"
    else
        curl -fL --progress-bar -o "$tmp" "$url" || { rm -f "$tmp"; die "download failed."; }

        # Verify before making it executable — same stance as every other AppImage
        # here: a binary off the internet about to run with your user's privileges.
        # A mismatch means a corrupt or truncated download and we stop rather than
        # chmod it.
        verify_gammagui "$tmp" "$digest" || { rm -f "$tmp"; die "Stalker GAMMA GUI download could not be verified — refusing to install it."; }

        chmod +x "$tmp"
        mv -f "$tmp" "$GAMMAGUI_APPIMAGE"

        curl -fsSL -o "$GAMMAGUI_DIR/icon.png" \
            "https://raw.githubusercontent.com/$GAMMAGUI_REPO/main/packaging/icon-256.png" \
            || warn "couldn't fetch the icon — the launcher entry will fall back to a generic one"

        write_gammagui_desktop
        prune_competing_launchers "com.stalkergamma.gui.desktop"
        printf '%s\n' "$tag" > "$stamp"
        refresh_desktop_db
    fi

    ok "Stalker GAMMA GUI $tag installed to $GAMMAGUI_APPIMAGE"
    report "Stalker GAMMA GUI" "$tag (prebuilt AppImage) → $GAMMAGUI_APPIMAGE"
}

# Verify the AppImage against the sha256 digest the releases API reported for the
# asset (the release ships no .sig or checksum file). Returns non-zero if the API
# carried no digest or the hash doesn't match — "couldn't check" is treated as
# "failed", never as "passed".
verify_gammagui() {
    local file="$1" digest="$2"

    [[ -n "$digest" ]] || { warn "no sha256 digest in the release's API record — cannot verify the download"; return 1; }

    local actual
    actual="$(sha256sum "$file" | awk '{print $1}')"

    if [[ "$actual" == "$digest" ]]; then
        ok "checksum verified (sha256, from the releases API)"
        return 0
    fi

    warn "CHECKSUM MISMATCH — the download does not match the API's sha256 digest"
    warn "  expected: $digest"
    warn "  got:      $actual"
    return 1
}

# StartupWMClass matches what the app's own AppDir .desktop declares
# (StalkerGamma.Gui — Avalonia takes it from the assembly name), so the taskbar
# groups the running window under this launcher instead of showing a duplicate.
write_gammagui_desktop() {
    cat > "$APPS_DIR/com.stalkergamma.gui.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Stalker GAMMA GUI
Comment=Download, install, update and play S.T.A.L.K.E.R. GAMMA (Steam/Proton)
Exec=$GAMMAGUI_APPIMAGE
Icon=$GAMMAGUI_DIR/icon.png
Terminal=false
Categories=Game;Utility;
StartupNotify=true
StartupWMClass=StalkerGamma.Gui
EOF
}

# ── 9. LoreRim Autoinstall (prebuilt AppImage) ────────────────────────────────
# An Avalonia/.NET GUI that installs the LoreRim Wabbajack modlist for Skyrim —
# Steam, Proton and Nexus handled automatically. Same GitHub-Releases-AppImage
# shape as Stalker GAMMA GUI: no in-app updater, so the version stamp on re-run
# is the update path. The release ships no signature or checksum asset, so the
# download is verified against the sha256 digest the releases API reports for
# the asset (integrity, not a signature — see the note by LORERIM_* above).
install_lorerim() {
    step "LoreRim Autoinstall"

    local stamp="$LORERIM_DIR/.version"
    local release tag url digest

    info "Checking latest release..."
    release="$(github_api "https://api.github.com/repos/$LORERIM_REPO/releases/latest")" \
        || die "couldn't fetch the latest release from GitHub."
    # `|| true` guards against grep's exit-1-on-no-match tripping pipefail+set -e
    # before the clear messages below can run — same reasoning as StreamHub.
    tag="$(printf '%s' "$release" | grep -m1 '"tag_name"' | cut -d'"' -f4 || true)"
    # The asset name is already stable/unversioned. The trailing `"` keeps the
    # match off any sibling asset URL that continues past `.AppImage`.
    url="$(printf '%s' "$release" | grep -o 'https://[^"]*/LorerimAutoinstall-x86_64\.AppImage"' | head -1 | tr -d '"' || true)"

    [[ -n "$tag" ]] || die "couldn't read a tag from the latest release."
    [[ -n "$url" ]] || die "no $LORERIM_ASSET asset in release $tag."

    # The releases API reports each asset's sha256 in a `digest` field — the only
    # checksum this release publishes anywhere. Matched to the asset by NAME via
    # a real JSON parse, not a blind grep: a second asset added to some future
    # release must not be able to swap its digest in for the AppImage's.
    digest="$(printf '%s' "$release" | LORERIM_ASSET="$LORERIM_ASSET" python -c '
import json, os, sys
for a in json.load(sys.stdin).get("assets", []):
    if a.get("name") == os.environ["LORERIM_ASSET"]:
        d = a.get("digest") or ""
        if d.startswith("sha256:"):
            print(d[len("sha256:"):])
        break
' 2>/dev/null || true)"

    if [[ -f "$LORERIM_APPIMAGE" && -f "$stamp" ]] && [[ "$(cat "$stamp")" == "$tag" ]]; then
        skip "LoreRim Autoinstall $tag already installed (no self-updater — a re-run picks up new releases)"

        # Same launcher-repair path as the others: a matching stamp would otherwise
        # skip this step forever, stranding a deleted .desktop or icon.
        if [[ ! -f "$APPS_DIR/com.lorerim.autoinstall.desktop" || ! -f "$LORERIM_DIR/icon.png" ]]; then
            info "Launcher missing — recreating it..."
            mkdir -p "$APPS_DIR" "$LORERIM_DIR"
            [[ -f "$LORERIM_DIR/icon.png" ]] || curl -fsSL -o "$LORERIM_DIR/icon.png" \
                "https://raw.githubusercontent.com/$LORERIM_REPO/main/packaging/icon-256.png" \
                || warn "couldn't fetch the icon"
            write_lorerim_desktop
            refresh_desktop_db
            ok "launcher recreated"
        fi

        # Outside the repair branch above on purpose: that only fires when ours
        # is missing or stale, and a stray can sit beside a perfectly good one.
        prune_competing_launchers "com.lorerim.autoinstall.desktop"

        report "LoreRim" "$tag already installed"
        return
    fi

    run mkdir -p "$BIN_DIR" "$LORERIM_DIR" "$APPS_DIR"

    info "Downloading LoreRim Autoinstall $tag..."
    # Temp file beside the target, moved into place only after it verifies — an
    # interrupted download never leaves a half-written AppImage where a runnable
    # one used to be.
    local tmp="$LORERIM_APPIMAGE.partial"
    if [[ $DRY_RUN -eq 1 ]]; then
        run curl -fL --progress-bar -o "$tmp" "$url"
        run "verify sha256 against the digest in the release's API record"
        run chmod +x "$tmp"
        run mv -f "$tmp" "$LORERIM_APPIMAGE"
        run curl -fsSL -o "$LORERIM_DIR/icon.png" "https://raw.githubusercontent.com/$LORERIM_REPO/main/packaging/icon-256.png"
        run "write $APPS_DIR/com.lorerim.autoinstall.desktop"
        prune_competing_launchers "com.lorerim.autoinstall.desktop"
        run "stamp version $tag"
    else
        curl -fL --progress-bar -o "$tmp" "$url" || { rm -f "$tmp"; die "download failed."; }

        # Verify before making it executable — same stance as every other AppImage
        # here: a binary off the internet about to run with your user's privileges.
        # A mismatch means a corrupt or truncated download and we stop rather than
        # chmod it.
        verify_lorerim "$tmp" "$digest" || { rm -f "$tmp"; die "LoreRim Autoinstall download could not be verified — refusing to install it."; }

        chmod +x "$tmp"
        mv -f "$tmp" "$LORERIM_APPIMAGE"

        curl -fsSL -o "$LORERIM_DIR/icon.png" \
            "https://raw.githubusercontent.com/$LORERIM_REPO/main/packaging/icon-256.png" \
            || warn "couldn't fetch the icon — the launcher entry will fall back to a generic one"

        write_lorerim_desktop
        prune_competing_launchers "com.lorerim.autoinstall.desktop"
        printf '%s\n' "$tag" > "$stamp"
        refresh_desktop_db
    fi

    ok "LoreRim Autoinstall $tag installed to $LORERIM_APPIMAGE"
    report "LoreRim" "$tag (prebuilt AppImage) → $LORERIM_APPIMAGE"
}

# Verify the AppImage against the sha256 digest the releases API reported for the
# asset (the release ships no .sig or checksum file). Returns non-zero if the API
# carried no digest or the hash doesn't match — "couldn't check" is treated as
# "failed", never as "passed".
verify_lorerim() {
    local file="$1" digest="$2"

    [[ -n "$digest" ]] || { warn "no sha256 digest in the release's API record — cannot verify the download"; return 1; }

    local actual
    actual="$(sha256sum "$file" | awk '{print $1}')"

    if [[ "$actual" == "$digest" ]]; then
        ok "checksum verified (sha256, from the releases API)"
        return 0
    fi

    warn "CHECKSUM MISMATCH — the download does not match the API's sha256 digest"
    warn "  expected: $digest"
    warn "  got:      $actual"
    return 1
}

# StartupWMClass matches what the app's own AppDir .desktop declares
# (Lorerim.Gui — Avalonia takes it from the assembly name), so the taskbar
# groups the running window under this launcher instead of showing a duplicate.
# MimeType/%u mirror that .desktop too: the app registers as the handler for
# jackify: links (Nexus downloads), and refresh_desktop_db's
# update-desktop-database is what makes the scheme registration take effect.
write_lorerim_desktop() {
    cat > "$APPS_DIR/com.lorerim.autoinstall.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=LoreRim Autoinstall
Comment=One-click LoreRim (Wabbajack) installer for Linux
Exec=$LORERIM_APPIMAGE %u
Icon=$LORERIM_DIR/icon.png
Terminal=false
Categories=Game;Utility;
StartupNotify=true
StartupWMClass=Lorerim.Gui
MimeType=x-scheme-handler/jackify;
EOF
}

# ── 10. WotLK Autoinstall (prebuilt AppImage) ─────────────────────────────────
# An Avalonia/.NET GUI that installs a World of Warcraft 3.3.5a client for a
# local server — client download, realmlist, addons and a Steam/Proton shortcut.
# Same GitHub-Releases-AppImage shape as Stalker GAMMA GUI and LoreRim: no
# in-app updater, so the version stamp on re-run is the update path. Unlike
# those two, the release publishes a SHA256SUMS file, which is what the download
# is verified against — see the note by WOTLK_* above for what that does and
# doesn't prove.
install_wotlk() {
    step "WotLK Autoinstall"

    local stamp="$WOTLK_DIR/.version"
    local release tag url sums_url digest

    info "Checking latest release..."
    release="$(github_api "https://api.github.com/repos/$WOTLK_REPO/releases/latest")" \
        || die "couldn't fetch the latest release from GitHub."
    # `|| true` guards against grep's exit-1-on-no-match tripping pipefail+set -e
    # before the clear messages below can run — same reasoning as StreamHub.
    tag="$(printf '%s' "$release" | grep -m1 '"tag_name"' | cut -d'"' -f4 || true)"
    # The asset name is already stable/unversioned. The trailing `"` keeps the
    # match off any sibling asset URL that continues past `.AppImage`.
    url="$(printf '%s' "$release" | grep -o 'https://[^"]*/WowWotlkAutoinstall-x86_64\.AppImage"' | head -1 | tr -d '"' || true)"
    # Anchored on /download/ so this can only match a release asset URL, and the
    # trailing `"` keeps it off anything whose name merely starts with SHA256SUMS.
    sums_url="$(printf '%s' "$release" | grep -o "https://[^\"]*/download/[^\"]*/$WOTLK_SUMS\"" | head -1 | tr -d '"' || true)"

    [[ -n "$tag" ]] || die "couldn't read a tag from the latest release."
    [[ -n "$url" ]] || die "no $WOTLK_ASSET asset in release $tag."

    # The releases API also reports a per-asset sha256, matched to the asset by
    # NAME via a real JSON parse rather than a blind grep: a second asset added
    # to some future release must not be able to swap its digest in for the
    # AppImage's. Cross-checked against SHA256SUMS below — SHA256SUMS is written
    # by CI at build time, this is computed by GitHub on upload, so agreement
    # says the file being served is the file CI built.
    digest="$(printf '%s' "$release" | WOTLK_ASSET="$WOTLK_ASSET" python -c '
import json, os, sys
for a in json.load(sys.stdin).get("assets", []):
    if a.get("name") == os.environ["WOTLK_ASSET"]:
        d = a.get("digest") or ""
        if d.startswith("sha256:"):
            print(d[len("sha256:"):])
        break
' 2>/dev/null || true)"

    if [[ -f "$WOTLK_APPIMAGE" && -f "$stamp" ]] && [[ "$(cat "$stamp")" == "$tag" ]]; then
        skip "WotLK Autoinstall $tag already installed (no self-updater — a re-run picks up new releases)"

        # Same launcher-repair path as the others: a matching stamp would otherwise
        # skip this step forever, stranding a deleted .desktop or icon.
        if [[ ! -f "$APPS_DIR/com.wowwotlk.autoinstall.desktop" || ! -f "$WOTLK_DIR/icon.png" ]]; then
            info "Launcher missing — recreating it..."
            mkdir -p "$APPS_DIR" "$WOTLK_DIR"
            [[ -f "$WOTLK_DIR/icon.png" ]] || curl -fsSL -o "$WOTLK_DIR/icon.png" \
                "https://raw.githubusercontent.com/$WOTLK_REPO/main/packaging/icon-256.png" \
                || warn "couldn't fetch the icon"
            write_wotlk_desktop
            refresh_desktop_db
            ok "launcher recreated"
        fi

        # Outside the repair branch above on purpose: that only fires when ours
        # is missing or stale, and a stray can sit beside a perfectly good one.
        prune_competing_launchers "com.wowwotlk.autoinstall.desktop"

        report "WotLK" "$tag already installed"
        return
    fi

    run mkdir -p "$BIN_DIR" "$WOTLK_DIR" "$APPS_DIR"

    info "Downloading WotLK Autoinstall $tag..."
    # Temp file beside the target, moved into place only after it verifies — an
    # interrupted download never leaves a half-written AppImage where a runnable
    # one used to be.
    local tmp="$WOTLK_APPIMAGE.partial"
    if [[ $DRY_RUN -eq 1 ]]; then
        run curl -fL --progress-bar -o "$tmp" "$url"
        run "verify sha256 against the release's SHA256SUMS"
        run chmod +x "$tmp"
        run mv -f "$tmp" "$WOTLK_APPIMAGE"
        run curl -fsSL -o "$WOTLK_DIR/icon.png" "https://raw.githubusercontent.com/$WOTLK_REPO/main/packaging/icon-256.png"
        run "write $APPS_DIR/com.wowwotlk.autoinstall.desktop"
        prune_competing_launchers "com.wowwotlk.autoinstall.desktop"
        run "stamp version $tag"
    else
        curl -fL --progress-bar -o "$tmp" "$url" || { rm -f "$tmp"; die "download failed."; }

        # Verify before making it executable — same stance as every other AppImage
        # here: a binary off the internet about to run with your user's privileges.
        # A mismatch means a corrupt or truncated download and we stop rather than
        # chmod it.
        verify_wotlk "$tmp" "$sums_url" "$digest" || { rm -f "$tmp"; die "WotLK Autoinstall download could not be verified — refusing to install it."; }

        chmod +x "$tmp"
        mv -f "$tmp" "$WOTLK_APPIMAGE"

        curl -fsSL -o "$WOTLK_DIR/icon.png" \
            "https://raw.githubusercontent.com/$WOTLK_REPO/main/packaging/icon-256.png" \
            || warn "couldn't fetch the icon — the launcher entry will fall back to a generic one"

        write_wotlk_desktop
        prune_competing_launchers "com.wowwotlk.autoinstall.desktop"
        printf '%s\n' "$tag" > "$stamp"
        refresh_desktop_db
    fi

    ok "WotLK Autoinstall $tag installed to $WOTLK_APPIMAGE"
    report "WotLK" "$tag (prebuilt AppImage) → $WOTLK_APPIMAGE"
}

# Verify the AppImage against the sha256 in the release's SHA256SUMS asset, and
# require the API's per-asset digest to agree when the API reports one. Returns
# non-zero if SHA256SUMS is missing, carries no line for our asset, or either
# hash disagrees — "couldn't check" is treated as "failed", never as "passed".
verify_wotlk() {
    local file="$1" sums_url="$2" digest="$3"

    [[ -n "$sums_url" ]] || { warn "no $WOTLK_SUMS asset in the release — cannot verify the download"; return 1; }

    local sums
    sums="$(curl -fsSL "$sums_url" 2>/dev/null)" \
        || { warn "couldn't fetch $WOTLK_SUMS — cannot verify the download"; return 1; }

    # Pull the line for OUR asset by name rather than taking the first hash in
    # the file: a release that later adds a second binary would otherwise be
    # checked against whichever line happened to come first.
    local expected
    expected="$(printf '%s\n' "$sums" | awk -v n="$WOTLK_ASSET" '$2 == n || $2 == "*" n { print $1; exit }')"
    [[ "$expected" =~ ^[0-9a-f]{64}$ ]] \
        || { warn "no sha256 for $WOTLK_ASSET in $WOTLK_SUMS — cannot verify the download"; return 1; }

    # A disagreement here means the asset being served isn't the one CI hashed.
    # Both records come from the same host, so this is a consistency check, not
    # a signature — but a re-uploaded asset that nobody re-hashed fails it.
    if [[ -n "$digest" && "$digest" != "$expected" ]]; then
        warn "DIGEST DISAGREEMENT — $WOTLK_SUMS and the releases API report different hashes"
        warn "  $WOTLK_SUMS: $expected"
        warn "  releases API:  $digest"
        return 1
    fi

    local actual
    actual="$(sha256sum "$file" | awk '{print $1}')"

    if [[ "$actual" == "$expected" ]]; then
        ok "checksum verified (sha256, from $WOTLK_SUMS)"
        return 0
    fi

    warn "CHECKSUM MISMATCH — the download does not match $WOTLK_SUMS"
    warn "  expected: $expected"
    warn "  got:      $actual"
    return 1
}

# StartupWMClass matches what the app's own AppDir .desktop declares
# (WowWotlk.Gui — Avalonia takes it from the assembly name), so the taskbar
# groups the running window under this launcher instead of showing a duplicate.
# No MimeType/%u here, unlike LoreRim: this app registers no URL scheme, and a
# %u on an Exec that ignores it is just noise desktop-file-validate tolerates.
write_wotlk_desktop() {
    cat > "$APPS_DIR/com.wowwotlk.autoinstall.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=WotLK Autoinstall
Comment=One-click WoW 3.3.5a client installer for Linux
Exec=$WOTLK_APPIMAGE
Icon=$WOTLK_DIR/icon.png
Terminal=false
Categories=Game;Utility;
StartupNotify=true
StartupWMClass=WowWotlk.Gui
EOF
}

# ── 11. Music AI Player (prebuilt AppImage) ───────────────────────────────────
# A local music player for long coding sessions — SQLite library, crossfade,
# shuffle, playlists, visualizer, tray and media keys. Same shape as ConsoleVault
# and GridDown (Tauri, updater on, minisign-signed release), so the download is
# checked against the embedded public key before it's made executable. Version
# stamped like the rest, though the app self-updates from here on.
install_musicai() {
    step "Music AI Player"

    local stamp="$MUSICAI_DIR/.version"
    local release tag url

    info "Checking latest release..."
    release="$(github_api "https://api.github.com/repos/$MUSICAI_REPO/releases/latest")" \
        || die "couldn't fetch the latest release from GitHub."
    # `|| true` guards against grep's exit-1-on-no-match tripping pipefail+set -e
    # before the clear messages below can run — same reasoning as StreamHub.
    tag="$(printf '%s' "$release" | grep -m1 '"tag_name"' | cut -d'"' -f4 || true)"
    # Versioned Tauri asset name (Music.AI.Player_x.y.z_amd64.AppImage), matched
    # by its suffix as ConsoleVault's is. The trailing `"` is what keeps this off
    # the sibling ..._amd64.AppImage.sig URL, which continues past `.AppImage`;
    # the `.AppImage` itself keeps it off the ..._amd64.deb the release also ships.
    url="$(printf '%s' "$release" | grep -o 'https://[^"]*_amd64\.AppImage"' | head -1 | tr -d '"' || true)"

    [[ -n "$tag" ]] || die "couldn't read a tag from the latest release."
    [[ -n "$url" ]] || die "no Music AI Player _amd64.AppImage asset in release $tag."

    if [[ -f "$MUSICAI_APPIMAGE" && -f "$stamp" ]] && [[ "$(cat "$stamp")" == "$tag" ]]; then
        skip "Music AI Player $tag already installed (it self-updates from here on)"

        # Same launcher-repair path as the others: a matching stamp would otherwise
        # skip this step forever, stranding a deleted .desktop or icon.
        if [[ ! -f "$APPS_DIR/music-ai-player.desktop" || ! -f "$MUSICAI_DIR/icon.png" ]]; then
            info "Launcher missing — recreating it..."
            mkdir -p "$APPS_DIR" "$MUSICAI_DIR"
            [[ -f "$MUSICAI_DIR/icon.png" ]] || curl -fsSL -o "$MUSICAI_DIR/icon.png" \
                "https://raw.githubusercontent.com/$MUSICAI_REPO/$MUSICAI_BRANCH/src-tauri/icons/icon.png" \
                || warn "couldn't fetch the icon"
            write_musicai_desktop
            refresh_desktop_db
            ok "launcher recreated"
        fi

        # Outside the repair branch above on purpose: that only fires when ours
        # is missing or stale, and a stray can sit beside a perfectly good one.
        prune_competing_launchers "music-ai-player.desktop"

        report "Music AI Player" "$tag already installed"
        return
    fi

    run mkdir -p "$BIN_DIR" "$MUSICAI_DIR" "$APPS_DIR"

    info "Downloading Music AI Player $tag..."
    # Temp file beside the target, moved into place only after it verifies — an
    # interrupted or unverifiable download never replaces a working AppImage.
    local tmp="$MUSICAI_APPIMAGE.partial"
    if [[ $DRY_RUN -eq 1 ]]; then
        run curl -fL --progress-bar -o "$tmp" "$url"
        run "verify minisign signature against the embedded public key"
        run chmod +x "$tmp"
        run mv -f "$tmp" "$MUSICAI_APPIMAGE"
        run curl -fsSL -o "$MUSICAI_DIR/icon.png" "https://raw.githubusercontent.com/$MUSICAI_REPO/$MUSICAI_BRANCH/src-tauri/icons/icon.png"
        run "write $APPS_DIR/music-ai-player.desktop"
        prune_competing_launchers "music-ai-player.desktop"
        run "stamp version $tag"
    else
        curl -fL --progress-bar -o "$tmp" "$url" || { rm -f "$tmp"; die "download failed."; }

        # Verify before making it executable — same stance as every other AppImage
        # here: a binary off the internet about to run with your user's privileges,
        # and Tauri signs every release, so there's no reason to trust it blind.
        verify_musicai "$tmp" "$url" || { rm -f "$tmp"; die "Music AI Player download could not be verified — refusing to install it."; }

        chmod +x "$tmp"
        mv -f "$tmp" "$MUSICAI_APPIMAGE"

        curl -fsSL -o "$MUSICAI_DIR/icon.png" \
            "https://raw.githubusercontent.com/$MUSICAI_REPO/$MUSICAI_BRANCH/src-tauri/icons/icon.png" \
            || warn "couldn't fetch the icon — the launcher entry will fall back to a generic one"

        write_musicai_desktop
        prune_competing_launchers "music-ai-player.desktop"
        printf '%s\n' "$tag" > "$stamp"
        refresh_desktop_db

        # The player itself needs nothing else, but its YouTube importer shells out
        # to yt-dlp and ffmpeg on PATH. Both are in packages/pacman.txt, so this
        # only fires under `--only musicai` on a box that skipped that step — say
        # so once rather than letting the Import panel be the one to explain it.
        if ! have yt-dlp || ! have ffmpeg; then
            warn "yt-dlp and/or ffmpeg are missing — playback works, but the YouTube importer won't (run this without --only, or: sudo pacman -S --needed yt-dlp ffmpeg)"
        fi
    fi

    ok "Music AI Player $tag installed to $MUSICAI_APPIMAGE"
    report "Music AI Player" "$tag (prebuilt AppImage) → $MUSICAI_APPIMAGE"
}

# Verify the AppImage against the minisign signature published beside it
# (…AppImage.sig), using the key baked into this script. Returns non-zero if the
# signature is missing, malformed or doesn't match — "couldn't check" is treated
# exactly like "failed", never like "passed".
verify_musicai() {
    local file="$1" url="$2"

    # minisign is in packages/pacman.txt (for ConsoleVault), but `--only musicai`
    # can reach here without the packages step, so pull it in rather than failing.
    if ! have minisign; then
        info "Installing minisign (needed to verify the download)..."
        run sudo pacman -S --needed --noconfirm minisign \
            || { warn "couldn't install minisign — cannot verify the download"; return 1; }
    fi

    # Tauri publishes the .sig as base64 of the actual minisign signature file, so
    # it has to be decoded before minisign will read it.
    local sig="$file.minisig"
    curl -fsSL "$url.sig" 2>/dev/null | base64 -d > "$sig" 2>/dev/null \
        || { warn "couldn't fetch/decode the .sig — cannot verify the download"; rm -f "$sig"; return 1; }
    [[ -s "$sig" ]] || { warn "empty signature — cannot verify the download"; rm -f "$sig"; return 1; }

    if minisign -Vm "$file" -x "$sig" -P "$MUSICAI_PUBKEY" >/dev/null 2>&1; then
        rm -f "$sig"
        ok "signature verified (minisign)"
        return 0
    fi

    rm -f "$sig"
    warn "SIGNATURE MISMATCH — the download does not match the published minisign signature"
    return 1
}

# Named music-ai-player.desktop, not com.<app>.app.desktop like the others: on
# Wayland the compositor matches a running window to a .desktop by its app-id,
# which Tauri takes from the crate name ("music-ai-player" here) — so a
# com.musicaiplayer.app.desktop would leave the running window with a generic
# icon. StartupWMClass carries the same value for X11's WM_CLASS match.
write_musicai_desktop() {
    cat > "$APPS_DIR/music-ai-player.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Music AI Player
Comment=Local music player — YouTube import, folder scan, ACE-Step generation
Exec=$MUSICAI_APPIMAGE
Icon=$MUSICAI_DIR/icon.png
Terminal=false
Categories=AudioVideo;Audio;Player;
StartupNotify=true
StartupWMClass=music-ai-player
EOF
}

# ── 12. system config ─────────────────────────────────────────────────────────
configure_system() {
    step "System config"

    # LACT is useless without its daemon — the GUI just reports that it can't
    # connect. Failure here is not fatal: on a machine with no AMD GPU (a VM,
    # say) the daemon legitimately won't start, and that shouldn't sink an
    # otherwise good run.
    if systemctl is-enabled lactd >/dev/null 2>&1; then
        skip "lactd already enabled"
        report "Services" "lactd already enabled"
    elif run sudo systemctl enable --now lactd; then
        ok "lactd enabled (LACT can now talk to the GPU)"
        report "Services" "lactd enabled and started"
    else
        warn "couldn't start lactd — expected if this machine has no AMD GPU"
        report "Services" "lactd FAILED to start (no AMD GPU?)"
    fi

    # A fresh CachyOS doesn't have ~/.local/bin on PATH, and both custom apps
    # install their binaries there — so without this, 'agenttilecli' isn't a
    # command, which looks like the install silently failed.
    ensure_path

    configure_power_profile
    configure_powerdevil
    configure_brave_extensions
    configure_keepassxc_browser
    configure_taskbar
}

# Auto-install Brave extensions via Chromium enterprise policy.
#
# Brave is a Chromium fork and reads managed policy from /etc/brave/policies —
# confirmed by the paths compiled into the brave-origin binary. Dropping a policy
# file there makes Brave fetch the listed extensions from the Chrome Web Store on
# first launch.
#
# installation_mode is "normal_installed", NOT "force_installed": both install
# automatically, but force_installed also makes the extension impossible to
# disable or remove, even by the machine's owner. That's a reasonable thing for a
# corporate fleet and an unreasonable thing to do to yourself.
configure_brave_extensions() {
    local list="$PKG_DIR/brave-extensions.txt"
    local policy_dir="/etc/brave/policies/managed"
    local policy="$policy_dir/extensions.json"

    [[ -f "$list" ]] || { skip "no brave-extensions.txt — skipping"; return; }

    local ids=()
    mapfile -t ids < <(read_list "$list")
    [[ ${#ids[@]} -gt 0 ]] || { skip "no Brave extensions listed"; return; }

    local json="" id
    for id in "${ids[@]}"; do
        json+="${json:+,}
        \"$id\": {
            \"installation_mode\": \"normal_installed\",
            \"update_url\": \"https://clients2.google.com/service/update2/crx\"
        }"
    done

    if [[ $DRY_RUN -eq 1 ]]; then
        run "sudo mkdir -p $policy_dir"
        run "sudo write $policy (${#ids[@]} extensions, homepage + new tab -> $BRAVE_HOMEPAGE)"
        report "Brave" "${#ids[@]} extensions, homepage $BRAVE_HOMEPAGE"
        return
    fi

    sudo mkdir -p "$policy_dir"

    # HomepageIsNewTabPage=false is required, not decorative: leave it true and
    # Brave ignores HomepageLocation entirely and the Home button opens the new
    # tab page instead. NewTabPageLocation then points new tabs at the same URL.
    sudo tee "$policy" > /dev/null <<EOF
{
    "HomepageLocation": "$BRAVE_HOMEPAGE",
    "HomepageIsNewTabPage": false,
    "NewTabPageLocation": "$BRAVE_HOMEPAGE",
    "ShowHomeButton": true,

    "ExtensionSettings": {$json
    }
}
EOF

    ok "${#ids[@]} Brave extensions set to auto-install on first launch"
    ok "Brave homepage and new tab set to $BRAVE_HOMEPAGE"
    report "Brave" "${#ids[@]} extensions; homepage + new tab -> $BRAVE_HOMEPAGE"

    configure_brave_filters
}

# Which Brave profile directory to write into.
#
# CachyOS's brave-origin-bin is a different BUILD from upstream Brave, and the
# two keep separate profiles: ~/.config/BraveSoftware/Brave-Origin against
# .../Brave-Browser. Off CachyOS there is no brave-origin at all — Omarchy gets
# upstream brave-bin from the AUR — so hardcoding Brave-Origin there means the
# filter lists and the KeePassXC manifest are written to a directory the running
# browser never opens. No error, no effect.
#
# The installed binary decides it, not whichever directory happens to exist: a
# leftover profile from a browser that is no longer installed is not the answer.
brave_profile_dir() {
    local base="$HOME/.config/BraveSoftware"

    if have brave-origin; then printf '%s/Brave-Origin'  "$base"; return; fi
    if have brave;        then printf '%s/Brave-Browser' "$base"; return; fi

    # Not installed yet. In a full run it will be by the time this is called —
    # packages is step 1 and the config step is last — so this is really the
    # `--only config` path on a box with no Brave at all. Go with whichever
    # profile is already on disk, then with whichever Brave this machine could
    # even install: brave-origin-bin exists only in the CachyOS repos, so
    # without them upstream Brave is the only possible answer.
    if [[ -d "$base/Brave-Origin"  ]]; then printf '%s/Brave-Origin'  "$base"; return; fi
    if [[ -d "$base/Brave-Browser" ]]; then printf '%s/Brave-Browser' "$base"; return; fi
    if has_cachyos_repos; then
        printf '%s/Brave-Origin'  "$base"
    else
        printf '%s/Brave-Browser' "$base"
    fi
}

# Switch on Brave's optional ad-block filter lists.
#
# There is no enterprise policy for these — they're stored per-profile in Brave's
# "Local State" JSON, keyed by the filter list's UUID. So we seed the file
# directly. Brave merges what's already there on startup, so writing this before
# it has ever run is fine, and it also works on an existing profile.
configure_brave_filters() {
    [[ ${#BRAVE_FILTER_LISTS[@]} -gt 0 ]] || return 0

    local state_dir; state_dir="$(brave_profile_dir)"
    local state="$state_dir/Local State"

    if [[ $DRY_RUN -eq 1 ]]; then
        run "enable ${#BRAVE_FILTER_LISTS[@]} Brave filter list(s) in $state"
        return
    fi

    # Brave rewrites Local State when it exits, so anything we write under a
    # running Brave gets thrown away without a word.
    if pgrep -x brave >/dev/null 2>&1; then
        warn "Brave is running — close it and re-run '--only config', or it will overwrite this"
    fi

    mkdir -p "$state_dir"

    if BRAVE_STATE="$state" BRAVE_UUIDS="${BRAVE_FILTER_LISTS[*]}" python - <<'PY'
import json, os

path   = os.environ["BRAVE_STATE"]
uuids  = os.environ["BRAVE_UUIDS"].split()

# Merge into whatever is already there; on a fresh box the file won't exist yet
# and Brave will happily fill in the rest of its defaults around what we write.
try:
    with open(path) as f:
        state = json.load(f)
except (FileNotFoundError, ValueError):
    state = {}

filters = state.setdefault("brave", {}).setdefault("ad_block", {}).setdefault("regional_filters", {})
for u in uuids:
    filters.setdefault(u, {})["enabled"] = True

with open(path, "w") as f:
    json.dump(state, f, separators=(",", ":"))
PY
    then
        ok "enabled ${#BRAVE_FILTER_LISTS[@]} Brave filter list(s) (experimental ad block)"
        report "" "experimental ad-block filter list enabled"
    else
        warn "couldn't write Brave's Local State — enable the filter list by hand in brave://settings/shields/filters"
    fi
}

# Wire KeePassXC's browser integration up to whichever Brave is installed.
#
# KeePassXC's "Brave" checkbox writes its native-messaging manifest to
# ~/.config/BraveSoftware/Brave-Browser/ — the path UPSTREAM Brave uses. Brave
# Origin is a different build and reads ~/.config/BraveSoftware/Brave-Origin/,
# so on CachyOS ticking that box achieves precisely nothing and the extension
# sits there unable to reach the database. The manifest has to be placed by
# hand; this does it, which is the whole reason this function exists. On a box
# running upstream Brave (Omarchy, via brave-bin) it lands in Brave-Browser and
# agrees with the checkbox — see brave_profile_dir().
configure_keepassxc_browser() {
    have keepassxc-proxy || { skip "keepassxc not installed — skipping browser integration"; return; }

    local profile; profile="$(brave_profile_dir)"
    local nm_dir="$profile/NativeMessagingHosts"
    local manifest="$nm_dir/org.keepassxc.keepassxc_browser.json"
    local ini="$HOME/.config/keepassxc/keepassxc.ini"

    if [[ $DRY_RUN -eq 1 ]]; then
        run "write $manifest"
        run "set Browser/Enabled=true in $ini"
        report "KeePassXC" "would wire browser integration to ${profile##*/}"
        return
    fi

    # KeePassXC rewrites its ini on exit, so a running instance would undo this.
    if pgrep -x keepassxc >/dev/null 2>&1; then
        warn "KeePassXC is running — close it and re-run '--only config', or it will overwrite this"
    fi

    mkdir -p "$nm_dir"
    cat > "$manifest" <<EOF
{
    "allowed_origins": [
        "chrome-extension://pdffhmdngciaglkoonimfcmckehcpafo/",
        "chrome-extension://oboonakemofpalcgghocfoadofidjkkk/"
    ],
    "description": "KeePassXC integration with native messaging support",
    "name": "org.keepassxc.keepassxc_browser",
    "path": "$(command -v keepassxc-proxy)",
    "type": "stdio"
}
EOF

    # The manifest alone isn't enough — KeePassXC won't answer the proxy unless
    # browser integration is switched on in its own settings.
    #
    # kwriteconfig6 when it's there, a python fallback when it isn't. This is
    # NOT a KDE-only step — KeePassXC is Qt, not KDE, and it is exactly as
    # useful on Omarchy — but kwriteconfig6 ships in kconfig, which a Hyprland
    # box has no reason to carry. Calling it unguarded there is not a skipped
    # setting: it is exit 127, and set -e ends the entire run on the spot.
    mkdir -p "$(dirname "$ini")"
    if ! ini_set "$ini" Browser Enabled true; then
        warn "couldn't enable browser integration in $ini — tick it by hand in KeePassXC's settings"
    fi

    ok "KeePassXC browser integration wired to ${profile##*/}"
    report "KeePassXC" "browser integration enabled + ${profile##*/} manifest installed"
    info "  You still need the KeePassXC-Browser extension in Brave itself."
}

# Set the CPU power profile.
#
# power-profiles-daemon does NOT remember the active profile across reboots — it
# comes up on its default ("balanced") every time. Setting it once here would
# last until the next boot and no longer, so we also install a user service that
# reapplies it at login.
configure_power_profile() {
    if ! have powerprofilesctl; then
        warn "powerprofilesctl not found — skipping power profile"
        report "Power" "SKIPPED (power-profiles-daemon not installed)"
        return
    fi

    # dbus-activatable, so it works unenabled — but then nothing reapplies the
    # profile after a reboot.
    #
    # The `|| warn` matters: the command after a final `||` is NOT exempt from
    # set -e, so a failing enable would kill the whole run here and skip every
    # step after it (Brave, KeePassXC, the taskbar). And it can legitimately
    # fail — tuned-ppd also provides powerprofilesctl, so the `have` check above
    # passes on a machine where this unit doesn't exist at all.
    if ! systemctl is-enabled power-profiles-daemon >/dev/null 2>&1; then
        run sudo systemctl enable --now power-profiles-daemon \
            || warn "couldn't enable power-profiles-daemon (using tuned-ppd instead?)"
    fi

    # Not every machine offers every profile: it depends on the CPU's scaling
    # driver. A VM typically has no 'performance' at all. Setting a profile that
    # doesn't exist is an error, so check before asking for it.
    if ! powerprofilesctl list 2>/dev/null | grep -q "$POWER_PROFILE"; then
        warn "'$POWER_PROFILE' profile isn't available on this machine (no scaling driver? a VM?)"
        warn "available: $(powerprofilesctl list 2>/dev/null | grep -oE '^\*?[[:space:]]*[a-z-]+:' | tr -d '*: ' | tr '\n' ' ')"
        report "Power" "SKIPPED ('$POWER_PROFILE' unavailable here)"
        return
    fi

    run powerprofilesctl set "$POWER_PROFILE"

    # Reapply at every login, since the daemon won't remember it.
    local unit_dir="$HOME/.config/systemd/user"
    local unit="$unit_dir/power-profile.service"

    if [[ $DRY_RUN -eq 1 ]]; then
        run "write $unit (reapplies '$POWER_PROFILE' at login)"
        run "systemctl --user enable power-profile.service"
        report "Power" "would set '$POWER_PROFILE' and reapply at login"
        return
    fi

    mkdir -p "$unit_dir"
    cat > "$unit" <<EOF
[Unit]
Description=Set the power profile to $POWER_PROFILE
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=oneshot
ExecStart=$(command -v powerprofilesctl) set $POWER_PROFILE

[Install]
WantedBy=graphical-session.target
EOF

    systemctl --user daemon-reload 2>/dev/null || true
    if systemctl --user enable power-profile.service >/dev/null 2>&1; then
        ok "power profile set to '$POWER_PROFILE', and reapplied at each login"
        report "Power" "'$POWER_PROFILE' set, persists across reboots"
    else
        warn "set '$POWER_PROFILE' for this boot, but couldn't enable the login service"
        report "Power" "'$POWER_PROFILE' set (will reset on reboot)"
    fi
}

# Stop the desktop putting itself to sleep behind your back.
#
# Distinct from configure_power_profile above: that one is the CPU's governor
# (power-profiles-daemon), this is KDE's idle behaviour (powerdevil). The two are
# unrelated and live in different places, despite both being "power" in the UI.
#
# The settings, in KDE's own words:
#
#   Suspend session, when inactive:  Do nothing
#   Dim automatically:               Never
#   Turn off screen:                 after SCREEN_OFF_MINS
#     ...when locked:                after SCREEN_OFF_LOCKED_MINS
#
# A box that suspends mid-download, mid-build, or mid-stream is worse than
# useless, and a desktop isn't running off a battery — but blanking the screen is
# still worth having, since a static desktop left on for hours is how OLED panels
# acquire a permanent taskbar.
#
# Everything else on that page (power button shows the logout screen, no profile
# switching on idle) is already KDE's default, so it isn't written here: keys
# absent from powerdevilrc mean "the default", and pinning them would only create
# something to drift out of date the day KDE changes its mind.
configure_powerdevil() {
    local conf="$HOME/.config/powerdevilrc"

    # powerdevil IS Plasma's power manager — there is no version of it running
    # anywhere else, and powerdevilrc on a box without Plasma is a file nothing
    # will ever read. Gated on the desktop rather than on `have kwriteconfig6`,
    # which passes on any machine carrying a single KDE application.
    if [[ "$DESKTOP" != kde ]]; then
        skip "not KDE ($(desktop_label)) — powerdevil isn't what handles idle here"
        report "Power (KDE)" "SKIPPED (not KDE — $(desktop_label))"
        if [[ "$DESKTOP" == omarchy ]]; then
            info "  Omarchy idles through hypridle — ~/.config/hypr/hypridle.conf, or Omarchy's own settings menu."
        fi
        return 0
    fi

    if ! have kwriteconfig6; then
        warn "kwriteconfig6 not found — skipping the KDE power settings"
        report "Power (KDE)" "SKIPPED (kwriteconfig6 missing)"
        return
    fi

    local off=$(( SCREEN_OFF_MINS * 60 ))
    local off_locked=$(( SCREEN_OFF_LOCKED_MINS * 60 ))

    if [[ $DRY_RUN -eq 1 ]]; then
        run "kwriteconfig6 --file $conf [AC][SuspendAndShutdown] AutoSuspendAction=0"
        run "kwriteconfig6 --file $conf [AC][Display] no dimming, screen off after ${off}s (${off_locked}s locked)"
        report "Power (KDE)" "would never suspend; screen off after ${SCREEN_OFF_MINS}m"
        return
    fi

    # 0 is powerdevil's "do nothing" — the same value the GUI writes when you pick
    # it from the dropdown. There's no separate "idle suspend off" switch.
    kwriteconfig6 --file "$conf" --group AC --group SuspendAndShutdown \
        --key AutoSuspendAction 0

    # DimDisplayIdleTimeoutSec is dead while WhenIdle is false, but the KCM writes
    # -1 next to it regardless, and matching it keeps this file identical to a
    # hand-configured one. The `--` is load-bearing: without it kwriteconfig6
    # reads the -1 as a command-line option and exits 1, which under set -e takes
    # the whole run down with it.
    kwriteconfig6 --file "$conf" --group AC --group Display \
        --key DimDisplayWhenIdle --type bool false
    kwriteconfig6 --file "$conf" --group AC --group Display \
        --key DimDisplayIdleTimeoutSec -- -1

    kwriteconfig6 --file "$conf" --group AC --group Display \
        --key TurnOffDisplayWhenIdle --type bool true
    kwriteconfig6 --file "$conf" --group AC --group Display \
        --key TurnOffDisplayIdleTimeoutSec "$off"
    kwriteconfig6 --file "$conf" --group AC --group Display \
        --key TurnOffDisplayIdleTimeoutWhenLockedSec "$off_locked"

    # powerdevil reads its config once at startup, so a running session keeps the
    # old idle timers until told otherwise. Ask it to re-read them; if it isn't
    # running (no desktop session — an SSH run, say) there's nothing to tell, and
    # the file we just wrote is picked up at next login anyway.
    if have qdbus6; then
        qdbus6 org.kde.Solid.PowerManagement /org/kde/Solid/PowerManagement \
            org.kde.Solid.PowerManagement.reparseConfiguration >/dev/null 2>&1 || true
    else
        dbus-send --session --type=method_call --dest=org.kde.Solid.PowerManagement \
            /org/kde/Solid/PowerManagement \
            org.kde.Solid.PowerManagement.reparseConfiguration >/dev/null 2>&1 || true
    fi

    ok "never suspends, never dims; screen off after ${SCREEN_OFF_MINS}m (${SCREEN_OFF_LOCKED_MINS}m locked)"
    report "Power (KDE)" "no suspend, no dimming, screen off after ${SCREEN_OFF_MINS}m"
}

# Pin the taskbar launchers, in the order given in packages/taskbar.txt.
#
# Plasma keeps these in the Icons-only Task Manager applet's config. The applet
# and containment IDs are assigned at first login and differ per machine, so they
# have to be looked up rather than hardcoded.
configure_taskbar() {
    local conf="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
    local list="$PKG_DIR/taskbar.txt"

    # Everything below this line — pinned launchers, tray visibility, panel
    # height, stopping and restarting plasmashell — is the Plasma panel and
    # nothing else. Omarchy's bar is Waybar, which has no pinned-launcher
    # concept at all: there is no equivalent to do instead, so the honest thing
    # is to skip and say so.
    if [[ "$DESKTOP" != kde ]]; then
        skip "not KDE ($(desktop_label)) — no Plasma panel to pin launchers to"
        report "Taskbar" "SKIPPED (not KDE — $(desktop_label))"
        return 0
    fi

    [[ -f "$list" ]] || { skip "no taskbar.txt — leaving the taskbar alone"; return; }

    if ! have kwriteconfig6; then
        warn "kwriteconfig6 not found — skipping taskbar setup"
        report "Taskbar" "SKIPPED (kwriteconfig6 missing)"
        return
    fi

    # Written at first login to Plasma. If it doesn't exist the user has never
    # logged into the desktop, and there's no applet to configure yet.
    if [[ ! -f "$conf" ]]; then
        warn "Plasma config not found — log into the desktop once, then re-run with --only config"
        report "Taskbar" "SKIPPED (no Plasma session yet)"
        return
    fi

    local entries=()
    mapfile -t entries < <(read_list "$list")
    [[ ${#entries[@]} -gt 0 ]] || { skip "taskbar.txt is empty"; return; }

    # Rebuild KDE's application cache FIRST.
    #
    # Plasma resolves each launcher's icon and name through sycoca, an index
    # built at login. Everything this script installed landed after that, so
    # Plasma doesn't know those .desktop files exist and the tiles render as
    # blank generic-document icons.
    #
    # This MUST run inside the desktop session's environment. KDE hashes
    # XDG_DATA_DIRS into the cache's filename, and a shell that isn't the session
    # (an SSH login, say) has a subtly different value — even just missing
    # trailing slashes. Build it from there and you write a cache under a
    # different hash, leaving the session reading a stale one: the result is an
    # entirely empty application menu. systemd-run --user borrows the real
    # session environment, which is exactly what we need.
    if [[ $DRY_RUN -eq 0 ]] && have kbuildsycoca6; then
        have update-desktop-database && update-desktop-database "$APPS_DIR" 2>/dev/null || true
        if have systemd-run && systemd-run --user --wait --collect --quiet kbuildsycoca6 2>/dev/null; then
            :
        else
            kbuildsycoca6 2>/dev/null || true
        fi
    fi

    # Drop anything that isn't actually installed — a launcher pointing at a
    # missing .desktop shows up as a dead, blank tile.
    local present=() missing=() e
    for e in "${entries[@]}"; do
        if [[ -f "/usr/share/applications/$e" || -f "$APPS_DIR/$e" \
              || -f "/var/lib/flatpak/exports/share/applications/$e" ]]; then
            present+=("$e")
        else
            missing+=("$e")
        fi
    done
    [[ ${#missing[@]} -gt 0 ]] && warn "not installed, so not pinned: ${missing[*]}"
    [[ ${#present[@]} -gt 0 ]] || { warn "none of the taskbar apps are installed"; return; }

    # Find the Icons-only Task Manager applet. Its containment/applet IDs are
    # per-machine, so walk the ini for the group that declares the plugin.
    local group
    group="$(awk '/^\[/ { g=$0 } /^plugin=org\.kde\.plasma\.icontasks$/ { print g; exit }' "$conf")"
    if [[ -z "$group" ]]; then
        warn "couldn't find the taskbar applet in the Plasma config — skipping"
        report "Taskbar" "SKIPPED (no icontasks applet found)"
        return
    fi

    local cont applet
    cont="$(sed -E 's/\[Containments\]\[([0-9]+)\].*/\1/' <<<"$group")"
    applet="$(sed -E 's/.*\[Applets\]\[([0-9]+)\]/\1/' <<<"$group")"

    local launchers=""
    for e in "${present[@]}"; do
        launchers+="${launchers:+,}applications:$e"
    done

    info "Pinning ${#present[@]} launchers..."

    if [[ $DRY_RUN -eq 1 ]]; then
        run "kwriteconfig6 ... launchers=$launchers"
        report "Taskbar" "${#present[@]} launchers would be pinned"
        return
    fi

    # Order matters. plasmashell rewrites this file when it exits, so writing
    # while it's running means our change is overwritten seconds later by its
    # in-memory copy. Quit it first, write, then bring it back.
    local was_running=0
    if pgrep -x plasmashell >/dev/null 2>&1; then
        was_running=1
        PLASMA_STOPPED=1          # cleanup() restores it if we die from here on
        kquitapp6 plasmashell 2>/dev/null || true

        # kquitapp6 returns 0 for a *delivered* DBus message, not for a process
        # that actually exited — so its exit code says nothing. Wait for the
        # process to really go, and escalate if it won't. Writing the config
        # under a live plasmashell means it dumps its in-memory copy over our
        # changes the moment it next exits: launchers, height and tray settings
        # all silently reverted, while we cheerfully print "✓ taskbar pinned".
        local i
        for i in {1..20}; do
            pgrep -x plasmashell >/dev/null 2>&1 || break
            sleep 0.5
        done
        if pgrep -x plasmashell >/dev/null 2>&1; then
            warn "plasmashell ignored the quit request — killing it so it can't revert our changes"
            pkill -x plasmashell 2>/dev/null || true
            sleep 1
        fi
        if pgrep -x plasmashell >/dev/null 2>&1; then
            warn "can't stop plasmashell — skipping panel changes rather than have them silently reverted"
            report "Taskbar" "SKIPPED (plasmashell wouldn't stop)"
            PLASMA_STOPPED=0
            return 0
        fi
    fi

    kwriteconfig6 --file "$conf" \
        --group Containments --group "$cont" \
        --group Applets --group "$applet" \
        --group Configuration --group General \
        --key launchers "$launchers"

    # Safe to edit the file directly: plasmashell is stopped, so nothing is going
    # to write its in-memory copy over the top of us.
    panel_remove_widgets "$conf" "$cont"
    tray_hide_items "$conf" "$cont"

    # Panel height lives in plasmashellrc, keyed by the same containment id —
    # not in the appletsrc with the rest of the panel's configuration.
    kwriteconfig6 --file "$HOME/.config/plasmashellrc" \
        --group PlasmaViews --group "Panel $cont" --group Defaults \
        --key thickness "$PANEL_HEIGHT"
    ok "panel height set to ${PANEL_HEIGHT}px"

    if [[ $was_running -eq 0 ]]; then
        ok "taskbar pinned (applies at next login)"
        report "Taskbar" "${#present[@]} launchers pinned — takes effect at next login"
        return
    fi

    # Restart it through systemd, NOT by launching it directly.
    #
    # Plasma 6 runs plasmashell as a systemd user unit, so restarting the unit
    # hands it the session's real environment. Spawning it straight from this
    # shell hands it OUR environment instead — and if this script is being run
    # from anywhere but a terminal inside the session, that environment is subtly
    # wrong, which produces a plasmashell that cannot see a single installed
    # application. An empty menu and seven blank tiles.
    if ! systemctl --user restart plasma-plasmashell.service 2>/dev/null; then
        setsid plasmashell > /dev/null 2>&1 &
        disown 2>/dev/null || true
    fi

    # Confirm it actually came back before disarming cleanup()'s safety net.
    # Clearing the flag on faith means that if plasmashell failed to start — say
    # `setsid plasmashell` from a shell with no Wayland display, where it dies
    # instantly — we'd print "✓ restarted", disarm the one thing that would have
    # rescued it, and leave the user staring at a desktop with no panel.
    local i
    for i in {1..20}; do
        pgrep -x plasmashell >/dev/null 2>&1 && break
        sleep 0.5
    done

    if pgrep -x plasmashell >/dev/null 2>&1; then
        PLASMA_STOPPED=0
        ok "taskbar pinned (plasmashell restarted)"
    else
        warn "plasmashell didn't come back — cleanup will try again on exit; log out and in if the panel is missing"
    fi
    report "Taskbar" "${#present[@]} launchers pinned, in order"
    return 0
}

# ── Omarchy desktop ───────────────────────────────────────────────────────────
#
# Everything Omarchy-specific lives in this one step, gated on the detected
# desktop, and every piece of it is skipped with a reason on KDE or anything
# else. The pieces are separate functions rather than one long one because each
# writes a different file and each has to be able to fail on its own: a theme
# that won't apply must not stop the bar from being configured.
#
# What it configures, and where that lands:
#
#   ~/.config/omarchy/shell.toml    shell text size          (hot-reloaded)
#   ~/.config/omarchy/shell.json    bar layout and widgets   (hot-reloaded)
#   ~/.config/omarchy/plugins/      the bar and tray clones, hyprmoncfg
#   ~/.config/hypr/                 window rules, input, monitors
#   ~/.config/foot/foot.ini         terminal font size
#
# Nothing here writes to /usr/share/omarchy. That directory belongs to the
# omarchy package and `omarchy update` overwrites it, so a change made there
# survives exactly until the next update.
configure_omarchy() {
    step "Omarchy desktop"

    if [[ "$DESKTOP" != omarchy ]]; then
        skip "not Omarchy ($(desktop_label)) — there's no omarchy-shell here to configure"
        report "Omarchy" "SKIPPED (not Omarchy — $(desktop_label))"
        return 0
    fi

    if ! have omarchy; then
        warn "the omarchy CLI isn't on PATH — skipping the Omarchy desktop config"
        report "Omarchy" "SKIPPED (omarchy CLI missing)"
        return 0
    fi

    # Set by the pieces below when they change something the running shell has
    # already read, so the restart at the end happens once instead of five times.
    OMARCHY_SHELL_DIRTY=0

    omarchy_shell_font
    omarchy_theme
    omarchy_background
    omarchy_plugins
    omarchy_bar_layout
    omarchy_hypr
    omarchy_terminal_font
    omarchy_default_agent
    omarchy_mise_quiet
    omarchy_restart_shell

    return 0
}

# Shell text size — the bar and everything else omarchy-shell draws.
#
# ~/.config/omarchy/shell.toml is a machine-level override layered on top of
# whichever theme is active, so the size survives a theme switch, and the shell
# watches the file, so it re-flows live. [font] base-size is the rem root every
# other size derives from; the bar's own height tracks it too, because [bar]
# scale-with-font defaults to true.
#
# Deliberately NOT `omarchy display text size`, which writes this same key but
# also drives GTK's text-scaling-factor and every terminal's font size in
# lockstep. We want the shell bigger and the rest of the desktop left alone.
#
# The awk below mirrors omarchy-display-text-size's own upsert: replace
# base-size in place if it's there, insert it into an existing [font] section,
# or append a fresh section. Any other section in the file is left untouched.
omarchy_shell_font() {
    local conf="$HOME/.config/omarchy/shell.toml"
    local want="$OMARCHY_SHELL_FONT_PX" current=""

    if [[ -f "$conf" ]]; then
        current="$(awk '
            /^[[:space:]]*\[/ { in_font = ($0 ~ /^[[:space:]]*\[font\]([[:space:]]|$)/); next }
            in_font && /^[[:space:]]*base-size[[:space:]]*=/ {
                v = $0; sub(/^[^=]*=[[:space:]]*/, "", v); sub(/[[:space:]]*(#.*)?$/, "", v)
                print v; exit
            }' "$conf")"
    fi

    if [[ "$current" == "$want" ]]; then
        skip "shell text already ${want}px"
        report "Omarchy shell" "text already ${want}px"
        return 0
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        run "set [font] base-size = $want in $conf"
        report "Omarchy shell" "would set shell text to ${want}px"
        return 0
    fi

    mkdir -p "$(dirname "$conf")"
    if [[ ! -f "$conf" ]]; then
        printf '[font]\nbase-size = %s\n' "$want" > "$conf"
    else
        local tmp; tmp="$(mktemp)"
        awk -v val="$want" '
            function emit() { print "base-size = " val; done = 1 }
            /^[[:space:]]*\[/ {
                if (in_font && !done) emit()
                in_font = ($0 ~ /^[[:space:]]*\[font\]([[:space:]]|$)/)
                print; next
            }
            in_font && /^[[:space:]]*base-size[[:space:]]*=/ { if (!done) emit(); next }
            { print }
            END {
                if (in_font && !done) emit()
                else if (!done) { print "[font]"; print "base-size = " val }
            }' "$conf" > "$tmp"
        mv "$tmp" "$conf"
    fi

    OMARCHY_SHELL_DIRTY=1
    ok "shell text ${want}px (GTK apps and terminals left alone)"
    report "Omarchy shell" "text ${want}px"
}

# Theme. `omarchy theme set` regenerates every themed config and restarts what
# needs restarting, so it is not a cheap no-op — check the current theme first.
omarchy_theme() {
    local current=""
    [[ -r "$HOME/.local/state/omarchy/current/theme.name" ]] \
        && current="$(cat "$HOME/.local/state/omarchy/current/theme.name")"

    if [[ "$current" == "$OMARCHY_THEME" ]]; then
        skip "theme already $OMARCHY_THEME"
        report "Omarchy theme" "already $OMARCHY_THEME"
        return 0
    fi

    if run omarchy theme set "$OMARCHY_THEME"; then
        ok "theme set to $OMARCHY_THEME"
        report "Omarchy theme" "$OMARCHY_THEME"
    else
        warn "couldn't set the $OMARCHY_THEME theme — is it installed? (omarchy theme list)"
        report "Omarchy theme" "FAILED to set $OMARCHY_THEME"
    fi
}

# Wallpapers. Omarchy reads a theme's backgrounds from
# ~/.config/omarchy/backgrounds/<theme>/, which is the user's own folder — the
# stock ones live under the theme in /usr/share and are left alone, so these are
# added alongside them rather than replacing anything.
omarchy_background() {
    local src="$REPO_DIR/omarchy/backgrounds/$OMARCHY_THEME"
    local dest="$HOME/.config/omarchy/backgrounds/$OMARCHY_THEME"

    if [[ ! -d "$src" ]]; then
        skip "no wallpapers vendored for $OMARCHY_THEME"
        return 0
    fi

    local copied=0 f
    for f in "$src"/*; do
        [[ -f "$f" ]] || continue
        if [[ -f "$dest/$(basename "$f")" ]] && cmp -s "$f" "$dest/$(basename "$f")"; then
            continue
        fi
        [[ $DRY_RUN -eq 1 ]] || mkdir -p "$dest"
        run cp "$f" "$dest/"
        copied=$((copied + 1))
    done

    if [[ $copied -gt 0 ]]; then
        ok "$copied wallpaper(s) installed for $OMARCHY_THEME"
        report "Omarchy wallpaper" "$copied installed"
    else
        skip "wallpapers already installed"
    fi

    # Selecting one is separate: the copy above is just files on disk, and the
    # current background is a symlink in ~/.local/state that the shell follows.
    [[ -n "$OMARCHY_BACKGROUND" ]] || return 0
    local want="$dest/$OMARCHY_BACKGROUND"
    if [[ ! -f "$want" && $DRY_RUN -eq 0 ]]; then
        warn "background $OMARCHY_BACKGROUND isn't in $dest — leaving the current one"
        return 0
    fi

    local current=""
    current="$(readlink -f "$HOME/.local/state/omarchy/current/background" 2>/dev/null || true)"
    if [[ "$current" == "$want" ]]; then
        skip "background already $OMARCHY_BACKGROUND"
        return 0
    fi

    if run omarchy theme bg set "$want"; then
        ok "background set to $OMARCHY_BACKGROUND"
        report "Omarchy wallpaper" "set to $OMARCHY_BACKGROUND"
    else
        warn "couldn't set the background to $OMARCHY_BACKGROUND"
    fi
}

# Shell plugins: the third-party ones from git, then the two first-party ones we
# carry patches for.
#
# The bar and the tray are Omarchy's own code. Editing it in place under
# /usr/share/omarchy would last until the next `omarchy update`, so both are
# cloned into ~/.config/omarchy/plugins/ — which is what `omarchy plugin clone`
# is for — and the clone is patched. The clone id is always
# <username>.<plugin>, assigned by omarchy-plugin-clone itself.
omarchy_plugins() {
    local url found d

    for url in "${OMARCHY_PLUGINS_GIT[@]}"; do
        found=""
        for d in "$HOME"/.config/omarchy/plugins/*/; do
            [[ -d "$d/.git" ]] || continue
            [[ "$(git -C "$d" remote get-url origin 2>/dev/null)" == "$url" ]] && found="$d"
        done
        if [[ -n "$found" ]]; then
            skip "$(basename "${found%/}") already installed"
            continue
        fi
        if run omarchy plugin add "$url" --enable --yes; then
            ok "installed $(basename "$url" .git)"
            report "Omarchy plugins" "added $(basename "$url" .git)"
            OMARCHY_SHELL_DIRTY=1
        else
            warn "couldn't install the shell plugin from $url"
        fi
    done

    omarchy_clone_and_patch omarchy.bar  "$REPO_DIR/omarchy/patches/bar-islands.patch" \
        "/usr/share/omarchy/shell/plugins/bar/Bar.qml" "$OMARCHY_BAR_BASELINE_SHA" \
        "island bar"
    omarchy_clone_and_patch omarchy.tray "$REPO_DIR/omarchy/patches/tray-collapse.patch" \
        "/usr/share/omarchy/shell/plugins/bar/widgets/Tray.qml" "$OMARCHY_TRAY_BASELINE_SHA" \
        "tray drawer"
}

# Clone one first-party plugin and apply our patch to it.
#
#   $1  source plugin id (omarchy.bar)
#   $2  patch file
#   $3  the upstream file the patch was generated against
#   $4  that file's sha256 at the time it was generated
#   $5  human label for the messages
#
# A patch that no longer applies is a warning, never a failure: Omarchy ships new
# shell code on its own schedule, and a bar that looks stock is a far better
# outcome than a run that dies — or, worse, a half-patched QML file that stops
# the shell from starting at all.
omarchy_clone_and_patch() {
    local source_id="$1" patch_file="$2" upstream="$3" baseline_sha="$4" label="$5"
    local clone_id="${USER:-$(id -un)}.${source_id#omarchy.}"
    local dir="$HOME/.config/omarchy/plugins/$clone_id"

    if [[ ! -f "$patch_file" ]]; then
        warn "$patch_file is missing — skipping the $label patch"
        return 0
    fi

    # patch rides in with base-devel, which the packages step installs, so this
    # only fires on a --only omarchy run against a box that never had one.
    if ! have patch; then
        warn "the 'patch' command isn't installed — skipping the $label patch"
        report "Omarchy plugins" "SKIPPED $label (no patch command)"
        return 0
    fi

    if [[ ! -d "$dir" ]]; then
        if ! run omarchy plugin clone "$source_id"; then
            warn "couldn't clone $source_id — skipping the $label patch"
            return 0
        fi
        OMARCHY_SHELL_DIRTY=1
    fi

    # -R --dry-run succeeds when the patch is ALREADY in the file: that is the
    # idempotence check. Without it a second run would fail noisily, or apply the
    # hunks twice with enough fuzz to do real damage. It reads and writes
    # nothing, so it runs before the dry-run branch — a dry run that claims it
    # would patch an already-patched file is a dry run telling you the wrong
    # thing about the machine.
    if [[ -d "$dir" ]] && patch -p1 -R --dry-run -f -s -d "$dir" < "$patch_file" >/dev/null 2>&1; then
        skip "$clone_id already carries the $label patch"
        report "Omarchy plugins" "$clone_id already patched ($label)"
        return 0
    fi

    # Nothing left to patch on a dry run: on a fresh box the clone above never
    # happened, so there is no file here to test the hunks against.
    if [[ $DRY_RUN -eq 1 ]]; then
        run "patch -p1 -d $dir < $patch_file   # $label"
        report "Omarchy plugins" "would patch $clone_id ($label)"
        return 0
    fi

    # Warn, then try anyway. The patch is context-based, so it often still
    # applies to a changed file — and when it doesn't, the failure below says so.
    if [[ -n "$baseline_sha" && -r "$upstream" ]]; then
        local now; now="$(sha256sum "$upstream" | awk '{print $1}')"
        if [[ "$now" != "$baseline_sha" ]]; then
            warn "$(basename "$upstream") has changed since the $label patch was made — trying it anyway"
        fi
    fi

    if patch -p1 --forward -s -d "$dir" < "$patch_file" >/dev/null 2>&1; then
        OMARCHY_SHELL_DIRTY=1
        ok "$clone_id patched ($label)"
        report "Omarchy plugins" "$clone_id patched ($label)"
    else
        warn "the $label patch didn't apply to $clone_id — it's running Omarchy's stock code"
        report "Omarchy plugins" "$label patch FAILED (stock $source_id in use)"
        # Leave no half-applied file behind: .rej/.orig next to live QML would
        # be loaded by the shell as if it were code.
        find "$dir" -name '*.rej' -o -name '*.orig' -delete 2>/dev/null || true
    fi
}

# Bar layout: which widgets sit where, and the two clones taking over from the
# first-party bar and tray.
#
# shell.json is a plain JSON file the shell watches, so this applies live. It is
# edited rather than overwritten — the layout is something you also change by
# dragging widgets around the bar, and a setup script has no business throwing
# that away on every run.
omarchy_bar_layout() {
    local conf="$HOME/.config/omarchy/shell.json"
    local stock="/usr/share/omarchy/config/omarchy/shell.json"
    local bar_id="${USER:-$(id -un)}.bar"
    local tray_id="${USER:-$(id -un)}.tray"

    if [[ ! -f "$conf" ]]; then
        if [[ $DRY_RUN -eq 1 ]]; then
            run "seed $conf from $stock"
        elif [[ -r "$stock" ]]; then
            mkdir -p "$(dirname "$conf")"
            cp "$stock" "$conf"
        else
            warn "no $conf and no stock shell.json to seed it from — skipping the bar layout"
            return 0
        fi
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        run "set bar.id=$bar_id, tray=$tray_id, clock format, extra widgets in $conf"
        report "Omarchy bar" "would set the bar layout"
        return 0
    fi

    # Only claim the cloned bar/tray when the clone is actually there and
    # patched — pointing shell.json at a plugin that doesn't exist is how you
    # get no bar at all.
    [[ -d "$HOME/.config/omarchy/plugins/$bar_id"  ]] || bar_id=""
    [[ -d "$HOME/.config/omarchy/plugins/$tray_id" ]] || tray_id=""

    local before after
    before="$(cat "$conf")"

    BAR_ID="$bar_id" TRAY_ID="$tray_id" \
    CLOCK_FORMAT="$OMARCHY_CLOCK_FORMAT" CLOCK_VERTICAL="$OMARCHY_CLOCK_FORMAT_VERTICAL" \
    EXTRA_RIGHT="$(IFS=,; printf '%s' "${OMARCHY_BAR_RIGHT_EXTRA[*]}")" \
    BAR_MONITORS="$(IFS=,; printf '%s' "${OMARCHY_BAR_MONITORS[*]}")" \
    python - "$conf" <<'PY'
import json, os, sys

path = sys.argv[1]
with open(path) as f:
    data = json.load(f)

bar = data.setdefault("bar", {})
layout = bar.setdefault("layout", {})
right = layout.setdefault("right", [])
center = layout.setdefault("center", [])

bar_id, tray_id = os.environ["BAR_ID"], os.environ["TRAY_ID"]

# The bar plugin itself. Absent id means "use the built-in bar", which is what
# the key looks like on a stock install, so only write it when we have a clone.
if bar_id:
    bar["id"] = bar_id

# The tray widget is a layout entry like any other, so swapping it is a matter
# of renaming the entry in place — which keeps its position in the section.
if tray_id:
    for entry in right:
        if entry.get("id") in ("omarchy.tray", tray_id):
            entry["id"] = tray_id

# Extra widgets go directly after the tray, matching the real bar. Anything the
# user has since dragged elsewhere is left where they put it.
have_ids = {e.get("id") for e in right}
extras = [w for w in os.environ["EXTRA_RIGHT"].split(",") if w and w not in have_ids]
if extras:
    tray_names = {tray_id, "omarchy.tray"} - {""}
    at = next((i for i, e in enumerate(right) if e.get("id") in tray_names), -1)
    right[at + 1:at + 1] = [{"id": w} for w in extras]

# Which monitors carry a bar. Read by the patched bar clone; stock Omarchy has
# no such key and puts one on every screen.
monitors = [m for m in os.environ["BAR_MONITORS"].split(",") if m]
if monitors:
    bar["monitors"] = monitors

# Clock formats. Qt date-format strings, and the widget re-renders on save.
for entry in center:
    if entry.get("id") == "omarchy.clock":
        entry["format"] = os.environ["CLOCK_FORMAT"]
        entry["verticalFormat"] = os.environ["CLOCK_VERTICAL"]

# sort_keys matches how omarchy-shell itself serializes this file, so the next
# widget you drag doesn't produce a diff that is mostly key reordering.
with open(path, "w") as f:
    json.dump(data, f, indent=2, sort_keys=True, ensure_ascii=False)
    f.write("\n")
PY

    after="$(cat "$conf")"
    if [[ "$before" == "$after" ]]; then
        skip "bar layout already set"
        report "Omarchy bar" "layout already set"
    else
        OMARCHY_SHELL_DIRTY=1
        ok "bar layout set (${bar_id:-stock bar}, clock, ${#OMARCHY_BAR_RIGHT_EXTRA[@]} extra widget(s))"
        report "Omarchy bar" "layout, clock format, ${#OMARCHY_BAR_RIGHT_EXTRA[@]} extra widget(s)"
    fi
}

# Hyprland: window rules, input, monitors.
#
# ~/.config/hypr/*.lua are yours — Omarchy ships them once and never touches
# them again, which is exactly why a setup script must not rewrite them either.
# So the rules live in their own file that this repo owns and replaces whole,
# and hyprland.lua gets one dofile line pointing at it. The only edits made to
# Omarchy's own files are single lines, added only when they aren't there yet.
omarchy_hypr() {
    local hypr="$HOME/.config/hypr"
    local changed=0

    [[ -d "$hypr" ]] || { skip "no ~/.config/hypr — is this really Omarchy?"; return 0; }

    # 1. The rules file, replaced wholesale on every run.
    local src="$REPO_DIR/omarchy/hypr/personal.lua" dst="$hypr/arch-setup.lua"
    if [[ -f "$src" ]] && ! cmp -s "$src" "$dst" && run cp "$src" "$dst"; then
        changed=1
        ok "window rules and session PATH installed (hypr/arch-setup.lua)"
        report "Omarchy hypr" "window rules + session PATH"
    fi

    # 2. One line in hyprland.lua to load it. Appended at the end, which is
    #    where Omarchy's own comment invites personal configuration, and after
    #    require("hypr.input") so these rules win.
    local main="$hypr/hyprland.lua"
    if [[ -f "$main" ]] && ! grep -qF 'hypr/arch-setup.lua' "$main"; then
        if [[ $DRY_RUN -eq 1 ]]; then
            run "append the arch-setup.lua dofile line to $main"
        else
            printf '\n-- Added by arch-setup: personal window rules and session PATH.\ndofile(os.getenv("HOME") .. "/.config/hypr/arch-setup.lua")\n' >> "$main"
        fi
        changed=1
    fi

    # 3. Mouse acceleration, in input.lua where Omarchy documents input overrides.
    #    Appended, not written: input.lua is also where you'd put a keyboard
    #    layout, and that must survive.
    local input_src="$REPO_DIR/omarchy/hypr/input-accel.lua" input="$hypr/input.lua"
    if [[ -f "$input_src" && -f "$input" ]] && ! grep -qF 'accel_profile' "$input"; then
        if [[ $DRY_RUN -eq 1 ]]; then
            run "append the flat accel_profile block to $input"
        else
            printf '\n' >> "$input"
            cat "$input_src" >> "$input"
        fi
        changed=1
        ok "mouse acceleration off (flat accel profile)"
        report "Omarchy hypr" "flat mouse accel"
    fi

    # 4. Monitors, if this repo carries a layout. Installed only when the file
    #    isn't there: hyprmoncfg REGENERATES it every time you rearrange screens
    #    in its bar widget, so overwriting on every run would throw away the
    #    layout you just set on a machine whose displays differ from these.
    local mon_src="$REPO_DIR/omarchy/hypr/monitors.lua" mon="$hypr/hyprmoncfg-monitors.lua"
    if [[ -f "$mon_src" ]]; then
        if [[ -f "$mon" ]]; then
            skip "monitor layout already present — left as hyprmoncfg wrote it"
        else
            run cp "$mon_src" "$mon"
            changed=1
            ok "monitor layout installed (matched by display name, ignored on other hardware)"
            report "Omarchy hypr" "monitor layout"
        fi
        # hyprmoncfg adds this line itself when it first writes a layout; on a
        # rebuild we get there first. Same text, so it stays one line either way.
        if [[ -f "$main" ]] && ! grep -qF 'hyprmoncfg-monitors.lua' "$main"; then
            if [[ $DRY_RUN -eq 1 ]]; then
                run "append the hyprmoncfg dofile line to $main"
            else
                printf '\n-- Added by hyprmoncfg: its generated monitor rules load last, so nothing before this can override the applied layout.\ndofile(os.getenv("HOME") .. "/.config/hypr/hyprmoncfg-monitors.lua")\n' >> "$main"
            fi
            changed=1
        fi
    fi

    [[ $changed -eq 1 ]] || { skip "Hyprland config already set"; return 0; }

    # Hyprland reloads on its own when a config file is saved, but only for the
    # files it is watching — a brand new dofile target isn't one of them. An
    # explicit reload also gives us configerrors to check, which is the
    # difference between "applied" and "silently ignored".
    if [[ $DRY_RUN -eq 0 && -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] && have hyprctl; then
        hyprctl reload >/dev/null 2>&1 || true
        local errors; errors="$(hyprctl configerrors 2>/dev/null || true)"
        if [[ -n "$errors" && "$errors" != *"no errors"* ]]; then
            warn "Hyprland reported config errors after the reload: $errors"
        fi
    elif [[ $DRY_RUN -eq 0 ]]; then
        info "  Hyprland isn't running here — the config applies at next login"
    fi
}

# foot's font size. Omarchy ships 9pt, which is small on a big screen at scale 1.
# The other three terminals it ships are left alone: this is the one in use, and
# rewriting configs nobody reads is how a setup script grows a reputation.
omarchy_terminal_font() {
    local conf="$HOME/.config/foot/foot.ini"
    [[ -f "$conf" ]] || { skip "no foot.ini — skipping the terminal font"; return 0; }

    local current
    current="$(sed -n 's/^font=.*:size=\([0-9.]*\).*$/\1/p' "$conf" | head -1)"
    if [[ -z "$current" ]]; then
        skip "no font=...:size= line in foot.ini — left alone"
        return 0
    fi
    if [[ "$current" == "$FOOT_FONT_SIZE" ]]; then
        skip "foot font already ${FOOT_FONT_SIZE}pt"
        return 0
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        run "set foot font size to $FOOT_FONT_SIZE in $conf"
        report "Omarchy terminal" "would set foot font to ${FOOT_FONT_SIZE}pt"
        return 0
    fi

    sed -i "s/^\(font=.*:size=\)[0-9.]*/\1$FOOT_FONT_SIZE/" "$conf"
    ok "foot font ${FOOT_FONT_SIZE}pt (was ${current}pt)"
    report "Omarchy terminal" "foot font ${FOOT_FONT_SIZE}pt"
    have omarchy && run omarchy restart terminal >/dev/null 2>&1 || true
}

# Which AI agent Omarchy's menu and keybindings launch. Omarchy ships no
# default and invites you to pick one on first update; this answers that
# question up front so the invitation never fires.
omarchy_default_agent() {
    [[ -n "$OMARCHY_DEFAULT_AGENT" ]] || return 0
    local f="$HOME/.config/omarchy/defaults/agent"

    if [[ -r "$f" && "$(cat "$f" 2>/dev/null)" == "$OMARCHY_DEFAULT_AGENT" ]]; then
        skip "default agent already $OMARCHY_DEFAULT_AGENT"
        return 0
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        run "write $OMARCHY_DEFAULT_AGENT to $f"
        return 0
    fi

    mkdir -p "$(dirname "$f")"
    printf '%s\n' "$OMARCHY_DEFAULT_AGENT" > "$f"
    ok "default agent set to $OMARCHY_DEFAULT_AGENT"
    report "Omarchy" "default agent $OMARCHY_DEFAULT_AGENT"
}

# Stop mise's tool wrappers printing a status banner to stdout.
#
# Omarchy writes ~/.local/bin/<tool> for every mise-managed tool (claude, codex,
# gh, opencode...), and each one runs `mise use -g <tool>` before exec'ing the
# real binary. That command prints "mise <config> tools: <tool>@<version>" — on
# STDOUT, ahead of the output the caller asked for. So on a stock Omarchy box
# every `t="$(gh auth token)"` in every script on the machine captures the
# banner as part of the value. This script's own github_token() is hardened
# against it, but it is far from the only caller, and the fix is one setting.
#
# `quiet` silences mise's informational output only; errors still print.
omarchy_mise_quiet() {
    local conf="$HOME/.config/mise/config.toml"

    have mise || return 0
    [[ -f "$conf" ]] || { skip "no mise config to quieten"; return 0; }

    if grep -qE '^[[:space:]]*quiet[[:space:]]*=' "$conf"; then
        skip "mise already has a quiet setting"
        return 0
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        run "set quiet = true under [settings] in $conf"
        report "Omarchy" "would quieten mise's tool wrappers"
        return 0
    fi

    # TOML forbids the same table twice, so an existing [settings] gets the key
    # inserted into it rather than a second section appended after it.
    if grep -qE '^[[:space:]]*\[settings\][[:space:]]*$' "$conf"; then
        local tmp; tmp="$(mktemp)"
        awk '
            { print }
            !done && /^[[:space:]]*\[settings\][[:space:]]*$/ {
                print "# Silences the \"mise <config> tools: ...\" banner that Omarchy'"'"'s"
                print "# ~/.local/bin wrappers print to STDOUT before every command."
                print "quiet = true"
                done = 1
            }' "$conf" > "$tmp"
        mv "$tmp" "$conf"
    else
        printf '\n[settings]\n# Silences the "mise <config> tools: ..." banner that Omarchy'"'"'s\n# ~/.local/bin wrappers print to STDOUT before every command.\nquiet = true\n' >> "$conf"
    fi

    ok "mise's tool wrappers no longer print a banner over their output"
    report "Omarchy" "mise banner silenced"
}

# One restart at the end instead of one per change.
#
# shell.json, shell.toml and user plugin code all hot-reload on save, so this is
# belt-and-braces for the cases that don't: a plugin that was cloned or added
# mid-run has to be picked up by the registry, not just re-read.
omarchy_restart_shell() {
    [[ ${OMARCHY_SHELL_DIRTY:-0} -eq 1 ]] || return 0

    if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
        info "  no Hyprland session here — the shell picks all this up at next login"
        return 0
    fi

    if run omarchy restart shell; then
        ok "omarchy-shell restarted"
    else
        warn "couldn't restart omarchy-shell — log out and back in to pick up the changes"
    fi
}

ensure_path() {
    # Deliberately does NOT test "$PATH".
    #
    # ensure_claude_cli exports BIN_DIR onto this process's PATH earlier in the
    # run, so by the time we get here $PATH always contains it — and an early
    # return on that basis would skip persisting anything at all. The script would
    # report "already on PATH", and at the user's next login `agenttilecli` would
    # not be a command. Check what's written to disk, not what's in this shell.
    local done_any=0 shells=() already=()

    # fish_add_path silently refuses to add a directory that doesn't exist, so a
    # config-only run (before anything has installed a binary there) would fail
    # with no useful explanation. Make sure the directory is there first.
    run mkdir -p "$BIN_DIR"

    # fish is the CachyOS default. fish_add_path writes a universal variable, so
    # it persists across sessions and is idempotent — running it twice doesn't
    # duplicate the entry.
    #
    # Its exit code is NOT a success signal: it returns non-zero when it made no
    # change, which includes the "already present" case AND, empirically, some
    # runs that did add the path. So set it, then check the variable to see
    # whether it actually took.
    if have fish; then
        if [[ $DRY_RUN -eq 0 ]] && fish -c 'contains "'"$BIN_DIR"'" $fish_user_paths' 2>/dev/null; then
            already+=(fish)
            done_any=1
        else
            run fish -c 'fish_add_path -U "'"$BIN_DIR"'"' || true
            if [[ $DRY_RUN -eq 1 ]] || fish -c 'contains "'"$BIN_DIR"'" $fish_user_paths' 2>/dev/null; then
                ok "added to fish PATH"
                done_any=1
                shells+=(fish)
            else
                warn "fish_add_path didn't take — add $BIN_DIR to fish_user_paths by hand"
            fi
        fi
    fi

    # Cover bash/zsh too, in case the shell ever changes. Guarded on the line
    # already being there so a re-run doesn't keep appending to the rc file.
    local rc name
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        [[ -f "$rc" ]] || continue
        name="$(basename "$rc")"
        if grep -qF '.local/bin' "$rc"; then
            already+=("$name")
            done_any=1
            continue
        fi
        if [[ $DRY_RUN -eq 1 ]]; then
            run "append PATH export to $rc"
        else
            printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$rc"
        fi
        ok "added to $name"
        done_any=1
        shells+=("$name")
    done

    [[ ${#already[@]} -gt 0 ]] && skip "already on PATH for: ${already[*]}"

    if [[ ${#shells[@]} -gt 0 ]]; then
        info "Open a new shell (or 'exec fish') for this to take effect."
        report "PATH" "$BIN_DIR added for: ${shells[*]}"
    elif [[ $done_any -eq 1 ]]; then
        report "PATH" "$BIN_DIR already on PATH"
    else
        warn "couldn't add $BIN_DIR to PATH — add it to your shell config by hand"
        report "PATH" "FAILED — add $BIN_DIR by hand"
    fi
    return 0
}

# ── run ───────────────────────────────────────────────────────────────────────
main() {
    banner
    if [[ $DRY_RUN -eq 1 ]]; then
        printf '   %sDRY RUN%s — showing what would happen. Nothing will be changed.\n' \
            "$BOLD$YELLOW" "$RESET"
    fi

    preflight
    wanted packages     && install_packages
    wanted flatpak      && install_flatpaks
    wanted agenttilecli && install_agenttilecli
    wanted streamhub    && install_streamhub
    wanted consolevault && install_consolevault
    wanted discripper   && install_discripper
    wanted griddown     && install_griddown
    wanted gammagui     && install_gammagui
    wanted lorerim      && install_lorerim
    wanted wotlk        && install_wotlk
    wanted musicai      && install_musicai
    wanted config       && configure_system
    wanted omarchy      && configure_omarchy

    if [[ $DRY_RUN -eq 1 ]]; then
        box "$BOLD$YELLOW" \
            "Dry run complete" \
            "Nothing was installed, changed or downloaded."
        printf '\n'
        return
    fi

    local mins=$((SECONDS / 60)) secs=$((SECONDS % 60))
    box "$BOLD$GREEN" \
        "✓ Done in ${mins}m ${secs}s" \
        "Nothing left to do by hand."

    if [[ ${#SUMMARY[@]} -gt 0 ]]; then
        printf '\n%s  What changed%s\n' "$BOLD" "$RESET"
        local line
        for line in "${SUMMARY[@]}"; do
            printf '    %s\n' "$line"
        done
    fi

    # A warning that scrolled past ten minutes ago is a warning nobody read.
    if [[ ${#WARNINGS[@]} -gt 0 ]]; then
        printf '\n%s  Worth a look%s\n' "$BOLD$YELLOW" "$RESET"
        local w
        for w in "${WARNINGS[@]}"; do
            printf '    %s▲%s %s\n' "$YELLOW" "$RESET" "$w"
        done
    fi

    printf '\n%s  Run them%s\n' "$BOLD" "$RESET"
    printf '    %sagenttilecli%s          tiling terminal for AI CLI sessions\n' "$BOLD" "$RESET"
    printf '    %sStreamHub.AppImage%s    Netflix / Prime / Disney+ in one app\n' "$BOLD" "$RESET"
    printf '    %sConsoleVault.AppImage%s ROM-collection launcher (SNES → PS3)\n' "$BOLD" "$RESET"
    printf '    %sDiscRipper.AppImage%s   auto-rip DVDs/Blu-rays to H.265 (Plex/Jellyfin)\n' "$BOLD" "$RESET"
    printf '    %sGridDown.AppImage%s     offline US maps — roads, trails, terrain\n' "$BOLD" "$RESET"
    printf '    %sStalkerGammaGui.AppImage%s  install, update and play S.T.A.L.K.E.R. GAMMA\n' "$BOLD" "$RESET"
    printf '    %sLorerimAutoinstall.AppImage%s  one-click LoreRim (Wabbajack) install\n' "$BOLD" "$RESET"
    printf '    %sWowWotlkAutoinstall.AppImage%s  one-click WoW 3.3.5a client install\n' "$BOLD" "$RESET"
    printf '    %sMusicAIPlayer.AppImage%s  music for long coding sessions (YouTube import, ACE-Step)\n' "$BOLD" "$RESET"
    printf '    %s(or find everything in the app menu)%s\n\n' "$DIM" "$RESET"
}

# Only auto-run when executed. Sourcing the script (as tests/run.sh does) just
# defines the functions.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
