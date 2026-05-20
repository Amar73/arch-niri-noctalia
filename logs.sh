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

echo "===== ssh-proxy.service ====="
journalctl -b -u ssh-proxy.service -n 40 --no-pager || true
echo

echo "===== privoxy.service ====="
journalctl -b -u privoxy.service -n 20 --no-pager || true
echo

echo "===== failed units (system) ====="
systemctl --failed || true
echo

echo "===== failed units (user) ====="
systemctl --user --failed || true
