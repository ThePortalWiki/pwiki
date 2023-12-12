#!/usr/bin/env bash

set -euo pipefail

if [ "$(whoami)" != root ]; then
	echo 'Run me as root.' >&2
	exit 1
fi

rotate_nginx_log() {
	rm -f /var/log/nginx/access.log.bak || true
	mv /var/log/nginx/access.log /var/log/nginx/access.log.bak
	systemctl restart nginx
}

vaccuum_systemd_journal() {
	journalctl --vacuum-size=$((10 * 1024 * 1024))
}

rotate_pacman_cache() {
	bash -c 'rm -rf /var/cache/pacman/pkg/*.bak' || true
	bash -c 'for f in /var/cache/pacman/pkg/*.tar.*; do mv "$f" "$f.bak"; done'
}

docker_prune() {
	docker system prune --all --force --volumes
}

rotate_nginx_log || true
vaccuum_systemd_journal || true
rotate_pacman_cache || true
docker_prune || true
