#!/bin/bash
# Shared helpers for ios-backup, ios-sync-photos, ios-sync.
# Sourced — do not execute directly.

set -u

IOSSYNC_ENV="${IOSSYNC_ENV:-/etc/iossync/iossync.env}"
IOSSYNC_DEVICES="${IOSSYNC_DEVICES:-/etc/iossync/devices.conf}"

# shellcheck disable=SC1090
[[ -r "$IOSSYNC_ENV" ]] && source "$IOSSYNC_ENV"

: "${IOSSYNC_NFS_MOUNTPOINT:?IOSSYNC_NFS_MOUNTPOINT not set — is /etc/iossync/iossync.env present?}"
: "${IOSSYNC_NFS_IPHONE_SUBDIR:?IOSSYNC_NFS_IPHONE_SUBDIR not set — is /etc/iossync/iossync.env present?}"

_log()  { printf '[iossync] %s\n' "$*" >&2; }
_warn() { printf '[iossync] WARN: %s\n' "$*" >&2; }
_die()  { printf '[iossync] ERROR: %s\n' "$*" >&2; exit "${2:-1}"; }

_nfs_is_mounted() { mountpoint -q "$IOSSYNC_NFS_MOUNTPOINT"; }

# Mount NFS if not already mounted. Sets _IOSSYNC_WE_MOUNTED=1 if WE did it.
# Pair with _nfs_maybe_unmount in a trap.
_IOSSYNC_WE_MOUNTED=0
_nfs_ensure_mounted() {
    if _nfs_is_mounted; then
        _log "NFS already mounted at $IOSSYNC_NFS_MOUNTPOINT"
        return 0
    fi
    _log "Mounting NFS at $IOSSYNC_NFS_MOUNTPOINT"
    mount "$IOSSYNC_NFS_MOUNTPOINT" \
        || _die "mount $IOSSYNC_NFS_MOUNTPOINT failed (fstab entry present? noauto+user?)" 2
    _IOSSYNC_WE_MOUNTED=1
}

_nfs_maybe_unmount() {
    [[ "$_IOSSYNC_WE_MOUNTED" -eq 1 ]] || return 0
    _log "Unmounting NFS (we mounted it, so we clean up)"
    umount "$IOSSYNC_NFS_MOUNTPOINT" || _warn "umount failed (in use?)"
}

# Lookup UDID -> "Owner/Model" via grep. Empty + nonzero rc if not found.
_lookup_device() {
    local udid="$1"
    grep -E "^${udid}=" "$IOSSYNC_DEVICES" 2>/dev/null \
        | head -n1 | cut -d= -f2- | tr -d '"' | tr -d "'"
}

# Confirm a device is attached and paired. Echo UDID on stdout.
_require_device() {
    local udid
    udid="$(idevice_id -l 2>/dev/null | head -n1)" || true
    [[ -n "${udid:-}" ]] || _die "No iOS device connected (idevice_id -l empty)" 3
    ideviceinfo -u "$udid" -k DeviceName >/dev/null 2>&1 \
        || _die "Device $udid not paired/trusted — tap 'Trust' on the iPhone and retry" 4
    printf '%s\n' "$udid"
}

# Resolve UDID -> "Owner/Model" subdir. If unknown, print guidance and exit 5.
_require_known_device() {
    local udid="$1" mapping name
    mapping="$(_lookup_device "$udid")"
    if [[ -z "$mapping" ]]; then
        name="$(ideviceinfo -u "$udid" -k DeviceName 2>/dev/null || echo '?')"
        _warn "Unknown device — not in $IOSSYNC_DEVICES"
        _warn "  UDID:       $udid"
        _warn "  DeviceName: $name"
        _warn "Add a line to $IOSSYNC_DEVICES, e.g.:"
        _warn "  ${udid}=Owner/Model"
        exit 5
    fi
    printf '%s\n' "$mapping"
}
