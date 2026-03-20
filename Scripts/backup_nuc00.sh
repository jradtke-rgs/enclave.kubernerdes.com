#!/bin/bash
set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
HOSTNAME_REQUIRED="nuc-00"
USB_UUID="49d64274-7cb0-442d-bf76-67a6cbc43566"
MOUNT_POINT="/mnt/backup-usb"
WWW_DIR="/srv/www"
SHUTDOWN_TIMEOUT=120   # seconds to wait for graceful VM shutdown
LOG_PREFIX="[backup_nuc00]"

# ── Helpers ───────────────────────────────────────────────────────────────────
log() { echo "$LOG_PREFIX $(date '+%F %T') $*"; }
die() { log "ERROR: $*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [--vms]

  --vms    Also back up libvirt VM disk images (default: skip VM backup)

Without --vms, only /srv/www is backed up.
EOF
  exit 1
}

# ── Parse arguments ───────────────────────────────────────────────────────────
BACKUP_VMS=false
for arg in "$@"; do
  case "$arg" in
    --vms) BACKUP_VMS=true ;;
    -h|--help) usage ;;
    *) die "Unknown option: $arg"; usage ;;
  esac
done

# ── 1. Ensure running on nuc-00 ───────────────────────────────────────────────
[[ "$(hostname -s)" == "$HOSTNAME_REQUIRED" ]] \
  || die "Must run on ${HOSTNAME_REQUIRED} (current host: $(hostname -s))"

[[ $EUID -eq 0 ]] || die "Must run as root"

# ── 2. Locate USB drive by UUID ───────────────────────────────────────────────
USB_DEV=$(blkid -U "$USB_UUID" 2>/dev/null) \
  || die "USB drive UUID ${USB_UUID} not found — is the drive plugged in?"

log "Found USB device: $USB_DEV"

MOUNTED_AT=$(findmnt -n -o TARGET --source "$USB_DEV" 2>/dev/null || true)
WE_MOUNTED=false

if [[ -n "$MOUNTED_AT" ]]; then
  log "USB already mounted at $MOUNTED_AT"
  MOUNT_POINT="$MOUNTED_AT"
else
  log "Mounting $USB_DEV at $MOUNT_POINT"
  mkdir -p "$MOUNT_POINT"
  mount "$USB_DEV" "$MOUNT_POINT"
  WE_MOUNTED=true
fi

cleanup() {
  if [[ "$WE_MOUNTED" == true ]]; then
    log "Unmounting $MOUNT_POINT"
    umount "$MOUNT_POINT" || log "WARNING: Failed to unmount $MOUNT_POINT"
  fi
}
trap cleanup EXIT

log "Backup destination root: $MOUNT_POINT (paths mirrored from /)"

# ── 3. Back up each VM ────────────────────────────────────────────────────────
if [[ "$BACKUP_VMS" == false ]]; then
  log "Skipping VM backup (use --vms to enable)"
else

mapfile -t VMS < <(virsh list --all --name | grep -v '^[[:space:]]*$')

if [[ ${#VMS[@]} -eq 0 ]]; then
  log "No VMs found — skipping VM backup"
else
  log "Found ${#VMS[@]} VM(s): ${VMS[*]}"

  for VM in "${VMS[@]}"; do
    log "──── VM: $VM ────────────────────────────────────"

    VM_STATE=$(virsh domstate "$VM" | tr -d '[:space:]')
    log "$VM state: $VM_STATE"

    # Shut down gracefully if running
    if [[ "$VM_STATE" == "running" ]]; then
      log "Sending shutdown to $VM"
      virsh shutdown "$VM"

      ELAPSED=0
      while [[ $ELAPSED -lt $SHUTDOWN_TIMEOUT ]]; do
        sleep 5
        ELAPSED=$((ELAPSED + 5))
        CURRENT_STATE=$(virsh domstate "$VM" | tr -d '[:space:]')
        if [[ "$CURRENT_STATE" == "shutoff" ]]; then
          log "$VM is off"
          break
        fi
        log "Waiting for $VM to shut off... (${ELAPSED}s)"
      done

      if [[ "$(virsh domstate "$VM" | tr -d '[:space:]')" != "shutoff" ]]; then
        log "WARNING: $VM did not shut down in ${SHUTDOWN_TIMEOUT}s — forcing off"
        virsh destroy "$VM"
        sleep 2
      fi
    fi

    # Copy each disk image, mirroring its absolute path under $MOUNT_POINT
    while IFS= read -r DISK_PATH; do
      [[ -z "$DISK_PATH" || "$DISK_PATH" == "-" ]] && continue
      if [[ ! -f "$DISK_PATH" ]]; then
        log "WARNING: Disk image not found: $DISK_PATH"
        continue
      fi
      DEST="${MOUNT_POINT}${DISK_PATH}"
      log "Copying $DISK_PATH → $DEST"
      rsync -ahRS --info=progress2 "$DISK_PATH" "$MOUNT_POINT/"
    done < <(virsh domblklist "$VM" --details | awk '$2=="disk" {print $4}')

    # Restart only if it was running before
    if [[ "$VM_STATE" == "running" ]]; then
      log "Starting $VM"
      virsh start "$VM"
    fi

    log "$VM backup complete"
  done
fi # inner: VMs found
fi # outer: BACKUP_VMS

# ── 4. Back up /srv/www ───────────────────────────────────────────────────────
log "Syncing $WWW_DIR → ${MOUNT_POINT}${WWW_DIR}"
rsync -ahRS --info=progress2 --delete "$WWW_DIR/" "$MOUNT_POINT/"

log "════════════════════════════════════════════════"
log "Backup complete → $MOUNT_POINT"
