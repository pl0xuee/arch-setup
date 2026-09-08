# NAS first-click permissions error: handoff for the setup-script agent

The user requested that the fix applied to this PC be passed to the agent working on this project so new setups can avoid the same issue. Please integrate it into the installer using the project's existing conventions. This note does not change installer code.

## Observed problem and diagnosis

Opening Backup in the file-manager sidebar after reboot displayed:

> error 13 (Permission denied) opening credential file /etc/samba/creds-nas

After dismissing the dialog, a second click worked. The existing host fstab configured Storage, More Storage, and Backup with systemd automounting plus `x-gvfs-show`. Host checks confirmed the credentials file was correctly root:root, mode 0600. Journal entries showed a `mount.cifs` process triggering the automount, followed by a successful systemd mount. This supports a competing file-manager mount attempt failing to read the protected credentials while systemd successfully mounts the share. This was not a failed NAS login.

## Fix applied successfully on the host (2026-09-08)

1. In only the three NAS fstab entries, replace `x-gvfs-show` with `x-gvfs-hide`.
2. Preserve `x-systemd.automount`, `_netdev`, `nofail`, and the credentials and permission settings. The host also retained its existing `x-systemd.idle-timeout=60`.
3. Add normal folder bookmarks to the desktop user's `~/.config/gtk-3.0/bookmarks`, preserving existing entries:

```text
file:///mnt/Storage Storage
file:///mnt/MoreStorage More Storage
file:///mnt/Backup Backup
```

4. Run `systemctl daemon-reload` after editing fstab. The host automount units were already active; no forced unmount or reboot was needed.

The bookmarks access the folder paths directly, allowing systemd to mount as root. Hiding the device entries removes the sidebar path that initiated the competing mount attempt. Keep credentials root-owned and mode 0600.

## Installer integration points and cautions

- At handoff time, `install.sh` defines `SMB_MOUNT_OPTS` near line 219 with `x-gvfs-show` and WITHOUT `x-systemd.automount`. Include automounting when adopting the bookmark approach; hiding device entries alone does not provide on-demand mounts.
- Review `configure_network_shares` near line 2500, especially fstab creation/existing-entry handling and how mounts are activated. For a fresh setup, ensure the corresponding automount units are started after daemon-reload so bookmarks work immediately and after boot. Derive unit names safely with `systemd-escape --path --suffix=automount`.
- Make bookmark creation idempotent by URI, preserve unrelated bookmarks/custom labels, and use the actual target desktop user's home and ownership rather than root's home.
- Honor existing dry-run, skip, and credential-prompt behavior. If this installer supports upgrading existing entries, handle its own previous `x-gvfs-show` entries without duplicating fstab records or touching unrelated shares.
- Existing `x-systemd.device-timeout=10` is ignored for these CIFS network sources (confirmed by systemd journal warnings). A mount timeout is a separate decision; it was not changed as part of this host fix.

## Verification already performed on this PC

- `gio mount -li`: NAS device entries disappeared as intended.
- `gio info -a standard::type /mnt/Storage` (and MoreStorage, Backup): all succeeded.
- All three `.automount` units remained active.
- `/etc/fstab` exactly matched the prepared three-option replacement.
- Backups: `/etc/fstab.bak-nas-sidebar-20260908-114402` and `~/.config/gtk-3.0/bookmarks.bak-nas-sidebar-20260908-114409`.
- A reboot and fresh installation have NOT been tested. Validate first bookmark access after reboot or an idle unmount when testing the installer; do not force unmount shares with active work.

GNOME documents `x-gvfs-hide` here: https://github.com/GNOME/gvfs/blob/master/monitor/udisks2/what-is-shown.txt
