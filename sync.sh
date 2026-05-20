#!/usr/bin/env bash
set -Eeuo pipefail

# =============================================================================
# sync.sh — синхронизация конфигов из репо в систему
#
# ВАЖНО: перед синхронизацией автоматически создаётся бэкап через backup.sh
# Синхронизируются только конкретные поддиректории ~/.config/ — не весь каталог.
# =============================================================================

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${ROOT_DIR}/config.sh"

FILES_DIR="${REPO_FILES}"

die()  { printf '\n[ERROR] %s\n' "$*" >&2; exit 1; }
log()  { printf '\n[%s] %s\n' "$(date +'%F %T')" "$*"; }
ok()   { printf '[OK]   %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; }

backup_if_exists() {
    local path="$1"
    if [[ -e "$path" && ! -L "$path" ]]; then
        local stamp; stamp="$(date +%F-%H%M%S)"
        cp -a "$path" "${path}.bak.${stamp}"
        ok "Бэкап: ${path}.bak.${stamp}"
    fi
}

# -----------------------------------------------------------------------------
# Бэкап перед изменениями
# -----------------------------------------------------------------------------
log "Создание бэкапа перед синхронизацией"
bash "${ROOT_DIR}/backup.sh"

# -----------------------------------------------------------------------------
# niri-start wrapper
# -----------------------------------------------------------------------------
log "Sync /usr/local/bin/niri-start"
if [[ ! -f /usr/local/bin/niri-start ]]; then
    sudo tee /usr/local/bin/niri-start > /dev/null << 'EOF'
#!/bin/bash
exec dbus-run-session niri
EOF
    sudo chmod +x /usr/local/bin/niri-start
    ok "niri-start создан"
else
    ok "niri-start уже существует"
fi

# -----------------------------------------------------------------------------
# /etc/greetd
# -----------------------------------------------------------------------------
log "Sync /etc/greetd"
sudo install -d -m 755 /etc/greetd
sudo rsync -a --delete "${FILES_DIR}/etc/greetd/" /etc/greetd/

# -----------------------------------------------------------------------------
# ~/.config — ТОЛЬКО конкретные директории (не весь ~/.config/)
# -----------------------------------------------------------------------------
log "Sync ~/.config (selective)"
config_src="${FILES_DIR}/home/.config"
config_dst="${REPO_HOME}/.config"

[[ -d "$config_src" ]] || die "Директория конфигов не найдена: $config_src"
mkdir -p "${config_dst}"

sync_dirs=(niri waybar alacritty swaylock mako fuzzel mc qt6ct gtk-3.0 gtk-4.0 systemd)
for dir in "${sync_dirs[@]}"; do
    if [[ -d "${config_src}/${dir}" ]]; then
        rsync -a --delete \
            "${config_src}/${dir}/" \
            "${config_dst}/${dir}/"
        ok "Synced: ~/.config/${dir}"
    fi
done

# -----------------------------------------------------------------------------
# alacritty themes
# -----------------------------------------------------------------------------
log "Update alacritty themes"
_themes_dir="${config_dst}/alacritty/themes"
if [[ -d "${_themes_dir}/.git" ]]; then
    git -C "${_themes_dir}" pull --ff-only \
        && ok "alacritty-theme обновлены" \
        || warn "Не удалось обновить alacritty-theme"
else
    mkdir -p "${_themes_dir}"
    git clone https://github.com/alacritty/alacritty-theme "${_themes_dir}" \
        && ok "alacritty-theme установлены" \
        || warn "Не удалось клонировать alacritty-theme"
fi

# -----------------------------------------------------------------------------
# .bashrc и .ssh/config
# -----------------------------------------------------------------------------
log "Sync ~/.bashrc и ~/.ssh/config"
mkdir -p "${REPO_HOME}/.ssh"
chmod 700 "${REPO_HOME}/.ssh"
backup_if_exists "${REPO_HOME}/.bashrc"
backup_if_exists "${REPO_HOME}/.ssh/config"
install -m 644 "${FILES_DIR}/home/.bashrc"     "${REPO_HOME}/.bashrc"
install -m 600 "${FILES_DIR}/home/.ssh/config"  "${REPO_HOME}/.ssh/config"

# -----------------------------------------------------------------------------
# ~/bin/claude wrapper (генерируем с правильным HOME)
# -----------------------------------------------------------------------------
log "Sync ~/bin/claude wrapper"
mkdir -p "${REPO_HOME}/bin"
cat > "${REPO_HOME}/bin/claude" << EOF
#!/bin/bash
# Wrapper для Claude Code — проксирование через privoxy → SSH SOCKS5 туннель
export HTTPS_PROXY="http://127.0.0.1:8118"
exec "\${HOME}/.local/bin/claude" "\$@"
EOF
chmod 755 "${REPO_HOME}/bin/claude"
ok "claude wrapper задеплоен"

# -----------------------------------------------------------------------------
# ~/.local/bin/set-wallpapers (генерируем с реальными путями)
# -----------------------------------------------------------------------------
log "Sync set-wallpapers"
mkdir -p "${REPO_HOME}/.local/bin"
local_wallpapers_path="${INSTALLED_REPO_PATH}/Wallpapers"
cat > "${REPO_HOME}/.local/bin/set-wallpapers" << EOF
#!/bin/bash
# set-wallpapers — обои для amar224 (3 монитора DP-2, DP-3, DP-4)
# Сгенерирован sync.sh для пользователя ${REPO_USER}
pkill swaybg 2>/dev/null || true
exec swaybg \\
  -o DP-2 -i ${local_wallpapers_path}/arch.jpeg    -m fill \\
  -o DP-3 -i ${local_wallpapers_path}/arch3.jpeg   -m fill \\
  -o DP-4 -i ${local_wallpapers_path}/wallpaper.jpg -m fill
EOF
chmod 755 "${REPO_HOME}/.local/bin/set-wallpapers"
ok "set-wallpapers сгенерирован"

# -----------------------------------------------------------------------------
# Перезагрузка user-юнитов и сервисов
# -----------------------------------------------------------------------------
log "Reload user units"
systemctl --user daemon-reload

log "Restart user services"
for svc in waybar cliphist-text cliphist-images; do
    if systemctl --user is-enabled "${svc}.service" >/dev/null 2>&1; then
        systemctl --user restart "${svc}.service" \
            && ok "restarted: $svc" \
            || warn "failed to restart: $svc"
    fi
done

# swayidle управляется через niri spawn-at-startup — не перезапускаем через systemd
warn "swayidle управляется через niri spawn-at-startup. Для применения: make reload"

# -----------------------------------------------------------------------------
# Проверки
# -----------------------------------------------------------------------------
log "Check failed units"
failed=$(systemctl --user --failed --no-legend 2>/dev/null | awk '{print $1}' | tr '\n' ' ')
if [[ -n "$failed" ]]; then
    warn "Failed user units: $failed"
else
    ok "No failed user units"
fi

log "Validate niri config"
niri validate || warn "niri validate не прошёл — проверь конфиг"

log "Validate bashrc"
bash -n "${REPO_HOME}/.bashrc" && ok "bashrc: синтаксис OK"

log "Validate ssh config"
ssh -G github.com >/dev/null && ok "ssh config: валиден"

# -----------------------------------------------------------------------------
# Deploy outputs, wallpapers, ssh config
# -----------------------------------------------------------------------------
log "Deploy outputs config"
bash "${ROOT_DIR}/deploy-outputs.sh"

log "Deploy ssh config"
bash "${ROOT_DIR}/deploy-ssh-config.sh"

ok "=== Sync done ==="
