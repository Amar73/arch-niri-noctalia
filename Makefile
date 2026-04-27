SHELL := /usr/bin/env bash

.PHONY: install check check-local sync logs backup dots dots-local validate reload update outputs packages ssh-config claude-proxy claude-check

install:
	./install.sh

check:
	./post-install-check.sh

check-local:
	./check-local.sh

sync:
	./sync.sh

logs:
	./logs.sh

backup:
	./backup.sh

dots:
	./bootstrap-dotfiles.sh

dots-local:
	./bootstrap-dotfiles.sh --local

validate:
	niri validate

reload:
	niri msg action load-config-file || true

update:
	./update.sh

outputs:
	./deploy-outputs.sh

packages:
	./install-packages.sh

ssh-config:
	./deploy-ssh-config.sh

claude-proxy:
	./deploy-claude-proxy.sh

claude-check:
	./deploy-claude-proxy.sh --check-only
