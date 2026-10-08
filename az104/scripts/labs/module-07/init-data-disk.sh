#!/usr/bin/env bash
# init-data-disk.sh — exécuté DANS la VM (run-command, root) : disque de données du LUN 0
# Partitionne (GPT), formate (ext4, étiquette arveo-data) et monte sur /srv/arveo.
# Montage par étiquette + option nofail : la VM démarre même si le disque est détaché.
# Idempotent : disque déjà formaté ou déjà monté conservé.
# Usage (Cloud Shell) : vmrun web01 "$(cat scripts/labs/module-07/init-data-disk.sh)"
set -euo pipefail

DISK=/dev/disk/azure/scsi1/lun0     # lien stable créé par les règles udev de l'agent Azure
MOUNT=/srv/arveo
LABEL=arveo-data

[[ -e "$DISK" ]] || { echo "Aucun disque de données au LUN 0"; exit 1; }

if ! blkid -L "$LABEL" >/dev/null 2>&1; then
  parted "$DISK" --script mklabel gpt mkpart "$LABEL" ext4 0% 100%
  partprobe "$DISK"
  udevadm settle
  mkfs.ext4 -q -L "$LABEL" "${DISK}-part1"
fi

mkdir -p "$MOUNT"
grep -q "LABEL=${LABEL}" /etc/fstab \
  || echo "LABEL=${LABEL} ${MOUNT} ext4 defaults,nofail 0 2" >> /etc/fstab
mountpoint -q "$MOUNT" || mount "$MOUNT"
df -h --output=source,size,target "$MOUNT" | tail -n 1
