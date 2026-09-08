# Arch post-install setup

Runs on **CachyOS (KDE Plasma)** and on **Omarchy (Arch + Hyprland)** — two
Arch-based boxes with very different desktops. The desktop is detected, and the
steps that only exist on one of them are skipped on the other — see
[Two desktops](#two-desktops).

On a fresh box, log into the desktop once, then:

```bash
curl -fsSL https://raw.githubusercontent.com/pl0xuee/arch-setup/master/bootstrap.sh | bash
```

Safe to re-run — a second run is a no-op.

```bash
./install.sh --dry-run             # show what it would do, change nothing
./install.sh --only config         # just the desktop/Brave config
./install.sh --only omarchy        # just the Omarchy bar, theme and Hyprland rules
./install.sh --desktop omarchy     # force the desktop instead of detecting it
./tests/run.sh                     # 300+ tests, no VM needed
```

**On KDE, log in once before running it.** Plasma doesn't write its panel config
until first login, so the taskbar step has nothing to configure before then.
Omarchy has no such step and no such requirement.

**Close Brave and KeePassXC first.** Both rewrite their own config on exit and
will silently undo the changes.

## Two desktops

The desktop is detected and printed before anything is installed:

- **Which desktop?** — the running session decides whenever there is one:
  `XDG_CURRENT_DESKTOP` says what is on screen, where the installed markers are
  all true at once on a box carrying both. A Hyprland session counts as Omarchy
  only if Omarchy is also installed, since Omarchy sets nothing more specific
  than `Hyprland`; any other session is `other`, however much of KDE or Omarchy
  is sitting on the disk. Only with no session environment at all — an SSH
  command, a TTY — does it fall back to what's installed: Omarchy's path
  (`/usr/share/omarchy`), then `plasmashell`. Override it with
  `--desktop kde|omarchy|other`.

What that changes:

| | KDE Plasma | Omarchy |
|---|---|---|
| Apps, AppImages, Flatpaks, PATH, LACT, power profile | ✅ | ✅ |
| Brave policy, filter lists, KeePassXC integration | ✅ | ✅ |
| Taskbar launchers, panel height, tray | ✅ | skipped — omarchy-shell has no pinned launchers |
| Powerdevil idle settings | ✅ | skipped — Omarchy idles through its own shell |
| `kscreen`, `qt6-imageformats` | ✅ | skipped — Plasma-only |
| Bar, theme, wallpaper, Hyprland rules, monitors | skipped — no omarchy-shell | ✅ — see [The Omarchy desktop](#the-omarchy-desktop) |
| Brave Origin and Vesktop from `packages/aur.txt` | ✅ — yay or paru | ✅ — yay or paru |

Nothing here fails the run. A skipped step says why, and the summary at the end
lists what was left out.

### Package sources

The script uses the existing pacman repositories for `packages/pacman.txt` and
an installed **yay or paru** for `packages/aur.txt`. The AUR lookup is explicit
(`--aur`), so Brave Origin and Vesktop are not selected from a binary repository.
Brave Origin uses [Brave's AUR package](https://brave.com/origin/linux/), and
Vesktop uses the [upstream-recommended `vesktop-bin`](https://vesktop.dev/install/linux/).
If neither helper is installed, the packages step stops before changing anything
and explains what is missing. Both apps remain part of `--only packages`.

No CachyOS repository, signing key, mirrorlist, gaming bundles, Proton/Wine
runners, ProtonUp-Qt, or extra gaming drivers are added. Gaming packages are
left to the distro defaults, including Omarchy's defaults on Omarchy.
Existing repositories and installed packages are not removed or migrated by
this script. A machine configured by an older version keeps that configuration
until it is changed separately.

## The Omarchy desktop

The `omarchy` step configures the Hyprland desktop the way the taskbar step
configures Plasma's: skipped with a reason anywhere else, and idempotent piece
by piece. What it sets:

| | |
|---|---|
| **Shell text size** | `[font] base-size` in `~/.config/omarchy/shell.toml` — 16px against Omarchy's 12, and the bar's height scales from it. Written directly rather than through `omarchy display text size`, which would drag GTK's text scaling and every terminal font along with it. |
| **Bar layout** | Clock format, plus Dropbox and hyprmoncfg in the right section. `shell.json` is edited, never overwritten, so widgets you drag around the bar afterwards survive a re-run. |
| **One bar, one monitor** | Stock Omarchy puts a bar on every screen — `Variants { model: Quickshell.screens }`, with no option to narrow it. The patched clone reads `bar.monitors` from shell.json, so the bar lands on the ultrawide alone. A name that matches nothing falls back to every screen, so a box with different displays gets a bar rather than none. |
| **Island bar** | `omarchy.bar` cloned to `<user>.bar` and patched: the panel surface goes transparent and each of the three sections paints its own rounded slab, so the bar reads as three islands instead of one edge-to-edge strip. |
| **Tray drawer** | `omarchy.tray` cloned to `<user>.tray` and patched so the collapsed drawer stops holding width open for its hidden icons — otherwise the right island always carries a blank tail. |
| **Theme and wallpaper** | The `nebula` theme — vendored in `omarchy/themes/nebula/`, not one of Omarchy's — installed into `~/.config/omarchy/themes/` and then applied, with its wallpaper selected. Its palette is sampled off that wallpaper, and it carries its own `hyprland.lua`, so windows get 14px rounded corners and a cyan-to-coral gradient border. Any wallpapers in `omarchy/backgrounds/<theme>/` are installed alongside. |
| **Hyprland** | Window rules (Steam tiles, StreamHub stays opaque), background blur so the transparent terminal reads over a busy wallpaper — Omarchy ships blur off — the session PATH fix that keeps `~/.local/bin` ahead of `/usr/bin`, flat mouse acceleration, and this machine's monitor layout. |
| **X11 app scale** | `GDK_SCALE=1`, over the 2 Omarchy sets for the HiDPI laptop its default is written for. The variable reaches XWayland clients only — Wayland apps take their scale from the compositor — and at 2 every X11 client drew at twice the size it asked for, the Tauri AppImages above worst of all, since their packaging forces them onto X11. Exact on a monitor at scale 1 and 20% small on one at 1.25; GTK on X11 has no fractional step in between. Pushed into the running session as well as the config, so it applies without a re-login. |
| **Terminal** | foot's font size, and its background transparency — `alpha` in `[colors-dark]`, upserted after the `[main]` include so it wins over the palette the theme generates. Only the background goes translucent; text and the 16-colour palette stay opaque, which is what foot's alpha does and Hyprland window opacity does not. Applies to new windows: foot re-reads its config only on open. |
| **Agent** | Omarchy's default agent, so its first-update invitation never fires. |

All of it is variables at the top of `install.sh` — theme, background, font
sizes, clock format, the widget list, the plugin URLs.

Your own `~/.config/hypr/*.lua` are never rewritten. The window rules live in a
file this repo owns (`hypr/arch-setup.lua`), and hyprland.lua gets one `dofile`
line pointing at it, added only if it isn't already there.

### Patching Omarchy's own code

The bar and the tray are Omarchy's, and `/usr/share/omarchy` is overwritten by
`omarchy update`. So both are cloned into `~/.config/omarchy/plugins/` — what
`omarchy plugin clone` is for — and the clone is patched with the diffs in
`omarchy/patches/`.

A patch is applied to a temporary copy and published only after every hunk
succeeds. A patch that no longer applies is a **warning, never a failure**: Omarchy ships
new shell code on its own schedule, and a bar that comes back stock is a far
better outcome than a run that dies, or a half-patched QML file that stops the
shell from starting at all. The sha256 of each upstream file the patches were
made against is recorded in `install.sh`, so drift says so in the run log, and
`./tests/run.sh` checks the patches still apply to the installed Omarchy — which
is the earlier warning.

One of them also carries a workaround for an upstream bug: a cloned `bar`-kind
plugin cannot load at all, because `Bar.qml` declares required properties that
the host's `source:`-based Loader can't set
([#6915](https://github.com/basecamp/omarchy/issues/6915)). Without it, cloning
the bar leaves you with no bar and no error.

## Network shares

SMB/CIFS shares mount on demand through systemd, with folder bookmarks in the
file-manager sidebar. None of the server details are in this repo.
A server address, a login name and a list of share names are facts about one
house — the repo carries the mechanism, the machine carries the values.

The first run with a terminal attached asks for the server, username and
password, lists the shares it can see, and writes two files:

| File | Holds | Mode |
|---|---|---|
| `~/.config/arch-setup/smb.conf` | host, user, and `share -> mount point` list | `0600`, yours |
| `/etc/samba/creds-nas` | username and password | `0600`, root's |

Neither is in the repo, and the password is in neither the config nor
`/etc/fstab` — that gets `credentials=` pointing at the root-only file, because
`/etc/fstab` is world-readable. Every run after the first reads `smb.conf` and
asks nothing.

Shares whose names end in `$` are skipped: `ADMIN$`, `IPC$`, `C$` and the rest
are the administrative shares every Windows box exports, not the ones anyone
means. Mount points are `/mnt/<share name with spaces removed>`; a space in the
share name itself becomes `\040` in `fstab`, which is the only place it is
allowed to appear.

New entries use `x-systemd.automount`, `x-systemd.idle-timeout=60`, `_netdev`,
`nofail`, and `x-gvfs-hide`. The installer reloads systemd and starts each
`.automount` unit so the bookmarks work immediately and after boot. Opening a
bookmark accesses the folder directly and lets systemd mount as root. Hiding
the device entry prevents the competing file-manager mount attempt described
in [NAS-MOUNT-HANDOFF.md](NAS-MOUNT-HANDOFF.md). Credentials remain root-owned
and mode `0600`; no active share is forcibly unmounted.

Bookmarks are added to the desktop user's `~/.config/gtk-3.0/bookmarks` by URI,
preserving custom labels and unrelated entries. Reruns migrate matching older
fstab entries only when their source, mount point and credentials path match.
They replace `x-gvfs-show`, add automounting, and preserve existing permission,
protocol and idle-timeout settings. The ignored CIFS `device-timeout` option is
removed; no mount timeout is imposed. Changed files are backed up first.

Edit `smb.conf` to add shares. Removing or changing an existing share also
requires removing its old fstab entry and bookmark separately; the installer
does not remove unrelated entries. Delete `smb.conf` to be asked again.

## What goes where

| File | |
|---|---|
| `packages/pacman.txt` | repo packages that exist on CachyOS *and* Arch |
| `packages/aur.txt` | Brave Origin and Vesktop, installed explicitly from the AUR |
| `packages/pacman-kde.txt` | packages only worth having on Plasma |
| `packages/flatpak.txt` | Dropbox |
| `packages/taskbar.txt` | pinned launchers, in order (KDE only) |
| `packages/brave-extensions.txt` | extensions to auto-install |
| `omarchy/patches/` | diffs applied to the cloned Omarchy bar and tray plugins |
| `omarchy/hypr/` | window rules, input and monitor layout, installed into `~/.config/hypr/` |
| `omarchy/themes/<theme>/` | custom themes installed into `~/.config/omarchy/themes/`, applied by name |
| `omarchy/backgrounds/<theme>/` | extra wallpapers installed into that theme's user folder |
| `~/.config/arch-setup/smb.conf` | network share settings — **outside the repo**, written on first run |
| `install.sh` | panel height, tray, homepage, power profile, every Omarchy setting — as variables at the top |
