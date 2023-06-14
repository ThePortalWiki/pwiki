FROM pwiki-mariadb:pwiki-mariadb

ARG BACKUP_UIDGID

RUN apt-get update && apt-get install -y sudo xz-utils
RUN mkdir /backups && touch /backups/no-volume && chmod 700 /backups

COPY setup-env.sh /setup-env.sh
RUN chmod 555 /setup-env.sh && /setup-env.sh && rm /setup-env.sh

COPY backup.sh /backup.sh
RUN chmod 555 /backup.sh
ENTRYPOINT ["/backup.sh"]
CMD []
