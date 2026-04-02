#!/usr/bin/env bash
set -Eeuo pipefail

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
for cmd in niri niri-session alacritty fuzzel mako waybar swayidle swaylock wl-paste cliphist tuigreet nwg-look qt6ct ssh keychain yay btop; do
  check_cmd "$cmd"
done

echo
echo "=== package checks ==="
for pkg in \
  niri greetd greetd-tuigreet alacritty fuzzel mako waybar swayidle swaylock btop \
  wl-clipboard cliphist xdg-desktop-portal xdg-desktop-portal-wlr \
  qt6ct kvantum nwg-look noto-fonts papirus-icon-theme \
  keychain openssh; do
  if pacman -Q "$pkg" >/dev/null 2>&1; then
    ok "package: $pkg"
  else
    fail "package missing: $pkg"
  fi
done

# ИСПРАВЛЕНО v6.3: qt5-wayland переведён в warn —
# в Arch 2026 пакет может быть частью qt5-base или отсутствовать отдельно.
# Падение не должно ломать check.
echo
echo "=== qt5-wayland (optional) ==="
if pacman -Q qt5-wayland >/dev/null 2>&1; then
  ok "package: qt5-wayland"
else
  warn "qt5-wayland не найден как отдельный пакет — возможно включён в qt5-base, это нормально"
fi

echo
echo "=== AUR packages ==="
pacman -Q bibata-cursor-theme >/dev/null 2>&1 \
  && ok "package: bibata-cursor-theme (AUR)" \
  || warn "package missing: bibata-cursor-theme — установи: yay -S bibata-cursor-theme"

echo
echo "=== config files ==="
for f in \
  /etc/greetd/config.toml \
  "$HOME/.bashrc" \
  "$HOME/.ssh/config" \
  "$HOME/.config/niri/config.kdl" \
  "$HOME/.config/niri/conf.d/keymap.xkb" \
  "$HOME/.config/alacritty/alacritty.toml" \
  "$HOME/.config/waybar/config.jsonc" \
  "$HOME/.config/waybar/style.css" \
  "$HOME/.config/swaylock/config" \
  "$HOME/.config/systemd/user/swayidle.service" \
  "$HOME/.config/systemd/user/cliphist-text.service" \
  "$HOME/.config/systemd/user/cliphist-images.service" \
  "$HOME/.config/mako/config" \
  "$HOME/.config/fuzzel/fuzzel.ini" \
  "$HOME/.config/qt6ct/qt6ct.conf" \
  "$HOME/.config/gtk-3.0/settings.ini" \
  "$HOME/.config/gtk-4.0/settings.ini"; do
  [[ -f "$f" ]] && ok "file: $f" || fail "missing file: $f"
done

echo
echo "=== syntax checks ==="
if bash -n "$HOME/.bashrc" >/dev/null 2>&1; then
  ok "bashrc syntax valid"
else
  fail "bashrc syntax invalid"
fi

if ssh -G github.com >/dev/null 2>&1; then
  ok "ssh config parses"
else
  fail "ssh config parse failed"
fi

echo
echo "=== system services ==="
systemctl is-enabled NetworkManager.service >/dev/null 2>&1 && ok "NetworkManager enabled" || warn "NetworkManager not enabled"
systemctl is-enabled seatd.service          >/dev/null 2>&1 && ok "seatd enabled"          || warn "seatd not enabled"
systemctl is-enabled greetd.service         >/dev/null 2>&1 && ok "greetd enabled"         || warn "greetd not enabled"

echo
echo "=== user services ==="
systemctl --user is-enabled swayidle.service        >/dev/null 2>&1 && ok "swayidle.service enabled"        || warn "swayidle.service not enabled"
systemctl --user is-enabled cliphist-text.service   >/dev/null 2>&1 && ok "cliphist-text.service enabled"   || warn "cliphist-text.service not enabled"
systemctl --user is-enabled cliphist-images.service >/dev/null 2>&1 && ok "cliphist-images.service enabled" || warn "cliphist-images.service not enabled"

echo
echo "=== niri config validation ==="
if niri validate >/dev/null 2>&1; then
  ok "niri config valid"
else
  fail "niri config invalid"
fi

echo
echo "=== niri keyboard layouts ==="
if niri msg --json keyboard-layouts >/dev/null 2>&1; then
  niri msg --json keyboard-layouts | jq -r \
    '"Layouts: " + ([.keyboard_layouts.layouts[].name] | join(", ")) +
     "\nActive:  " + .keyboard_layouts.layouts[.keyboard_layouts.current_idx].name'
  ok "keyboard-layouts IPC работает"
else
  warn "niri msg --json keyboard-layouts недоступен — запущен ли niri?"
fi
