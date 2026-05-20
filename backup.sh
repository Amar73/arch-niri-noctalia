#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${ROOT_DIR}/config.sh"

STAMP="$(date +%F-%H%M%S)"
BACKUP_DIR="${REPO_HOME}/backup/niri-waybar-${STAMP}"

mkdir -p "${BACKUP_DIR}/etc/greetd"
mkdir -p "${BACKUP_DIR}/home/.ssh"

echo "[*] Backup /etc/greetd"
sudo rsync -a /etc/greetd/ "${BACKUP_DIR}/etc/greetd/"

echo "[*] Backup ~/.config (только управляемые директории)"
# Бэкапим только то, что мы синхронизируем — не весь ~/.config/
for dir in niri waybar alacritty swaylock mako fuzzel mc qt6ct gtk-3.0 gtk-4.0 systemd; do
    if [[ -d "${REPO_HOME}/.config/${dir}" ]]; then
        mkdir -p "${BACKUP_DIR}/home/.config/${dir}"
        rsync -a "${REPO_HOME}/.config/${dir}/" "${BACKUP_DIR}/home/.config/${dir}/"
    fi
done

if [[ -f "${REPO_HOME}/.bashrc" ]]; then
    echo "[*] Backup ~/.bashrc"
    cp -a "${REPO_HOME}/.bashrc" "${BACKUP_DIR}/home/.bashrc"
fi

if [[ -f "${REPO_HOME}/.ssh/config" ]]; then
    echo "[*] Backup ~/.ssh/config"
    cp -a "${REPO_HOME}/.ssh/config" "${BACKUP_DIR}/home/.ssh/config"
fi

echo "[OK] Backup saved to: ${BACKUP_DIR}"
