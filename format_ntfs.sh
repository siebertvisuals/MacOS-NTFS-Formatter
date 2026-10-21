#!/bin/bash
# Formate un disque externe (ex. exFAT) en NTFS depuis macOS.
# Usage : ./format_ntfs.sh [disqueN] [NOM_DU_VOLUME]
# Prérequis : mkntfs (paquet ntfs-3g), voir le message d'erreur si absent.
# ATTENTION : TOUTES les données du disque sont effacées.

set -euo pipefail

DISK="${1:-}"
LABEL="${2:-NTFS}"

# --- 1. mkntfs disponible ? -------------------------------------------------
MKNTFS="$(command -v mkntfs || true)"
for p in /opt/homebrew/sbin/mkntfs /usr/local/sbin/mkntfs /opt/homebrew/bin/mkntfs /usr/local/bin/mkntfs; do
  [ -z "$MKNTFS" ] && [ -x "$p" ] && MKNTFS="$p"
done
if [ -z "$MKNTFS" ]; then
  cat >&2 <<'EOF'
mkntfs est introuvable. macOS ne sait pas créer de NTFS nativement.
Installe-le avec Homebrew :

  brew tap gromgit/homebrew-fuse
  brew install ntfs-3g-mac

(si besoin, installe aussi macFUSE : brew install --cask macfuse)
Puis relance ce script.
EOF
  exit 1
fi

# --- 2. Choix du disque -----------------------------------------------------
if [ -z "$DISK" ]; then
  diskutil list external physical
  echo
  read -r -p "Identifiant du disque à formater (ex. disk4) : " DISK
fi
DISK="${DISK#/dev/}"

if ! [[ "$DISK" =~ ^disk[0-9]+$ ]]; then
  echo "Identifiant invalide : '$DISK' (attendu : diskN, sans le 's1')." >&2
  exit 1
fi

# --- 3. Garde-fous : jamais un disque interne -------------------------------
INFO="$(diskutil info "/dev/$DISK")" || { echo "Disque introuvable." >&2; exit 1; }
if ! echo "$INFO" | grep -qE "Device Location:\s+External|Removable Media:\s+(Removable|Yes)"; then
  echo "Refus : /dev/$DISK n'est pas un disque externe." >&2
  exit 1
fi
if echo "$INFO" | grep -qE "Whole:\s+No"; then
  echo "Refus : donne le disque entier (ex. disk4), pas une partition." >&2
  exit 1
fi

echo
echo "=== Disque ciblé ==="
echo "$INFO" | grep -E "Device / Media Name|Disk Size|Device Location|Protocol"
diskutil list "/dev/$DISK"
echo
echo "TOUTES les données de /dev/$DISK seront EFFACÉES."
read -r -p "Pour confirmer, retape l'identifiant du disque ($DISK) : " CONFIRM
[ "$CONFIRM" = "$DISK" ] || { echo "Annulé."; exit 1; }

# --- 4. Repartitionnement (GPT, une seule partition) -------------------------
echo ">> Démontage..."
diskutil unmountDisk force "/dev/$DISK"

echo ">> Création de la table de partitions GPT..."
# s1 = EFI, s2 = volume de données (type "Microsoft Basic Data", valable pour NTFS)
diskutil partitionDisk "/dev/$DISK" 1 GPT ExFAT TMP R >/dev/null
PART="/dev/${DISK}s2"

diskutil unmount "$PART" >/dev/null 2>&1 || true

# --- 5. Formatage NTFS --------------------------------------------------------
echo ">> Formatage NTFS de $PART (nom : $LABEL)..."
sudo "$MKNTFS" -Q -F -L "$LABEL" "$PART"

# --- 6. Fin ----------------------------------------------------------------
diskutil unmountDisk "/dev/$DISK" >/dev/null 2>&1 || true
echo
echo "Terminé. Le disque est en NTFS."
echo "Note : macOS le monte en lecture seule. Pour écrire dessus, utilise ntfs-3g-mac, Paragon, Tuxera ou iBoysoft."
