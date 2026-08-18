# CachyOS post-install setup

Runs on **CachyOS (KDE Plasma)** and on **Omarchy (Arch + Hyprland)**. The
desktop is detected, and the steps that only exist on one of them are skipped on
the other — see [Two desktops](#two-desktops).

On a fresh box, log into the desktop once, then:

```bash
curl -fsSL https://raw.githubusercontent.com/pl0xuee/cachyos-setup/master/bootstrap.sh | bash
```

Safe to re-run — a second run is a no-op.

```bash
./install.sh --dry-run             # show what it would do, change nothing
./install.sh --only config         # just the desktop/Brave config
./install.sh --desktop omarchy     # force the desktop instead of detecting it
./tests/run.sh                     # 288 tests, no VM needed
```

**On KDE, log in once before running it.** Plasma doesn't write its panel config
until first login, so the taskbar step has nothing to configure before then.
Omarchy has no such step and no such requirement.

**Close Brave and KeePassXC first.** Both rewrite their own config on exit and
will silently undo the changes.

## Two desktops

Two separate questions get asked at the start of the run, and both are printed
before anything is installed:

- **Which desktop?** — decided by the running session (`XDG_CURRENT_DESKTOP`)
  first, then by Omarchy's install path (`/usr/share/omarchy`), then by whether
  `plasmashell` is installed. Override it with `--desktop kde|omarchy|other`.
- **Are the CachyOS repos enabled?** — asked separately, via `pacman-conf`,
  because CachyOS-with-something-else and Arch-with-the-CachyOS-repos-added are
  both real machines. If they aren't, the signed `[cachyos]` repo is added so
  the CachyOS-only packages install anyway. No AUR helper is used.

What that changes:

| | KDE Plasma | Omarchy |
|---|---|---|
| Apps, AppImages, Flatpaks, PATH, LACT, power profile | ✅ | ✅ |
| Brave policy, filter lists, KeePassXC integration | ✅ | ✅ |
| Taskbar launchers, panel height, tray | ✅ | skipped — Waybar has no pinned launchers |
| Powerdevil idle settings | ✅ | skipped — Omarchy idles through `hypridle` |
| `kscreen`, `qt6-imageformats` | ✅ | skipped — Plasma-only |
| Everything in `packages/pacman-cachyos.txt` | ✅ | ✅ — the `[cachyos]` repo is added first (see below) |

Nothing here fails the run. A skipped step says why, and the summary at the end
lists what was left out.

### Adding the CachyOS repo

On a box without it, `[cachyos]` is **appended** to `/etc/pacman.conf` — landing
below `core`/`extra`/`multilib` — after CachyOS's signing key
(`F3B607488DB35A47`) is imported and locally signed. `multilib` is enabled too,
since Steam and the `lib32-*` packages live there. The original `pacman.conf` is
saved to `pacman.conf.before-cachyos-setup`.

The ordering is the whole point, and it is deliberately **not** what CachyOS's
own `cachyos-repo.sh` does — that inserts `[cachyos]` *above* the Arch repos.
The plain `cachyos` repo shares 90 package names with Arch's, among them
`pacman`, `mesa`, `linux-firmware`, `mkinitcpio`, `sddm`, `xz` and `zstd`.
Ordered first, the next `pacman -Syu` — which `omarchy-update` runs on its own —
would start replacing Omarchy's base system with CachyOS builds. Ordered last,
pacman takes every one of those names from Arch, and the only packages that come
from CachyOS are the ones Arch doesn't carry at all.

To undo it: delete the `[cachyos]` section from `/etc/pacman.conf`, then
`sudo pacman -R cachyos-keyring cachyos-mirrorlist` and
`sudo pacman-key --delete F3B607488DB35A47`.

## What goes where

| File | |
|---|---|
| `packages/pacman.txt` | repo packages that exist on CachyOS *and* Arch |
| `packages/pacman-cachyos.txt` | packages only in the CachyOS repos (the repo is added if missing) |
| `packages/pacman-kde.txt` | packages only worth having on Plasma |
| `packages/flatpak.txt` | Dropbox |
| `packages/taskbar.txt` | pinned launchers, in order (KDE only) |
| `packages/brave-extensions.txt` | extensions to auto-install |
| `install.sh` | panel height, tray, homepage, power profile — as variables at the top |
