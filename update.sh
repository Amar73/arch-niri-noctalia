#!/usr/bin/env bash
set -Eeuo pipefail

# =============================================================================
# update.sh — комплексное обновление системы
# Порядок: pacman → yay AUR → orphans → daemon-reload → валидация
# =============================================================================

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${ROOT_DIR}/config.sh"

log()  { printf '\n[%s] %s\n' "$(date +'%F %T')" "$*"; }
die()  { printf '\n[ERROR] %s\n' "$*" >&2; exit 1; }
warn() { printf '[WARN] %s\n' "$*"; }
ok()   { printf '[OK]   %s\n' "$*"; }

[[ $EUID -eq 0 ]] && die "Запускай от обычного пользователя."

command -v pacman >/dev/null 2>&1 || die "pacman не найден — это точно Arch?"
command -v yay    >/dev/null 2>&1 || die "yay не найден: make install"

log "Обновление официальных пакетов (pacman)"
sudo pacman -Syu --noconfirm

log "Обновление AUR-пакетов (yay)"
yay -Sua --noconfirm --answerdiff=None --answerclean=None

log "Проверка orphan-пакетов"
orphans=$(pacman -Qtdq 2>/dev/null || true)
if [[ -n "$orphans" ]]; then
    echo "Найдены orphan-пакеты:"
    echo "$orphans" | sed 's/^/  /'
    # shellcheck disable=SC2086
    sudo pacman -Rns --noconfirm $orphans
    ok "Orphans удалены: $(echo "$orphans" | wc -l) шт."
else
    ok "Orphan-пакеты не найдены"
fi

log "Перезагрузка systemd user daemon"
systemctl --user daemon-reload
ok "daemon-reload выполнен"

log "Валидация конфигов"

bash -n "${REPO_HOME}/.bashrc" 2>/dev/null \
    && ok "bashrc синтаксис валиден" \
    || warn "bashrc: синтаксические ошибки — проверь вручную"

ssh -G github.com >/dev/null 2>&1 \
    && ok "ssh config парсится" \
    || warn "ssh config: ошибки парсинга — проверь вручную"

if command -v niri >/dev/null 2>&1; then
    niri validate >/dev/null 2>&1 \
        && ok "niri config валиден" \
        || warn "niri config: ошибки — проверь: niri validate"
fi

log "Обновление завершено"
