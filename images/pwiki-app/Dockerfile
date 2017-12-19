FROM php:5-fpm

ARG REBUILD=1

RUN apt-get update && apt-get upgrade -y

ARG WIKI_UIDGID=1000:1000
COPY setup-wiki.sh /
RUN chmod 555 /setup-wiki.sh && /setup-wiki.sh && rm /setup-wiki.sh

ARG MEDIAWIKI_RELEASE
COPY extra /extra
RUN chown -R pwiki:pwiki /extra
COPY install-mediawiki.sh extra-keys.asc /
RUN chmod 555 /install-mediawiki.sh && sudo -u pwiki --preserve-env --set-home /install-mediawiki.sh && rm /install-mediawiki.sh /extra-keys.asc
RUN rm -rf --one-file-system /extra

# Volume handling.
RUN mkdir /pwiki-secrets /home/pwiki/www/w/images /home/pwiki/www-private/cache && touch /pwiki-secrets/no-volume /home/pwiki/www/w/images/no-volume && chown pwiki:pwiki /home/pwiki/www/w/images /home/pwiki/www-private/cache
VOLUME /home/pwiki/www-private/cache

COPY pwiki-app.sh /pwiki-app.sh
RUN chmod 555 /pwiki-app.sh
WORKDIR /home/pwiki/www
ENTRYPOINT /pwiki-app.sh
