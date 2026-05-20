#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${ROOT_DIR}/config.sh"

ok()   { printf '[OK]   %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*"; }

check_cmd() {
    local cmd="$1"
    if command -v "$cmd" >/dev/null 2>&1; then
        ok "command: $cmd"
    else
        fail "command missing: $cmd"
    fi
}

echo "=== commands ==="
for cmd in niri niri-session alacritty fuzzel mako waybar swayidle swaylock \
           wl-paste cliphist tuigreet nwg-look qt6ct ssh keychain yay btop jq pulsemixer \
           autossh privoxy; do
    check_cmd "$cmd"
done

echo
echo "=== package checks ==="
for pkg in \
    niri greetd greetd-tuigreet alacritty fuzzel mako waybar swayidle swaylock btop jq \
    wl-clipboard cliphist xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk \
    pipewire wireplumber pipewire-pulse pulsemixer \
    qt6ct kvantum nwg-look noto-fonts papirus-icon-theme \
    keychain openssh autossh privoxy; do
    if pacman -Q "$pkg" >/dev/null 2>&1; then
        ok "package: $pkg"
    else
        fail "package missing: $pkg"
    fi
done

echo
echo "=== optional packages ==="
pacman -Q qt5-wayland >/dev/null 2>&1 \
    && ok "package: qt5-wayland" \
    || warn "qt5-wayland не найден отдельно — возможно в qt5-base, это нормально"

echo
echo "=== AUR packages ==="
pacman -Q bibata-cursor-theme >/dev/null 2>&1 \
    && ok "package: bibata-cursor-theme (AUR)" \
    || warn "bibata-cursor-theme не найден — установи: yay -S bibata-cursor-theme"

echo
echo "=== config files ==="
for f in \
    /etc/greetd/config.toml \
    "${REPO_HOME}/.bashrc" \
    "${REPO_HOME}/.ssh/config" \
    "${REPO_HOME}/.config/niri/config.kdl" \
    "${REPO_HOME}/.config/niri/conf.d/keymap.xkb" \
    "${REPO_HOME}/.config/niri/conf.d/45-wallpaper.kdl" \
    "${REPO_HOME}/.config/niri/conf.d/60-outputs.kdl" \
    "${REPO_HOME}/.config/alacritty/alacritty.toml" \
    "${REPO_HOME}/.config/waybar/config.jsonc" \
    "${REPO_HOME}/.config/waybar/style.css" \
    "${REPO_HOME}/.config/swaylock/config" \
    "${REPO_HOME}/.config/systemd/user/swayidle.service" \
    "${REPO_HOME}/.config/systemd/user/cliphist-text.service" \
    "${REPO_HOME}/.config/systemd/user/cliphist-images.service" \
    "${REPO_HOME}/.config/mako/config" \
    "${REPO_HOME}/.config/fuzzel/fuzzel.ini" \
    "${REPO_HOME}/.config/qt6ct/qt6ct.conf" \
    "${REPO_HOME}/.config/gtk-3.0/settings.ini" \
    "${REPO_HOME}/.config/gtk-4.0/settings.ini"; do
    [[ -f "$f" ]] && ok "file: $f" || fail "missing file: $f"
done

echo
echo "=== generated files check ==="
# Проверяем что сгенерированные файлы не содержат /home/amar
for f in \
    "${REPO_HOME}/.config/niri/conf.d/45-wallpaper.kdl" \
    "${REPO_HOME}/.local/bin/set-wallpapers" \
    "${REPO_HOME}/bin/claude" \
    /etc/systemd/system/ssh-proxy.service; do
    if [[ -f "$f" ]]; then
        if grep -q "/home/amar" "$f" 2>/dev/null; then
            warn "Возможный хардкод /home/amar в: $f"
        else
            ok "Нет хардкода: $f"
        fi
    fi
done

echo
echo "=== syntax checks ==="
bash -n "${REPO_HOME}/.bashrc" >/dev/null 2>&1 \
    && ok "bashrc syntax valid" || fail "bashrc syntax invalid"

ssh -G github.com >/dev/null 2>&1 \
    && ok "ssh config parses" || fail "ssh config parse failed"

echo
echo "=== system services ==="
systemctl is-enabled NetworkManager.service >/dev/null 2>&1 \
    && ok "NetworkManager enabled" || warn "NetworkManager not enabled"
systemctl is-enabled seatd.service >/dev/null 2>&1 \
    && ok "seatd enabled" || warn "seatd not enabled"
systemctl is-enabled greetd.service >/dev/null 2>&1 \
    && ok "greetd enabled" || warn "greetd not enabled"

echo
echo "=== user services ==="
# swayidle намеренно НЕ включён через systemd (управляется spawn-at-startup)
systemctl --user is-enabled swayidle.service >/dev/null 2>&1 \
    && warn "swayidle.service enabled через systemd — должен управляться через niri spawn-at-startup" \
    || ok "swayidle.service: управляется через niri spawn-at-startup (OK)"

systemctl --user is-enabled cliphist-text.service >/dev/null 2>&1 \
    && ok "cliphist-text.service enabled" \
    || warn "cliphist-text.service not enabled"
systemctl --user is-enabled cliphist-images.service >/dev/null 2>&1 \
    && ok "cliphist-images.service enabled" \
    || warn "cliphist-images.service not enabled"

echo
echo "=== claude code ==="
systemctl is-enabled ssh-proxy.service >/dev/null 2>&1 \
    && ok "ssh-proxy.service enabled" \
    || warn "ssh-proxy.service не включён — запусти: make claude-proxy"

systemctl is-active ssh-proxy.service >/dev/null 2>&1 \
    && ok "ssh-proxy.service active" \
    || warn "ssh-proxy.service не запущен"

systemctl is-active privoxy.service >/dev/null 2>&1 \
    && ok "privoxy.service active" \
    || warn "privoxy.service не запущен"

[[ -x "${REPO_HOME}/bin/claude" ]] \
    && ok "~/bin/claude wrapper exists" \
    || warn "~/bin/claude не найден — запусти: make claude-proxy"

[[ -x "${REPO_HOME}/.local/bin/claude" ]] \
    && ok "claude: $("${REPO_HOME}/.local/bin/claude" --version 2>/dev/null || echo 'установлен')" \
    || warn "Claude Code не установлен — запусти: make claude-proxy"

echo
echo "=== niri-start wrapper ==="
if [[ -x /usr/local/bin/niri-start ]]; then
    ok "/usr/local/bin/niri-start exists and executable"
else
    fail "/usr/local/bin/niri-start missing — запусти: make sync"
fi
niri validate >/dev/null 2>&1 \
    && ok "niri config valid" || fail "niri config invalid"

echo
echo "=== niri keyboard layouts ==="
if niri msg --json keyboard-layouts >/dev/null 2>&1; then
    _kl_json="$(niri msg --json keyboard-layouts 2>/dev/null)"
    # Поддерживаем текущий формат: {"names":[...],"current_idx":N}
    _names=$(echo "$_kl_json" | jq -r '.names[]?' 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
    _idx=$(echo "$_kl_json" | jq -r '.current_idx?' 2>/dev/null)
    if [[ -n "$_names" ]]; then
        ok "Layouts: ${_names}"
        ok "Active:  $(echo "$_kl_json" | jq -r ".names[${_idx}]?" 2>/dev/null)"
    else
        warn "Нераспознанный формат keyboard-layouts: $_kl_json"
    fi
    ok "keyboard-layouts IPC работает"
else
    warn "niri msg --json keyboard-layouts недоступен — запущен ли niri?"
fi
