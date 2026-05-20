#!/usr/bin/env bash
# =============================================================================
# config.sh — централизованные переменные репозитория
#
# Источник истины для имени пользователя, путей и топологии.
# Подключается через: source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
#
# Переменные можно переопределить через окружение перед запуском скриптов:
#   REPO_USER=bob REPO_DIR=/home/bob/dotfiles make install
# =============================================================================

# Имя пользователя (по умолчанию — текущий)
REPO_USER="${REPO_USER:-${USER}}"

# Домашняя директория пользователя
REPO_HOME="${REPO_HOME:-$(eval echo "~${REPO_USER}")}"

# Корень репозитория (абсолютный путь, не зависит от cwd)
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# Директория files/ внутри репо
REPO_FILES="${REPO_ROOT}/files"

# Путь к репозиторию на целевой машине (используется в wallpaper kdl)
# По умолчанию: ~/Amar73/arch-niri (для совместимости),
# можно переопределить: INSTALLED_REPO_PATH=/home/bob/dotfiles make install
INSTALLED_REPO_PATH="${INSTALLED_REPO_PATH:-${REPO_HOME}/Amar73/arch-niri}"

# SSH-пользователь для VPS-туннеля
VPS_USER="${VPS_USER:-${REPO_USER}}"

# Экспортируем для дочерних процессов
export REPO_USER REPO_HOME REPO_ROOT REPO_FILES INSTALLED_REPO_PATH VPS_USER
