FROM mariadb:10

RUN mkdir /pwiki-secrets && touch /pwiki-secrets/no-volume && chmod 700 /pwiki-secrets
RUN mkdir -p /var/lib/mysql && touch /var/lib/mysql/no-volume
COPY pwiki-mariadb.sh /pwiki-mariadb.sh
RUN chmod 555 /pwiki-mariadb.sh
USER root
ENTRYPOINT /pwiki-mariadb.sh
