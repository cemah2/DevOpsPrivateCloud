#!/usr/bin/env bash
# ~/m15/e18/essais-comportement.sh — comportement des routes migrées (M15-E18, étape 5).
set -uo pipefail
A=apps.par1.medisphere.internal
ligne() { curl -sS -o /dev/null -w '%{http_code} %{redirect_url}\n' "$@"; }
echo "portail /          (attendu 302 → /accueil) : $(ligne "https://portail-infoger.$A/")"
echo "portail /accueil   (attendu 200)            : $(ligne "https://portail-infoger.$A/accueil")"
echo "ancien nom /x      (attendu 308 → https://portail-infoger.$A/accueil) : $(ligne "https://www-portail-infoger.$A/x")"
echo "api-rdv /rdv/hostname (attendu 200, pod v1 ou v2) : $(curl -sS "https://api-rdv-infoger.$A/rdv/hostname")"
echo "api-rdv en-tête v2 (attendu pod v2) : $(curl -sS -H 'X-Version-Rdv: v2' "https://api-rdv-infoger.$A/rdv/hostname")"
echo "api-rdv /RDV/hostname (casse ; attendu 404 ici, 200 chez nginx) : $(ligne "https://api-rdv-infoger.$A/RDV/hostname")"
echo "répartition sur 100 requêtes (attendu ≈ 80/20) :"
for _ in $(seq 100); do curl -sS "https://api-rdv-infoger.$A/rdv/hostname"; echo; done | sed -E 's/-[a-z0-9]+-[a-z0-9]+$//' | sort | uniq -c
P="$HOME/DevOpsPrivateCloud/modules/15-kubernetes-reseau/ressources"
echo "notif gRPC (attendu SERVING) ; nom non publié (pas de source gateway-grpcroute) : par l'adresse"
grpcurl -import-path "$P" -proto E16-health.proto -servername "notif-infoger.$A" -authority "notif-infoger.$A" \
  -d '{}' 10.10.41.10:443 grpc.health.v1.Health/Check
