# syntax=docker/dockerfile:1
# Image de Legacy-RDV 2.4.0 (projet legacy/legacy-rdv) — F4-S12, CHG-3412. Reprend le Dockerfile de
# M12-E19 (Apache + mod_php sous www-data, port 8080, configuration par l'environnement, journaux sur
# les sorties) et ajoute : sessions en base (inc/sessions.php), sonde de disponibilité (pret.php),
# purge corrigée, mod_remoteip, fichiers SQL de migration (hors racine web), racine en lecture seule
# possible (répertoires d'exécution d'Apache et /tmp montés en emptyDir par Kubernetes).
#
#   La CI construit et signe : composant construction-image (BuildKit sans privilège), M19.

# Base officielle PHP 8.4 + Apache sur Debian 13, par le cache Harbor, épinglée par empreinte d'index.
# Empreinte à relever au moment de la construction (Renovate la tient à jour, M13-E11).
FROM docker.io/library/php:8.4-apache-trixie@sha256:<EMPREINTE-PHP-8.4-APACHE-TRIXIE>

RUN docker-php-ext-install -j"$(nproc)" mysqli

RUN cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"
COPY conteneur/php-legacy-rdv.ini "$PHP_INI_DIR/conf.d/legacy-rdv.ini"

COPY conteneur/apache-legacy-rdv.conf /etc/apache2/sites-available/legacy-rdv.conf
RUN sed -ri 's/^Listen 80$/Listen 8080/' /etc/apache2/ports.conf \
 && a2dissite 000-default \
 && a2ensite legacy-rdv \
 && a2enmod remoteip \
 && printf 'ServerTokens Prod\nServerSignature Off\n' > /etc/apache2/conf-available/medisphere.conf \
 && a2enconf medisphere

WORKDIR /var/www/legacy-rdv
COPY --chown=root:root *.php ./
COPY --chown=root:root inc/ inc/
COPY --chown=root:root cron/ cron/
COPY --chown=root:root sql/ sql/
COPY --chown=root:root uploads/LISEZMOI.txt uploads/
RUN install -d -o www-data -g www-data -m 0750 /var/www/legacy-rdv/uploads /var/lib/php/sessions

ARG VERSION=2.4.0
LABEL org.opencontainers.image.title="legacy-rdv" \
      org.opencontainers.image.description="Legacy-RDV : ancienne prise de rendez-vous (MédiSphère, héritée d'InfoGér)" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.source="https://git01.par1.medisphere.internal/legacy/legacy-rdv" \
      org.opencontainers.image.vendor="MédiSphère"

ENV LEGACY_RDV_LOG_FILE=php://stderr \
    LEGACY_RDV_AFFICHER_ERREURS=0 \
    LEGACY_RDV_UPLOAD_DIR=/var/www/legacy-rdv/uploads \
    LEGACY_RDV_VERSION=${VERSION}

USER 33:33
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD ["curl", "-fsS", "-o", "/dev/null", "http://127.0.0.1:8080/sante.php"]
STOPSIGNAL SIGWINCH
CMD ["apache2-foreground"]
