#!/usr/bin/env bash
# =============================================================================
# check-local.sh — локальная проверка без pacman/systemctl
# Безопасна в контейнере, CI, на не-Arch окружении.
# Проверяет: синтаксис bash-скриптов + наличие всех файлов репо.
#
# make check       — полная боевая проверка (требует Arch + живые сервисы)
# make check-local — только синтаксис и структура, работает везде
# =============================================================================
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES_DIR="${ROOT_DIR}/files"

ok()   { printf '[OK]   %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*"; ERRORS=$((ERRORS+1)); }

ERRORS=0

# --------------------------------------------------------------------------
# 1. Синтаксис bash-скриптов
# --------------------------------------------------------------------------
echo "=== bash syntax ==="
SCRIPTS=(
    install.sh sync.sh update.sh logs.sh backup.sh
    bootstrap-dotfiles.sh post-install-check.sh check-local.sh
    deploy-outputs.sh deploy-ssh-config.sh deploy-claude-proxy.sh
    install-packages.sh config.sh
)
for script in "${SCRIPTS[@]}"; do
    f="${ROOT_DIR}/${script}"
    if [[ ! -f "$f" ]]; then
        fail "missing script: $script"
        continue
    fi
    if bash -n "$f" 2>/dev/null; then
        ok "syntax: $script"
    else
        fail "syntax error: $script"
        bash -n "$f" || true
    fi
done

# --------------------------------------------------------------------------
# 2. Наличие файлов в репо (files/)
# --------------------------------------------------------------------------
echo
echo "=== repo files ==="
expected_files=(
    "etc/greetd/config.toml"
    "etc/systemd/system/ssh-proxy.service"
    "home/.bashrc"
    "home/.ssh/config"
    "home/.config/niri/config.kdl"
    "home/.config/niri/conf.d/10-input.kdl"
    "home/.config/niri/conf.d/20-layout.kdl"
    "home/.config/niri/conf.d/30-environment.kdl"
    "home/.config/niri/conf.d/40-startup.kdl"
    "home/.config/niri/conf.d/50-binds.kdl"
    "home/.config/niri/conf.d/keymap.xkb"
    "home/.config/niri/outputs/amar224.kdl"
    "home/.config/niri/outputs/amar319.kdl"
    "home/.config/niri/outputs/amar319-1.kdl"
    "home/.config/niri/outputs/default.kdl"
    "home/.config/alacritty/alacritty.toml"
    "home/.config/waybar/config.jsonc"
    "home/.config/waybar/style.css"
    "home/.config/swaylock/config"
    "home/.config/mako/config"
    "home/.config/fuzzel/fuzzel.ini"
    "home/.config/qt6ct/qt6ct.conf"
    "home/.config/gtk-3.0/settings.ini"
    "home/.config/gtk-4.0/settings.ini"
    "home/.config/systemd/user/swayidle.service"
    "home/.config/systemd/user/cliphist-text.service"
    "home/.config/systemd/user/cliphist-images.service"
    "home/.config/mc/ini"
    "home/bin/claude"
)

for rel in "${expected_files[@]}"; do
    f="${FILES_DIR}/${rel}"
    if [[ -f "$f" ]]; then
        ok "file: files/$rel"
    else
        fail "missing: files/$rel"
    fi
done

# --------------------------------------------------------------------------
# 3. Makefile — наличие ключевых целей
# --------------------------------------------------------------------------
echo
echo "=== makefile targets ==="
TARGETS=(
    install check check-local sync update logs backup
    dots dots-local validate reload outputs packages
    ssh-config claude-proxy claude-check
)
for target in "${TARGETS[@]}"; do
    if grep -q "^${target}:" "${ROOT_DIR}/Makefile"; then
        ok "target: $target"
    else
        fail "missing target: $target"
    fi
done

# --------------------------------------------------------------------------
# 4. config.sh — переменные определены
# --------------------------------------------------------------------------
echo
echo "=== config.sh ==="
if [[ -f "${ROOT_DIR}/config.sh" ]]; then
    # Проверяем что ключевые переменные присутствуют
    for var in REPO_USER REPO_HOME REPO_ROOT REPO_FILES INSTALLED_REPO_PATH VPS_USER; do
        if grep -q "$var" "${ROOT_DIR}/config.sh"; then
            ok "config.sh: $var defined"
        else
            fail "config.sh: $var missing"
        fi
    done
else
    fail "config.sh not found"
fi

# --------------------------------------------------------------------------
# 5. Проверка что hardcode /home/amar не проник в скрипты
#    (в files/ допускается только в .ssh/config как пример)
# --------------------------------------------------------------------------
echo
echo "=== no hardcoded /home/amar in scripts ==="
# Ищем /home/amar в НЕкомментарных строках рабочих скриптов.
# check-local.sh и post-install-check.sh исключены — они содержат
# этот паттерн как поисковую строку, а не как реальный путь.
found=$(grep -rn "/home/amar" "${ROOT_DIR}" \
    --include="*.sh" \
    --include="Makefile" \
    2>/dev/null \
    | grep -v ':#\s*' \
    | grep -v ':\s*#' \
    | grep -v 'grep' \
    | grep -v 'check-local.sh' \
    | grep -v 'post-install-check.sh' \
    | cut -d: -f1 | sort -u || true)
if [[ -z "$found" ]]; then
    ok "Нет /home/amar хардкода в рабочих скриптах"
else
    fail "/home/amar hardcode найден в скриптах: $found"
fi

# --------------------------------------------------------------------------
# 6. Проверка что hardcode /home/amar не проник в kdl/конфиги
#    (допускается в files/home/.ssh/config как пример, но не в kdl)
# --------------------------------------------------------------------------
echo
echo "=== no hardcoded /home/amar in kdl/config files ==="
found_kdl=$(grep -r "/home/amar" "${ROOT_DIR}/files" \
    --include="*.kdl" \
    --include="*.toml" \
    --include="*.jsonc" \
    --include="*.css" \
    --include="*.ini" \
    -l 2>/dev/null || true)
if [[ -z "$found_kdl" ]]; then
    ok "Нет /home/amar хардкода в kdl/config файлах"
else
    fail "/home/amar hardcode в kdl/config: $found_kdl"
fi

# --------------------------------------------------------------------------
# Итог
# --------------------------------------------------------------------------
echo
if [[ $ERRORS -eq 0 ]]; then
    echo "[OK] check-local passed — $ERRORS errors"
else
    echo "[FAIL] check-local failed — ${ERRORS} error(s)"
    exit 1
fi
