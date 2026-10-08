#!/usr/bin/env bash
# verifier-tls-vip.sh — M10-E27 : émetteur, sujet, dates et empreinte du certificat servi par
# chaque VIP (avant/après renouvellement). Lecture seule, depuis adm01.
set -euo pipefail

RACINE=/usr/local/share/ca-certificates/medisphere-root-ca.crt
for point in openstack.par1.medisphere.internal:443 openstack.par1.medisphere.internal:5000 \
             openstack-int.par1.medisphere.internal:5000; do
  nom="${point%:*}"
  echo "== $point"
  openssl s_client -connect "$point" -servername "$nom" -CAfile "$RACINE" -verify_hostname "$nom" \
    -verify_return_error </dev/null 2>/dev/null \
    | openssl x509 -noout -issuer -subject -startdate -enddate -fingerprint -sha256 \
    || echo "   ÉCHEC : injoignable, chaîne non reconnue ou nom incorrect"
done
