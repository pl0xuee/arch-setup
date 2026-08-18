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
./tests/run.sh                     # 281 tests, no VM needed
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
  both real machines.

What that changes:

| | KDE Plasma | Omarchy |
|---|---|---|
| Apps, AppImages, Flatpaks, PATH, LACT, power profile | ✅ | ✅ |
| Brave policy, filter lists, KeePassXC integration | ✅ | ✅ |
| Taskbar launchers, panel height, tray | ✅ | skipped — Waybar has no pinned launchers |
| Powerdevil idle settings | ✅ | skipped — Omarchy idles through `hypridle` |
| `kscreen`, `qt6-imageformats` | ✅ | skipped — Plasma-only |
| `brave-origin-bin`, `vesktop`, `protonup-qt` | from the CachyOS repos | built from the AUR (`yay`/`paru`) |
| `cachyos-gaming-meta`, `cachyos-gaming-applications` | ✅ | no equivalent anywhere — install Steam by hand |

Nothing here fails the run. A skipped step says why, and the summary at the end
lists what was left out.

## What goes where

| File | |
|---|---|
| `packages/pacman.txt` | repo packages that exist on CachyOS *and* Arch |
| `packages/pacman-cachyos.txt` | packages only in the CachyOS repos |
| `packages/pacman-kde.txt` | packages only worth having on Plasma |
| `packages/aur.txt` | AUR substitutes, used when the CachyOS repos are absent |
| `packages/flatpak.txt` | Dropbox |
| `packages/taskbar.txt` | pinned launchers, in order (KDE only) |
| `packages/brave-extensions.txt` | extensions to auto-install |
| `install.sh` | panel height, tray, homepage, power profile — as variables at the top |
