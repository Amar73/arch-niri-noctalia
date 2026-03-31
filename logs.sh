#!/usr/bin/env bash
set -Eeuo pipefail

echo "===== greetd ====="
journalctl -b -u greetd -n 80 --no-pager || true
echo

echo "===== waybar ====="
journalctl --user -b -u waybar -n 80 --no-pager || true
echo

echo "===== swayidle.service ====="
journalctl --user -b -u swayidle.service -n 80 --no-pager || true
echo

echo "===== cliphist-text.service ====="
journalctl --user -b -u cliphist-text.service -n 80 --no-pager || true
echo

echo "===== cliphist-images.service ====="
journalctl --user -b -u cliphist-images.service -n 80 --no-pager || true
echo

echo "===== failed units ====="
systemctl --failed || true
systemctl --user --failed || true
