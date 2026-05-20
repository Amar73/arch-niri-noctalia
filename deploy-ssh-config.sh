#!/usr/bin/env bash
set -Eeuo pipefail

# =============================================================================
# deploy-ssh-config.sh — деплой ~/.ssh/config в зависимости от контекста
#
# Определяет где запускается:
#   - amar224 (jump-хост) — подключение к wn75 напрямую, без ProxyJump
#   - другие машины в домашней сети (amar319, amar319-1, ноутбуки)
#     — через ProxyJump amar224
#   - внешние машины — конфиг не трогается
#
# Запуск:
#   ./deploy-ssh-config.sh            # автоопределение
#   ./deploy-ssh-config.sh --dry-run  # показать что будет задеплоено
# =============================================================================

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${ROOT_DIR}/config.sh"

SSH_DIR="${REPO_HOME}/.ssh"
SSH_CONFIG="${SSH_DIR}/config"

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

log()  { printf '[%s] %s\n' "$(date +'%T')" "$*"; }
ok()   { printf '[OK]  %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; }

# -----------------------------------------------------------------------------
# Определение контекста
# -----------------------------------------------------------------------------
detect_context() {
    local hostname; hostname="$(hostname -s)"
    if [[ "$hostname" == "amar224" ]]; then
        echo "jump_host"; return
    fi
    if [[ "$hostname" =~ ^amar ]]; then
        echo "home_net"; return
    fi
    echo "external"
}

CONTEXT="$(detect_context)"
HOSTNAME="$(hostname -s)"

log "Hostname: $HOSTNAME"
log "Context:  $CONTEXT"

# -----------------------------------------------------------------------------
# Внешние машины — пропускаем
# -----------------------------------------------------------------------------
if [[ "$CONTEXT" == "external" ]]; then
    warn "Внешняя машина ($HOSTNAME) — ssh config не деплоится."
    warn "Если нужно — скопируй вручную из files/home/.ssh/config"
    exit 0
fi

# -----------------------------------------------------------------------------
# Генерация конфига
# -----------------------------------------------------------------------------
GITHUB_BLOCK="Host github.com
    HostName github.com
    User git
    IdentityFile ${REPO_HOME}/.ssh/id_ed25519
    AddKeysToAgent yes"

WN75_BLOCK="Host wn75
    HostName wn75
    User root
    IdentityFile ${REPO_HOME}/.ssh/id_ed25519
    AddKeysToAgent yes"

if [[ "$CONTEXT" == "jump_host" ]]; then
    COMMON_BLOCKS="Host arch03 arch04 arch05
    HostName %h
    User root
    ProxyJump wn75

Host ui
    HostName ui
    User ${REPO_USER}
    Port 7890

Host archminio01 archminio02
    HostName %h
    User ${REPO_USER}
    ProxyJump ui

Host *
    AddKeysToAgent yes
    ServerAliveInterval 60
    ServerAliveCountMax 3
    ConnectTimeout 15
    Compression yes
    ControlMaster auto
    ControlPath ${REPO_HOME}/.ssh/ctrl-%r@%h:%p
    ControlPersist 10m"
else
    COMMON_BLOCKS="Host amar224
    HostName amar
    User ${REPO_USER}
    IdentityFile ${REPO_HOME}/.ssh/id_ed25519
    AddKeysToAgent yes

Host arch03 arch04 arch05
    HostName %h
    User root
    ProxyJump wn75

Host ui
    HostName ui
    User ${REPO_USER}
    Port 7890

Host archminio01 archminio02
    HostName %h
    User ${REPO_USER}
    ProxyJump ui

Host *
    AddKeysToAgent yes
    ServerAliveInterval 60
    ServerAliveCountMax 3
    ConnectTimeout 15
    Compression yes
    ControlMaster auto
    ControlPath ${REPO_HOME}/.ssh/ctrl-%r@%h:%p
    ControlPersist 10m"
fi

CONFIG_CONTENT="# =============================================================================
# ~/.ssh/config — сгенерирован deploy-ssh-config.sh
# Контекст: $CONTEXT (hostname: $HOSTNAME, user: ${REPO_USER})
# Дата: $(date '+%F %T')
# =============================================================================
# Для ручного обновления: ./deploy-ssh-config.sh
# IP-адреса берутся из /etc/hosts — не хранятся в репозитории.
# =============================================================================

$GITHUB_BLOCK

$WN75_BLOCK

$COMMON_BLOCKS
"

# -----------------------------------------------------------------------------
# Деплой или dry-run
# -----------------------------------------------------------------------------
if [[ "$DRY_RUN" == "true" ]]; then
    echo ""
    echo "=== DRY RUN — итоговый ~/.ssh/config ==="
    echo "$CONFIG_CONTENT"
    exit 0
fi

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

if [[ -f "$SSH_CONFIG" && ! -L "$SSH_CONFIG" ]]; then
    STAMP="$(date +%F-%H%M%S)"
    cp -a "$SSH_CONFIG" "${SSH_CONFIG}.bak.${STAMP}"
    ok "Бэкап: ${SSH_CONFIG}.bak.${STAMP}"
fi

echo "$CONFIG_CONTENT" > "$SSH_CONFIG"
chmod 600 "$SSH_CONFIG"

if ssh -G github.com >/dev/null 2>&1; then
    ok "ssh config задеплоен и валиден"
    log "Контекст: $CONTEXT | Пользователь: ${REPO_USER}"
else
    warn "ssh config не прошёл валидацию — проверь вручную"
    exit 1
fi
