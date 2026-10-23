#!/usr/bin/env bash
# retour-arriere-legacy-rdv.sh — rend Legacy-RDV à legacy-rdv01 après la bascule (F4-S13, CHG-3413).
# Valable pendant les 48 h de garde (VM gelée, sauvegardée). Depuis adm01. Décision écrite (RB-346) :
# les rendez-vous pris sur Kubernetes APRÈS la bascule (identifiant > identifiant max. au gel) et leurs
# pièces jointes sont rapatriés sur la VM avant de lui rendre le nom : aucun rendez-vous perdu.
set -euo pipefail

VM=admin@legacy-rdv01.par1.medisphere.internal
ETAT="${XDG_STATE_HOME:-$HOME/.local/state}/f4-bascule"
cible=legacy-rdv-prod
[[ -s "$ETAT/max-id-bascule" && -s "$ETAT/bascule" ]] || { echo "état de bascule introuvable dans $ETAT" >&2; exit 1; }
max_id="$(cat "$ETAT/max-id-bascule")"
humain() { printf '\n==> ÉTAPE HUMAINE : %s\n    Entrée quand c'"'"'est fait… ' "$*"; read -r _; }
pod_db() { kubectl -n "$cible" get pods -l app.kubernetes.io/instance=legacy-rdv-db -o name | grep -v metrics | head -n 1; }

humain "fusionner la MR « legacy_rdv_cible: maintenance » (lb02 puis lb01) : plus aucune écriture côté Kubernetes"

echo ">> rendez-vous créés sur Kubernetes depuis la bascule (id > $max_id) -> legacy-rdv01"
# shellcheck disable=SC2016  # $MARIADB_ROOT_PASSWORD s'étend dans le pod
kubectl -n "$cible" exec "$(pod_db)" -c mariadb -- \
    sh -c "MYSQL_PWD=\"\$MARIADB_ROOT_PASSWORD\" mariadb-dump -uroot --no-create-info --skip-add-locks --default-character-set=utf8mb4 --where='id > $max_id' legacy_rdv rendez_vous" \
  | ssh "$VM" "sudo mariadb --default-character-set=utf8mb4 legacy_rdv"

echo ">> pièces jointes déposées depuis la bascule -> legacy-rdv01"
kubectl -n "$cible" exec deploy/legacy-rdv -c web -- \
    sh -c "cd /var/www/legacy-rdv/uploads && find . -type f -newermt '$(cat "$ETAT/bascule")' -print0 | tar --null -T - -czf -" \
  | ssh "$VM" "sudo tar -C /var/www/legacy-rdv/uploads -xzf - && sudo chown www-data:www-data /var/www/legacy-rdv/uploads/*"

echo ">> droits d'écriture rendus à l'application sur legacy-rdv01"
ssh "$VM" "sudo mariadb -e \"GRANT SELECT, INSERT, UPDATE, DELETE ON legacy_rdv.* TO 'legacy_rdv'@'localhost'\""

humain "fusionner la MR « legacy_rdv_cible: vm » (lb02, contrôle, lb01) ; réactiver /etc/cron.d/stats-rdv sur stats01 si besoin"
echo ">> retour arrière terminé : Legacy-RDV servi par legacy-rdv01. Compléter CHG-3413 (cause, durée)."
