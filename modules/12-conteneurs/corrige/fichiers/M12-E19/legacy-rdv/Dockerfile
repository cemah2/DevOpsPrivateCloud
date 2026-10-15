# syntax=docker/dockerfile:1
# Image de Legacy-RDV 2.3.1 (projet legacy/legacy-rdv) — M12-E19, ticket DEV-1319.
# Apache + mod_php (prefork) comme sur la VM, mais : Apache sous www-data sur le port 8080,
# configuration par l'environnement, journaux sur les sorties du conteneur, pièces jointes et
# sessions dans des volumes. Le comportement de l'application ne change pas.
#
#   docker build -t legacy-rdv:2.3.1 .

# Image officielle PHP 8.4 + Apache (mod_php, prefork) sur Debian 13 : la même pile que la VM.
# Nom complet + étiquette + empreinte d'index (relevée le 2026-10-15).
FROM docker.io/library/php:8.4-apache-trixie@sha256:901b0dbcd2419cc9cd307ea05e57403449ce722ccd5b32335da6e8d39f2b1ee0

# Extension mysqli (absente de l'image officielle) ; fileinfo, mbstring et session y sont déjà.
# docker-php-ext-install compile et active l'extension, puis nettoie les sources.
RUN docker-php-ext-install -j"$(nproc)" mysqli

# Réglages PHP de production de l'image, puis les nôtres.
RUN cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"
COPY conteneur/php-legacy-rdv.ini "$PHP_INI_DIR/conf.d/legacy-rdv.ini"

# Apache : port 8080, notre hôte virtuel seul, pas de signature de version.
COPY conteneur/apache-legacy-rdv.conf /etc/apache2/sites-available/legacy-rdv.conf
RUN sed -ri 's/^Listen 80$/Listen 8080/' /etc/apache2/ports.conf \
 && a2dissite 000-default \
 && a2ensite legacy-rdv \
 && printf 'ServerTokens Prod\nServerSignature Off\n' > /etc/apache2/conf-available/medisphere.conf \
 && a2enconf medisphere

# Le code appartient à root (lecture seule pour www-data) ; seuls les répertoires de données
# appartiennent à www-data : ils seront des volumes. On copie le CODE, pas le dépôt : ni vm/, ni
# conteneur/, ni schema.sql dans la racine du site.
WORKDIR /var/www/legacy-rdv
COPY --chown=root:root *.php ./
COPY --chown=root:root inc/ inc/
COPY --chown=root:root cron/ cron/
COPY --chown=root:root uploads/LISEZMOI.txt uploads/
RUN install -d -o www-data -g www-data -m 0750 /var/www/legacy-rdv/uploads /var/lib/php/sessions

ARG VERSION=2.3.1
LABEL org.opencontainers.image.title="legacy-rdv" \
      org.opencontainers.image.description="Legacy-RDV : ancienne prise de rendez-vous (MédiSphère, héritée d'InfoGér)" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.source="https://git01.par1.medisphere.internal/legacy/legacy-rdv" \
      org.opencontainers.image.vendor="MédiSphère"

# Valeurs propres au conteneur (les autres gardent leur défaut de config.php).
ENV LEGACY_RDV_LOG_FILE=php://stderr \
    LEGACY_RDV_AFFICHER_ERREURS=0 \
    LEGACY_RDV_UPLOAD_DIR=/var/www/legacy-rdv/uploads

VOLUME ["/var/www/legacy-rdv/uploads", "/var/lib/php/sessions"]
USER 33:33
EXPOSE 8080
# Sonde qui ne touche pas à la base (sante.php) ; curl est présent dans l'image officielle.
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD ["curl", "-fsS", "-o", "/dev/null", "http://127.0.0.1:8080/sante.php"]
# apache2-foreground (script de l'image) fait « exec apache2 -DFOREGROUND » : Apache est le PID 1.
# Arrêt « gracieux » d'Apache : SIGWINCH (l'image officielle le déclare déjà ; on le répète).
STOPSIGNAL SIGWINCH
CMD ["apache2-foreground"]
