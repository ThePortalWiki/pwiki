# https://github.com/TecharoHQ/anubis/pkgs/container/anubis/versions
# Note: Need to replace the ":sha256-" with "@sha256:".
FROM ghcr.io/techarohq/anubis@sha256:865cf92aa260ce85017dea6e8230cd43e02024d38863016d8c33bf62592c3647

USER root

# https://anubis.techaro.lol/docs/admin/installation
ENV BIND=:3888
ENV BIND_NETWORK=tcp
ENV OG_PASSTHROUGH=true
ENV SERVE_ROBOTS_TXT=false
ENV TARGET=unix:///run/pwiki/wiki.sock
