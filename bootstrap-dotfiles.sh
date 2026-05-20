#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${ROOT_DIR}/config.sh"

FILES_DIR="${REPO_FILES}/home"
MODE="${1:-}"

backup_if_exists() {
    local path="$1"
    if [[ -e "$path" && ! -L "$path" ]]; then
        local stamp; stamp="$(date +%F-%H%M%S)"
        cp -a "$path" "${path}.bak.${stamp}"
    fi
}

deploy_local() {
    echo "[*] Deploy local .bashrc and .ssh/config from repo"
    mkdir -p "${REPO_HOME}/.ssh"
    chmod 700 "${REPO_HOME}/.ssh"
    backup_if_exists "${REPO_HOME}/.bashrc"
    backup_if_exists "${REPO_HOME}/.ssh/config"
    install -m 644 "${FILES_DIR}/.bashrc" "${REPO_HOME}/.bashrc"
    install -m 600 "${FILES_DIR}/.ssh/config" "${REPO_HOME}/.ssh/config"
    bash -n "${REPO_HOME}/.bashrc"
    ssh -G github.com >/dev/null
    echo "[OK] Local dotfiles deployed"
}

if [[ "$MODE" == "--local" ]]; then
    deploy_local
    exit 0
fi

if [[ -z "${MODE}" ]]; then
    echo "Usage:"
    echo "  $0 --local"
    echo "  $0 <git@github.com:USER/dotfiles.git>"
    exit 1
fi

REPO_URL="$MODE"
TARGET_DIR="${REPO_HOME}/src/dotfiles"
mkdir -p "${REPO_HOME}/src"

if [[ -d "${TARGET_DIR}/.git" ]]; then
    echo "[*] Repo already exists, pulling updates"
    git -C "${TARGET_DIR}" pull --ff-only
else
    echo "[*] Cloning dotfiles"
    git clone "${REPO_URL}" "${TARGET_DIR}"
fi

if [[ -x "${TARGET_DIR}/install.sh" ]]; then
    echo "[*] Running dotfiles install.sh"
    (cd "${TARGET_DIR}" && ./install.sh)
else
    echo "[WARN] ${TARGET_DIR}/install.sh not found or not executable"
fi
