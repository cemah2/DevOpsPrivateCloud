# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant
# check-E22.sh — M13-E22 « Panne : Harbor ne démarre plus » : santé, conteneurs, disque de données,
# droits de la base et du certificat du proxy, configuration générée et chemins de harbor.yml.
# Lecture seule (systemctl show, docker ps/inspect, df, stat, test sur reg01, avec sudo -n).

# shellcheck source=_m13-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m13-expert.sh"

title "M13-E22 — Harbor démarre"
require_cmd jq curl

# Dossier d'installation et volume de données, lus sur reg01 (même méthode que le script de panne).
_m13_e22_aide='I=$(systemctl show -p WorkingDirectory --value harbor.service); [ -n "$I" ] && [ -f "$I/harbor.yml" ] || I=/opt/harbor
D=$(sudo -n sed -nE "s/^data_volume:[[:space:]]*([^[:space:]#]+).*/\1/p" "$I/harbor.yml" | head -n 1); D=${D:-/data}'

check_cmd "/api/v2.0/health : tous les composants « healthy »" _m13p_sante
check_ssh "harbor.service actif" "$_m13x_reg01" 'systemctl is-active -q harbor.service'
check_ssh "les conteneurs de Harbor tournent, sans redémarrage en boucle" "$_m13x_reg01" \
  'n=0; for c in harbor-log registry registryctl harbor-db harbor-core harbor-portal harbor-jobservice redis nginx; do
     s=$(sudo -n docker inspect -f "{{.State.Status}} {{.State.Restarting}}" "$c" 2>/dev/null) || exit 1
     [ "$s" = "running false" ] || exit 1; n=$((n+1)); done; [ $n -eq 9 ]'
check_ssh "/data occupé à moins de 85 %" "$_m13x_reg01" \
  "$_m13_e22_aide"'; p=$(df --output=pcent "$D" | tail -n 1 | tr -dc 0-9); [ -n "$p" ] && [ "$p" -lt 85 ]'
check_ssh "données de PostgreSQL : propriétaire uid 999" "$_m13x_reg01" \
  "$_m13_e22_aide"'; [ "$(sudo -n stat -c %u "$D/database")" = 999 ]'
check_ssh "clé et certificat du proxy lisibles par l'utilisateur du proxy (uid 10000)" "$_m13x_reg01" \
  "$_m13_e22_aide"'; for f in "$D/secret/cert/server.key" "$D/secret/cert/server.crt"; do
     m=$(sudo -n stat -c "%u %a" "$f") || exit 1; set -- $m
     [ "$1" = 10000 ] && [ $(( 0$2 & 0400 )) -ne 0 ] || [ $(( 0$2 & 0004 )) -ne 0 ] || exit 1; done'
check_ssh "configuration générée présente (common/config/core/env, docker-compose.yml)" "$_m13x_reg01" \
  "$_m13_e22_aide"'; sudo -n test -s "$I/common/config/core/env" && sudo -n test -s "$I/docker-compose.yml"'
check_ssh "les chemins de certificat de harbor.yml existent" "$_m13x_reg01" \
  "$_m13_e22_aide"'; for k in certificate private_key; do
     f=$(sudo -n sed -nE "/^https:/,/^[^[:space:]#]/ s/^[[:space:]]+$k:[[:space:]]*([^[:space:]#]+).*/\1/p" "$I/harbor.yml" | head -n 1)
     [ -n "$f" ] && sudo -n test -s "$f" || exit 1; done'
check_ssh "aucun fichier de plus de 1 Gio hors de registry/ et database/ dans /data" "$_m13x_reg01" \
  "$_m13_e22_aide"'; ! sudo -n find "$D" -xdev -type f -size +1G -not -path "$D/registry/*" -not -path "$D/database/*" -print -quit 2>/dev/null | grep -q .'
check_cmd "RB-135 publié dans docs/registre/runbooks/" _m13p_doc_prefixe docs/registre/runbooks RB-135
check_cmd "panne M13-E22 close (lab/bin/break 13 22 --annuler après réparation)" _m13p_aucune_panne_active E22
