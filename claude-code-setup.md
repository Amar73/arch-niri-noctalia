# Claude Code на Arch Linux — Установка и интеграция в arch-niri

> Руководство описывает полную установку Claude Code с обходом региональных
> ограничений через SSH SOCKS5-туннель и интеграцию в bootstrap-репозиторий
> `arch-niri`. После прохождения инструкции `make claude-proxy` поднимает всё
> автоматически на любой новой машине.

---

## Содержание

1. [Архитектура решения](#1-архитектура-решения)
2. [Предварительные требования](#2-предварительные-требования)
3. [Интеграция в репозиторий arch-niri](#3-интеграция-в-репозиторий-arch-niri)
   - 3.1 [Новые файлы репозитория](#31-новые-файлы-репозитория)
   - 3.2 [Изменения в существующих файлах](#32-изменения-в-существующих-файлах)
4. [Ручная установка (без репо)](#4-ручная-установка-без-репо)
5. [Проверка работоспособности](#5-проверка-работоспособности)
6. [Диагностика](#6-диагностика)
7. [Итоговый чеклист](#7-итоговый-чеклист)

---

## 1. Архитектура решения

```
Claude Code
    │
    │  HTTPS_PROXY=http://127.0.0.1:8118
    ▼
privoxy (127.0.0.1:8118)      ← SOCKS5 → HTTP конвертер
    │
    │  socks5://127.0.0.1:1080
    ▼
autossh / ssh-proxy.service   ← systemd, автозапуск при загрузке
    │
    │  SSH-туннель (-D 1080)
    ▼
VPS (amar@vps)
    │
    ▼
api.anthropic.com
```

**Почему не SOCKS5 напрямую:** Claude Code поддерживает только `HTTPS_PROXY` /
`HTTP_PROXY`. SOCKS5 — не поддерживается. `privoxy` решает это прозрачно.

**Почему autossh, а не просто ssh:** `autossh` следит за туннелем и
перезапускает его при обрыве. systemd следит за `autossh`. Двойная страховка.

**Почему wrapper `~/bin/claude`:** прокси нужен только Claude Code, а не всему
трафику системы. Wrapper устанавливает `HTTPS_PROXY` только для своего процесса.

---

## 2. Предварительные требования

### VPS

- Любой зарубежный VPS с доступом по SSH и публичным ключом
- Пользователь `amar` (или другой) с доступом по ключу без пароля
- Хост добавлен в `~/.ssh/known_hosts` (хотя бы одно ручное подключение)

Проверка доступа:

```bash
ssh amar@vps echo ok
# Вывод: ok — всё в порядке
```

### SSH ControlMaster

**Критично:** если в `~/.ssh/config` есть `ControlMaster auto` (а у нас есть),
перед запуском `ssh-proxy.service` необходимо убедиться что нет активного
мультиплексного сокета на этот хост. Иначе `autossh` прицепится к
существующему сокету и немедленно выйдет.

В конфиге systemd-сервиса это решено флагами `ControlMaster=no` и
`ControlPath=none` — они полностью отключают мультиплексирование для
процесса autossh.

### Аккаунт Anthropic

- Активный аккаунт на `claude.ai` (Pro или выше)
- Авторизация Claude Code проходит через браузер — при первом запуске
  `claude` откроет URL, который нужно открыть вручную

---

## 3. Интеграция в репозиторий arch-niri

Все изменения рассчитаны на внесение в репозиторий `~/Amar73/arch-niri`
с последующим `git commit`. После этого `make claude-proxy` работает
на любой машине с нужными данными VPS.

### 3.1 Новые файлы репозитория

#### `files/etc/systemd/system/ssh-proxy.service`

Шаблон systemd-сервиса для SSH SOCKS5-туннеля.

```bash
mkdir -p files/etc/systemd/system/
```

Содержимое файла `files/etc/systemd/system/ssh-proxy.service`:

```ini
[Unit]
Description=SSH SOCKS5 proxy to VPS
After=network-online.target
Wants=network-online.target

[Service]
User=amar
Environment=HOME=/home/amar
ExecStart=/usr/bin/autossh -M 0 -N -D 1080 \
  -i /home/amar/.ssh/id_ed25519 \
  -o "ServerAliveInterval=15" \
  -o "ServerAliveCountMax=2" \
  -o "ExitOnForwardFailure=yes" \
  -o "StrictHostKeyChecking=accept-new" \
  -o "BatchMode=yes" \
  -o "ControlMaster=no" \
  -o "ControlPath=none" \
  amar@vps
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

> **Адаптация под другой VPS:** замени `amar@vps` на нужный адрес.
> Если имя пользователя отличается от `amar` — замени также `User=` и пути
> к ключу.

---

#### `files/home/bin/claude`

Wrapper-скрипт для Claude Code. Устанавливает прокси только для этого процесса.

```bash
mkdir -p files/home/bin/
```

Содержимое файла `files/home/bin/claude`:

```bash
#!/bin/bash
# Wrapper для Claude Code — проксирование через privoxy → SSH SOCKS5 туннель
# Устанавливает HTTPS_PROXY только для этого процесса, не глобально
export HTTPS_PROXY="http://127.0.0.1:8118"
exec ~/.local/bin/claude "$@"
```

---

#### `deploy-claude-proxy.sh`

Скрипт установки и настройки всей цепочки: пакеты → сервисы → wrapper →
Claude Code.

```bash
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
# Использование:
#   ./deploy-claude-proxy.sh
#   ./deploy-claude-proxy.sh --check-only   # только проверка без установки
# =============================================================================

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
        die "VPS vps не найден в known_hosts. Сначала подключись вручную:
  ssh amar@vps echo ok
И ответь yes на вопрос про fingerprint."
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

    # Проверяем что listen-address раскомментирован
    if ! grep -q "^listen-address.*127.0.0.1:8118" /etc/privoxy/config; then
        sudo sed -i 's/^#.*listen-address.*127\.0\.0\.1:8118/listen-address  127.0.0.1:8118/' \
            /etc/privoxy/config
        # Если строки не было вообще — добавляем
        grep -q "^listen-address" /etc/privoxy/config \
            || echo "listen-address  127.0.0.1:8118" | sudo tee -a /etc/privoxy/config
    fi

    # socket-timeout — критично для долгих ответов Opus
    if ! grep -q "^socket-timeout" /etc/privoxy/config; then
        echo "socket-timeout 900" | sudo tee -a /etc/privoxy/config
    fi

    sudo systemctl enable --now privoxy.service
    ok "privoxy настроен и запущен (127.0.0.1:8118)"
}

# --- Деплой systemd-сервиса ---
deploy_ssh_proxy_service() {
    log "Деплой ssh-proxy.service"

    local svc_src="${ROOT_DIR}/files/etc/systemd/system/ssh-proxy.service"

    if [[ -f "$svc_src" ]]; then
        sudo install -m 644 "$svc_src" /etc/systemd/system/ssh-proxy.service
        ok "Сервис задеплоен из репо"
    else
        warn "Файл $svc_src не найден — пропускаю деплой сервиса"
        warn "Создай files/etc/systemd/system/ssh-proxy.service и запусти ещё раз"
        return
    fi

    sudo systemctl daemon-reload
    sudo systemctl enable --now ssh-proxy.service

    # Даём время подняться
    sleep 3

    if systemctl is-active ssh-proxy.service >/dev/null 2>&1; then
        ok "ssh-proxy.service запущен"
    else
        fail "ssh-proxy.service не запустился"
        journalctl -u ssh-proxy.service -n 10 --no-pager
        die "Проверь конфиг сервиса и доступность VPS"
    fi
}

# --- Деплой wrapper ---
deploy_wrapper() {
    log "Деплой ~/bin/claude wrapper"
    mkdir -p "${HOME}/bin"

    local wrapper_src="${ROOT_DIR}/files/home/bin/claude"

    if [[ -f "$wrapper_src" ]]; then
        install -m 755 "$wrapper_src" "${HOME}/bin/claude"
        ok "Wrapper задеплоен из репо: ~/bin/claude"
    else
        cat > "${HOME}/bin/claude" << 'EOF'
#!/bin/bash
export HTTPS_PROXY="http://127.0.0.1:8118"
exec ~/.local/bin/claude "$@"
EOF
        chmod +x "${HOME}/bin/claude"
        ok "Wrapper создан: ~/bin/claude"
    fi

    # Проверяем что ~/bin первый в PATH
    if ! echo "$PATH" | grep -q "${HOME}/bin:"; then
        warn "~/bin не первый в PATH. Добавь в ~/.bashrc:"
        warn "  add_to_path \"\$HOME/bin\"  (должен быть ВЫШЕ ~/.local/bin)"
        warn "Или перезапусти shell: source ~/.bashrc"
    else
        ok "~/bin первый в PATH — wrapper будет найден раньше ~/.local/bin/claude"
    fi
}

# --- Установка Claude Code ---
install_claude_code() {
    if command -v claude >/dev/null 2>&1 && [[ "$(command -v claude)" == "${HOME}/bin/claude" ]]; then
        # Проверяем что ~/.local/bin/claude существует
        if [[ -x "${HOME}/.local/bin/claude" ]]; then
            ok "Claude Code уже установлен: $(~/.local/bin/claude --version 2>/dev/null || echo 'версия недоступна')"
            return
        fi
    fi

    log "Установка Claude Code через HTTPS_PROXY"

    # Проверяем что цепочка работает
    if ! curl -s -x http://127.0.0.1:8118 https://api.anthropic.com/v1/models \
            -H "x-api-key: test" 2>&1 | grep -q "authentication_error"; then
        die "Цепочка прокси не работает. Проверь:
  systemctl status ssh-proxy.service
  systemctl status privoxy.service"
    fi

    HTTPS_PROXY="http://127.0.0.1:8118" \
        curl -fsSL https://claude.ai/install.sh | bash

    ok "Claude Code установлен: $(~/.local/bin/claude --version 2>/dev/null || echo 'ok')"
}

# --- Финальная проверка ---
run_checks() {
    log "Проверка всей цепочки"
    local errors=0

    # autossh
    command -v autossh >/dev/null 2>&1 && ok "autossh: установлен" \
        || { fail "autossh: не найден"; ((errors++)); }

    # privoxy
    systemctl is-active privoxy.service >/dev/null 2>&1 && ok "privoxy: active" \
        || { fail "privoxy: не запущен"; ((errors++)); }

    # ssh-proxy
    systemctl is-active ssh-proxy.service >/dev/null 2>&1 && ok "ssh-proxy: active" \
        || { fail "ssh-proxy: не запущен"; ((errors++)); }

    # порт 8118
    ss -tlnp | grep -q "8118" && ok "privoxy: слушает 127.0.0.1:8118" \
        || { fail "privoxy: порт 8118 не слушает"; ((errors++)); }

    # туннель (проверяем через privoxy)
    if curl -s -x http://127.0.0.1:8118 https://api.anthropic.com/v1/models \
            -H "x-api-key: test" 2>&1 | grep -q "authentication_error"; then
        ok "Туннель → anthropic.com: OK (authentication_error = трафик доходит)"
    else
        fail "Туннель → anthropic.com: не работает"
        ((errors++))
    fi

    # wrapper
    [[ -x "${HOME}/bin/claude" ]] && ok "wrapper ~/bin/claude: существует" \
        || { fail "wrapper ~/bin/claude: не найден"; ((errors++)); }

    # claude binary
    [[ -x "${HOME}/.local/bin/claude" ]] && ok "~/.local/bin/claude: установлен" \
        || { warn "~/.local/bin/claude: не установлен — запусти без --check-only"; }

    # which claude
    local which_claude
    which_claude=$(command -v claude 2>/dev/null || echo "не найден")
    if [[ "$which_claude" == "${HOME}/bin/claude" ]]; then
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

    cat << 'EOF'

========================================
Claude Code установлен
========================================

Первый запуск:
  claude

При первом запуске Claude Code откроет URL для авторизации через браузер.
Скопируй URL и открой в Chrome (через прокси или напрямую — оба варианта работают).

Управление сервисами:
  systemctl status ssh-proxy.service    # состояние туннеля
  systemctl status privoxy.service      # состояние HTTP прокси
  journalctl -u ssh-proxy -f            # живой лог туннеля

Обновление Claude Code:
  HTTPS_PROXY="http://127.0.0.1:8118" claude update

Повторная проверка:
  ./deploy-claude-proxy.sh --check-only
  make claude-check

EOF
}

main "$@"
```

---

#### Добавить в `.gitignore`

Ничего нового добавлять не нужно — `.gitignore` уже корректный.

---

### 3.2 Изменения в существующих файлах

#### `Makefile` — добавить цели

```makefile
claude-proxy:
	./deploy-claude-proxy.sh

claude-check:
	./deploy-claude-proxy.sh --check-only
```

Итоговый раздел Makefile (добавить после существующих целей):

```makefile
claude-proxy:
	./deploy-claude-proxy.sh

claude-check:
	./deploy-claude-proxy.sh --check-only
```

---

#### `packages/base.txt` — добавить пакеты

В секцию «Утилиты командной строки» добавить:

```
# --- Claude Code proxy stack ---
autossh                        # Мониторинг и перезапуск SSH-туннеля
privoxy                        # SOCKS5 → HTTP прокси конвертер
```

---

#### `post-install-check.sh` — добавить проверки

В секцию `=== commands ===` добавить:

```bash
check_cmd autossh
check_cmd privoxy
```

После секции `=== user services ===` добавить новую секцию:

```bash
echo
echo "=== claude code ==="

# ssh-proxy.service (system)
systemctl is-enabled ssh-proxy.service >/dev/null 2>&1 \
    && ok "ssh-proxy.service enabled" \
    || warn "ssh-proxy.service не включён — запусти: make claude-proxy"

systemctl is-active ssh-proxy.service >/dev/null 2>&1 \
    && ok "ssh-proxy.service active" \
    || warn "ssh-proxy.service не запущен"

# privoxy
systemctl is-active privoxy.service >/dev/null 2>&1 \
    && ok "privoxy.service active" \
    || warn "privoxy.service не запущен"

# wrapper
[[ -x "${HOME}/bin/claude" ]] \
    && ok "~/bin/claude wrapper exists" \
    || warn "~/bin/claude не найден — запусти: make claude-proxy"

# claude binary
[[ -x "${HOME}/.local/bin/claude" ]] \
    && ok "claude: $("${HOME}/.local/bin/claude" --version 2>/dev/null || echo 'установлен')" \
    || warn "Claude Code не установлен — запусти: make claude-proxy"
```

---

#### `check-local.sh` — добавить проверку файлов

В массив `expected_files` добавить:

```bash
"home/bin/claude"
```

В массив проверки Makefile-целей добавить:

```bash
"claude-proxy"
"claude-check"
```

---

#### `sync.sh` — добавить деплой wrapper

После блока деплоя `set-wallpapers` добавить:

```bash
# Claude Code wrapper
if [[ -f "${ROOT_DIR}/files/home/bin/claude" ]]; then
    mkdir -p "${HOME}/bin"
    install -m 755 "${ROOT_DIR}/files/home/bin/claude" "${HOME}/bin/claude"
    echo "[OK] claude wrapper задеплоен"
fi
```

---

#### `README.md` — добавить в таблицу Makefile

```markdown
| `make claude-proxy` | Установка Claude Code с SSH-туннелем и privoxy |
| `make claude-check` | Проверка цепочки Claude Code без установки |
```

---

## 4. Ручная установка (без репо)

Если нужно поднять всё на машине, не входящей в arch-niri, или при первоначальной
настройке до клонирования репо.

### Шаг 1 — Пакеты

```bash
sudo pacman -S autossh privoxy
```

### Шаг 2 — Privoxy

```bash
# Проверяем listen-address
grep "^listen-address" /etc/privoxy/config
# Ожидаем: listen-address  127.0.0.1:8118

# Если закомментировано:
sudo sed -i 's/^#.*listen-address.*127\.0\.0\.1:8118/listen-address  127.0.0.1:8118/' \
    /etc/privoxy/config

# Таймаут для долгих ответов Opus (10+ минут на плоских тарифах)
echo "socket-timeout 900" | sudo tee -a /etc/privoxy/config

sudo systemctl enable --now privoxy
```

### Шаг 3 — SSH-туннель (тест)

```bash
# Убедись что хост в known_hosts
ssh amar@vps echo ok

# Тест туннеля (Ctrl+C для выхода)
ssh -D 1080 -N -o ControlMaster=no -o ControlPath=none amar@vps
```

### Шаг 4 — systemd-сервис туннеля

```bash
sudo tee /etc/systemd/system/ssh-proxy.service << 'EOF'
[Unit]
Description=SSH SOCKS5 proxy to VPS
After=network-online.target
Wants=network-online.target

[Service]
User=amar
Environment=HOME=/home/amar
ExecStart=/usr/bin/autossh -M 0 -N -D 1080 \
  -i /home/amar/.ssh/id_ed25519 \
  -o "ServerAliveInterval=15" \
  -o "ServerAliveCountMax=2" \
  -o "ExitOnForwardFailure=yes" \
  -o "StrictHostKeyChecking=accept-new" \
  -o "BatchMode=yes" \
  -o "ControlMaster=no" \
  -o "ControlPath=none" \
  amar@vps
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now ssh-proxy.service
sleep 3
systemctl status ssh-proxy.service
```

### Шаг 5 — Wrapper

```bash
mkdir -p ~/bin
cat > ~/bin/claude << 'EOF'
#!/bin/bash
export HTTPS_PROXY="http://127.0.0.1:8118"
exec ~/.local/bin/claude "$@"
EOF
chmod +x ~/bin/claude
source ~/.bashrc
which claude   # должно быть /home/amar/bin/claude
```

### Шаг 6 — Установка Claude Code

```bash
HTTPS_PROXY="http://127.0.0.1:8118" curl -fsSL https://claude.ai/install.sh | bash
```

### Шаг 7 — Первый запуск

```bash
claude
```

При первом запуске появится URL вида `https://claude.ai/oauth/...` — открой
его в браузере, авторизуйся. Токен сохранится в `~/.claude/`.

---

## 5. Проверка работоспособности

### Пошаговая диагностика цепочки

```bash
# 1. Туннель поднят?
systemctl status ssh-proxy.service
ss -tlnp | grep 1080      # должен слушать autossh или ssh

# 2. Privoxy работает?
systemctl status privoxy.service
ss -tlnp | grep 8118      # должен слушать privoxy

# 3. Трафик доходит до Anthropic?
curl -s -x http://127.0.0.1:8118 https://api.anthropic.com/v1/models \
    -H "x-api-key: test" | python3 -m json.tool
# Ожидаем: {"type":"error","error":{"type":"authentication_error",...}}
# authentication_error = трафик дошёл, ключ тестовый — это нормально

# 4. Wrapper подхватывается?
which claude
# Ожидаем: /home/amar/bin/claude

# 5. Версия Claude Code
claude --version
# Ожидаем: X.Y.Z (Claude Code)

# 6. Полная проверка через make
make claude-check
```

### Статус после перезагрузки

Оба сервиса стартуют автоматически. Проверить:

```bash
sudo reboot
# После входа:
systemctl status ssh-proxy privoxy
```

---

## 6. Диагностика

### Сервис не запускается: `ssh exited prematurely with status 0`

**Причина:** активный ControlMaster-сокет. ssh прицепляется к нему и выходит.

```bash
# Найти активные сокеты на VPS
ls ~/.ssh/ctrl-*vps*

# Убрать сокет
rm -f ~/.ssh/ctrl-amar@vps:22

# Или убить все ControlMaster-процессы к VPS
ssh -O exit amar@vps 2>/dev/null || true

sudo systemctl restart ssh-proxy.service
```

Постоянное решение уже в сервисе: `-o "ControlMaster=no" -o "ControlPath=none"`.

---

### Сервис не запускается: `Permission denied (publickey)`

```bash
# Проверить что ключ существует
ls -la ~/.ssh/id_ed25519

# Проверить что ключ добавлен на VPS
ssh-copy-id -i ~/.ssh/id_ed25519.pub amar@vps

# Проверить авторизацию
ssh -i ~/.ssh/id_ed25519 amar@vps echo ok
```

---

### Privoxy не конвертирует трафик

```bash
# Живой лог privoxy
journalctl -u privoxy -f

# Тест минуя privoxy напрямую через SOCKS5
curl --socks5-hostname 127.0.0.1:1080 https://api.anthropic.com/v1/models \
    -H "x-api-key: test"
# Если работает — проблема в privoxy, если нет — в туннеле
```

---

### Claude Code зависает или не отвечает

Скорее всего `socket-timeout` в privoxy слишком мал. Opus на плоских тарифах
может думать 10–40 минут. Текущее значение — 900 секунд (15 минут).

```bash
grep "socket-timeout" /etc/privoxy/config
# Если нужно увеличить:
sudo sed -i 's/^socket-timeout.*/socket-timeout 3600/' /etc/privoxy/config
sudo systemctl restart privoxy
```

---

### Обновление Claude Code

```bash
HTTPS_PROXY="http://127.0.0.1:8118" claude update
```

Или через wrapper, если он добавлен в PATH первым:

```bash
claude update   # wrapper пробрасывает HTTPS_PROXY автоматически
```

---

### Проверка логов туннеля

```bash
# Последние события
journalctl -u ssh-proxy.service -n 50 --no-pager

# Живой режим
journalctl -u ssh-proxy.service -f
```

---

## 7. Итоговый чеклист

### Файлы репозитория (добавить/изменить)

```
arch-niri/
├── deploy-claude-proxy.sh              ← новый скрипт (chmod +x)
├── Makefile                            ← добавить цели claude-proxy, claude-check
├── packages/
│   └── base.txt                        ← добавить autossh, privoxy
├── post-install-check.sh               ← добавить секцию claude code
├── check-local.sh                      ← добавить файл и цели
├── sync.sh                             ← добавить деплой wrapper
└── files/
    ├── etc/
    │   └── systemd/
    │       └── system/
    │           └── ssh-proxy.service   ← новый файл
    └── home/
        └── bin/
            └── claude                  ← новый wrapper-скрипт
```

### После клонирования на новой машине

```bash
cd ~/Amar73/arch-niri

# Убедиться что VPS в known_hosts
ssh amar@vps echo ok

# Установить всё
make claude-proxy

# Первый запуск
claude
```

### Ежедневная работа

```bash
# Запустить Claude Code
claude

# Проверить статус
make claude-check

# Посмотреть логи туннеля
journalctl -u ssh-proxy -f

# Работа в tmux (доступ с телефона через SSH)
tmux new-session -s claude
claude
# Ctrl+B D — отцепиться, ssh → tmux attach -t claude — вернуться
```

---

*Если туннель упал — `systemctl restart ssh-proxy.service`. Если privoxy —
`systemctl restart privoxy`. Если всё упало — `make claude-check` покажет где.*
