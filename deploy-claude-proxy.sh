#!/usr/bin/env bash
set -Eeuo pipefail

# =============================================================================
# deploy-claude-proxy.sh — установка Claude Code с SSH SOCKS5 + privoxy
#
# Что делает:
#   1. Устанавливает autossh и privoxy
#   2. Настраивает /etc/privoxy/config
#   3. Деплоит systemd-сервис ssh-proxy (SSH SOCKS5 туннель к VPS)
#   4. Деплоит wrapper ~/bin/claude с HTTPS_PROXY
#   5. Устанавливает Claude Code через HTTPS_PROXY
#   6. Проверяет что вся цепочка работает
#
# ВАЖНО: Перед запуском VPS должен быть в known_hosts:
#   ssh ${VPS_USER}@vps echo ok
#
# Использование:
#   ./deploy-claude-proxy.sh
#   ./deploy-claude-proxy.sh --check-only   # только проверка без установки
# =============================================================================

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${ROOT_DIR}/config.sh"

log()  { printf '\n[%s] %s\n' "$(date +'%F %T')" "$*"; }
ok()   { printf '[OK]   %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*"; }
die()  { printf '\n[ERROR] %s\n' "$*" >&2; exit 1; }

CHECK_ONLY=false
[[ "${1:-}" == "--check-only" ]] && CHECK_ONLY=true

# --- Проверка наличия VPS в known_hosts ---
check_vps_known() {
    if ! ssh-keygen -F vps >/dev/null 2>&1; then
        die "VPS (vps) не найден в known_hosts. Сначала подключись вручную:
  ssh ${VPS_USER}@vps echo ok
И ответь yes на вопрос про fingerprint.
Убедись что vps прописан в /etc/hosts."
    fi
    ok "VPS в known_hosts"
}

# --- Установка пакетов ---
install_packages() {
    log "Установка autossh и privoxy"
    sudo pacman -S --needed --noconfirm autossh privoxy
    ok "autossh, privoxy установлены"
}

# --- Настройка privoxy ---
configure_privoxy() {
    log "Настройка privoxy"

    if ! grep -q "^listen-address.*127.0.0.1:8118" /etc/privoxy/config; then
        sudo sed -i \
            's/^#.*listen-address.*127\.0\.0\.1:8118/listen-address  127.0.0.1:8118/' \
            /etc/privoxy/config
        grep -q "^listen-address" /etc/privoxy/config \
            || echo "listen-address  127.0.0.1:8118" | sudo tee -a /etc/privoxy/config
    fi

    # socket-timeout — критично для долгих ответов (Opus: до 40 минут)
    if ! grep -q "^socket-timeout" /etc/privoxy/config; then
        echo "socket-timeout 900" | sudo tee -a /etc/privoxy/config
    fi

    sudo systemctl enable --now privoxy.service
    ok "privoxy настроен и запущен (127.0.0.1:8118)"
}

# --- Деплой ssh-proxy.service с правильным пользователем ---
deploy_ssh_proxy_service() {
    log "Деплой ssh-proxy.service"
    local key_path="${REPO_HOME}/.ssh/id_ed25519"

    # Проверяем что ключ существует (нужен без пароля для автозапуска)
    if [[ ! -f "$key_path" ]]; then
        die "SSH-ключ не найден: ${key_path}
Для автозапуска туннеля ключ должен существовать.
Сгенерируй: ssh-keygen -t ed25519 -C '${REPO_USER}@vps' -f ${key_path}
И скопируй на VPS: ssh-copy-id -i ${key_path}.pub ${VPS_USER}@vps"
    fi

    sudo tee /etc/systemd/system/ssh-proxy.service > /dev/null << EOF
[Unit]
Description=SSH SOCKS5 proxy to VPS
After=network-online.target
Wants=network-online.target

[Service]
User=${REPO_USER}
Environment=HOME=${REPO_HOME}
ExecStart=/usr/bin/autossh -M 0 -N -D 1080 \\
  -i ${key_path} \\
  -o "ServerAliveInterval=15" \\
  -o "ServerAliveCountMax=2" \\
  -o "ExitOnForwardFailure=yes" \\
  -o "StrictHostKeyChecking=accept-new" \\
  -o "BatchMode=yes" \\
  -o "ControlMaster=no" \\
  -o "ControlPath=none" \\
  ${VPS_USER}@vps
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    # Примечание по безопасности: StrictHostKeyChecking=accept-new принимает
    # ключ только при первом подключении. Последующие подключения проверяют
    # known_hosts. Убедись что VPS добавлен вручную (check_vps_known выше).

    sudo systemctl daemon-reload
    sudo systemctl enable --now ssh-proxy.service

    sleep 3

    if systemctl is-active ssh-proxy.service >/dev/null 2>&1; then
        ok "ssh-proxy.service запущен (User=${REPO_USER})"
    else
        fail "ssh-proxy.service не запустился"
        journalctl -u ssh-proxy.service -n 10 --no-pager
        die "Проверь конфиг сервиса и доступность VPS"
    fi
}

# --- Деплой wrapper ---
deploy_wrapper() {
    log "Деплой ~/bin/claude wrapper"
    mkdir -p "${REPO_HOME}/bin"

    cat > "${REPO_HOME}/bin/claude" << 'WRAPPER'
#!/bin/bash
# Wrapper для Claude Code — проксирование через privoxy → SSH SOCKS5 туннель
# Устанавливает HTTPS_PROXY только для этого процесса, не глобально
export HTTPS_PROXY="http://127.0.0.1:8118"
exec "${HOME}/.local/bin/claude" "$@"
WRAPPER
    chmod 755 "${REPO_HOME}/bin/claude"
    ok "Wrapper создан: ~/bin/claude"

    if ! echo "$PATH" | grep -q "${REPO_HOME}/bin:"; then
        warn "~/bin не первый в PATH. Добавь в ~/.bashrc:"
        warn "  add_to_path \"\$HOME/bin\"  (должен быть ВЫШЕ ~/.local/bin)"
        warn "Или: source ~/.bashrc"
    else
        ok "~/bin первый в PATH — wrapper будет найден раньше ~/.local/bin/claude"
    fi
}

# --- Установка Claude Code ---
install_claude_code() {
    if [[ -x "${REPO_HOME}/.local/bin/claude" ]]; then
        ok "Claude Code уже установлен: \
$(${REPO_HOME}/.local/bin/claude --version 2>/dev/null || echo 'версия недоступна')"
        return
    fi

    log "Установка Claude Code через HTTPS_PROXY"

    if ! curl -s -x http://127.0.0.1:8118 https://api.anthropic.com/v1/models \
            -H "x-api-key: test" 2>&1 | grep -q "authentication_error"; then
        die "Цепочка прокси не работает. Проверь:
  systemctl status ssh-proxy.service
  systemctl status privoxy.service"
    fi

    HTTPS_PROXY="http://127.0.0.1:8118" \
        curl -fsSL https://claude.ai/install.sh | bash

    ok "Claude Code установлен: \
$(${REPO_HOME}/.local/bin/claude --version 2>/dev/null || echo 'ok')"
}

# --- Финальная проверка ---
run_checks() {
    log "Проверка всей цепочки"
    local errors=0

    command -v autossh >/dev/null 2>&1 \
        && ok "autossh: установлен" \
        || { fail "autossh: не найден"; ((errors++)); }

    systemctl is-active privoxy.service >/dev/null 2>&1 \
        && ok "privoxy: active" \
        || { fail "privoxy: не запущен"; ((errors++)); }

    systemctl is-active ssh-proxy.service >/dev/null 2>&1 \
        && ok "ssh-proxy: active" \
        || { fail "ssh-proxy: не запущен"; ((errors++)); }

    ss -tlnp | grep -q "8118" \
        && ok "privoxy: слушает 127.0.0.1:8118" \
        || { fail "privoxy: порт 8118 не слушает"; ((errors++)); }

    if curl -s -x http://127.0.0.1:8118 https://api.anthropic.com/v1/models \
            -H "x-api-key: test" 2>&1 | grep -q "authentication_error"; then
        ok "Туннель → anthropic.com: OK (authentication_error = трафик доходит)"
    else
        fail "Туннель → anthropic.com: не работает"
        ((errors++))
    fi

    [[ -x "${REPO_HOME}/bin/claude" ]] \
        && ok "wrapper ~/bin/claude: существует" \
        || { fail "wrapper ~/bin/claude: не найден"; ((errors++)); }

    [[ -x "${REPO_HOME}/.local/bin/claude" ]] \
        && ok "~/.local/bin/claude: установлен" \
        || warn "~/.local/bin/claude: не установлен — запусти без --check-only"

    local which_claude
    which_claude=$(command -v claude 2>/dev/null || echo "не найден")
    if [[ "$which_claude" == "${REPO_HOME}/bin/claude" ]]; then
        ok "which claude → ~/bin/claude (wrapper подхвачен)"
    else
        warn "which claude → $which_claude (ожидался ~/bin/claude)"
        warn "Перезапусти shell: source ~/.bashrc"
    fi

    echo
    if [[ $errors -eq 0 ]]; then
        ok "Все проверки пройдены. Запускай: claude"
    else
        fail "Ошибок: $errors — см. вывод выше"
        exit 1
    fi
}

# --- Main ---
main() {
    echo "=== deploy-claude-proxy.sh ==="
    echo "Пользователь: ${REPO_USER} | VPS: ${VPS_USER}@vps"

    check_vps_known

    if [[ "$CHECK_ONLY" == "true" ]]; then
        run_checks
        exit 0
    fi

    install_packages
    configure_privoxy
    deploy_ssh_proxy_service
    deploy_wrapper
    install_claude_code
    run_checks

    cat << EOF

========================================
Claude Code установлен
========================================

Первый запуск:
  claude

При первом запуске Claude Code откроет URL для авторизации через браузер.

Управление сервисами:
  systemctl status ssh-proxy.service    # состояние туннеля
  systemctl status privoxy.service      # состояние HTTP прокси
  journalctl -u ssh-proxy -f            # живой лог туннеля

Обновление Claude Code:
  HTTPS_PROXY="http://127.0.0.1:8118" claude update

Повторная проверка:
  make claude-check

EOF
}

main "$@"
