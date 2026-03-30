#!/usr/bin/env bash
set -Eeuo pipefail

# =============================================================================
# update.sh — комплексное обновление системы
# Порядок: pacman → yay AUR → orphans → daemon-reload → валидация
# =============================================================================

log()  { printf '\n[%s] %s\n' "$(date +'%F %T')" "$*"; }
die()  { printf '\n[ERROR] %s\n' "$*" >&2; exit 1; }
warn() { printf '[WARN] %s\n' "$*"; }
ok()   { printf '[OK]   %s\n' "$*"; }

[[ $EUID -eq 0 ]] && die "Запускай от обычного пользователя."

command -v pacman >/dev/null 2>&1 || die "pacman не найден — это точно Arch?"
command -v yay    >/dev/null 2>&1 || die "yay не найден: make install"

# --- 1. Официальные репозитории ---
log "Обновление официальных пакетов (pacman)"
sudo pacman -Syu --noconfirm

# --- 2. AUR ---
log "Обновление AUR-пакетов (yay)"
yay -Sua --noconfirm

# --- 3. Orphan-пакеты ---
log "Проверка orphan-пакетов"
orphans=$(pacman -Qtdq 2>/dev/null || true)
if [[ -n "$orphans" ]]; then
    echo "Найдены orphan-пакеты:"
    echo "$orphans" | sed 's/^/  /'
    # shellcheck disable=SC2086  # intentional word splitting on package names
    sudo pacman -Rns --noconfirm $orphans
    ok "Orphans удалены: $(echo "$orphans" | wc -l) шт."
else
    ok "Orphan-пакеты не найдены"
fi

# --- 4. Перезагрузка user-юнитов ---
log "Перезагрузка systemd user daemon"
systemctl --user daemon-reload
ok "daemon-reload выполнен"

# --- 5. Валидация ---
log "Валидация конфигов"

if bash -n ~/.bashrc 2>/dev/null; then
    ok "bashrc синтаксис валиден"
else
    warn "bashrc: синтаксические ошибки — проверь вручную"
fi

if ssh -G github.com >/dev/null 2>&1; then
    ok "ssh config парсится"
else
    warn "ssh config: ошибки парсинга — проверь вручную"
fi

if command -v niri >/dev/null 2>&1; then
    if niri validate >/dev/null 2>&1; then
        ok "niri config валиден"
    else
        warn "niri config: ошибки — проверь: niri validate"
    fi
fi

log "Обновление завершено"
