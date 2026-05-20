#!/usr/bin/env bash
set -Eeuo pipefail

# =============================================================================
# install.sh — полная установка с нуля
#
# Использование:
#   ./install.sh
#   REPO_USER=bob INSTALLED_REPO_PATH=/home/bob/dots make install
#
# Прогресс сохраняется в ~/.install-progress.
# Повторный запуск пропускает выполненные шаги.
# Для полной переустановки: rm ~/.install-progress && make install
# =============================================================================

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${ROOT_DIR}/config.sh"

FILES_DIR="${REPO_FILES}"
PROGRESS_FILE="${REPO_HOME}/.install-progress"

log()  { printf '\n[%s] %s\n' "$(date +'%F %T')" "$*"; }
ok()   { printf '[OK]   %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; }
die()  { printf '\n[ERROR] %s\n' "$*" >&2; exit 1; }

step_done() { echo "$1" >> "${PROGRESS_FILE}"; }
step_skip() { grep -q "^${1}$" "${PROGRESS_FILE}" 2>/dev/null; }

[[ $EUID -eq 0 ]] && die "Запускай от обычного пользователя, не от root."
[[ "${REPO_USER}" != "${USER}" ]] && \
    die "REPO_USER=${REPO_USER} не совпадает с текущим пользователем ${USER}. Запускай от нужного пользователя."

need() {
    command -v "$1" >/dev/null 2>&1 \
        || die "Не найдено: $1. На чистом Arch: sudo pacman -S $1"
}

# -----------------------------------------------------------------------------
# Шаг 1: Обновление системы и установка официальных пакетов
# -----------------------------------------------------------------------------
install_official_packages() {
    log "Обновление системы"
    sudo pacman -Syu --noconfirm

    log "Установка официальных пакетов"
    # Читаем из packages/base.txt и packages/niri.txt чтобы не дублировать список
    local pkgs
    pkgs=$(grep -hv '^#\|^$' \
        "${ROOT_DIR}/packages/base.txt" \
        "${ROOT_DIR}/packages/niri.txt" \
        | sed 's/#.*//' | tr -s ' \t\n' ' ')
    # shellcheck disable=SC2086
    sudo pacman -S --needed --noconfirm $pkgs
}

# -----------------------------------------------------------------------------
# Шаг 2: Системные сервисы
# -----------------------------------------------------------------------------
enable_system_services() {
    log "Включение system services"
    sudo systemctl enable NetworkManager.service
    sudo systemctl enable seatd.service
    sudo systemctl enable greetd.service
}

# -----------------------------------------------------------------------------
# Шаг 3: Локаль
# -----------------------------------------------------------------------------
setup_locale() {
    log "Настройка локали"
    if ! locale -a 2>/dev/null | grep -q "ru_RU.utf8"; then
        sudo sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
        sudo sed -i 's/^#ru_RU.UTF-8/ru_RU.UTF-8/' /etc/locale.gen
        sudo locale-gen
    fi
    if [[ ! -f /etc/locale.conf ]] || ! grep -q "LANG=" /etc/locale.conf; then
        sudo tee /etc/locale.conf > /dev/null << 'EOF'
LANG=ru_RU.UTF-8
LC_COLLATE=C
EOF
        ok "/etc/locale.conf создан (LANG=ru_RU.UTF-8)"
    else
        ok "/etc/locale.conf уже существует: $(head -1 /etc/locale.conf)"
    fi
}

# -----------------------------------------------------------------------------
# Шаг 4: Группы пользователя
# -----------------------------------------------------------------------------
add_groups() {
    log "Добавление пользователя в группы"
    for group in video input seat; do
        if getent group "$group" >/dev/null 2>&1; then
            sudo usermod -aG "$group" "${REPO_USER}"
            ok "Добавлен в группу: $group"
        else
            warn "Группа $group не существует — пропускаю"
        fi
    done
}

# -----------------------------------------------------------------------------
# Шаг 5: yay (AUR helper)
# -----------------------------------------------------------------------------
install_yay() {
    if command -v yay >/dev/null 2>&1; then
        log "yay уже установлен"
        return 0
    fi
    local tmpdir
    tmpdir="$(mktemp -d)"
    # Гарантируем очистку даже при ошибке
    trap "rm -rf '${tmpdir}'" EXIT
    log "Установка yay"
    git clone https://aur.archlinux.org/yay.git "${tmpdir}/yay"
    (cd "${tmpdir}/yay" && makepkg -si --noconfirm)
    trap - EXIT
    rm -rf "${tmpdir}"
}

# -----------------------------------------------------------------------------
# Шаг 6: AUR-пакеты
# -----------------------------------------------------------------------------
install_aur_packages() {
    log "Установка AUR-пакетов (yay)"
    local aur_pkgs
    aur_pkgs=$(grep -v '^#\|^$' "${ROOT_DIR}/packages/aur.txt" \
        | grep -E '^(bibata-cursor-theme|qt5-wayland)$' \
        | tr '\n' ' ')
    if [[ -n "$aur_pkgs" ]]; then
        # shellcheck disable=SC2086
        yay -S --needed --noconfirm --answerdiff=None --answerclean=None $aur_pkgs \
            || warn "Некоторые AUR-пакеты не установились — проверь вручную"
    fi
}

# -----------------------------------------------------------------------------
# Шаг 7: niri-start wrapper
# -----------------------------------------------------------------------------
install_niri_start() {
    log "Установка niri-start wrapper"
    sudo tee /usr/local/bin/niri-start > /dev/null << 'EOF'
#!/bin/bash
exec dbus-run-session niri
EOF
    sudo chmod +x /usr/local/bin/niri-start
    ok "/usr/local/bin/niri-start создан"
}

# -----------------------------------------------------------------------------
# Шаг 8: Деплой конфигов (БЕЗОПАСНЫЙ — только конкретные директории)
# -----------------------------------------------------------------------------
backup_if_exists() {
    local path="$1"
    if [[ -e "$path" && ! -L "$path" ]]; then
        local stamp; stamp="$(date +%F-%H%M%S)"
        cp -a "$path" "${path}.bak.${stamp}"
        ok "Бэкап: ${path}.bak.${stamp}"
    fi
}

deploy_config_dirs() {
    log "Синхронизация конфигов (по директориям)"
    local config_src="${FILES_DIR}/home/.config"
    local config_dst="${REPO_HOME}/.config"

    [[ -d "$config_src" ]] || die "Директория конфигов не найдена: $config_src"

    mkdir -p "${config_dst}"

    # Синхронизируем ТОЛЬКО конкретные поддиректории репо
    # ~/.config/ в целом НЕ трогаем — там могут быть данные приложений
    local dirs=(
        niri waybar alacritty swaylock mako fuzzel mc qt6ct
        gtk-3.0 gtk-4.0 systemd
    )
    for dir in "${dirs[@]}"; do
        if [[ -d "${config_src}/${dir}" ]]; then
            rsync -a --delete \
                "${config_src}/${dir}/" \
                "${config_dst}/${dir}/"
            ok "Synced: ~/.config/${dir}"
        fi
    done
}

deploy_dotfiles() {
    log "Деплой .bashrc и .ssh/config"
    mkdir -p "${REPO_HOME}/.ssh"
    chmod 700 "${REPO_HOME}/.ssh"
    backup_if_exists "${REPO_HOME}/.bashrc"
    backup_if_exists "${REPO_HOME}/.ssh/config"
    install -m 644 "${FILES_DIR}/home/.bashrc"     "${REPO_HOME}/.bashrc"
    install -m 600 "${FILES_DIR}/home/.ssh/config"  "${REPO_HOME}/.ssh/config"
}

deploy_bin_scripts() {
    log "Деплой ~/bin и ~/.local/bin"

    # ~/bin/claude wrapper
    mkdir -p "${REPO_HOME}/bin"
    if [[ -f "${FILES_DIR}/home/bin/claude" ]]; then
        # Генерируем с правильным путём к ~/.local/bin/claude
        cat > "${REPO_HOME}/bin/claude" << EOF
#!/bin/bash
# Wrapper для Claude Code — проксирование через privoxy → SSH SOCKS5 туннель
# Устанавливает HTTPS_PROXY только для этого процесса, не глобально
export HTTPS_PROXY="http://127.0.0.1:8118"
exec "\${HOME}/.local/bin/claude" "\$@"
EOF
        chmod 755 "${REPO_HOME}/bin/claude"
        ok "claude wrapper задеплоен"
    fi

    # ~/.local/bin/set-wallpapers — генерируем с правильными путями
    mkdir -p "${REPO_HOME}/.local/bin"
    generate_set_wallpapers
}

# Генерация set-wallpapers с подстановкой реальных путей
generate_set_wallpapers() {
    local wallpapers_path="${INSTALLED_REPO_PATH}/Wallpapers"
    cat > "${REPO_HOME}/.local/bin/set-wallpapers" << EOF
#!/bin/bash
# set-wallpapers — обои для amar224 (3 монитора DP-2, DP-3, DP-4)
# Сгенерирован install.sh / sync.sh для пользователя ${REPO_USER}
pkill swaybg 2>/dev/null || true
exec swaybg \\
  -o DP-2 -i ${wallpapers_path}/arch.jpeg    -m fill \\
  -o DP-3 -i ${wallpapers_path}/arch3.jpeg   -m fill \\
  -o DP-4 -i ${wallpapers_path}/wallpaper.jpg -m fill
EOF
    chmod 755 "${REPO_HOME}/.local/bin/set-wallpapers"
    ok "set-wallpapers сгенерирован (путь: ${wallpapers_path})"
}

deploy_etc() {
    log "Деплой /etc/greetd"
    sudo install -d -m 755 /etc/greetd
    sudo rsync -a "${FILES_DIR}/etc/greetd/" /etc/greetd/
}

deploy_files() {
    deploy_etc
    deploy_config_dirs
    mkdir -p "${REPO_HOME}/Screenshots"
    deploy_dotfiles
    deploy_bin_scripts

    # Деплой конфига мониторов и обоев по hostname
    log "Деплой конфига мониторов и обоев"
    bash "${ROOT_DIR}/deploy-outputs.sh"

    # Деплой ssh config по контексту машины
    log "Деплой ssh config"
    bash "${ROOT_DIR}/deploy-ssh-config.sh"
}

# -----------------------------------------------------------------------------
# Шаг 9: alacritty themes
# -----------------------------------------------------------------------------
install_alacritty_themes() {
    local themes_dir="${REPO_HOME}/.config/alacritty/themes"
    if [[ -d "${themes_dir}/.git" ]]; then
        log "Обновление alacritty-theme"
        git -C "${themes_dir}" pull --ff-only \
            || warn "Не удалось обновить alacritty-theme — пропускаю"
    else
        log "Установка alacritty-theme"
        mkdir -p "${themes_dir}"
        git clone https://github.com/alacritty/alacritty-theme "${themes_dir}" \
            || warn "Не удалось клонировать alacritty-theme — пропускаю (не критично)"
    fi
}

# -----------------------------------------------------------------------------
# Шаг 10: User services
# -----------------------------------------------------------------------------
enable_user_services() {
    log "Включение user services"
    systemctl --user daemon-reload
    # swayidle запускается через niri spawn-at-startup, НЕ через systemd.
    # Сервис хранится как резерв/документация, но не активируется.
    # systemctl --user enable swayidle.service  ← намеренно отключено
    systemctl --user enable cliphist-text.service
    systemctl --user enable cliphist-images.service
    ok "cliphist сервисы включены"
    ok "swayidle НЕ включён через systemd (управляется через niri spawn-at-startup)"
}

# -----------------------------------------------------------------------------
# Деплой ssh-proxy.service с подстановкой пользователя
# -----------------------------------------------------------------------------
deploy_ssh_proxy_service() {
    local svc_src="${FILES_DIR}/etc/systemd/system/ssh-proxy.service"
    [[ -f "$svc_src" ]] || { warn "ssh-proxy.service не найден в repo"; return; }

    # Генерируем с правильным пользователем и путями
    local key_path="${REPO_HOME}/.ssh/id_ed25519"
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
    sudo systemctl daemon-reload
    ok "ssh-proxy.service задеплоен (User=${REPO_USER})"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
print_summary() {
    cat << EOF

========================================
Установка завершена
========================================

Конфигурация:
  Пользователь : ${REPO_USER}
  Домашняя дир.: ${REPO_HOME}
  Репозиторий  : ${REPO_ROOT}
  Обои из      : ${INSTALLED_REPO_PATH}/Wallpapers

Дальше:
  sudo reboot

Если после reboot greeter не пускает — очисти кеш tuigreet:
  sudo rm -f /var/cache/tuigreet/*

После входа:
  make check
  make logs

Для Claude Code (после настройки VPS):
  make claude-proxy

Для сброса и переустановки с нуля:
  rm ~/.install-progress && make install

EOF
}

main() {
    need sudo
    need pacman

    log "=== arch-niri install.sh ==="
    log "Пользователь: ${REPO_USER} | Репозиторий: ${REPO_ROOT}"

    # git и rsync могут отсутствовать на минимальном Arch
    if ! command -v git >/dev/null 2>&1 || ! command -v rsync >/dev/null 2>&1; then
        log "Предустановка git и rsync"
        sudo pacman -S --needed --noconfirm git rsync
    fi

    step_skip "packages"       || { install_official_packages;  step_done "packages"; }
    step_skip "services"       || { enable_system_services;     step_done "services"; }
    step_skip "locale"         || { setup_locale;               step_done "locale"; }
    step_skip "groups"         || { add_groups;                 step_done "groups"; }
    step_skip "yay"            || { install_yay;                step_done "yay"; }
    step_skip "aur"            || { install_aur_packages;       step_done "aur"; }
    step_skip "niri_start"     || { install_niri_start;         step_done "niri_start"; }
    step_skip "files"          || { deploy_files;               step_done "files"; }
    step_skip "alacritty_themes" || { install_alacritty_themes; step_done "alacritty_themes"; }
    step_skip "user_services"  || { enable_user_services;       step_done "user_services"; }
    step_skip "ssh_proxy_svc"  || { deploy_ssh_proxy_service;   step_done "ssh_proxy_svc"; }

    print_summary
}

main "$@"
