# Amun iOSsync

**amun-iossync** is a plugin for [amun](https://github.com/GonzaloAlvarez/amun) that turns a Debian host into a one-command iPhone backup machine.

It compiles the full [libimobiledevice](https://libimobiledevice.org/) stack from source (`libplist` → `libimobiledevice-glue` → `libusbmuxd` → `libimobiledevice` → `usbmuxd` → `ifuse`), wires up the NFS mount used to store backups, and installs three executable scripts that replace the manual backup checklist with a single command.

Designed for **vostro.lan** (Dell Vostro 3360, Debian 12 bookworm) — the homelab's iPhone backup host. The NFS target lives on `raidnas.lan:/volume1/data` ([[project_raidnas]]).

---

## Usage

Run the iossync plugin through amun on the target host:

```bash
amun iossync
```

Or from a control host via amun's `deploy` wrapper:

```bash
cd ~/dev/amun
./deploy <host> -P iossync -u <user> -i ~/.ssh/<key>
```

Then, with an iPhone plugged in:

```bash
ios-sync                  # both: full backup + photo rsync
ios-backup                # just the encrypted device backup
ios-sync-photos           # just the DCIM rsync via ifuse
ios-sync --snapshot-photos    # photos plus a dated DCIM-DDMMYYYY snapshot
```

## What it does

1. Installs Debian build deps and runtime deps (`nfs-common`, `rsync`, `fuse3`).
2. Compiles + installs each library in order under `/usr/local/`, idempotently — skips any library whose binary AND `pkg-config` registration already match.
3. Verifies the `usbmux` system user (created by upstream `usbmuxd make install`) and adds the target user to the `fuse` + `plugdev` groups.
4. Enables and starts `usbmuxd.service`.
5. Writes a canonical NFSv3 fstab entry (`raidnas.lan:/volume1/data → /home/<user>/nfs`, `noauto,user`). Does NOT mount during the role run — scripts mount on demand.
6. Renders `/etc/iossync/devices.conf` (UDID → Owner/Model mapping) and `/etc/iossync/iossync.env` (mount paths consumed by the scripts).
7. Installs `ios-backup`, `ios-sync-photos`, `ios-sync` to `/usr/local/bin/` and the shared helper library to `/usr/local/lib/iossync-common.sh`.

## Variables

| Var | Default | What |
|---|---|---|
| `iossync_user` | `gonzalo` | Target user, added to `fuse`+`plugdev`. Must already exist. |
| `iossync_build_dir` | `/usr/local/src` | Where libimobiledevice sources are checked out. |
| `iossync_force_rebuild` | `false` | Set `true` to rebuild every library regardless of idempotence guard. |
| `iossync_skip_build` | `false` | Set `true` to skip compilation (molecule uses this). |
| `iossync_manage_fstab` | `true` | Set `false` to skip the fstab entry (molecule uses this). |
| `iossync_nfs_server` | `raidnas.lan` | NFS server hostname. |
| `iossync_nfs_export` | `/volume1/data` | NFS export path. |
| `iossync_nfs_mountpoint` | `/home/{{ iossync_user }}/nfs` | Local mountpoint. |
| `iossync_nfs_iphone_subdir` | `iPhone` | Subdir under the mount where backups live. |
| `iossync_nfs_opts` | `nfsvers=3,user,noauto,relatime,rw,hard,intr,rsize=8192,wsize=8192` | fstab options. |
| `iossync_libraries` | (6-item ordered list) | The compilation order. Don't reorder. |
| `iossync_known_devices` | (seeded with 2 UDIDs) | Initial `devices.conf` content. |

## Device mapping

`/etc/iossync/devices.conf` is a plain `UDID=Owner/Model` file:

```
00008101-000A51942109001E=Gonzalo/iPhone12
00008110-0004184A0C90401E=Alicia/XR
```

When an unknown iPhone is plugged in, the scripts exit with code 5 and print the UDID + `DeviceName` plus the line to add. Edit the file by hand — it's intentionally not a YAML file so scripts can `grep` it without extra deps.

## Notes & gotchas

- **fstab change.** On a host already using the older `nfs4 vers=3` fstab entry (the historic vostro setup), the first `amun iossync` run rewrites the line to canonical `nfs nfsvers=3`. Run `sudo umount /home/<user>/nfs && mount nfs` once afterwards so the mount picks up the new options.
- **`idevicebackup2 -i encryption on` is interactive** the first time — it prompts for a password. The scripts are designed for interactive use; do not put them in cron.
- **`fuse` group changes require re-login.** If you're adding a fresh user, log out / log back in before running `ios-sync-photos`, otherwise `ifuse` will fail with EPERM.
- **Builds track upstream `master`.** libimobiledevice rarely tags releases. If a build fails because upstream regressed, set `iossync_force_rebuild: false` and pin known-good SHAs by adding `commit:` entries to `iossync_libraries`.

## Supported Platforms

| Platform | Method |
|----------|--------|
| Debian 12 (Bookworm) | apt build deps + compile-from-source |

macOS / Ubuntu / Arch are not supported — Apple ships its own backup tooling on macOS, and the role's libimobiledevice build chain is Debian-specific.

## Testing

```bash
./molecule    # role-level test in a Debian-12 Docker container (skips the actual compile)
./test debian # full VM-based end-to-end test via amun/test
```

The molecule scenario verifies file layout, idempotence, group membership, and `bash -n` syntax on every shipped script. It does NOT compile libimobiledevice (too slow for CI) nor exercise an iPhone (no USB in containers). Real verification happens on vostro after the first deploy.

## License

GNU GENERAL PUBLIC LICENSE
Version 3, 29 June 2007

Copyright (c) 2026 Gonzalo Alvarez
