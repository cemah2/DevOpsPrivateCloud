FROM debian:trixie-slim

RUN apt-get update && apt-get upgrade -y && apt-get install -y postgresql-client cron awscli sudo
COPY sauvegarde.sh /usr/local/bin/sauvegarde.sh
RUN echo "0 2 * * * root /usr/local/bin/sauvegarde.sh" > /etc/cron.d/sauvegarde
RUN echo "root:Lucas2026" | chpasswd

USER root
CMD cron -f
