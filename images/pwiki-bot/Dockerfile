FROM python:2.7.18

RUN apt-get update && apt-get install -y socat
COPY mrgusty /mrgusty
RUN mkdir /botConfig \
    && echo 'import sys; print("botConfig.py not mounted"); sys.exit(1)' > /botConfig/botConfig.py \
    && ln -s /botConfig/botConfig.py /mrgusty/botConfig.py
CMD ["bash", "-c", "if [[ ! -e /wiki.sock ]]; then echo 'Missing /wiki.sock' >&2 ; fi; socat TCP-LISTEN:3333,bind=127.0.0.1,reuseaddr,fork,range=127.0.0.0/8 UNIX-CLIENT:/wiki.sock & sleep 3 && python2 /mrgusty/bot.py"]
