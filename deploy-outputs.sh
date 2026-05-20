#!/usr/bin/env bash
set -Eeuo pipefail

# =============================================================================
# deploy-outputs.sh — деплой конфигов мониторов и обоев по hostname
#
# Копирует по hostname:
#   outputs/<host>.kdl    → conf.d/60-outputs.kdl
#   wallpapers/<host>.kdl → conf.d/45-wallpaper.kdl
#
# Для wallpapers: если файл содержит placeholder пути (hardcode /home/amar),
# генерирует kdl с реальными путями текущего пользователя.
#
# Запускается автоматически из install.sh и sync.sh,
# или вручную: ./deploy-outputs.sh
# =============================================================================

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${ROOT_DIR}/config.sh"

OUTPUTS_DIR="${REPO_FILES}/home/.config/niri/outputs"
WALLPAPERS_DIR="${REPO_FILES}/home/.config/niri/wallpapers"
TARGET_DIR="${REPO_HOME}/.config/niri/conf.d"

HOST="$(hostname -s)"

mkdir -p "${TARGET_DIR}"

ok()   { printf '[OK]  %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; }

# -----------------------------------------------------------------------------
# Мониторы (60-outputs.kdl) — статический деплой из репо
# -----------------------------------------------------------------------------
if [[ -f "${OUTPUTS_DIR}/${HOST}.kdl" ]]; then
    SRC_OUT="${OUTPUTS_DIR}/${HOST}.kdl"
    echo "[*] Outputs config: ${HOST}.kdl"
else
    SRC_OUT="${OUTPUTS_DIR}/default.kdl"
    echo "[*] Outputs config: default.kdl (hostname '${HOST}' не найден)"
fi
cp -f "$SRC_OUT" "${TARGET_DIR}/60-outputs.kdl"
ok "Deployed: $(basename "$SRC_OUT") → conf.d/60-outputs.kdl"

# -----------------------------------------------------------------------------
# Обои (45-wallpaper.kdl) — генерируем с реальными путями
#
# Не копируем статический файл из репо — там могут быть старые пути.
# Читаем шаблон из wallpapers/<host>.kdl и подставляем реальные пути.
# -----------------------------------------------------------------------------
WALLPAPER_REPO_PATH="${INSTALLED_REPO_PATH}/Wallpapers"

# Функция: генерирует wallpaper kdl с реальными путями
generate_wallpaper_kdl() {
    local host="$1"
    local target="$2"

    case "$host" in
        amar224)
            cat > "$target" << EOF
// Обои для ${host} — 3 монитора (DP-2, DP-3, DP-4)
// Сгенерирован deploy-outputs.sh для пользователя ${REPO_USER}
spawn-at-startup "${REPO_HOME}/.local/bin/set-wallpapers"
EOF
            ;;
        amar319)
            cat > "$target" << EOF
// Обои для ${host} — 2 монитора (DVI-I-1, HDMI-A-1)
// Сгенерирован deploy-outputs.sh для пользователя ${REPO_USER}
spawn-at-startup "swaybg" \\
  "-o" "DVI-I-1"  "-i" "${WALLPAPER_REPO_PATH}/arch.jpeg"  "-m" "fill" \\
  "-o" "HDMI-A-1" "-i" "${WALLPAPER_REPO_PATH}/arch3.jpeg" "-m" "fill"
EOF
            ;;
        amar319-1)
            cat > "$target" << EOF
// Обои для ${host} — 1 монитор (DVI-I-2, Apple Cinema HD)
// Сгенерирован deploy-outputs.sh для пользователя ${REPO_USER}
spawn-at-startup "swaybg" "-o" "DVI-I-2" "-i" "${WALLPAPER_REPO_PATH}/wallpaper.jpg" "-m" "fill"
EOF
            ;;
        *)
            # default — один монитор без -o флага
            cat > "$target" << EOF
// Обои по умолчанию — один монитор
// Сгенерирован deploy-outputs.sh для пользователя ${REPO_USER}
spawn-at-startup "swaybg" "-i" "${WALLPAPER_REPO_PATH}/arch.jpeg" "-m" "fill"
EOF
            ;;
    esac
}

# Используем шаблон из репо для определения hostname'а, но генерируем kdl сами
if [[ -f "${WALLPAPERS_DIR}/${HOST}.kdl" ]]; then
    echo "[*] Wallpaper config: генерация для ${HOST}"
else
    echo "[*] Wallpaper config: генерация default (hostname '${HOST}' не найден)"
fi

generate_wallpaper_kdl "$HOST" "${TARGET_DIR}/45-wallpaper.kdl"
ok "Generated: wallpaper kdl → conf.d/45-wallpaper.kdl (пути: ${WALLPAPER_REPO_PATH})"

# -----------------------------------------------------------------------------
# Перезагрузка niri config если сессия активна
# -----------------------------------------------------------------------------
if command -v niri >/dev/null 2>&1 && [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
    niri msg action load-config-file 2>/dev/null \
        && ok "niri config reloaded" \
        || warn "niri reload не удался — перезайди в сессию"
else
    echo "[INFO] niri не запущен — конфиг применится при следующем входе"
fi
