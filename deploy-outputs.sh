#!/usr/bin/env bash
set -Eeuo pipefail

# =============================================================================
# deploy-outputs.sh — деплой конфигов мониторов и обоев по hostname
#
# Копирует по hostname:
#   outputs/<host>.kdl    → conf.d/60-outputs.kdl
#   wallpapers/<host>.kdl → conf.d/45-wallpaper.kdl
#
# Запускается автоматически из install.sh и sync.sh,
# или вручную: ./deploy-outputs.sh
#
# Файлы в outputs/:
#   amar224.kdl   — 3x 1920x1080 (DP-2, DP-3, DP-4)
#   amar319.kdl   — 2x 1920x1080 (DVI-I-1, HDMI-A-1)
#   amar319-1.kdl — 1x 2560x1600 (DVI-I-2, Apple Cinema HD)
#   default.kdl   — ноутбуки и неизвестные хосты (auto)
#
# Файлы в wallpapers/:
#   amar224.kdl   — DP-2/DP-3/DP-4 → arch.jpeg / arch3.jpeg / wallpaper.jpg
#   amar319.kdl   — DVI-I-1/HDMI-A-1
#   amar319-1.kdl — DVI-I-2
#   default.kdl   — один монитор без -o флага
# =============================================================================

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUTS_DIR="${ROOT_DIR}/files/home/.config/niri/outputs"
WALLPAPERS_DIR="${ROOT_DIR}/files/home/.config/niri/wallpapers"
TARGET_DIR="${HOME}/.config/niri/conf.d"

HOST="$(hostname -s)"

mkdir -p "${TARGET_DIR}"

# --- Мониторы (60-outputs.kdl) ---
if [[ -f "${OUTPUTS_DIR}/${HOST}.kdl" ]]; then
    SRC_OUT="${OUTPUTS_DIR}/${HOST}.kdl"
    echo "[*] Outputs config: ${HOST}.kdl"
elif [[ -f "${OUTPUTS_DIR}/${HOST}.cnf" ]]; then
    SRC_OUT="${OUTPUTS_DIR}/${HOST}.cnf"
    echo "[*] Outputs config: ${HOST}.cnf"
else
    SRC_OUT="${OUTPUTS_DIR}/default.kdl"
    echo "[*] Outputs config: default.kdl (hostname '$HOST' не найден)"
fi
cp -f "$SRC_OUT" "${TARGET_DIR}/60-outputs.kdl"
echo "[OK] Deployed: $SRC_OUT → ${TARGET_DIR}/60-outputs.kdl"

# --- Обои (45-wallpaper.kdl) ---
if [[ -f "${WALLPAPERS_DIR}/${HOST}.kdl" ]]; then
    SRC_WP="${WALLPAPERS_DIR}/${HOST}.kdl"
    echo "[*] Wallpaper config: ${HOST}.kdl"
else
    SRC_WP="${WALLPAPERS_DIR}/default.kdl"
    echo "[*] Wallpaper config: default.kdl (hostname '$HOST' не найден)"
fi
cp -f "$SRC_WP" "${TARGET_DIR}/45-wallpaper.kdl"
echo "[OK] Deployed: $SRC_WP → ${TARGET_DIR}/45-wallpaper.kdl"

# Валидация если niri доступен
if command -v niri >/dev/null 2>&1 && [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
    pkill swaybg 2>/dev/null || true
    niri msg action load-config-file 2>/dev/null \
        && echo "[OK] niri config reloaded" \
        || echo "[WARN] niri reload failed — перезайди в сессию"
else
    echo "[INFO] niri не запущен — конфиг применится при следующем входе"
fi
