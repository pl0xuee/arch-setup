#!/usr/bin/env bash
#
# Tests for install.sh. Runs entirely locally — installs nothing, needs no VM.
#
# Covers the parts that can actually be wrong without a fresh machine to try
# them on: argument handling, the package-list parser, the GitHub release-API
# parsing, the generated .desktop file, and that --dry-run really is inert.
#
#   ./tests/run.sh
#
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$TESTS_DIR")"
SCRIPT="$REPO_ROOT/install.sh"

PASS=0; FAIL=0
GREEN=$'\e[32m'; RED=$'\e[31m'; DIM=$'\e[2m'; BOLD=$'\e[1m'; RESET=$'\e[0m'

pass() { PASS=$((PASS+1)); printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$1"; }
fail() { FAIL=$((FAIL+1)); printf '  %s✗%s %s\n' "$RED" "$RESET" "$1"
         [[ $# -gt 1 ]] && printf '      %sgot: %s%s\n' "$DIM" "$2" "$RESET"; }
group(){ printf '\n%s%s%s\n' "$BOLD" "$1" "$RESET"; }

check_eq() { # desc, expected, actual
    if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$2], got [$3]"; fi
}
check_contains() { # desc, needle, haystack
    if [[ "$3" == *"$2"* ]]; then pass "$1"; else fail "$1" "no '$2' in: $3"; fi
}

# Pull in the functions without running main().
# shellcheck source=../install.sh
source "$SCRIPT"
# install.sh runs under `set -euo pipefail`, and sourcing leaks all of that into
# this shell. Each part breaks the suite differently:
#   -e         aborts on the first deliberately-failing command
#   pipefail   makes `awk ... | grep -q ...` report failure even on a match,
#              because grep -q exits early and awk dies of SIGPIPE
#   -u         turns any unset variable in a test into a hard error
# Turn the lot off; the tests manage their own exit codes.
set +e +u +o pipefail

# ── argument handling ─────────────────────────────────────────────────────────
group "Argument handling"

out="$(bash "$SCRIPT" --help 2>&1)"; rc=$?
check_eq "--help exits 0" "0" "$rc"
check_contains "--help documents --dry-run" "--dry-run" "$out"

out="$(bash "$SCRIPT" --bogus 2>&1)"; rc=$?
[[ $rc -ne 0 ]] && pass "unknown option is rejected" || fail "unknown option is rejected" "exit $rc"
check_contains "unknown option names the culprit" "--bogus" "$out"

out="$(bash "$SCRIPT" --only nonsense 2>&1)"; rc=$?
[[ $rc -ne 0 ]] && pass "--only rejects an invalid step" || fail "--only rejects an invalid step" "exit $rc"

# ── set -e footguns ───────────────────────────────────────────────────────────
group "set -e cannot silently kill the run"

# A function whose LAST command is `[[ cond ]] && something` returns 1 when the
# condition is false. Called as `wanted x && install_x`, that's the command after
# the final &&, which set -e does NOT exempt — so the script exits, silently,
# with no summary and every later step skipped. This actually happened.
if awk '/^install_packages\(\)/,/^}/' "$SCRIPT" | grep -qE '^\s*\[\[.*\]\] && report'; then
    fail "install_packages doesn't end on a bare [[ ]] && ..." \
         "returns 1 when nothing new was installed; set -e kills the whole run"
else
    pass "install_packages doesn't end on a bare [[ ]] && ..."
fi

# grep exits 1 on no-match; under pipefail that propagates to the assignment and
# set -e kills the script BEFORE the `|| die` on the next line can report it.
if awk '/^install_streamhub\(\)/,/^}/' "$SCRIPT" | grep -q 'grep -o .*StreamHub.*|| true'; then
    pass "StreamHub asset parsing survives a no-match (|| true)"
else
    fail "StreamHub asset parsing survives a no-match" \
         "a renamed asset would exit 1 with no message instead of the intended die"
fi

if awk '/^install_consolevault\(\)/,/^}/' "$SCRIPT" | grep -q 'grep -o .*_amd64.*|| true'; then
    pass "ConsoleVault asset parsing survives a no-match (|| true)"
else
    fail "ConsoleVault asset parsing survives a no-match" \
         "a renamed asset would exit 1 with no message instead of the intended die"
fi

if awk '/^install_discripper\(\)/,/^}/' "$SCRIPT" | grep -q 'grep -o .*DiscRipper.*|| true'; then
    pass "Disc Ripper asset parsing survives a no-match (|| true)"
else
    fail "Disc Ripper asset parsing survives a no-match" \
         "a renamed asset would exit 1 with no message instead of the intended die"
fi

# Disc Ripper's release has no signature/checksum asset — it verifies against the
# .zsync's SHA-1/length. Assert the verify step exists and is actually wired into
# the install path, so a refactor can't quietly drop the only integrity check.
if awk '/^verify_discripper\(\)/,/^}/' "$SCRIPT" | grep -q 'sha1sum'; then
    pass "Disc Ripper verifies the download against the .zsync sha1"
else
    fail "Disc Ripper verifies the download" "verify_discripper no longer checks a sha1"
fi
if awk '/^install_discripper\(\)/,/^}/' "$SCRIPT" | grep -q 'verify_discripper .* || .*die'; then
    pass "Disc Ripper aborts the install on a failed verify"
else
    fail "Disc Ripper aborts on failed verify" "the download is chmod'd without a passing verify"
fi

if awk '/^install_griddown\(\)/,/^}/' "$SCRIPT" | grep -q 'grep -o .*_amd64.*|| true'; then
    pass "GridDown asset parsing survives a no-match (|| true)"
else
    fail "GridDown asset parsing survives a no-match" \
         "a renamed asset would exit 1 with no message instead of the intended die"
fi

if awk '/^install_gammagui\(\)/,/^}/' "$SCRIPT" | grep -q 'grep -o .*StalkerGammaGui.*|| true'; then
    pass "Stalker GAMMA GUI asset parsing survives a no-match (|| true)"
else
    fail "Stalker GAMMA GUI asset parsing survives a no-match" \
         "a renamed asset would exit 1 with no message instead of the intended die"
fi

if awk '/^install_lorerim\(\)/,/^}/' "$SCRIPT" | grep -q 'grep -o .*LorerimAutoinstall.*|| true'; then
    pass "LoreRim Autoinstall asset parsing survives a no-match (|| true)"
else
    fail "LoreRim Autoinstall asset parsing survives a no-match" \
         "a renamed asset would exit 1 with no message instead of the intended die"
fi

if awk '/^install_wotlk\(\)/,/^}/' "$SCRIPT" | grep -q 'grep -o .*WowWotlkAutoinstall.*|| true'; then
    pass "WotLK Autoinstall asset parsing survives a no-match (|| true)"
else
    fail "WotLK Autoinstall asset parsing survives a no-match" \
         "a renamed asset would exit 1 with no message instead of the intended die"
fi

# The SHA256SUMS URL is grepped out of the same release JSON, and a no-match
# there has to reach verify_wotlk's "cannot verify" message rather than exiting
# silently under pipefail.
if awk '/^install_wotlk\(\)/,/^}/' "$SCRIPT" | grep -q 'grep -o .*download.*SUMS.*|| true'; then
    pass "WotLK SHA256SUMS parsing survives a no-match (|| true)"
else
    fail "WotLK SHA256SUMS parsing survives a no-match" \
         "a release without SHA256SUMS would exit 1 with no message"
fi

# Both new steps must abort rather than chmod an unverified download — same stance
# as the three above, asserted so a refactor can't quietly drop the check.
if awk '/^install_griddown\(\)/,/^}/' "$SCRIPT" | grep -q 'verify_griddown .* || .*die'; then
    pass "GridDown aborts the install on a failed verify"
else
    fail "GridDown aborts on failed verify" "the download is chmod'd without a passing verify"
fi
if awk '/^install_gammagui\(\)/,/^}/' "$SCRIPT" | grep -q 'verify_gammagui .* || .*die'; then
    pass "Stalker GAMMA GUI aborts the install on a failed verify"
else
    fail "Stalker GAMMA GUI aborts on failed verify" "the download is chmod'd without a passing verify"
fi
if awk '/^install_lorerim\(\)/,/^}/' "$SCRIPT" | grep -q 'verify_lorerim .* || .*die'; then
    pass "LoreRim Autoinstall aborts the install on a failed verify"
else
    fail "LoreRim Autoinstall aborts on failed verify" "the download is chmod'd without a passing verify"
fi
if awk '/^install_wotlk\(\)/,/^}/' "$SCRIPT" | grep -q 'verify_wotlk .* || .*die'; then
    pass "WotLK Autoinstall aborts the install on a failed verify"
else
    fail "WotLK Autoinstall aborts on failed verify" "the download is chmod'd without a passing verify"
fi

if awk '/^install_musicai\(\)/,/^}/' "$SCRIPT" | grep -q 'grep -o .*_amd64.*|| true'; then
    pass "Music AI Player asset parsing survives a no-match (|| true)"
else
    fail "Music AI Player asset parsing survives a no-match" \
         "a renamed asset would exit 1 with no message instead of the intended die"
fi
if awk '/^install_musicai\(\)/,/^}/' "$SCRIPT" | grep -q 'verify_musicai .* || .*die'; then
    pass "Music AI Player aborts the install on a failed verify"
else
    fail "Music AI Player aborts on failed verify" "the download is chmod'd without a passing verify"
fi

# `--only` with no value: `shift 2` fails, set -e exits, user sees nothing.
out="$(bash "$SCRIPT" --only 2>&1)"; rc=$?
[[ $rc -ne 0 ]] && pass "--only with no value exits non-zero" || fail "--only with no value exits non-zero"
check_contains "--only with no value explains itself" "needs a step" "$out"

# ── package-list parser ───────────────────────────────────────────────────────
group "Package-list parser"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/list.txt" <<'EOF'
# a leading comment
alpha

beta      # trailing comment
   # indented comment
gamma
EOF

mapfile -t parsed < <(read_list "$tmp/list.txt")
check_eq "strips comments and blanks" "alpha beta gamma" "${parsed[*]}"
check_eq "yields exactly 3 entries" "3" "${#parsed[@]}"

# The real lists must not be empty and must not smuggle a '#' through.
mapfile -t real < <(read_list "$REPO_ROOT/packages/pacman.txt")
[[ ${#real[@]} -gt 0 ]] && pass "pacman.txt is non-empty (${#real[@]} packages)" \
                        || fail "pacman.txt is non-empty"
if printf '%s\n' "${real[@]}" | grep -q '#'; then
    fail "no '#' survives the parser"
else
    pass "no '#' survives the parser"
fi
# A stray space would silently become two bogus package names.
if printf '%s\n' "${real[@]}" | grep -q ' '; then
    fail "no package name contains a space"
else
    pass "no package name contains a space"
fi

mapfile -t fp < <(read_list "$REPO_ROOT/packages/flatpak.txt")
check_eq "flatpak.txt parses to the Dropbox app id" "com.dropbox.Client" "${fp[*]}"

# A stock CachyOS install has no flatpak binary — verified in a VM. If the
# flatpak.txt list is non-empty, pacman.txt MUST install flatpak, or the
# Flatpak step dies on a fresh machine. (It doesn't die here, on a box that
# already has it — which is exactly why this needs asserting.)
if [[ ${#fp[@]} -gt 0 ]]; then
    if printf '%s\n' "${real[@]}" | grep -qx flatpak; then
        pass "pacman.txt installs flatpak (flatpak.txt is non-empty)"
    else
        fail "pacman.txt installs flatpak" "flatpak.txt lists apps but flatpak isn't in pacman.txt"
    fi
fi

# rsync arrived with the desktop-rice step and was kept after it was removed.
if printf '%s\n' "${real[@]}" | grep -qx rsync; then
    pass "pacman.txt installs rsync"
else
    fail "pacman.txt installs rsync" "listed under General desktop"
fi

# kscreen and qt6-imageformats came from the rice too and now live in the
# KDE-only list — both drag a slice of Plasma onto a box that has no use for it.
# Assert they are in exactly one list, so a merge that "tidied" them back into
# pacman.txt doesn't quietly reintroduce that on Omarchy.
# Assert the file exists before reading it. Every check below it is a negative
# ("this name is NOT in that list"), which an empty array satisfies — so without
# this, a list file that was never committed makes the suite go green for
# precisely the deployment it would break.
for f in pacman-cachyos pacman-kde; do
    if [[ -f "$REPO_ROOT/packages/$f.txt" ]]; then
        pass "packages/$f.txt exists"
    else
        fail "packages/$f.txt exists" "install.sh skips a missing list; the checks below would pass on nothing"
    fi
done

mapfile -t kde_pkgs < <(read_list "$REPO_ROOT/packages/pacman-kde.txt")
for p in kscreen qt6-imageformats; do
    if printf '%s\n' "${kde_pkgs[@]}" | grep -qx "$p"; then
        pass "pacman-kde.txt installs $p"
    else
        fail "pacman-kde.txt installs $p" "the KDE-only list is where these belong"
    fi
    if printf '%s\n' "${real[@]}" | grep -qx "$p"; then
        fail "$p is not also in pacman.txt" "it would be installed on Omarchy too"
    else
        pass "$p is not also in pacman.txt"
    fi
done

# The whole point of the split: pacman.txt must be installable on plain Arch.
# Anything cachyos-only left in it fails the ENTIRE pacman transaction there —
# pacman is all-or-nothing on an unknown package name — and takes the run with
# it under set -e, before a single other step has run.
mapfile -t cachy_pkgs < <(read_list "$REPO_ROOT/packages/pacman-cachyos.txt")

# Checked against the plain-Arch repos directly, NOT against the names that
# happen to be in pacman-cachyos.txt. The realistic way this regresses is a
# CachyOS-only package added to pacman.txt and never added to the other list,
# and a cross-list comparison cannot see that at all.
#
# core/extra/multilib are Arch's own repos, present under those names on CachyOS
# too (its optimised rebuilds live in separate cachyos-* repos), so this is a
# real answer to "would plain Arch find this?" from either kind of box.
if arch_only="$(pacman -Sl core extra multilib 2>/dev/null | awk '{print $2}' | sort -u)" \
   && [[ -n "$arch_only" ]]; then
    unavailable=()
    for p in "${real[@]}"; do
        grep -qxF "$p" <<<"$arch_only" || unavailable+=("$p")
    done
    if [[ ${#unavailable[@]} -eq 0 ]]; then
        pass "every one of the ${#real[@]} pacman.txt packages exists in plain Arch's repos"
    else
        fail "every pacman.txt package exists in plain Arch's repos" \
             "Omarchy could not install these, and pacman fails the whole transaction: ${unavailable[*]}"
    fi
else
    printf '  %s·%s core/extra/multilib not all enabled — skipping the plain-Arch availability check\n' "$DIM" "$RESET"
fi

leaked=()
for p in "${cachy_pkgs[@]}"; do
    printf '%s\n' "${real[@]}" | grep -qx "$p" && leaked+=("$p")
done
if [[ ${#leaked[@]} -eq 0 ]]; then
    pass "no CachyOS-only package leaked into pacman.txt (${#cachy_pkgs[@]} checked)"
else
    fail "no CachyOS-only package leaked into pacman.txt" \
         "these would break the whole transaction on Arch: ${leaked[*]}"
fi


# AgentTileCLI's own install.sh preflights every one of these with pkg-config
# (rust as cargo) and refuses to build without them. None can be assumed on a
# bare box: gtksourceview5 is required by nothing else in the list, and
# libadwaita only rides in as a dependency of lact — one lact update away from
# not arriving at all.
for p in rust pkgconf gtk4 vte4 libadwaita gtksourceview5; do
    if printf '%s\n' "${real[@]}" | grep -qx "$p"; then
        pass "pacman.txt installs $p (AgentTileCLI)"
    else
        fail "pacman.txt installs $p (AgentTileCLI)" "AgentTileCLI's build preflight refuses without it"
    fi
done

# Music AI Player's importer shells out to whatever is on PATH — it doesn't
# bundle either of these. Without them the app starts and plays fine and the
# Import panel simply refuses, which is a silent half-install: the feature the
# app's own README calls the reliable way to fill the library just isn't there.
for p in yt-dlp ffmpeg; do
    if printf '%s\n' "${real[@]}" | grep -qx "$p"; then
        pass "pacman.txt installs $p (Music AI Player)"
    else
        fail "pacman.txt installs $p (Music AI Player)" "the YouTube importer refuses without it"
    fi
done

# ── every package actually resolves in an enabled repo ────────────────────────
group "Package names resolve (live pacman query)"

missing=()
for p in "${real[@]}"; do
    pacman -Si "$p" >/dev/null 2>&1 || missing+=("$p")
done
if [[ ${#missing[@]} -eq 0 ]]; then
    pass "all ${#real[@]} packages found in enabled repos"
else
    fail "all packages resolve" "not found: ${missing[*]}"
fi

# The KDE-only list has to resolve too — it goes through the same pacman
# transaction as pacman.txt on any Plasma box.
missing=()
for p in "${kde_pkgs[@]}"; do
    pacman -Si "$p" >/dev/null 2>&1 || missing+=("$p")
done
if [[ ${#missing[@]} -eq 0 ]]; then
    pass "all ${#kde_pkgs[@]} KDE-only packages found in enabled repos"
else
    fail "all KDE-only packages resolve" "not found: ${missing[*]}"
fi

# The cachyos list can only be checked where the CachyOS repos are actually
# enabled — on plain Arch every name in it is expected to be missing, which is
# the entire reason the list exists.
if has_cachyos_repos; then
    missing=()
    for p in "${cachy_pkgs[@]}"; do
        pacman -Si "$p" >/dev/null 2>&1 || missing+=("$p")
    done
    if [[ ${#missing[@]} -eq 0 ]]; then
        pass "all ${#cachy_pkgs[@]} CachyOS-only packages found in the CachyOS repos"
    else
        fail "all CachyOS-only packages resolve" "not found: ${missing[*]}"
    fi

    # And the converse: a package that resolves WITHOUT the CachyOS repos does
    # not belong in this list — it would be needlessly withheld from Arch.
    strays=()
    for p in "${cachy_pkgs[@]}"; do
        repo="$(pacman -Si "$p" 2>/dev/null | awk -F': ' '/^Repository/{print $2; exit}')"
        [[ "$repo" == cachyos* ]] || strays+=("$p (in $repo)")
    done
    if [[ ${#strays[@]} -eq 0 ]]; then
        pass "every package in pacman-cachyos.txt really is CachyOS-only"
    else
        fail "every package in pacman-cachyos.txt really is CachyOS-only" \
             "these come from a repo Arch has too: ${strays[*]}"
    fi
else
    printf '  %s·%s no CachyOS repos here — skipping the CachyOS-only package check\n' "$DIM" "$RESET"
fi

# ── the CachyOS repo bootstrap ────────────────────────────────────────────────
group "CachyOS repo bootstrap"

# THE property that makes this safe. CachyOS's own cachyos-repo.sh inserts
# [cachyos] above core/extra/multilib; the plain cachyos repo shares 90 package
# names with Arch's, including pacman, mesa, linux-firmware, mkinitcpio, sddm,
# xz and zstd. Ordered first, the next `pacman -Syu` — which omarchy-update runs
# by itself — starts replacing Omarchy's base system with CachyOS builds.
# Appending is what keeps Arch winning every one of those collisions, so a
# refactor that "tidies" this into an insert has to fail loudly.
fn="$(awk '/^ensure_cachyos_repo\(\)/,/^}/' "$SCRIPT")"
if grep -q 'tee -a "\$conf"' <<<"$fn"; then
    pass "the [cachyos] section is APPENDED, so it lands below Arch's repos"
else
    fail "the [cachyos] section is appended" \
         "inserted above core/extra, CachyOS would replace pacman, mesa and linux-firmware"
fi
if grep -qE 'pacman-key --lsign-key' <<<"$fn"; then
    pass "the signing key is locally signed before the repo is used"
else
    fail "the signing key is locally signed" "pacman refuses packages from an unsigned key"
fi

# The key must be imported BEFORE pacman.conf is touched. A pacman.conf naming a
# repo whose packages can't be verified breaks every later pacman call —
# including the ones that would undo it.
if [[ "$(grep -n 'pacman-key --recv-keys' <<<"$fn" | head -1 | cut -d: -f1)" -lt \
      "$(grep -n 'tee -a "\$conf"'          <<<"$fn" | head -1 | cut -d: -f1)" ]]; then
    pass "the key is imported before pacman.conf is edited"
else
    fail "the key is imported before pacman.conf is edited" \
         "a failed key import would leave a pacman.conf that breaks every later pacman call"
fi

# It must not touch a box that already has the repos — this is your machine.
out="$( has_cachyos_repos() { return 0; }; DRY_RUN=1; ensure_cachyos_repo 2>&1 )"
check_contains "it no-ops where the repos already exist" "already configured" "$out"
if grep -q 'dry-run' <<<"$out"; then
    fail "it no-ops where the repos already exist" "it still proposed changes"
else
    pass "it proposes no changes where the repos already exist"
fi

# ...and a dry run must not touch pacman.conf even where they don't.
conf_before="$(sha256sum /etc/pacman.conf)"
( has_cachyos_repos() { return 1; }; DRY_RUN=1; ensure_cachyos_repo ) >/dev/null 2>&1
check_eq "a dry run leaves /etc/pacman.conf untouched" "$conf_before" "$(sha256sum /etc/pacman.conf)"

# A dry run must predict the real run. The repo is added before the lists are
# consulted, so a dry run that reported the CachyOS-only packages as skipped
# would be describing itself rather than the install it stands in for.
out="$( has_cachyos_repos() { [[ "$CACHYOS_REPOS" == 1 ]]; }
        DRY_RUN=1 SKIP_UPGRADE=1 DESKTOP=omarchy CACHYOS_REPOS=0
        install_packages 2>&1 )"
check_contains "a dry run without the repos still shows Brave installing" "brave-origin-bin" "$out"
check_contains "...and the gaming metapackages"  "cachyos-gaming-meta" "$out"

# The gaming metapackages need steam and lib32-mangohud, which are multilib.
# pacman fails the whole transaction on an unsatisfiable dependency, so the
# repo being present is not enough on its own.
if grep -q 'multilib' <<<"$fn"; then
    pass "multilib is enabled too (steam and the lib32 packages live there)"
else
    fail "multilib is enabled too" "cachyos-gaming-applications can't resolve steam without it"
fi

# The key fingerprint is the one thing here that must not be guessed: it is what
# every package from this repo is verified against.
check_contains "the pinned key is CachyOS's published one" "F3B607488DB35A47" \
    "$(grep '^CACHYOS_KEY=' "$SCRIPT")"

# ── desktop detection ─────────────────────────────────────────────────────────
group "Desktop detection"

# --desktop is the escape hatch when the guess is wrong, so it must actually
# win over every marker on the box.
for d in kde omarchy other; do
    ( DESKTOP_FORCED="$d"; DESKTOP=""; detect_desktop; [[ "$DESKTOP" == "$d" ]] ) \
        && pass "--desktop $d overrides detection" \
        || fail "--desktop $d overrides detection"
done

out="$(bash "$SCRIPT" --desktop bogus 2>&1)"; rc=$?
[[ $rc -ne 0 ]] && pass "--desktop rejects an unknown desktop" \
                || fail "--desktop rejects an unknown desktop" "exit $rc"
out="$(bash "$SCRIPT" --desktop 2>&1)"; rc=$?
[[ $rc -ne 0 ]] && pass "--desktop with no argument is an error, not a silent exit" \
                || fail "--desktop with no argument is an error" "exit $rc"

# The session on screen beats whatever is installed: a box carrying both KDE and
# Omarchy is judged by the session its owner is logged into.
d="$( DESKTOP_FORCED=""; DESKTOP=""; XDG_CURRENT_DESKTOP="KDE"; detect_desktop; printf '%s' "$DESKTOP" )"
check_eq "XDG_CURRENT_DESKTOP=KDE detects kde" "kde" "$d"
d="$( DESKTOP_FORCED=""; DESKTOP=""; XDG_CURRENT_DESKTOP="plasma"; detect_desktop; printf '%s' "$DESKTOP" )"
check_eq "the session match is case-insensitive" "kde" "$d"

# Omarchy 3.x exports OMARCHY_PATH; Hyprland sets XDG_CURRENT_DESKTOP=Hyprland,
# which must NOT be mistaken for a Plasma session.
d="$( DESKTOP_FORCED=""; DESKTOP=""; XDG_CURRENT_DESKTOP="Hyprland"; DESKTOP_SESSION="hyprland"
      OMARCHY_PATH=/usr/share/omarchy; detect_desktop; printf '%s' "$DESKTOP" )"
check_eq "OMARCHY_PATH under Hyprland detects omarchy" "omarchy" "$d"

# Over SSH or from a TTY there is no session environment at all, so detection
# falls back to the install path — the case that matters most, since that's how
# this script is often run.
d="$( DESKTOP_FORCED=""; DESKTOP=""; XDG_CURRENT_DESKTOP=""; DESKTOP_SESSION=""; OMARCHY_PATH=""
      HOME="$tmp/omahome"; mkdir -p "$HOME/.local/share/omarchy"; detect_desktop; printf '%s' "$DESKTOP" )"
check_eq "an omarchy clone in HOME is found with no session env" "omarchy" "$d"

# Neither KDE nor Omarchy: everything desktop-specific has to skip rather than
# guess. plasmashell is the KDE fallback marker precisely so this holds.
d="$( DESKTOP_FORCED=""; DESKTOP=""; XDG_CURRENT_DESKTOP="GNOME"; DESKTOP_SESSION=""; OMARCHY_PATH=""
      HOME="$tmp/gnomehome"; mkdir -p "$HOME"
      have() { [[ "$1" != plasmashell && "$1" != omarchy-version ]]; }
      detect_desktop; printf '%s' "$DESKTOP" )"
check_eq "a desktop that is neither reports 'other'" "other" "$d"

# ...and it must still report 'other' when the markers for another desktop are
# sitting on disk. This is the normal state of a CachyOS box whose owner added
# GNOME or bare Hyprland and logged into that: Plasma is still installed, but
# configuring its panel and its idle timers would be configuring a desktop
# nobody is looking at. The session is the authority, which is why the
# installed-package fallback only runs when there is no session at all.
#
# omarchy_installed is stubbed false because that is the scenario — a box
# WITHOUT Omarchy — and the suite has to be able to describe it from a machine
# that does have /usr/share/omarchy on it.
for x in GNOME Hyprland XFCE; do
    d="$( DESKTOP_FORCED=""; DESKTOP=""; XDG_CURRENT_DESKTOP="$x"; DESKTOP_SESSION=""; OMARCHY_PATH=""
          HOME="$tmp/gnomehome"; omarchy_installed() { return 1; }
          detect_desktop; printf '%s' "$DESKTOP" )"
    check_eq "a $x session isn't called kde just because plasmashell is installed" "other" "$d"
done

# The converse of the Hyprland case: Omarchy IS a Hyprland session and sets
# nothing more specific, so the session name alone cannot tell the two apart.
# Both facts together can.
d="$( DESKTOP_FORCED=""; DESKTOP=""; XDG_CURRENT_DESKTOP="Hyprland"; DESKTOP_SESSION=""; OMARCHY_PATH=""
      omarchy_installed() { return 0; }
      detect_desktop; printf '%s' "$DESKTOP" )"
check_eq "Hyprland on a box that has Omarchy is omarchy" "omarchy" "$d"

# And the bug this ordering exists to prevent: an Omarchy install is on the
# disk, but the user is logged into something else. Installed markers must not
# beat the session — otherwise every Omarchy-only step runs against a desktop
# that is not on screen.
for x in GNOME XFCE KDE; do
    want=other; [[ "$x" == KDE ]] && want=kde
    d="$( DESKTOP_FORCED=""; DESKTOP=""; XDG_CURRENT_DESKTOP="$x"; DESKTOP_SESSION=""
          OMARCHY_PATH=/usr/share/omarchy
          detect_desktop; printf '%s' "$DESKTOP" )"
    check_eq "a $x session beats an Omarchy install on disk" "$want" "$d"
done

# The converse, so the fix above can't be "solved" by never consulting the
# installed packages: with NO session environment — an SSH command, a TTY — the
# installed-package fallback is all there is, and it must still find KDE.
d="$( DESKTOP_FORCED=""; DESKTOP=""; XDG_CURRENT_DESKTOP=""; DESKTOP_SESSION=""; OMARCHY_PATH=""
      HOME="$tmp/gnomehome"; have() { [[ "$1" == plasmashell ]]; }
      omarchy_installed() { return 1; }
      detect_desktop; printf '%s' "$DESKTOP" )"
check_eq "no session env at all still detects kde from plasmashell" "kde" "$d"

# kwriteconfig6 must NOT be what decides "this is KDE". It ships in kconfig,
# which rides in behind any single KDE app — Omarchy's own package list has
# kdenlive — and using it here would run the Plasma panel step on Hyprland.
if awk '/^detect_desktop\(\)/,/^}/' "$SCRIPT" | sed 's/#.*//' | grep -q 'kwriteconfig6'; then
    fail "detection doesn't key off kwriteconfig6" \
         "kconfig arrives with any KDE app; this would call Omarchy 'kde'"
else
    pass "detection doesn't key off kwriteconfig6"
fi

# ── the KDE-only steps really are gated ───────────────────────────────────────
group "KDE-only steps skip elsewhere"

# Both of these write Plasma's own config files. Off KDE there is nothing there
# to write — and, worse, configure_taskbar stops plasmashell, which on a box
# without one is a pgrep that finds nothing and a config file it would create
# from scratch for no reader.
for fn in configure_powerdevil configure_taskbar; do
    if awk "/^$fn\(\)/,/^}/" "$SCRIPT" | grep -q '\[\[ "\$DESKTOP" != kde \]\]'; then
        pass "$fn returns early off KDE"
    else
        fail "$fn returns early off KDE" "it would write Plasma config on Omarchy"
    fi
done

# The footgun this repo already guards install_packages against, now reachable
# through the new skip paths: configure_system's value is configure_taskbar's,
# and it is called as `wanted config && configure_system` — the command after
# the final &&, which set -e does NOT exempt. A non-zero return there ends the
# run with every step already done, just before the summary prints.
for d in kde omarchy other; do
    if ( set -e
         DESKTOP="$d" DRY_RUN=1
         have() { case "$1" in kwriteconfig6|kreadconfig6|plasmashell) return 1 ;;
                               *) command -v "$1" >/dev/null 2>&1 ;; esac; }
         wanted config && configure_system ) >/dev/null 2>&1; then
        pass "configure_system returns 0 on $d"
    else
        fail "configure_system returns 0 on $d" \
             "set -e would kill the run just before the summary"
    fi
done

if ( set -e
     DESKTOP=omarchy DRY_RUN=1 SKIP_UPGRADE=1
     has_cachyos_repos() { return 1; }
     wanted packages && install_packages ) >/dev/null 2>&1; then
    pass "install_packages returns 0 when the CachyOS repo couldn't be added"
else
    fail "install_packages returns 0 when the CachyOS repo couldn't be added" \
         "set -e would kill the run before any other step"
fi

gate_home="$tmp/gatehome"; mkdir -p "$gate_home/.config"
( HOME="$gate_home" DESKTOP=omarchy DRY_RUN=0 configure_powerdevil ) >/dev/null 2>&1
if [[ -e "$gate_home/.config/powerdevilrc" ]]; then
    fail "no powerdevilrc is written on Omarchy" "the file was created anyway"
else
    pass "no powerdevilrc is written on Omarchy"
fi

out="$( HOME="$gate_home" DESKTOP=omarchy DRY_RUN=1 configure_taskbar 2>&1 )"
check_contains "the taskbar step says why it skipped" "no Plasma panel" "$out"

# ── the Brave profile directory follows the Brave that's installed ────────────
group "Brave profile directory"

# brave-origin-bin (CachyOS) and upstream brave-bin are
# different builds with different profile directories. Writing the filter lists
# and the KeePassXC manifest into the wrong one is silent: no error, no effect,
# and the extension simply never reaches the database.
d="$( have() { [[ "$1" == brave-origin ]]; }; brave_profile_dir )"
check_eq "brave-origin installed -> Brave-Origin" "$HOME/.config/BraveSoftware/Brave-Origin" "$d"
d="$( have() { [[ "$1" == brave ]]; }; brave_profile_dir )"
check_eq "upstream brave installed -> Brave-Browser" "$HOME/.config/BraveSoftware/Brave-Browser" "$d"

# Neither installed yet — this run may be about to install one. An existing
# profile is the next best evidence; failing that, CachyOS's is the default.
d="$( have() { false; }; HOME="$tmp/nobrave"; mkdir -p "$HOME/.config/BraveSoftware/Brave-Browser"; brave_profile_dir )"
check_eq "no brave, but a Brave-Browser profile -> Brave-Browser" \
    "$tmp/nobrave/.config/BraveSoftware/Brave-Browser" "$d"
# With nothing installed and no profile yet, the repos decide: brave-origin-bin
# exists only in the CachyOS repos, so without them upstream Brave is the only
# Brave this machine could end up running.
d="$( have() { false; }; has_cachyos_repos() { true; }
      HOME="$tmp/nobrave2"; mkdir -p "$HOME"; brave_profile_dir )"
check_eq "nothing to go on, CachyOS repos -> Brave-Origin" \
    "$tmp/nobrave2/.config/BraveSoftware/Brave-Origin" "$d"
d="$( have() { false; }; has_cachyos_repos() { false; }
      HOME="$tmp/nobrave3"; mkdir -p "$HOME"; brave_profile_dir )"
check_eq "nothing to go on, Arch repos only -> Brave-Browser" \
    "$tmp/nobrave3/.config/BraveSoftware/Brave-Browser" "$d"

# ── the KeePassXC step must not need KDE ──────────────────────────────────────
group "INI writing without kwriteconfig6"

# kwriteconfig6 ships in kconfig. KeePassXC is Qt, not KDE, and is exactly as
# useful on Omarchy — but calling kwriteconfig6 there unguarded is exit 127,
# which under set -e ends the whole run on the spot.
ini="$tmp/kp/keepassxc.ini"; mkdir -p "$(dirname "$ini")"
( have() { false; }; ini_set "$ini" Browser Enabled true )
check_contains "creates the file and the group" "[Browser]" "$(cat "$ini" 2>/dev/null)"
check_contains "writes the key"                 "Enabled=true" "$(cat "$ini" 2>/dev/null)"

# Qt writes CamelCase keys and values containing % (percent-encoded paths).
# configparser lowercases keys and interpolates % unless told not to — either
# would corrupt a real keepassxc.ini rather than just failing.
printf '[General]\nLastDir=%%2Fhome%%2Fme\n' > "$ini"
( have() { false; }; ini_set "$ini" Browser Enabled true )
kept="$(cat "$ini" 2>/dev/null)"
check_contains "preserves an existing CamelCase key" "LastDir="        "$kept"
check_contains "preserves a % in an existing value"  "%2Fhome%2Fme"    "$kept"
check_contains "still adds the new group"            "Enabled=true"    "$kept"

if awk '/^configure_keepassxc_browser\(\)/,/^}/' "$SCRIPT" | grep -qE '^\s*kwriteconfig6'; then
    fail "the KeePassXC step calls kwriteconfig6 unguarded" \
         "exit 127 on Omarchy, and set -e ends the run there"
else
    pass "the KeePassXC step never calls kwriteconfig6 unguarded"
fi

# ── taskbar list ──────────────────────────────────────────────────────────────
group "Taskbar launcher list"

mapfile -t tb < <(read_list "$REPO_ROOT/packages/taskbar.txt")
check_eq "taskbar.txt parses to 14 launchers" "14" "${#tb[@]}"

# Every entry must be a .desktop name — 'applications:' prefixes or bare app
# names silently produce a dead tile rather than an error.
bad=()
for e in "${tb[@]}"; do
    [[ "$e" == *.desktop ]] || bad+=("$e")
done
if [[ ${#bad[@]} -eq 0 ]]; then
    pass "every entry is a .desktop file name"
else
    fail "every entry is a .desktop file name" "not .desktop: ${bad[*]}"
fi

# The order IS the feature — assert it, so a careless edit that reshuffles the
# list gets caught rather than silently rearranging the taskbar.
check_eq "launchers are in the intended order" \
    "brave-origin.desktop vesktop.desktop steam.desktop org.keepassxc.KeePassXC.desktop org.kde.dolphin.desktop dev.agenttilecli.AgentTileCli.desktop com.streamhub.app.desktop com.consolevault.app.desktop com.discripper.app.desktop com.griddown.app.desktop com.stalkergamma.gui.desktop com.lorerim.autoinstall.desktop com.wowwotlk.autoinstall.desktop music-ai-player.desktop" \
    "${tb[*]}"

# ── KDE power settings ────────────────────────────────────────────────────────
group "KDE power settings (powerdevil)"

if have kwriteconfig6; then
    pd_home="$tmp/pdhome"; mkdir -p "$pd_home/.config"
    # DESKTOP is set explicitly: the step is gated on it now, and the suite
    # never runs preflight, so it would otherwise be empty and skip everything.
    ( HOME="$pd_home" DESKTOP=kde DRY_RUN=0 configure_powerdevil ) >/dev/null 2>&1
    pd="$(cat "$pd_home/.config/powerdevilrc" 2>/dev/null || true)"

    # 0 is "do nothing". Any other value here means the machine suspends itself
    # mid-build, which is the whole thing this setting exists to prevent.
    check_contains "idle suspend is off"        "AutoSuspendAction=0"                  "$pd"
    check_contains "dimming is off"             "DimDisplayWhenIdle=false"             "$pd"
    check_contains "screen still turns off"     "TurnOffDisplayWhenIdle=true"          "$pd"
    check_contains "screen off after 10m"       "TurnOffDisplayIdleTimeoutSec=600"     "$pd"
    check_contains "screen off after 1m locked" "TurnOffDisplayIdleTimeoutWhenLockedSec=60" "$pd"

    # Written under [AC], not at the top level: a key in the wrong group is
    # silently ignored by powerdevil, so the file would look right and do nothing.
    if grep -q '^\[AC\]\[Display\]' "$pd_home/.config/powerdevilrc" 2>/dev/null; then
        pass "keys land in the [AC][Display] group"
    else
        fail "keys land in the [AC][Display] group" "$pd"
    fi

    # kwriteconfig6 parses a bare -1 as a command-line option and exits 1, which
    # under set -e would take the entire run down. The `--` is what stops it.
    if awk '/^configure_powerdevil\(\)/,/^}/' "$SCRIPT" | grep -q -- '--key DimDisplayIdleTimeoutSec -- -1'; then
        pass "the negative dim timeout is passed after --"
    else
        fail "the negative dim timeout is passed after --" \
             "a bare -1 makes kwriteconfig6 exit 1 and set -e kills the run"
    fi
else
    printf '  %s·%s kwriteconfig6 not installed — skipping\n' "$DIM" "$RESET"
fi

# ── nothing may block on stdin ────────────────────────────────────────────────
group "No step can hang waiting for input"

# AgentTileCLI's own install.sh prompts to install the `claude` CLI, but ONLY
# when stdin is a tty — so it passes silently over SSH and hangs forever when a
# human runs this from a real terminal. Every sub-script we shell out to must
# have stdin closed.
#
# Scoped to the function, not the whole script, so an identical invocation in
# some other step can never vouch for this one.
if awk '/^install_agenttilecli\(\)/,/^}/' "$SCRIPT" | grep -qF './install.sh < /dev/null'; then
    pass "AgentTileCLI's installer is run with stdin closed"
else
    fail "AgentTileCLI's installer is run with stdin closed" \
         "it can prompt for the claude CLI and block a real terminal run"
fi

# Both developer CLIs are prepared before the AgentTileCLI build. Codex follows
# the same idempotent, official-installer shape as Claude, while intentionally
# remaining part of this existing step rather than becoming a separate --only
# target.
if awk '/^install_agenttilecli\(\)/,/^}/' "$SCRIPT" | grep -qF 'ensure_codex_cli'; then
    pass "AgentTileCLI setup also ensures the Codex CLI"
else
    fail "AgentTileCLI setup also ensures the Codex CLI" \
         "install_agenttilecli never calls ensure_codex_cli"
fi
if awk '/^ensure_codex_cli\(\)/,/^}/' "$SCRIPT" | grep -qF 'curl -fsSL https://chatgpt.com/codex/install.sh | sh'; then
    pass "Codex uses the official standalone installer"
else
    fail "Codex uses the official standalone installer" \
         "ensure_codex_cli is missing the official install command"
fi

# pacman/flatpak must never stop to ask either.
if grep -qE 'pacman -S(yu)? .*--noconfirm' "$SCRIPT"; then
    pass "pacman runs with --noconfirm"
else
    fail "pacman runs with --noconfirm"
fi
if grep -qF 'flatpak install -y --noninteractive' "$SCRIPT"; then
    pass "flatpak runs non-interactively"
else
    fail "flatpak runs non-interactively"
fi

# ── GitHub release-API parsing ────────────────────────────────────────────────
group "StreamHub release-API parsing"

release="$(github_api "https://api.github.com/repos/$STREAMHUB_REPO/releases/latest" 2>/dev/null)"
if [[ -z "$release" ]]; then
    fail "fetched the latest release" "empty response (rate-limited?)"
else
    pass "fetched the latest release"

    tag="$(printf '%s' "$release" | grep -m1 '"tag_name"' | cut -d'"' -f4)"
    url="$(printf '%s' "$release" | grep -o 'https://[^"]*/StreamHub\.AppImage' | head -1)"

    [[ "$tag" =~ ^v[0-9]+\.[0-9]+ ]] && pass "tag parses as a version ($tag)" \
                                     || fail "tag parses as a version" "$tag"
    check_contains "asset URL ends in StreamHub.AppImage" "StreamHub.AppImage" "$url"
    check_contains "asset URL is a GitHub download URL" "github.com" "$url"

    # The unversioned filename is load-bearing: electron-updater only overwrites
    # in place when the name carries no version. A versioned asset would mean the
    # in-app updater writes a NEW file and every shortcut we create breaks.
    if [[ "$url" =~ StreamHub-[0-9] ]]; then
        fail "asset name carries no version" "$url"
    else
        pass "asset name carries no version (in-place self-update works)"
    fi

    # The URL must actually serve a file — catches a renamed/pulled asset.
    code="$(curl -sIL -o /dev/null -w '%{http_code}' "$url" 2>/dev/null)"
    check_eq "asset URL is reachable (HTTP 200)" "200" "$code"
fi

# ── the AppImage is verified before it's made executable ──────────────────────
group "StreamHub checksum verification"

# This is the one binary the script downloads and runs directly, so a missing or
# skipped checksum check is a real supply-chain hole, not a nicety.
if grep -qF 'verify_streamhub "$tmp" "$tag" ||' "$SCRIPT"; then
    pass "download is verified before chmod +x"
else
    fail "download is verified before chmod +x" "the AppImage would be run unverified"
fi

# A failure to FETCH the checksum must also abort — "couldn't verify" is not
# "verified", and must not degrade into installing the thing anyway.
if awk '/^verify_streamhub\(\)/,/^}/' "$SCRIPT" | grep -q 'return 1'; then
    pass "an unfetchable checksum aborts rather than warning"
else
    fail "an unfetchable checksum aborts rather than warning"
fi

# And prove the real thing actually verifies: fetch the published sha512 and
# check it's the right shape (base64 sha512 = 88 chars ending in '==').
if [[ -n "${tag:-}" ]]; then
    yml="$(curl -fsSL "https://github.com/$STREAMHUB_REPO/releases/download/$tag/latest-linux.yml" 2>/dev/null)"
    sha="$(grep -m1 '^sha512:' <<<"$yml" | awk '{print $2}')"
    if [[ ${#sha} -eq 88 ]]; then
        pass "release publishes a base64 sha512 we can check against"
    else
        fail "release publishes a base64 sha512" "got ${#sha} chars: ${sha:0:20}..."
    fi
fi

# ── generated .desktop file ───────────────────────────────────────────────────
group "Generated .desktop file"

APPS_DIR="$tmp"                                   # redirect the writer at a temp dir
STREAMHUB_APPIMAGE="/home/user/.local/bin/StreamHub.AppImage"
STREAMHUB_DIR="/home/user/.local/share/streamhub"
write_streamhub_desktop

desktop="$tmp/com.streamhub.app.desktop"
[[ -f "$desktop" ]] && pass ".desktop file is written" || fail ".desktop file is written"
content="$(cat "$desktop" 2>/dev/null || true)"

check_contains "has [Desktop Entry] header" "[Desktop Entry]" "$content"
check_contains "Exec points at the AppImage" "Exec=$STREAMHUB_APPIMAGE" "$content"
check_contains "Icon uses an absolute path"  "Icon=$STREAMHUB_DIR/icon.png" "$content"
check_contains "Type=Application" "Type=Application" "$content"

if have desktop-file-validate; then
    if err="$(desktop-file-validate "$desktop" 2>&1)"; then
        pass "passes desktop-file-validate"
    else
        fail "passes desktop-file-validate" "$err"
    fi
else
    printf '  %s·%s desktop-file-validate not installed — skipping spec validation\n' "$DIM" "$RESET"
fi

# ── ConsoleVault release-API parsing ──────────────────────────────────────────
group "ConsoleVault release-API parsing"

cv_release="$(github_api "https://api.github.com/repos/$CONSOLEVAULT_REPO/releases/latest" 2>/dev/null)"
if [[ -z "$cv_release" ]]; then
    fail "fetched the latest release" "empty response (rate-limited?)"
else
    pass "fetched the latest release"

    cv_tag="$(printf '%s' "$cv_release" | grep -m1 '"tag_name"' | cut -d'"' -f4)"
    # Same pattern the installer uses: the trailing quote is what excludes the
    # sibling .AppImage.sig asset.
    cv_url="$(printf '%s' "$cv_release" | grep -o 'https://[^"]*_amd64\.AppImage"' | head -1 | tr -d '"')"

    [[ "$cv_tag" =~ ^v[0-9]+\.[0-9]+ ]] && pass "tag parses as a version ($cv_tag)" \
                                        || fail "tag parses as a version" "$cv_tag"
    check_contains "asset URL ends in _amd64.AppImage" "_amd64.AppImage" "$cv_url"
    check_contains "asset URL is a GitHub download URL" "github.com" "$cv_url"

    # The pattern must not pick up the detached signature as the download target.
    if [[ "$cv_url" == *.sig ]]; then
        fail "asset URL is the AppImage, not the .sig" "$cv_url"
    else
        pass "asset URL is the AppImage, not the .sig"
    fi

    code="$(curl -sIL -o /dev/null -w '%{http_code}' "$cv_url" 2>/dev/null)"
    check_eq "asset URL is reachable (HTTP 200)" "200" "$code"
fi

# ── the AppImage is verified before it's made executable ──────────────────────
group "ConsoleVault signature verification"

# Same supply-chain concern as StreamHub: this binary is downloaded and then run
# with the user's privileges, so verification can't be skippable.
if grep -qF 'verify_consolevault "$tmp" "$url" ||' "$SCRIPT"; then
    pass "download is verified before chmod +x"
else
    fail "download is verified before chmod +x" "the AppImage would be run unverified"
fi

# An unfetchable/undecodable signature must abort, not warn-and-continue.
if awk '/^verify_consolevault\(\)/,/^}/' "$SCRIPT" | grep -q 'return 1'; then
    pass "an unverifiable signature aborts rather than warning"
else
    fail "an unverifiable signature aborts rather than warning"
fi

# The public key is hard-coded, never fetched from the release host (which would
# defeat the point). Prove nothing in the verify path pulls the key off the wire.
if awk '/^verify_consolevault\(\)/,/^}/' "$SCRIPT" | grep -qi 'pubkey.*curl\|curl.*pubkey\|tauri.conf'; then
    fail "public key is embedded, not fetched at runtime"
else
    pass "public key is embedded, not fetched at runtime"
fi

# And prove the real thing verifies: fetch the signed AppImage + its .sig and run
# minisign against the embedded key. Skipped where minisign or the net is absent.
if have minisign && [[ -n "${cv_tag:-}" && -n "${cv_url:-}" ]]; then
    cvd="$(mktemp -d)"
    if curl -fsSL "$cv_url" -o "$cvd/app.AppImage" 2>/dev/null \
       && curl -fsSL "$cv_url.sig" 2>/dev/null | base64 -d > "$cvd/app.AppImage.minisig" 2>/dev/null; then
        if minisign -Vm "$cvd/app.AppImage" -x "$cvd/app.AppImage.minisig" -P "$CONSOLEVAULT_PUBKEY" >/dev/null 2>&1; then
            pass "real release verifies against the embedded public key"
        else
            fail "real release verifies against the embedded public key" "minisign rejected it"
        fi
    else
        printf '  %s·%s couldn'\''t download the release — skipping live verify\n' "$DIM" "$RESET"
    fi
    rm -rf "$cvd"
else
    printf '  %s·%s minisign not installed — skipping live signature check\n' "$DIM" "$RESET"
fi

# ── generated .desktop file ───────────────────────────────────────────────────
group "ConsoleVault .desktop file"

APPS_DIR="$tmp"
CONSOLEVAULT_APPIMAGE="/home/user/.local/bin/ConsoleVault.AppImage"
CONSOLEVAULT_DIR="/home/user/.local/share/consolevault"
write_consolevault_desktop

cv_desktop="$tmp/com.consolevault.app.desktop"
[[ -f "$cv_desktop" ]] && pass ".desktop file is written" || fail ".desktop file is written"
cv_content="$(cat "$cv_desktop" 2>/dev/null || true)"

check_contains "has [Desktop Entry] header" "[Desktop Entry]" "$cv_content"
check_contains "Exec points at the AppImage" "Exec=$CONSOLEVAULT_APPIMAGE" "$cv_content"
check_contains "Icon uses an absolute path"  "Icon=$CONSOLEVAULT_DIR/icon.png" "$cv_content"
check_contains "Type=Application" "Type=Application" "$cv_content"

if have desktop-file-validate; then
    if err="$(desktop-file-validate "$cv_desktop" 2>&1)"; then
        pass "passes desktop-file-validate"
    else
        fail "passes desktop-file-validate" "$err"
    fi
else
    printf '  %s·%s desktop-file-validate not installed — skipping spec validation\n' "$DIM" "$RESET"
fi

# ── GridDown release-API parsing ──────────────────────────────────────────────
group "GridDown release-API parsing"

gd_release="$(github_api "https://api.github.com/repos/$GRIDDOWN_REPO/releases/latest" 2>/dev/null)"
if [[ -z "$gd_release" || "$gd_release" == *'"Not Found"'* ]]; then
    # GridDown's first release may not be published yet; the installer dies with a
    # clear message in that case, which is the intended behaviour, not a test bug.
    printf '  %s·%s no published release yet — skipping live release checks\n' "$DIM" "$RESET"
else
    pass "fetched the latest release"

    gd_tag="$(printf '%s' "$gd_release" | grep -m1 '"tag_name"' | cut -d'"' -f4)"
    gd_url="$(printf '%s' "$gd_release" | grep -o 'https://[^"]*_amd64\.AppImage"' | head -1 | tr -d '"')"

    [[ "$gd_tag" =~ ^v[0-9]+\.[0-9]+ ]] && pass "tag parses as a version ($gd_tag)" \
                                        || fail "tag parses as a version" "$gd_tag"
    check_contains "asset URL ends in _amd64.AppImage" "_amd64.AppImage" "$gd_url"
    check_contains "asset URL is a GitHub download URL" "github.com" "$gd_url"

    if [[ "$gd_url" == *.sig ]]; then
        fail "asset URL is the AppImage, not the .sig" "$gd_url"
    else
        pass "asset URL is the AppImage, not the .sig"
    fi

    code="$(curl -sIL -o /dev/null -w '%{http_code}' "$gd_url" 2>/dev/null)"
    check_eq "asset URL is reachable (HTTP 200)" "200" "$code"
fi

# ── GridDown signature verification ───────────────────────────────────────────
group "GridDown signature verification"

if grep -qF 'verify_griddown "$tmp" "$url" ||' "$SCRIPT"; then
    pass "download is verified before chmod +x"
else
    fail "download is verified before chmod +x" "the AppImage would be run unverified"
fi

# A repo with no published release yet must warn+skip, not abort the whole run —
# but only for 404. A release that exists with a bad/missing asset must still die,
# so the skip can't quietly become a blanket "ignore all failures".
if awk '/^install_griddown\(\)/,/^}/' "$SCRIPT" | grep -q '"404"'; then
    pass "no published release warns and skips rather than aborting the run"
else
    fail "no published release warns and skips" "an unreleased app would kill the whole installer"
fi
if awk '/^install_griddown\(\)/,/^}/' "$SCRIPT" | grep -q 'no GridDown _amd64.AppImage asset.*\|| die\|die "no GridDown'; then
    pass "a published release with no AppImage asset still dies"
else
    fail "a published release with no AppImage asset still dies" "the 404 skip may have swallowed real failures"
fi

if awk '/^verify_griddown\(\)/,/^}/' "$SCRIPT" | grep -q 'return 1'; then
    pass "an unverifiable signature aborts rather than warning"
else
    fail "an unverifiable signature aborts rather than warning"
fi

# The key is embedded, never pulled off the wire from the host it vouches for.
if awk '/^verify_griddown\(\)/,/^}/' "$SCRIPT" | grep -qi 'pubkey.*curl\|curl.*pubkey\|tauri.conf'; then
    fail "public key is embedded, not fetched at runtime"
else
    pass "public key is embedded, not fetched at runtime"
fi

# The pubkey in install.sh must match what the app actually ships in its Tauri
# config (stored there as base64 of the whole minisign key file). A drift here
# means every download would fail verification — catch it at test time.
gd_conf="$(curl -fsSL "https://raw.githubusercontent.com/$GRIDDOWN_REPO/$GRIDDOWN_BRANCH/src-tauri/tauri.conf.json" 2>/dev/null || true)"
if [[ -n "$gd_conf" ]]; then
    gd_conf_key="$(printf '%s' "$gd_conf" | grep -m1 '"pubkey"' | cut -d'"' -f4 | base64 -d 2>/dev/null | tail -1 || true)"
    if [[ -n "$gd_conf_key" ]]; then
        check_eq "embedded pubkey matches the app's tauri.conf.json" "$gd_conf_key" "$GRIDDOWN_PUBKEY"
    else
        printf '  %s·%s couldn'\''t decode the pubkey from tauri.conf.json — skipping\n' "$DIM" "$RESET"
    fi
else
    printf '  %s·%s couldn'\''t fetch tauri.conf.json — skipping pubkey cross-check\n' "$DIM" "$RESET"
fi

# And prove the real release verifies against the embedded key.
if have minisign && [[ -n "${gd_tag:-}" && -n "${gd_url:-}" ]]; then
    gdd="$(mktemp -d)"
    if curl -fsSL "$gd_url" -o "$gdd/app.AppImage" 2>/dev/null \
       && curl -fsSL "$gd_url.sig" 2>/dev/null | base64 -d > "$gdd/app.AppImage.minisig" 2>/dev/null; then
        if minisign -Vm "$gdd/app.AppImage" -x "$gdd/app.AppImage.minisig" -P "$GRIDDOWN_PUBKEY" >/dev/null 2>&1; then
            pass "real release verifies against the embedded public key"
        else
            fail "real release verifies against the embedded public key" "minisign rejected it"
        fi
    else
        printf '  %s·%s couldn'\''t download the release — skipping live verify\n' "$DIM" "$RESET"
    fi
    rm -rf "$gdd"
else
    printf '  %s·%s minisign missing or no release — skipping live signature check\n' "$DIM" "$RESET"
fi

# ── GridDown .desktop file ────────────────────────────────────────────────────
group "GridDown .desktop file"

APPS_DIR="$tmp"
GRIDDOWN_APPIMAGE="/home/user/.local/bin/GridDown.AppImage"
GRIDDOWN_DIR="/home/user/.local/share/griddown"
write_griddown_desktop

gd_desktop="$tmp/com.griddown.app.desktop"
[[ -f "$gd_desktop" ]] && pass ".desktop file is written" || fail ".desktop file is written"
gd_content="$(cat "$gd_desktop" 2>/dev/null || true)"

check_contains "has [Desktop Entry] header" "[Desktop Entry]" "$gd_content"
check_contains "Exec points at the AppImage" "Exec=$GRIDDOWN_APPIMAGE" "$gd_content"
check_contains "Icon uses an absolute path"  "Icon=$GRIDDOWN_DIR/icon.png" "$gd_content"
check_contains "Type=Application" "Type=Application" "$gd_content"

if have desktop-file-validate; then
    if err="$(desktop-file-validate "$gd_desktop" 2>&1)"; then
        pass "passes desktop-file-validate"
    else
        fail "passes desktop-file-validate" "$err"
    fi
else
    printf '  %s·%s desktop-file-validate not installed — skipping spec validation\n' "$DIM" "$RESET"
fi

# ── Stalker GAMMA GUI release-API parsing ─────────────────────────────────────
group "Stalker GAMMA GUI release-API parsing"

gg_release="$(github_api "https://api.github.com/repos/$GAMMAGUI_REPO/releases/latest" 2>/dev/null)"
if [[ -z "$gg_release" ]]; then
    fail "fetched the latest release" "empty response (rate-limited?)"
else
    pass "fetched the latest release"

    gg_tag="$(printf '%s' "$gg_release" | grep -m1 '"tag_name"' | cut -d'"' -f4)"
    gg_url="$(printf '%s' "$gg_release" | grep -o 'https://[^"]*/StalkerGammaGui-x86_64\.AppImage"' | head -1 | tr -d '"')"

    [[ "$gg_tag" =~ ^v[0-9]+\.[0-9]+ ]] && pass "tag parses as a version ($gg_tag)" \
                                        || fail "tag parses as a version" "$gg_tag"
    check_contains "asset URL ends in the AppImage name" "$GAMMAGUI_ASSET" "$gg_url"
    check_contains "asset URL is a GitHub download URL" "github.com" "$gg_url"

    # The stable asset name is load-bearing: a versioned name would break the
    # installer's grep and every re-run's update path.
    if [[ "$gg_url" =~ StalkerGammaGui-[0-9] ]]; then
        fail "asset name carries no version" "$gg_url"
    else
        pass "asset name carries no version (re-run updates keep working)"
    fi

    code="$(curl -sIL -o /dev/null -w '%{http_code}' "$gg_url" 2>/dev/null)"
    check_eq "asset URL is reachable (HTTP 200)" "200" "$code"
fi

# ── Stalker GAMMA GUI checksum verification ───────────────────────────────────
group "Stalker GAMMA GUI checksum verification"

if grep -qF 'verify_gammagui "$tmp" "$digest" ||' "$SCRIPT"; then
    pass "download is verified before chmod +x"
else
    fail "download is verified before chmod +x" "the AppImage would be run unverified"
fi

if awk '/^verify_gammagui\(\)/,/^}/' "$SCRIPT" | grep -q 'return 1'; then
    pass "an unverifiable checksum aborts rather than warning"
else
    fail "an unverifiable checksum aborts rather than warning"
fi

# The API's per-asset digest is the only checksum this release publishes — prove
# it's actually there and the right shape, using the installer's own extraction.
# If GitHub ever drops or renames the field, the installer would refuse every
# download, and this is where we'd find out.
if [[ -n "$gg_release" ]]; then
    gg_digest="$(printf '%s' "$gg_release" | GAMMAGUI_ASSET="$GAMMAGUI_ASSET" python -c '
import json, os, sys
for a in json.load(sys.stdin).get("assets", []):
    if a.get("name") == os.environ["GAMMAGUI_ASSET"]:
        d = a.get("digest") or ""
        if d.startswith("sha256:"):
            print(d[len("sha256:"):])
        break
' 2>/dev/null)"
    if [[ "$gg_digest" =~ ^[0-9a-f]{64}$ ]]; then
        pass "releases API carries a sha256 digest for the asset"
    else
        fail "releases API carries a sha256 digest" "got: ${gg_digest:-nothing}"
    fi

    # Prove the digest matches the real asset — a mismatch here means either a
    # bad release or a broken verify path, and both would refuse every install.
    if [[ -n "${gg_url:-}" && "$gg_digest" =~ ^[0-9a-f]{64}$ ]]; then
        ggd="$(mktemp -d)"
        if curl -fsSL "$gg_url" -o "$ggd/app.AppImage" 2>/dev/null; then
            gg_actual="$(sha256sum "$ggd/app.AppImage" | awk '{print $1}')"
            check_eq "real release matches the API's sha256 digest" "$gg_digest" "$gg_actual"
        else
            printf '  %s·%s couldn'\''t download the release — skipping live checksum\n' "$DIM" "$RESET"
        fi
        rm -rf "$ggd"
    fi
fi

# ── Stalker GAMMA GUI .desktop file ───────────────────────────────────────────
group "Stalker GAMMA GUI .desktop file"

APPS_DIR="$tmp"
GAMMAGUI_APPIMAGE="/home/user/.local/bin/StalkerGammaGui.AppImage"
GAMMAGUI_DIR="/home/user/.local/share/stalkergammagui"
write_gammagui_desktop

gg_desktop="$tmp/com.stalkergamma.gui.desktop"
[[ -f "$gg_desktop" ]] && pass ".desktop file is written" || fail ".desktop file is written"
gg_content="$(cat "$gg_desktop" 2>/dev/null || true)"

check_contains "has [Desktop Entry] header" "[Desktop Entry]" "$gg_content"
check_contains "Exec points at the AppImage" "Exec=$GAMMAGUI_APPIMAGE" "$gg_content"
check_contains "Icon uses an absolute path"  "Icon=$GAMMAGUI_DIR/icon.png" "$gg_content"
check_contains "Type=Application" "Type=Application" "$gg_content"
# The WM_CLASS comes from the .NET assembly name, matching the app's own AppDir
# .desktop — a drift here brings back the duplicate-taskbar-icon problem.
check_contains "StartupWMClass matches the Avalonia assembly" "StartupWMClass=StalkerGamma.Gui" "$gg_content"

if have desktop-file-validate; then
    if err="$(desktop-file-validate "$gg_desktop" 2>&1)"; then
        pass "passes desktop-file-validate"
    else
        fail "passes desktop-file-validate" "$err"
    fi
else
    printf '  %s·%s desktop-file-validate not installed — skipping spec validation\n' "$DIM" "$RESET"
fi

# ── competing launcher pruning ────────────────────────────────────────────────
# A launcher left behind by a manual install claims the same StartupWMClass as
# ours, so KDE binds the running window to whichever it finds first. When it
# picks the stray, the pinned icon never lights up and the app opens a second
# taskbar entry beside it.
group "Competing launcher pruning"

# The real one shells out to kbuildsycoca6, which would rebuild the running
# session's KDE cache — the suite installs nothing and changes nothing.
# Nothing later in this file calls it in-process (the --dry-run tests run
# install.sh as a subprocess), so a no-op for the rest of the run is safe.
refresh_desktop_db() { :; }

prune_dir="$tmp/prune"
mkdir -p "$prune_dir"
APPS_DIR="$prune_dir"
GAMMAGUI_APPIMAGE="/home/user/.local/bin/StalkerGammaGui.AppImage"
GAMMAGUI_DIR="/home/user/.local/share/stalkergammagui"
write_gammagui_desktop

# what a manual install leaves behind: same window class, different Exec
cat > "$prune_dir/stalker-gamma-gui.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Stalker GAMMA GUI
Exec="/home/user/.local/bin/StalkerGammaGui-x86_64.appimage"
Icon=stalker-gamma-gui
StartupWMClass=StalkerGamma.Gui
EOF

# an unrelated launcher that must survive untouched
cat > "$prune_dir/com.example.other.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Something Else
Exec=/usr/bin/true
StartupWMClass=Something.Else
EOF

DRY_RUN=0
prune_competing_launchers "com.stalkergamma.gui.desktop"

[[ ! -f "$prune_dir/stalker-gamma-gui.desktop" ]] \
    && pass "removes a stray launcher claiming the same StartupWMClass" \
    || fail "removes a stray launcher claiming the same StartupWMClass" "it survived"
[[ -f "$prune_dir/com.stalkergamma.gui.desktop" ]] \
    && pass "keeps our own launcher" \
    || fail "keeps our own launcher" "it was deleted"
[[ -f "$prune_dir/com.example.other.desktop" ]] \
    && pass "leaves unrelated launchers alone" \
    || fail "leaves unrelated launchers alone" "it was deleted"

# --dry-run must not delete: the suite guarantees a dry run changes nothing.
prune_dry="$tmp/prune-dry"
mkdir -p "$prune_dry"
APPS_DIR="$prune_dry"
write_gammagui_desktop
cp "$prune_dir/com.example.other.desktop" "$prune_dry/" 2>/dev/null
cat > "$prune_dry/stalker-gamma-gui.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Stalker GAMMA GUI
StartupWMClass=StalkerGamma.Gui
EOF

DRY_RUN=1
prune_competing_launchers "com.stalkergamma.gui.desktop" >/dev/null
DRY_RUN=0

[[ -f "$prune_dry/stalker-gamma-gui.desktop" ]] \
    && pass "--dry-run reports but deletes nothing" \
    || fail "--dry-run reports but deletes nothing" "the stray was removed during a dry run"

# The class is a literal, not a pattern. Every class here contains a dot —
# StalkerGamma.Gui, Lorerim.Gui — and an unescaped dot in a regex matches any
# character, so a launcher for a different app would be deleted.
prune_re="$tmp/prune-regex"
mkdir -p "$prune_re"
APPS_DIR="$prune_re"
printf '[Desktop Entry]\nStartupWMClass=StalkerGammaXGui\n' > "$prune_re/innocent.desktop"
DRY_RUN=0
prune_competing_launchers "com.stalkergamma.gui.desktop" >/dev/null 2>&1
[[ -f "$prune_re/innocent.desktop" ]] \
    && pass "matches the window class literally, not as a regex" \
    || fail "matches the window class literally, not as a regex" \
            "a launcher for StalkerGammaXGui was deleted by the dot in StalkerGamma.Gui"

# Claiming a removal that didn't happen is worse than the duplicate icon: it
# reports the problem fixed while it is still there.
if [[ "$(id -u)" -eq 0 ]]; then
    printf '  %s·%s running as root — skipping the unremovable-file check\n' "$DIM" "$RESET"
else
    prune_ro="$tmp/prune-readonly"
    mkdir -p "$prune_ro"
    APPS_DIR="$prune_ro"
    printf '[Desktop Entry]\nStartupWMClass=StalkerGamma.Gui\n' > "$prune_ro/stuck.desktop"
    chmod 500 "$prune_ro"
    prune_msg="$(prune_competing_launchers "com.stalkergamma.gui.desktop" 2>&1)"
    chmod 700 "$prune_ro"

    if [[ -f "$prune_ro/stuck.desktop" && "$prune_msg" == *"removed stuck.desktop"* ]]; then
        fail "doesn't claim to have removed a file it couldn't" "$prune_msg"
    else
        pass "doesn't claim to have removed a file it couldn't"
    fi
fi

# The class is read from the launcher we wrote rather than passed in at each
# call site. Seven apps would otherwise repeat the literal seven times, and
# these do drift — 63b72a5 changed GridDown's from GridDown to griddown.
prune_derive="$tmp/prune-derive"
mkdir -p "$prune_derive"
APPS_DIR="$prune_derive"
GAMMAGUI_APPIMAGE="/home/user/.local/bin/StalkerGammaGui.AppImage"
GAMMAGUI_DIR="/home/user/.local/share/stalkergammagui"
write_gammagui_desktop
printf '[Desktop Entry]\nStartupWMClass=StalkerGamma.Gui\n' > "$prune_derive/stray.desktop"
DRY_RUN=0
prune_competing_launchers "com.stalkergamma.gui.desktop" >/dev/null 2>&1
[[ ! -f "$prune_derive/stray.desktop" ]] \
    && pass "reads the window class from the launcher it keeps" \
    || fail "reads the window class from the launcher it keeps" "the stray survived"

# Nothing to compare against must mean nothing is touched. If a missing or
# class-less launcher yielded an empty class, a loose match would sweep the
# whole directory.
prune_none="$tmp/prune-noclass"
mkdir -p "$prune_none"
APPS_DIR="$prune_none"
printf '[Desktop Entry]\nName=Some Other App\nExec=/usr/bin/true\n' > "$prune_none/bystander.desktop"
prune_competing_launchers "com.stalkergamma.gui.desktop" >/dev/null 2>&1
[[ -f "$prune_none/bystander.desktop" ]] \
    && pass "a missing launcher prunes nothing" \
    || fail "a missing launcher prunes nothing" "it deleted an unrelated launcher"

printf '[Desktop Entry]\nName=Ours\nExec=/usr/bin/true\n' > "$prune_none/com.stalkergamma.gui.desktop"
prune_competing_launchers "com.stalkergamma.gui.desktop" >/dev/null 2>&1
[[ -f "$prune_none/bystander.desktop" ]] \
    && pass "a launcher with no StartupWMClass prunes nothing" \
    || fail "a launcher with no StartupWMClass prunes nothing" "an empty class matched everything"

# ...and a missing launcher must RETURN 0, not merely delete nothing. The test
# two above only checks the latter, and this harness clears the -e and pipefail
# it would need to see the difference: under install.sh's real flags, sed exiting
# 2 on the missing file was handed to the assignment by pipefail and killed the
# whole run. It fires on the dry-run path of every app (nothing writes the
# launcher there) on any box where $APPS_DIR already exists. So assert the exit
# status under the flags the script actually runs with, not the harness's.
if ( set -eo pipefail
     APPS_DIR="$prune_none"
     prune_competing_launchers "not-installed-yet.desktop" >/dev/null 2>&1 ); then
    pass "a missing launcher returns 0 under set -e -o pipefail"
else
    fail "a missing launcher returns 0 under set -e -o pipefail" \
         "prune aborts the run instead of pruning nothing"
fi

# A stray can sit beside a perfectly good launcher, so the prune cannot live in
# the launcher-repair branch — that only fires when ours is missing or stale.
# It has to run on the already-installed path too, or a re-run never fixes it.
gg_skip_block="$(awk '/^install_gammagui\(\)/,/^}/' "$SCRIPT" \
                 | awk '/already installed \(no self-updater/,/^        return$/')"
if grep -q 'prune_competing_launchers' <<<"$gg_skip_block"; then
    pass "the already-installed path still prunes strays"
else
    fail "the already-installed path still prunes strays" \
         "a matching version stamp returns before any pruning happens"
fi

# Every app that writes a launcher prunes competitors for it, on both the
# already-installed path and the install path — so a new app added later can't
# quietly skip it.
for app in streamhub consolevault discripper griddown gammagui lorerim wotlk musicai; do
    app_block="$(awk "/^install_$app\\(\\)/,/^}/" "$SCRIPT")"
    n="$(grep -c 'prune_competing_launchers' <<<"$app_block")"
    if [[ "$n" -ge 2 ]]; then
        pass "install_$app prunes competing launchers"
    else
        fail "install_$app prunes competing launchers" "only $n call(s) — expected the skip and install paths"
    fi
done

# ── GitHub API access ─────────────────────────────────────────────────────────
# Unauthenticated callers get 60 requests/hour per IP, and GitHub answers 403 —
# not 429 — once they're spent. Reading that as "couldn't reach the API" sends
# you hunting for a network fault that isn't there.
group "GitHub API access"

GH_TOKEN="from-gh-token"; GITHUB_TOKEN="from-github-token"
check_eq "GH_TOKEN wins over GITHUB_TOKEN" "from-gh-token" "$(github_token)"

unset GH_TOKEN
check_eq "falls back to GITHUB_TOKEN" "from-github-token" "$(github_token)"

GH_TOKEN=$'padded-token\n'
check_eq "strips newlines so the auth header stays valid" "padded-token" "$(github_token)"
unset GH_TOKEN GITHUB_TOKEN

gh() { printf 'tok-from-gh\n'; }          # the real binary exists, so `have gh` is true
check_eq "falls back to the gh CLI" "tok-from-gh" "$(github_token)"
unset -f gh

# `gh` on PATH is not always the gh binary. Omarchy writes a wrapper into
# ~/.local/bin for every mise-managed tool, and each runs `mise use -g <tool>`
# first — which prints a status banner to STDOUT, ahead of the real output.
# Gluing that onto a good token (which is what stripping the newline and
# keeping both does) produces a 401 that reads exactly like a bad token.
gh() { printf 'mise ~/.config/mise/config.toml tools: gh@2.97.0\ngho_realTokenValue123\n'; }
check_eq "a wrapper's status banner is not mistaken for the token" \
         "gho_realTokenValue123" "$(github_token)"
unset -f gh

# ...and the same when a wrapper prints its banner after the command's output.
gh() { printf 'gho_realTokenValue123\nmise ~/.config/mise/config.toml tools: gh@2.97.0\n'; }
check_eq "a trailing banner is ignored too" "gho_realTokenValue123" "$(github_token)"
unset -f gh

# Nothing token-shaped at all must read as "no token" — the unauthenticated
# path — rather than as a token GitHub will reject with a misleading 401.
gh() { printf 'mise ~/.config/mise/config.toml tools: gh@2.97.0\n'; }
check_eq "banner-only output yields no token, not a bad one" "" "$(github_token)"
unset -f gh

# An explicit token is the user's own choice and is passed through as set:
# classic PATs are 40 bare hex characters with no prefix to match on.
GH_TOKEN=0123456789abcdef0123456789abcdef01234567
check_eq "an explicit classic PAT is passed through verbatim" \
         "0123456789abcdef0123456789abcdef01234567" "$(github_token)"
unset GH_TOKEN

rl_body='{"message":"API rate limit exceeded for 1.2.3.4.","documentation_url":"https://docs.github.com/"}'

msg="$(github_api_diagnose 403 "$rl_body" 0 2>&1)"
check_contains "a 403 rate-limit names the rate limit" "rate limit" "$msg"
check_contains "an unauthenticated 403 suggests a token" "GH_TOKEN" "$msg"

msg="$(github_api_diagnose 403 "$rl_body" 1 2>&1)"
if [[ "$msg" != *"gh auth login"* ]]; then
    pass "an authenticated 403 doesn't suggest logging in again"
else
    fail "an authenticated 403 doesn't suggest logging in again" "$msg"
fi

msg="$(github_api_diagnose 403 '{"message":"Resource not accessible"}' 0 2>&1)"
if [[ "$msg" != *"rate limit"* ]]; then
    pass "a non-rate-limit 403 isn't blamed on the rate limit"
else
    fail "a non-rate-limit 403 isn't blamed on the rate limit" "$msg"
fi

msg="$(github_api_diagnose 404 '{"message":"Not Found"}' 0 2>&1)"
check_contains "a 404 is reported as a missing repo or release" "404" "$msg"

# curl's own -w writes the status line even when the transfer fails, so adding
# another on the error path leaves two — and the body then reads "\n000"
# instead of empty. Only the status is parsed today, so this is latent, but any
# caller that reads the body of a failed request would get that garbage.
unreachable="$(github_api_raw "https://nonexistent.invalid.example/x" 2>/dev/null)"
check_eq "an unreachable host reports status 000" "000" "${unreachable##*$'\n'}"
check_eq "an unreachable host leaves an empty body" "" "${unreachable%$'\n'*}"

# Every release lookup must go through the helper, or it stays unauthenticated
# and keeps reporting a rate-limit refusal as a network failure. Matches any
# curl against /repos, not one spelling of it — the first version of this check
# only looked for `curl -fsSL` and sailed past GridDown's `curl -sSL -w`.
bypass="$(grep -n 'curl[^|]*api\.github\.com/repos' "$SCRIPT" || true)"
if [[ -z "$bypass" ]]; then
    pass "no release lookup bypasses the API helper"
else
    fail "no release lookup bypasses the API helper" "$bypass"
fi

# GridDown may not have cut a release yet, so it alone treats 404 as "skip and
# carry on". Routing it through the helper must not cost it that.
gd_block="$(awk '/^install_griddown\(\)/,/^}/' "$SCRIPT")"
if grep -q 'github_api_raw' <<<"$gd_block"; then
    pass "GridDown fetches through the helper too"
else
    fail "GridDown fetches through the helper too" "it still calls curl directly"
fi
if grep -q '"404"' <<<"$gd_block"; then
    pass "GridDown still skips gracefully when there is no release"
else
    fail "GridDown still skips gracefully when there is no release" "the 404 branch is gone"
fi

# ── LoreRim Autoinstall release-API parsing ───────────────────────────────────
group "LoreRim Autoinstall release-API parsing"

lr_release="$(github_api "https://api.github.com/repos/$LORERIM_REPO/releases/latest" 2>/dev/null)"
if [[ -z "$lr_release" ]]; then
    fail "fetched the latest release" "empty response (rate-limited? no release published yet?)"
else
    pass "fetched the latest release"

    lr_tag="$(printf '%s' "$lr_release" | grep -m1 '"tag_name"' | cut -d'"' -f4)"
    lr_url="$(printf '%s' "$lr_release" | grep -o 'https://[^"]*/LorerimAutoinstall-x86_64\.AppImage"' | head -1 | tr -d '"')"

    [[ "$lr_tag" =~ ^v[0-9]+\.[0-9]+ ]] && pass "tag parses as a version ($lr_tag)" \
                                        || fail "tag parses as a version" "$lr_tag"
    check_contains "asset URL ends in the AppImage name" "$LORERIM_ASSET" "$lr_url"
    check_contains "asset URL is a GitHub download URL" "github.com" "$lr_url"

    # The stable asset name is load-bearing: a versioned name would break the
    # installer's grep and every re-run's update path.
    if [[ "$lr_url" =~ LorerimAutoinstall-[0-9] ]]; then
        fail "asset name carries no version" "$lr_url"
    else
        pass "asset name carries no version (re-run updates keep working)"
    fi

    code="$(curl -sIL -o /dev/null -w '%{http_code}' "$lr_url" 2>/dev/null)"
    check_eq "asset URL is reachable (HTTP 200)" "200" "$code"
fi

# ── LoreRim Autoinstall checksum verification ─────────────────────────────────
group "LoreRim Autoinstall checksum verification"

if grep -qF 'verify_lorerim "$tmp" "$digest" ||' "$SCRIPT"; then
    pass "download is verified before chmod +x"
else
    fail "download is verified before chmod +x" "the AppImage would be run unverified"
fi

if awk '/^verify_lorerim\(\)/,/^}/' "$SCRIPT" | grep -q 'return 1'; then
    pass "an unverifiable checksum aborts rather than warning"
else
    fail "an unverifiable checksum aborts rather than warning"
fi

# The API's per-asset digest is the only checksum this release publishes — prove
# it's actually there and the right shape, using the installer's own extraction.
# If GitHub ever drops or renames the field, the installer would refuse every
# download, and this is where we'd find out.
if [[ -n "$lr_release" ]]; then
    lr_digest="$(printf '%s' "$lr_release" | LORERIM_ASSET="$LORERIM_ASSET" python -c '
import json, os, sys
for a in json.load(sys.stdin).get("assets", []):
    if a.get("name") == os.environ["LORERIM_ASSET"]:
        d = a.get("digest") or ""
        if d.startswith("sha256:"):
            print(d[len("sha256:"):])
        break
' 2>/dev/null)"
    if [[ "$lr_digest" =~ ^[0-9a-f]{64}$ ]]; then
        pass "releases API carries a sha256 digest for the asset"
    else
        fail "releases API carries a sha256 digest" "got: ${lr_digest:-nothing}"
    fi

    # Prove the digest matches the real asset — a mismatch here means either a
    # bad release or a broken verify path, and both would refuse every install.
    if [[ -n "${lr_url:-}" && "$lr_digest" =~ ^[0-9a-f]{64}$ ]]; then
        lrd="$(mktemp -d)"
        if curl -fsSL "$lr_url" -o "$lrd/app.AppImage" 2>/dev/null; then
            lr_actual="$(sha256sum "$lrd/app.AppImage" | awk '{print $1}')"
            check_eq "real release matches the API's sha256 digest" "$lr_digest" "$lr_actual"
        else
            printf '  %s·%s couldn'\''t download the release — skipping live checksum\n' "$DIM" "$RESET"
        fi
        rm -rf "$lrd"
    fi
fi

# ── LoreRim Autoinstall .desktop file ─────────────────────────────────────────
group "LoreRim Autoinstall .desktop file"

APPS_DIR="$tmp"
LORERIM_APPIMAGE="/home/user/.local/bin/LorerimAutoinstall.AppImage"
LORERIM_DIR="/home/user/.local/share/lorerim-autoinstall"
write_lorerim_desktop

lr_desktop="$tmp/com.lorerim.autoinstall.desktop"
[[ -f "$lr_desktop" ]] && pass ".desktop file is written" || fail ".desktop file is written"
lr_content="$(cat "$lr_desktop" 2>/dev/null || true)"

check_contains "has [Desktop Entry] header" "[Desktop Entry]" "$lr_content"
check_contains "Exec points at the AppImage" "Exec=$LORERIM_APPIMAGE" "$lr_content"
check_contains "Icon uses an absolute path"  "Icon=$LORERIM_DIR/icon.png" "$lr_content"
check_contains "Type=Application" "Type=Application" "$lr_content"
# The WM_CLASS comes from the .NET assembly name, matching the app's own AppDir
# .desktop — a drift here brings back the duplicate-taskbar-icon problem.
check_contains "StartupWMClass matches the Avalonia assembly" "StartupWMClass=Lorerim.Gui" "$lr_content"
# The app's own .desktop registers the jackify: URL scheme (Nexus download
# links); dropping it here would silently break click-to-download.
check_contains "registers the jackify: scheme handler" "MimeType=x-scheme-handler/jackify;" "$lr_content"
check_contains "Exec takes the URL argument (%u)" "%u" "$lr_content"

if have desktop-file-validate; then
    if err="$(desktop-file-validate "$lr_desktop" 2>&1)"; then
        pass "passes desktop-file-validate"
    else
        fail "passes desktop-file-validate" "$err"
    fi
else
    printf '  %s·%s desktop-file-validate not installed — skipping spec validation\n' "$DIM" "$RESET"
fi

# ── WotLK Autoinstall release-API parsing ─────────────────────────────────────
group "WotLK Autoinstall release-API parsing"

wk_release="$(github_api "https://api.github.com/repos/$WOTLK_REPO/releases/latest" 2>/dev/null)"
if [[ -z "$wk_release" ]]; then
    fail "fetched the latest release" "empty response (rate-limited? no release published yet?)"
else
    pass "fetched the latest release"

    wk_tag="$(printf '%s' "$wk_release" | grep -m1 '"tag_name"' | cut -d'"' -f4)"
    wk_url="$(printf '%s' "$wk_release" | grep -o 'https://[^"]*/WowWotlkAutoinstall-x86_64\.AppImage"' | head -1 | tr -d '"')"
    wk_sums_url="$(printf '%s' "$wk_release" | grep -o "https://[^\"]*/download/[^\"]*/$WOTLK_SUMS\"" | head -1 | tr -d '"')"

    [[ "$wk_tag" =~ ^v[0-9]+\.[0-9]+ ]] && pass "tag parses as a version ($wk_tag)" \
                                        || fail "tag parses as a version" "$wk_tag"
    check_contains "asset URL ends in the AppImage name" "$WOTLK_ASSET" "$wk_url"
    check_contains "asset URL is a GitHub download URL" "github.com" "$wk_url"

    # The stable asset name is load-bearing: a versioned name would break the
    # installer's grep and every re-run's update path.
    if [[ "$wk_url" =~ WowWotlkAutoinstall-[0-9] ]]; then
        fail "asset name carries no version" "$wk_url"
    else
        pass "asset name carries no version (re-run updates keep working)"
    fi

    # The whole verify path hangs off this asset still being published.
    check_contains "release publishes a $WOTLK_SUMS asset" "/$WOTLK_SUMS" "$wk_sums_url"

    code="$(curl -sIL -o /dev/null -w '%{http_code}' "$wk_url" 2>/dev/null)"
    check_eq "asset URL is reachable (HTTP 200)" "200" "$code"
fi

# ── WotLK Autoinstall checksum verification ───────────────────────────────────
group "WotLK Autoinstall checksum verification"

if grep -qF 'verify_wotlk "$tmp" "$sums_url" "$digest" ||' "$SCRIPT"; then
    pass "download is verified before chmod +x"
else
    fail "download is verified before chmod +x" "the AppImage would be run unverified"
fi

if awk '/^verify_wotlk\(\)/,/^}/' "$SCRIPT" | grep -q 'return 1'; then
    pass "an unverifiable checksum aborts rather than warning"
else
    fail "an unverifiable checksum aborts rather than warning"
fi

# verify_wotlk exercised for real against local SHA256SUMS files served over
# file:// — the parsing rules below are the ones that decide whether a bad
# download gets chmod'd, so they're tested by behaviour, not by grepping source.
wkv="$tmp/wotlk-verify"; mkdir -p "$wkv"
printf 'the payload\n' > "$wkv/app.AppImage"
wk_real="$(sha256sum "$wkv/app.AppImage" | awk '{print $1}')"
wk_other="$(printf 'something else\n' | sha256sum | awk '{print $1}')"

printf '%s  %s\n' "$wk_real" "$WOTLK_ASSET" > "$wkv/good.sums"
if verify_wotlk "$wkv/app.AppImage" "file://$wkv/good.sums" "" >/dev/null 2>&1; then
    pass "a matching sha256 verifies"
else
    fail "a matching sha256 verifies" "a good download was refused"
fi

printf '%s  %s\n' "$wk_other" "$WOTLK_ASSET" > "$wkv/bad.sums"
if verify_wotlk "$wkv/app.AppImage" "file://$wkv/bad.sums" "" >/dev/null 2>&1; then
    fail "a mismatched sha256 is refused" "a corrupt download would be chmod'd and run"
else
    pass "a mismatched sha256 is refused"
fi

# A second binary in the release must not be able to stand in for ours: the
# line is picked by asset name, not by being first in the file.
{ printf '%s  SomeOtherThing.AppImage\n' "$wk_other"
  printf '%s  %s\n' "$wk_real" "$WOTLK_ASSET"; } > "$wkv/multi.sums"
if verify_wotlk "$wkv/app.AppImage" "file://$wkv/multi.sums" "" >/dev/null 2>&1; then
    pass "the sha256 is matched to our asset by name, not by position"
else
    fail "the sha256 is matched to our asset by name" "it read the first line instead of ours"
fi

# No line for our asset at all is "couldn't check", which must fail closed.
printf '%s  SomeOtherThing.AppImage\n' "$wk_other" > "$wkv/absent.sums"
if verify_wotlk "$wkv/app.AppImage" "file://$wkv/absent.sums" "" >/dev/null 2>&1; then
    fail "a SHA256SUMS with no line for our asset is refused" "couldn't-check was treated as passed"
else
    pass "a SHA256SUMS with no line for our asset is refused"
fi

# Same for a missing SHA256SUMS asset and an unfetchable one.
if verify_wotlk "$wkv/app.AppImage" "" "$wk_real" >/dev/null 2>&1; then
    fail "a missing $WOTLK_SUMS asset is refused" "couldn't-check was treated as passed"
else
    pass "a missing $WOTLK_SUMS asset is refused"
fi
if verify_wotlk "$wkv/app.AppImage" "file://$wkv/nope.sums" "" >/dev/null 2>&1; then
    fail "an unfetchable $WOTLK_SUMS is refused" "couldn't-check was treated as passed"
else
    pass "an unfetchable $WOTLK_SUMS is refused"
fi

# SHA256SUMS says one thing, the releases API another — that's an asset nobody
# re-hashed, and it fails rather than picking a winner.
if verify_wotlk "$wkv/app.AppImage" "file://$wkv/good.sums" "$wk_other" >/dev/null 2>&1; then
    fail "a SHA256SUMS/API digest disagreement is refused" "one record silently overrode the other"
else
    pass "a SHA256SUMS/API digest disagreement is refused"
fi

# sha256sum's binary-mode marker ('*name') is still our asset's line.
printf '%s *%s\n' "$wk_real" "$WOTLK_ASSET" > "$wkv/binmode.sums"
if verify_wotlk "$wkv/app.AppImage" "file://$wkv/binmode.sums" "" >/dev/null 2>&1; then
    pass "a binary-mode ('*name') SHA256SUMS line is understood"
else
    fail "a binary-mode ('*name') SHA256SUMS line is understood" "a valid release would be refused"
fi

# And the real release must pass all of it — a failure here means either a bad
# release or a broken verify path, and both would refuse every install.
if [[ -n "${wk_url:-}" && -n "${wk_sums_url:-}" ]]; then
    wkd="$(mktemp -d)"
    if curl -fsSL "$wk_url" -o "$wkd/app.AppImage" 2>/dev/null; then
        wk_api_digest="$(printf '%s' "$wk_release" | WOTLK_ASSET="$WOTLK_ASSET" python -c '
import json, os, sys
for a in json.load(sys.stdin).get("assets", []):
    if a.get("name") == os.environ["WOTLK_ASSET"]:
        d = a.get("digest") or ""
        if d.startswith("sha256:"):
            print(d[len("sha256:"):])
        break
' 2>/dev/null)"
        if verify_wotlk "$wkd/app.AppImage" "$wk_sums_url" "$wk_api_digest" >/dev/null 2>&1; then
            pass "the real release verifies against its own $WOTLK_SUMS"
        else
            fail "the real release verifies against its own $WOTLK_SUMS" \
                 "the published binary does not match the published checksum"
        fi
    else
        printf '  %s·%s couldn'\''t download the release — skipping live checksum\n' "$DIM" "$RESET"
    fi
    rm -rf "$wkd"
fi

# ── WotLK Autoinstall .desktop file ───────────────────────────────────────────
group "WotLK Autoinstall .desktop file"

APPS_DIR="$tmp"
WOTLK_APPIMAGE="/home/user/.local/bin/WowWotlkAutoinstall.AppImage"
WOTLK_DIR="/home/user/.local/share/wow-wotlk-autoinstall"
write_wotlk_desktop

wk_desktop="$tmp/com.wowwotlk.autoinstall.desktop"
[[ -f "$wk_desktop" ]] && pass ".desktop file is written" || fail ".desktop file is written"
wk_content="$(cat "$wk_desktop" 2>/dev/null || true)"

check_contains "has [Desktop Entry] header" "[Desktop Entry]" "$wk_content"
check_contains "Exec points at the AppImage" "Exec=$WOTLK_APPIMAGE" "$wk_content"
check_contains "Icon uses an absolute path"  "Icon=$WOTLK_DIR/icon.png" "$wk_content"
check_contains "Type=Application" "Type=Application" "$wk_content"
# The WM_CLASS comes from the .NET assembly name, matching the app's own AppDir
# .desktop — a drift here brings back the duplicate-taskbar-icon problem.
check_contains "StartupWMClass matches the Avalonia assembly" "StartupWMClass=WowWotlk.Gui" "$wk_content"
# Unlike LoreRim this app registers no URL scheme, so a %u would be handed to an
# Exec that ignores it. Assert it stays off rather than getting copy-pasted in.
if grep -q '%u' <<<"$wk_content"; then
    fail "Exec takes no URL argument" "a %u was added for an app that handles no scheme"
else
    pass "Exec takes no URL argument (this app registers no scheme)"
fi

if have desktop-file-validate; then
    if err="$(desktop-file-validate "$wk_desktop" 2>&1)"; then
        pass "passes desktop-file-validate"
    else
        fail "passes desktop-file-validate" "$err"
    fi
else
    printf '  %s·%s desktop-file-validate not installed — skipping spec validation\n' "$DIM" "$RESET"
fi

# ── Music AI Player release-API parsing ───────────────────────────────────────
group "Music AI Player release-API parsing"

# Run against a HOME that has an applications dir but none of our launchers —
# the state of any box that has run this script before but not yet installed
# this app. Doing it under the tester's real HOME would pass or fail depending
# on whether they happen to have the app already, which is not a test.
ma_home="$tmp/musicai-home"; mkdir -p "$ma_home/.local/share/applications"
printf '[Desktop Entry]\nName=Unrelated\nExec=/usr/bin/true\n' \
    > "$ma_home/.local/share/applications/unrelated.desktop"
out="$(HOME="$ma_home" bash "$SCRIPT" --only musicai --dry-run 2>&1)"; rc=$?
check_eq "--only musicai is accepted on a box without it installed" "0" "$rc"
check_contains "the dry run reaches the end of the step" "stamp version" "$out"

# The step must run before config: configure_taskbar pins music-ai-player.desktop,
# and a launcher that doesn't exist yet is skipped with a warning, not pinned.
ma_line="$(grep -n -m1 'wanted musicai' "$SCRIPT" | cut -d: -f1)"
ma_cfg_line="$(grep -n -m1 'wanted config' "$SCRIPT" | cut -d: -f1)"
if [[ -n "$ma_line" && -n "$ma_cfg_line" && "$ma_line" -lt "$ma_cfg_line" ]]; then
    pass "Music AI Player installs before the config step pins the taskbar"
else
    fail "Music AI Player installs before the config step" "musicai=$ma_line config=$ma_cfg_line"
fi

ma_release="$(github_api "https://api.github.com/repos/$MUSICAI_REPO/releases/latest" 2>/dev/null)"
if [[ -z "$ma_release" || "$ma_release" == *'"Not Found"'* ]]; then
    fail "fetched the latest release" "empty response (rate-limited?)"
else
    pass "fetched the latest release"

    ma_tag="$(printf '%s' "$ma_release" | grep -m1 '"tag_name"' | cut -d'"' -f4)"
    ma_url="$(printf '%s' "$ma_release" | grep -o 'https://[^"]*_amd64\.AppImage"' | head -1 | tr -d '"')"

    [[ "$ma_tag" =~ ^v[0-9]+\.[0-9]+ ]] && pass "tag parses as a version ($ma_tag)" \
                                        || fail "tag parses as a version" "$ma_tag"
    check_contains "asset URL ends in _amd64.AppImage" "_amd64.AppImage" "$ma_url"
    check_contains "asset URL is a GitHub download URL" "github.com" "$ma_url"

    if [[ "$ma_url" == *.sig ]]; then
        fail "asset URL is the AppImage, not the .sig" "$ma_url"
    else
        pass "asset URL is the AppImage, not the .sig"
    fi

    # This release also ships a _amd64.deb (and its own .sig). The pattern must
    # pick the AppImage out of all four, and pick exactly one — a second match
    # would make `head -1` the thing deciding what gets installed.
    if [[ "$ma_url" == *.deb ]]; then
        fail "asset URL is the AppImage, not the .deb" "$ma_url"
    else
        pass "asset URL is the AppImage, not the .deb"
    fi
    # `grep -o | wc -l`, not `grep -c`: the API returns the whole release on one
    # line, and -c counts matching LINES, so it would report 1 for any number of
    # matches — exactly the case this test exists to catch.
    ma_matches="$(printf '%s' "$ma_release" | grep -o 'https://[^"]*_amd64\.AppImage"' | wc -l)"
    check_eq "exactly one asset URL matches the pattern" "1" "$ma_matches"

    code="$(curl -sIL -o /dev/null -w '%{http_code}' "$ma_url" 2>/dev/null)"
    check_eq "asset URL is reachable (HTTP 200)" "200" "$code"
fi

# ── Music AI Player signature verification ────────────────────────────────────
group "Music AI Player signature verification"

if grep -qF 'verify_musicai "$tmp" "$url" ||' "$SCRIPT"; then
    pass "download is verified before chmod +x"
else
    fail "download is verified before chmod +x" "the AppImage would be run unverified"
fi

if awk '/^verify_musicai\(\)/,/^}/' "$SCRIPT" | grep -q 'return 1'; then
    pass "an unverifiable signature aborts rather than warning"
else
    fail "an unverifiable signature aborts rather than warning"
fi

# The key is embedded, never pulled off the wire from the host it vouches for.
if awk '/^verify_musicai\(\)/,/^}/' "$SCRIPT" | grep -qi 'pubkey.*curl\|curl.*pubkey\|tauri.conf'; then
    fail "public key is embedded, not fetched at runtime"
else
    pass "public key is embedded, not fetched at runtime"
fi

# The pubkey in install.sh must match what the app actually ships in its Tauri
# config (stored there as base64 of the whole minisign key file). A drift here
# means every download would fail verification — catch it at test time.
ma_conf="$(curl -fsSL "https://raw.githubusercontent.com/$MUSICAI_REPO/$MUSICAI_BRANCH/src-tauri/tauri.conf.json" 2>/dev/null || true)"
if [[ -n "$ma_conf" ]]; then
    ma_conf_key="$(printf '%s' "$ma_conf" | grep -m1 '"pubkey"' | cut -d'"' -f4 | base64 -d 2>/dev/null | tail -1 || true)"
    if [[ -n "$ma_conf_key" ]]; then
        check_eq "embedded pubkey matches the app's tauri.conf.json" "$ma_conf_key" "$MUSICAI_PUBKEY"
    else
        printf '  %s·%s couldn'\''t decode the pubkey from tauri.conf.json — skipping\n' "$DIM" "$RESET"
    fi
else
    printf '  %s·%s couldn'\''t fetch tauri.conf.json — skipping pubkey cross-check\n' "$DIM" "$RESET"
fi

# And prove the real release verifies against the embedded key. Tauri v2 signs
# the AppImage itself here (not a .tar.gz of it), which is what makes verifying
# the downloaded file directly the right check.
if have minisign && [[ -n "${ma_tag:-}" && -n "${ma_url:-}" ]]; then
    mad="$(mktemp -d)"
    if curl -fsSL "$ma_url" -o "$mad/app.AppImage" 2>/dev/null \
       && curl -fsSL "$ma_url.sig" 2>/dev/null | base64 -d > "$mad/app.AppImage.minisig" 2>/dev/null; then
        if minisign -Vm "$mad/app.AppImage" -x "$mad/app.AppImage.minisig" -P "$MUSICAI_PUBKEY" >/dev/null 2>&1; then
            pass "real release verifies against the embedded public key"
        else
            fail "real release verifies against the embedded public key" "minisign rejected it"
        fi
    else
        printf '  %s·%s couldn'\''t download the release — skipping live verify\n' "$DIM" "$RESET"
    fi
    rm -rf "$mad"
else
    printf '  %s·%s minisign missing or no release — skipping live signature check\n' "$DIM" "$RESET"
fi

# The icon is fetched off the default branch, which is master here, not main —
# a wrong branch is a 404 and a launcher with no icon, warned about but installed.
ma_icon="https://raw.githubusercontent.com/$MUSICAI_REPO/$MUSICAI_BRANCH/src-tauri/icons/icon.png"
code="$(curl -sIL -o /dev/null -w '%{http_code}' "$ma_icon" 2>/dev/null)"
check_eq "icon URL is reachable on the app's default branch (HTTP 200)" "200" "$code"

# ── Music AI Player .desktop file ─────────────────────────────────────────────
group "Music AI Player .desktop file"

APPS_DIR="$tmp"
MUSICAI_APPIMAGE="/home/user/.local/bin/MusicAIPlayer.AppImage"
MUSICAI_DIR="/home/user/.local/share/music-ai-player"
write_musicai_desktop

# The file NAME is part of the contract, not a style choice: on Wayland the
# compositor matches the running window to a .desktop named for its app-id,
# which Tauri takes from the crate name — so this file cannot be renamed to the
# com.<app>.app form without leaving the running window a generic icon.
ma_desktop="$tmp/music-ai-player.desktop"
[[ -f "$ma_desktop" ]] && pass ".desktop file is written, named for the Wayland app-id" \
                       || fail ".desktop file is written, named for the Wayland app-id"
ma_content="$(cat "$ma_desktop" 2>/dev/null || true)"

check_contains "has [Desktop Entry] header" "[Desktop Entry]" "$ma_content"
check_contains "Exec points at the AppImage" "Exec=$MUSICAI_APPIMAGE" "$ma_content"
check_contains "Icon uses an absolute path"  "Icon=$MUSICAI_DIR/icon.png" "$ma_content"
check_contains "Type=Application" "Type=Application" "$ma_content"
check_contains "StartupWMClass matches the Tauri crate name" "StartupWMClass=music-ai-player" "$ma_content"

# The name pinned in taskbar.txt has to be the name actually written, or the
# taskbar step skips the tile with a warning.
if grep -qx 'music-ai-player.desktop' <(read_list "$REPO_ROOT/packages/taskbar.txt"); then
    pass "the pinned launcher name matches the file that gets written"
else
    fail "the pinned launcher name matches the file that gets written" \
         "taskbar.txt pins a name write_musicai_desktop never creates"
fi

if have desktop-file-validate; then
    if err="$(desktop-file-validate "$ma_desktop" 2>&1)"; then
        pass "passes desktop-file-validate"
    else
        fail "passes desktop-file-validate" "$err"
    fi
else
    printf '  %s·%s desktop-file-validate not installed — skipping spec validation\n' "$DIM" "$RESET"
fi

# ── the Omarchy step ──────────────────────────────────────────────────────────
group "Omarchy desktop step"

# Same gate, same reason as the KDE-only steps: this one writes omarchy-shell's
# config and clones its plugins, none of which exist anywhere else.
if awk '/^configure_omarchy\(\)/,/^}/' "$SCRIPT" | grep -q '\[\[ "\$DESKTOP" != omarchy \]\]'; then
    pass "configure_omarchy returns early off Omarchy"
else
    fail "configure_omarchy returns early off Omarchy" "it would write shell.json on KDE"
fi

# `wanted omarchy && configure_omarchy` puts this after the final && in main(),
# where a non-zero return is NOT exempt from set -e — the footgun this suite
# already guards install_packages and configure_system against.
for d in kde omarchy other; do
    om_home="$tmp/omhome-$d"; mkdir -p "$om_home"
    if ( set -e
         HOME="$om_home" DESKTOP="$d" DRY_RUN=1
         wanted omarchy && configure_omarchy ) >/dev/null 2>&1; then
        pass "configure_omarchy returns 0 on $d"
    else
        fail "configure_omarchy returns 0 on $d" \
             "set -e would kill the run just before the summary"
    fi
done

om_gate="$tmp/omgate"; mkdir -p "$om_gate/.config"
( HOME="$om_gate" DESKTOP=kde DRY_RUN=0 configure_omarchy ) >/dev/null 2>&1
if [[ -e "$om_gate/.config/omarchy" || -e "$om_gate/.config/hypr" ]]; then
    fail "no Omarchy config is written on KDE" "the step wrote to a Plasma box's HOME"
else
    pass "no Omarchy config is written on KDE"
fi

out="$( HOME="$om_gate" DESKTOP=kde DRY_RUN=1 configure_omarchy 2>&1 )"
check_contains "the Omarchy step says why it skipped" "not Omarchy" "$out"

# ── shell.toml: the shell's own text size ─────────────────────────────────────
#
# This file is a hand-editable override that the user may already have other
# sections in, so the upsert has to be surgical — the whole reason it mirrors
# omarchy-display-text-size's awk instead of rewriting the file.
sf_home="$tmp/sfhome"; mkdir -p "$sf_home/.config/omarchy"
printf '[bar]\nsize-horizontal = 30\n\n[font]\nbase-size = 12\nbody = 13\n' \
    > "$sf_home/.config/omarchy/shell.toml"
( HOME="$sf_home" DESKTOP=omarchy DRY_RUN=0 OMARCHY_SHELL_FONT_PX=16 omarchy_shell_font ) >/dev/null 2>&1
sf="$(cat "$sf_home/.config/omarchy/shell.toml" 2>/dev/null || true)"

check_contains "base-size is updated in place"     "base-size = 16"    "$sf"
check_contains "other [font] keys are left alone"  "body = 13"         "$sf"
check_contains "other sections are left alone"     "size-horizontal = 30" "$sf"
check_eq "base-size is written exactly once" "1" "$(grep -c 'base-size' <<<"$sf")"

# ...and the file gets created when the machine has none.
sf2_home="$tmp/sfhome2"; mkdir -p "$sf2_home"
( HOME="$sf2_home" DESKTOP=omarchy DRY_RUN=0 OMARCHY_SHELL_FONT_PX=16 omarchy_shell_font ) >/dev/null 2>&1
sf2="$(cat "$sf2_home/.config/omarchy/shell.toml" 2>/dev/null || true)"
check_contains "a missing shell.toml is created with [font]" "[font]" "$sf2"
check_contains "a missing shell.toml gets the size"          "base-size = 16" "$sf2"

# A dry run must not create it at all.
sf3_home="$tmp/sfhome3"; mkdir -p "$sf3_home"
( HOME="$sf3_home" DESKTOP=omarchy DRY_RUN=1 OMARCHY_SHELL_FONT_PX=16 omarchy_shell_font ) >/dev/null 2>&1
if [[ -e "$sf3_home/.config/omarchy/shell.toml" ]]; then
    fail "a dry run writes no shell.toml" "the file was created anyway"
else
    pass "a dry run writes no shell.toml"
fi

# ── shell.json: the bar layout ────────────────────────────────────────────────
#
# Edited, never overwritten: dragging a widget along the bar writes this same
# file, and a setup script that clobbers it would undo that on every run.
bj_home="$tmp/bjhome"
bj_user="${USER:-$(id -un)}"
mkdir -p "$bj_home/.config/omarchy/plugins/$bj_user.bar" \
         "$bj_home/.config/omarchy/plugins/$bj_user.tray"
cat > "$bj_home/.config/omarchy/shell.json" <<'JSON'
{
  "version": 1,
  "bar": {
    "position": "top",
    "layout": {
      "left": [ { "id": "omarchy.menu" } ],
      "center": [ { "id": "omarchy.clock", "format": "dddd HH:mm" } ],
      "right": [ { "id": "omarchy.tray" }, { "id": "omarchy.power" } ]
    }
  }
}
JSON
( HOME="$bj_home"; DESKTOP=omarchy; DRY_RUN=0
  OMARCHY_CLOCK_FORMAT="ddd d MMM h:mm AP"; OMARCHY_CLOCK_FORMAT_VERTICAL="h"
  OMARCHY_BAR_RIGHT_EXTRA=(omarchy.dropbox crmne.hyprmoncfg)
  OMARCHY_BAR_MONITORS=(DP-1)
  omarchy_bar_layout ) >/dev/null 2>&1

bj_read() { python -c "
import json,sys
d=json.load(open('$bj_home/.config/omarchy/shell.json'))
r=[e['id'] for e in d['bar']['layout']['right']]
c=[e for e in d['bar']['layout']['center'] if e['id']=='omarchy.clock']
print(d['bar'].get('id',''))
print(','.join(r))
print(c[0]['format'] if c else '')
" 2>/dev/null; }

check_eq "bar.id points at the cloned bar"  "$bj_user.bar" "$(bj_read | sed -n 1p)"
check_eq "the tray entry is swapped for the clone, in place" \
         "$bj_user.tray,omarchy.dropbox,crmne.hyprmoncfg,omarchy.power" "$(bj_read | sed -n 2p)"
check_eq "the clock format is applied" "ddd d MMM h:mm AP" "$(bj_read | sed -n 3p)"

# The monitor list only means anything to the patched clone, but writing it is
# harmless on a stock bar, which has no such key and ignores it.
if grep -q '"DP-1"' "$bj_home/.config/omarchy/shell.json"; then
    pass "the monitor list is written to shell.json"
else
    fail "the monitor list is written to shell.json" "the bar would appear on every screen"
fi

# Widgets the user has since moved must not be re-added, and a second run must
# not stack a second copy of the extras next to the tray.
bj_once="$(cat "$bj_home/.config/omarchy/shell.json")"
( HOME="$bj_home"; DESKTOP=omarchy; DRY_RUN=0
  OMARCHY_CLOCK_FORMAT="ddd d MMM h:mm AP"; OMARCHY_CLOCK_FORMAT_VERTICAL="h"
  OMARCHY_BAR_RIGHT_EXTRA=(omarchy.dropbox crmne.hyprmoncfg)
  OMARCHY_BAR_MONITORS=(DP-1)
  omarchy_bar_layout ) >/dev/null 2>&1
check_eq "a second run changes nothing" "$bj_once" "$(cat "$bj_home/.config/omarchy/shell.json")"

# Pointing shell.json at a plugin directory that isn't there is how you get a
# desktop with no bar at all, so the id is only claimed when the clone exists.
bj2_home="$tmp/bjhome2"; mkdir -p "$bj2_home/.config/omarchy"
cp "$bj_home/.config/omarchy/shell.json" "$bj2_home/.config/omarchy/shell.json"
python - "$bj2_home/.config/omarchy/shell.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d["bar"].pop("id",None)
json.dump(d,open(p,"w"),indent=2,sort_keys=True)
PY
( HOME="$bj2_home"; DESKTOP=omarchy; DRY_RUN=0
  OMARCHY_CLOCK_FORMAT="x"; OMARCHY_CLOCK_FORMAT_VERTICAL="x"
  OMARCHY_BAR_RIGHT_EXTRA=()
  OMARCHY_BAR_MONITORS=()
  omarchy_bar_layout ) >/dev/null 2>&1
if grep -q '"id": "'"$bj_user"'.bar"' "$bj2_home/.config/omarchy/shell.json"; then
    fail "no cloned bar id is written when the clone is missing" \
         "shell.json points at a plugin that doesn't exist — that's a blank bar"
else
    pass "no cloned bar id is written when the clone is missing"
fi

# ── the QML patches ───────────────────────────────────────────────────────────
for p in bar-islands tray-collapse; do
    if [[ -f "$REPO_ROOT/omarchy/patches/$p.patch" ]]; then
        pass "omarchy/patches/$p.patch is vendored"
    else
        fail "omarchy/patches/$p.patch is vendored" "the step would warn and run stock Omarchy code"
    fi
done

# The patches are context diffs against Omarchy's own shell. On a box that has
# it, check they still apply — this is the early warning that an omarchy update
# has moved the code out from under them, before a run reports it as a warning
# and quietly leaves you with a stock bar.
if have patch && [[ -r /usr/share/omarchy/shell/plugins/bar/Bar.qml ]]; then
    for pair in "bar-islands:/usr/share/omarchy/shell/plugins/bar/Bar.qml:Bar.qml" \
                "tray-collapse:/usr/share/omarchy/shell/plugins/bar/widgets/Tray.qml:Tray.qml"; do
        pname="${pair%%:*}"; rest="${pair#*:}"; upstream="${rest%%:*}"; fname="${rest##*:}"
        pdir="$(mktemp -d)"; cp "$upstream" "$pdir/$fname"
        if patch -p1 --forward -s -d "$pdir" < "$REPO_ROOT/omarchy/patches/$pname.patch" >/dev/null 2>&1; then
            pass "$pname.patch still applies to this machine's $fname"
        else
            fail "$pname.patch still applies to this machine's $fname" \
                 "regenerate it against the installed Omarchy, or the bar comes back stock"
        fi
        rm -rf "$pdir"
    done
else
    printf '  %s·%s no Omarchy shell installed — skipping the patch-applies check\n' "$DIM" "$RESET"
fi

# The background named in install.sh has to be one of the files this repo
# actually carries, or the step warns and leaves the stock wallpaper up. Either
# of the two places it can be carried counts, the same two omarchy_background
# looks in: loose under omarchy/backgrounds/<theme>/, or inside a vendored
# theme's own backgrounds/, which is where a self-contained theme keeps them.
if [[ -z "$OMARCHY_BACKGROUND" ]]; then
    pass "no background pinned — nothing to vendor"
elif [[ -f "$REPO_ROOT/omarchy/backgrounds/$OMARCHY_THEME/$OMARCHY_BACKGROUND" \
     || -f "$REPO_ROOT/omarchy/themes/$OMARCHY_THEME/backgrounds/$OMARCHY_BACKGROUND" ]]; then
    pass "the pinned background is vendored for the $OMARCHY_THEME theme"
else
    fail "the pinned background is vendored for the $OMARCHY_THEME theme" \
         "OMARCHY_BACKGROUND is in neither omarchy/backgrounds/$OMARCHY_THEME/ nor omarchy/themes/$OMARCHY_THEME/backgrounds/"
fi

# Hyprland rules live in a file this repo owns, loaded by one dofile line, so
# the user's own hyprland.lua is never rewritten. Both halves have to be there.
if [[ -f "$REPO_ROOT/omarchy/hypr/personal.lua" ]]; then
    pass "the Hyprland rules file is vendored"
else
    fail "the Hyprland rules file is vendored" "the dofile line would point at nothing"
fi
if awk '/^omarchy_hypr\(\)/,/^}/' "$SCRIPT" | grep -q 'grep -qF .hypr/arch-setup.lua'; then
    pass "the dofile line is only appended when it isn't already there"
else
    fail "the dofile line is only appended when it isn't already there" \
         "every run would add another copy to hyprland.lua"
fi

# ── mise's banner ─────────────────────────────────────────────────────────────
#
# The setting has to land INSIDE an existing [settings] table: TOML rejects the
# same table twice, and a config mise refuses to parse is worse than the banner.
if have mise; then
    mq_home="$tmp/mqhome"; mkdir -p "$mq_home/.config/mise"
    printf '[tools]\ngh = "latest"\n\n[settings]\nidiomatic_version_file_enable_tools = []\n' \
        > "$mq_home/.config/mise/config.toml"
    ( HOME="$mq_home"; DRY_RUN=0; omarchy_mise_quiet ) >/dev/null 2>&1
    mq="$(cat "$mq_home/.config/mise/config.toml" 2>/dev/null || true)"

    check_contains "quiet lands in the existing [settings]" "quiet = true" "$mq"
    check_eq "no second [settings] table is written" "1" "$(grep -c '^\[settings\]' <<<"$mq")"
    check_contains "the settings already there survive" "idiomatic_version_file_enable_tools" "$mq"

    mq_once="$mq"
    ( HOME="$mq_home"; DRY_RUN=0; omarchy_mise_quiet ) >/dev/null 2>&1
    check_eq "a second run adds nothing" "$mq_once" "$(cat "$mq_home/.config/mise/config.toml")"

    mq2_home="$tmp/mqhome2"; mkdir -p "$mq2_home/.config/mise"
    printf '[tools]\ngh = "latest"\n' > "$mq2_home/.config/mise/config.toml"
    ( HOME="$mq2_home"; DRY_RUN=0; omarchy_mise_quiet ) >/dev/null 2>&1
    mq2="$(cat "$mq2_home/.config/mise/config.toml" 2>/dev/null || true)"
    check_contains "[settings] is appended when the config has none" "[settings]" "$mq2"
    check_contains "...with the quiet setting in it" "quiet = true" "$mq2"
    check_contains "the tools section is left alone" 'gh = "latest"' "$mq2"
else
    printf '  %s·%s mise not installed — skipping the banner setting\n' "$DIM" "$RESET"
fi

# ── vendored themes ───────────────────────────────────────────────────────────
#
# The theme is applied by name in the very next step, so if these files don't
# land first, `omarchy theme set nebula` has nothing to set and the run ends on
# a warning about a theme that is sitting right there in the repo.
tf_home="$tmp/tfhome"; mkdir -p "$tf_home"
( HOME="$tf_home" DESKTOP=omarchy DRY_RUN=0 omarchy_theme_files ) >/dev/null 2>&1

for f in colors.toml hyprland.lua backgrounds/nebula.jpg; do
    if [[ -f "$tf_home/.config/omarchy/themes/nebula/$f" ]]; then
        pass "the vendored nebula theme installs $f"
    else
        fail "the vendored nebula theme installs $f" "not in ~/.config/omarchy/themes/nebula/"
    fi
done

# The rounding is the whole point of the theme carrying its own hyprland.lua —
# a colors.toml alone gets a generated one with borders and nothing else.
check_contains "the theme sets a corner radius" "rounding = 14" \
    "$(cat "$tf_home/.config/omarchy/themes/nebula/hyprland.lua" 2>/dev/null)"

# Re-running must be quiet, or every run reports files it didn't really install.
out="$( HOME="$tf_home" DESKTOP=omarchy DRY_RUN=0 omarchy_theme_files 2>&1 )"
check_contains "a second run copies nothing" "already installed" "$out"

# Nothing of the user's own is thrown away — a preview or an extra wallpaper
# dropped into the theme by hand is theirs.
printf 'mine\n' > "$tf_home/.config/omarchy/themes/nebula/preview.png"
( HOME="$tf_home" DESKTOP=omarchy DRY_RUN=0 omarchy_theme_files ) >/dev/null 2>&1
if [[ -f "$tf_home/.config/omarchy/themes/nebula/preview.png" ]]; then
    pass "files the repo doesn't carry are left alone"
else
    fail "files the repo doesn't carry are left alone" "the step deleted preview.png"
fi

tf2_home="$tmp/tfhome2"; mkdir -p "$tf2_home"
( HOME="$tf2_home" DESKTOP=omarchy DRY_RUN=1 omarchy_theme_files ) >/dev/null 2>&1
if [[ -e "$tf2_home/.config/omarchy/themes" ]]; then
    fail "a dry run installs no theme" "the files were copied anyway"
else
    pass "a dry run installs no theme"
fi

# The wallpaper lives in the theme's own backgrounds/, not in
# omarchy/backgrounds/<theme>/, so the selection half of omarchy_background has
# to keep going after finding nothing vendored under that name.
bg_home="$tmp/bghome"; mkdir -p "$bg_home"
( HOME="$bg_home" DESKTOP=omarchy DRY_RUN=0 omarchy_theme_files ) >/dev/null 2>&1
out="$( HOME="$bg_home" DESKTOP=omarchy DRY_RUN=1 \
        OMARCHY_THEME=nebula OMARCHY_BACKGROUND=nebula.jpg omarchy_background 2>&1 )"
check_contains "the background is selected from the theme's own folder" \
    "themes/nebula/backgrounds/nebula.jpg" "$out"

# Applying a theme symlinks the current background out of the copy under
# ~/.local/state, never out of the folder the file was installed to, so a path
# comparison alone always says "not set yet" and re-sets the wallpaper on every
# single run.
mkdir -p "$bg_home/.local/state/omarchy/current/theme/backgrounds"
cp "$bg_home/.config/omarchy/themes/nebula/backgrounds/nebula.jpg" \
   "$bg_home/.local/state/omarchy/current/theme/backgrounds/nebula.jpg"
ln -sfn "$bg_home/.local/state/omarchy/current/theme/backgrounds/nebula.jpg" \
        "$bg_home/.local/state/omarchy/current/background"
out="$( HOME="$bg_home" DESKTOP=omarchy DRY_RUN=1 \
        OMARCHY_THEME=nebula OMARCHY_BACKGROUND=nebula.jpg omarchy_background 2>&1 )"
check_contains "the wallpaper isn't re-set when it's already up" \
    "background already nebula.jpg" "$out"

# ── foot alpha ────────────────────────────────────────────────────────────────
#
# foot.ini is a file worth hand-editing, and the section alpha belongs in is the
# same one the theme fills with colours through an include at the top of [main].
# So the upsert has to be surgical in three different starting shapes.
fa_write() { mkdir -p "$1/.config/foot"; cat > "$1/.config/foot/foot.ini"; }
fa_read()  { cat "$1/.config/foot/foot.ini" 2>/dev/null; }
# ${3-0.85} rather than ${3:-0.85}: an empty third argument is the "no alpha
# pinned" case and has to reach the function as an empty string, not be
# swallowed by the default.
fa_run()   { ( HOME="$1" DESKTOP=omarchy DRY_RUN="${2:-0}" FOOT_ALPHA="${3-0.85}" \
               omarchy_terminal_alpha ) 2>&1; }

# 1. No [colors-dark] at all — the section is appended.
fa1="$tmp/fa1"; fa_write "$fa1" <<'INI'
[main]
include=~/.local/state/omarchy/current/theme/foot.ini
font=JetBrainsMono Nerd Font:size=11

[cursor]
style=block
INI
fa_run "$fa1" >/dev/null
fa="$(fa_read "$fa1")"
check_contains "a missing [colors-dark] is appended" "[colors-dark]" "$fa"
check_contains "...with the alpha in it"             "alpha=0.85"    "$fa"
check_contains "the include is left alone"           "include=~/.local/state" "$fa"
check_contains "other sections survive"              "style=block"   "$fa"

# The section must land after the include, or the theme's own [colors-dark]
# overrides it and the terminal stays opaque.
inc_line="$(grep -n 'include=' <<<"$fa" | cut -d: -f1)"
sec_line="$(grep -n '^\[colors-dark\]' <<<"$fa" | cut -d: -f1)"
if [[ -n "$inc_line" && -n "$sec_line" && $sec_line -gt $inc_line ]]; then
    pass "the alpha section is written after the include"
else
    fail "the alpha section is written after the include" \
         "include at $inc_line, [colors-dark] at $sec_line — the theme would win"
fi

# 2. [colors-dark] exists with a different alpha — replaced in place, once.
fa2="$tmp/fa2"; fa_write "$fa2" <<'INI'
[main]
font=JetBrainsMono Nerd Font:size=11

[colors-dark]
alpha=0.95
background=0a1621

[cursor]
style=block
INI
fa_run "$fa2" >/dev/null
fa="$(fa_read "$fa2")"
check_contains "an existing alpha is updated"   "alpha=0.85"      "$fa"
check_eq "the alpha is written exactly once" "1" "$(grep -c '^alpha=' <<<"$fa")"
check_contains "sibling keys are left alone"    "background=0a1621" "$fa"
check_contains "later sections are left alone"  "style=block"     "$fa"

# 3. [colors-dark] exists with no alpha — inserted into that section, not a new one.
fa3="$tmp/fa3"; fa_write "$fa3" <<'INI'
[colors-dark]
background=0a1621

[cursor]
style=block
INI
fa_run "$fa3" >/dev/null
fa="$(fa_read "$fa3")"
check_eq "no second [colors-dark] is written" "1" "$(grep -c '^\[colors-dark\]' <<<"$fa")"
check_contains "the alpha joins the existing section" "alpha=0.85" "$fa"
if [[ "$(grep -n 'alpha=0.85' <<<"$fa" | cut -d: -f1)" -lt "$(grep -n '^\[cursor\]' <<<"$fa" | cut -d: -f1)" ]]; then
    pass "the alpha lands inside [colors-dark], not after it"
else
    fail "the alpha lands inside [colors-dark], not after it" "it fell into [cursor]"
fi

# Re-running is quiet, and a dry run writes nothing.
check_contains "a second run reports no change" "already 0.85" "$(fa_run "$fa2")"

fa4="$tmp/fa4"; fa_write "$fa4" <<'INI'
[main]
font=JetBrainsMono Nerd Font:size=11
INI
before_fa="$(fa_read "$fa4")"
fa_run "$fa4" 1 >/dev/null
check_eq "a dry run changes no foot.ini" "$before_fa" "$(fa_read "$fa4")"

# An empty FOOT_ALPHA means "leave whatever is there", not "write nothing".
check_contains "an unset alpha is left alone" "left alone" "$(fa_run "$fa4" 0 "")"

# ── blur ──────────────────────────────────────────────────────────────────────
#
# The transparency above is only readable because the wallpaper behind it is
# blurred, and Omarchy ships blur off. The two are set in different files, so
# nothing but this check ties them together.
if grep -q "FOOT_ALPHA=" "$SCRIPT" && [[ -n "$FOOT_ALPHA" ]]; then
    if grep -qE '^\s*enabled = true' "$REPO_ROOT/omarchy/hypr/personal.lua" \
       && grep -q 'blur' "$REPO_ROOT/omarchy/hypr/personal.lua"; then
        pass "a transparent terminal comes with blur enabled"
    else
        fail "a transparent terminal comes with blur enabled" \
             "FOOT_ALPHA is set but personal.lua never turns blur on"
    fi
fi

out="$(HOME="$tmp/omonly" bash "$SCRIPT" --only omarchy --dry-run 2>&1)"; rc=$?
check_eq "--only omarchy is a valid step" "0" "$rc"
check_contains "--only omarchy runs the Omarchy step" "Omarchy desktop" "$out"

# ── --dry-run is genuinely inert ──────────────────────────────────────────────
group "--dry-run changes nothing"

fake_home="$tmp/home"
mkdir -p "$fake_home"
before="$(find "$fake_home" | sort)"

# Hand the child a token explicitly. It runs under a fake HOME, so `gh` can't
# find its config and the run would fall back to the 60/hour unauthenticated
# budget — making this assertion about dry-run inertness fail for an unrelated
# reason whenever that budget happens to be spent.
#
# Resolve it BEFORE the command rather than as an assignment prefix: earlier
# prefixes are visible to later expansions, so `HOME=... GH_TOKEN="$(github_token)"`
# would look the token up under the fake HOME and find nothing.
gh_tok="$(github_token)"
out="$(HOME="$fake_home" PROJECTS_DIR="$fake_home/Projects" GH_TOKEN="$gh_tok" \
       bash "$SCRIPT" --dry-run 2>&1)"; rc=$?
after="$(find "$fake_home" | sort)"

check_eq "--dry-run exits 0" "0" "$rc"
check_eq "--dry-run creates no files in HOME" "$before" "$after"
check_contains "--dry-run announces itself" "DRY RUN" "$out"
check_contains "--dry-run would install packages" "[dry-run] sudo pacman -S --needed" "$out"
check_contains "--dry-run would clone AgentTileCLI" "[dry-run] git clone" "$out"
check_contains "--dry-run never invokes sudo" "no sudo needed" "$out"

# A dry run must not leave a half-downloaded AppImage anywhere.
if [[ -e "$fake_home/.local/bin/StreamHub.AppImage" || -e "$fake_home/.local/bin/ConsoleVault.AppImage" \
   || -e "$fake_home/.local/bin/GridDown.AppImage" \
   || -e "$fake_home/.local/bin/StalkerGammaGui.AppImage" || -e "$fake_home/.local/bin/LorerimAutoinstall.AppImage" \
   || -e "$fake_home/.local/bin/WowWotlkAutoinstall.AppImage" ]]; then
    fail "--dry-run downloads no AppImage"
else
    pass "--dry-run downloads no AppImage"
fi

# ── summary ───────────────────────────────────────────────────────────────────
printf '\n%s%d passed, %d failed%s\n' "$BOLD" "$PASS" "$FAIL" "$RESET"
[[ $FAIL -eq 0 ]]
