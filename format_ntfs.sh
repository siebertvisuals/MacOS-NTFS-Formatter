#!/bin/bash
# Formats an external disk (e.g. exFAT) as NTFS from macOS.
# Usage: ./format_ntfs.sh [diskN] [VOLUME_NAME]
# Requires: mkntfs (ntfs-3g package), see the error message if missing.
# WARNING: ALL data on the disk is erased.

set -euo pipefail

DISK="${1:-}"
LABEL="${2:-NTFS}"

# --- 1. Is mkntfs available? --------------------------------------------------
MKNTFS="$(command -v mkntfs || true)"
for p in /opt/homebrew/sbin/mkntfs /usr/local/sbin/mkntfs /opt/homebrew/bin/mkntfs /usr/local/bin/mkntfs; do
  [ -z "$MKNTFS" ] && [ -x "$p" ] && MKNTFS="$p"
done
if [ -z "$MKNTFS" ]; then
  cat >&2 <<'MSG'
mkntfs not found. macOS cannot create NTFS volumes natively.
Install it with Homebrew:

  brew tap gromgit/homebrew-fuse
  brew install ntfs-3g-mac

(if needed, also install macFUSE: brew install --cask macfuse)
Then run this script again.
MSG
  exit 1
fi

# --- 2. Pick the disk -------------------------------------------------------
if [ -z "$DISK" ]; then
  diskutil list external physical
  echo
  read -r -p "Identifier of the disk to format (e.g. disk4): " DISK
fi
DISK="${DISK#/dev/}"

if ! [[ "$DISK" =~ ^disk[0-9]+$ ]]; then
  echo "Invalid identifier: '$DISK' (expected diskN, without the 's1')." >&2
  exit 1
fi

# --- 3. Safeguards: never an internal disk ----------------------------------
INFO="$(diskutil info "/dev/$DISK")" || { echo "Disk not found." >&2; exit 1; }
if ! echo "$INFO" | grep -qE "Device Location:\s+External|Removable Media:\s+(Removable|Yes)"; then
  echo "Refusing: /dev/$DISK is not an external disk." >&2
  exit 1
fi
if echo "$INFO" | grep -qE "Whole:\s+No"; then
  echo "Refusing: give the whole disk (e.g. disk4), not a partition." >&2
  exit 1
fi

echo
echo "=== Target disk ==="
echo "$INFO" | grep -E "Device / Media Name|Disk Size|Device Location|Protocol"
diskutil list "/dev/$DISK"
echo
echo "ALL data on /dev/$DISK will be ERASED."
read -r -p "To confirm, retype the disk identifier ($DISK): " CONFIRM
[ "$CONFIRM" = "$DISK" ] || { echo "Cancelled."; exit 1; }

# --- 4. Repartition (GPT, single partition) ---------------------------------
echo ">> Unmounting..."
diskutil unmountDisk force "/dev/$DISK"

echo ">> Creating the GPT partition table..."
# s1 = EFI, s2 = data volume ("Microsoft Basic Data" type, valid for NTFS)
diskutil partitionDisk "/dev/$DISK" 1 GPT ExFAT TMP R >/dev/null
PART="/dev/${DISK}s2"

diskutil unmount "$PART" >/dev/null 2>&1 || true

# --- 5. NTFS format -----------------------------------------------------------
echo ">> Formatting $PART as NTFS (name: $LABEL)..."
sudo "$MKNTFS" -Q -F -L "$LABEL" "$PART"

# --- 6. Done ----------------------------------------------------------------
diskutil unmountDisk "/dev/$DISK" >/dev/null 2>&1 || true
echo
echo "Done. The disk is now NTFS."
echo "Note: macOS mounts it read-only. To write to it, use ntfs-3g-mac, Paragon, Tuxera or iBoysoft."
