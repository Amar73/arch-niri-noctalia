#!/usr/bin/env bash
set -Eeuo pipefail

# =============================================================================
# install-packages.sh — установка пакетов из списков в packages/
#
# Использование:
#   ./install-packages.sh          # base + niri + aur
#   ./install-packages.sh base     # только base
#   ./install-packages.sh base niri  # base + niri
# =============================================================================

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="${ROOT_DIR}/packages"

log()  { printf '\n[%s] %s\n' "$(date +'%F %T')" "$*"; }
die()  { printf '\n[ERROR] %s\n' "$*" >&2; exit 1; }
ok()   { printf '[OK]   %s\n' "$*"; }

command -v pacman >/dev/null 2>&1 || die "pacman не найден"
command -v yay    >/dev/null 2>&1 || die "yay не найден — сначала make install"

# Читает файл пакетов: убирает комментарии и пустые строки
read_pkgs() {
    local file="$1"
    [[ -f "$file" ]] || { echo ""; return; }
    grep -v '^#' "$file" | grep -v '^$' | sed 's/#.*//' | tr -s ' \t' '\n' | grep -v '^$' | tr '\n' ' '
}

# Определяем какие файлы устанавливать
if [[ $# -eq 0 ]]; then
    LISTS="base niri aur"
else
    LISTS="$*"
fi

for list in $LISTS; do
    file="${PKG_DIR}/${list}.txt"
    [[ -f "$file" ]] || { echo "[WARN] Файл не найден: $file"; continue; }

    pkgs=$(read_pkgs "$file")
    [[ -z "$pkgs" ]] && { echo "[WARN] Пустой список: $file"; continue; }

    log "Установка: $list"

    if [[ "$list" == "aur" ]]; then
        # shellcheck disable=SC2086
        yay -S --needed --noconfirm $pkgs
    else
        # shellcheck disable=SC2086
        sudo pacman -S --needed --noconfirm $pkgs
    fi

    ok "$list — готово"
done

log "Все пакеты установлены"
