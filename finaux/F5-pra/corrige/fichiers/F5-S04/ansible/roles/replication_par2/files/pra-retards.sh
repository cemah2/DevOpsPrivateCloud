#!/usr/bin/env bash
# pra-retards.sh — retards de réplication vus de PAR2 (F5-S04), pour node_exporter (collecteur textfile).
# Mesure côté DESTINATION : âge du dernier objet arrivé dans s3-02 sous chaque préfixe surveillé, pas
# l'état du processus qui copie (il peut tourner sans rien copier). Lancé chaque minute (pra-retards.timer).
#
# Séries écrites dans $PRA_TEXTFILE/pra_replication.prom :
#   pra_replication_dernier_objet_horodatage_secondes{flux="…"}  date (epoch) du dernier objet arrivé
#   pra_replication_mesure_reussie{flux="…"}                     1 si la mesure a pu être faite
# Le retard = time() - pra_replication_dernier_objet_horodatage_secondes (calculé par Prometheus).
set -uo pipefail

: "${PRA_SERVEUR_PROD:?}" "${PRA_TEXTFILE:?}"
sortie="$PRA_TEXTFILE/pra_replication.prom"
tmp="$(mktemp "$PRA_TEXTFILE/.pra_replication.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

# flux → chemin rclone (distant par2) et fenêtre de recherche (--max-age : on ne liste pas tout l'historique)
declare -A chemins=(
  [wal-mediagenda]="par2:cnpg-k8s-par1/$PRA_SERVEUR_PROD/wals"
  [base-mediagenda]="par2:cnpg-k8s-par1/$PRA_SERVEUR_PROD/base"
  [coffre]="par2:openbao-instantanes/horaire"
  [legacy-rdv]="par2:mariadb-legacy-rdv"
  [velero]="par2:velero-k8s-par1"
  [medidoc]="par2:medidoc-documents"
)
declare -A fenetres=(
  [wal-mediagenda]=6h [base-mediagenda]=8d [coffre]=2d [legacy-rdv]=3d [velero]=3d [medidoc]=7d
)

{
  echo "# HELP pra_replication_dernier_objet_horodatage_secondes Date du dernier objet arrivé à PAR2, par flux."
  echo "# TYPE pra_replication_dernier_objet_horodatage_secondes gauge"
  echo "# HELP pra_replication_mesure_reussie 1 si la mesure du flux a abouti."
  echo "# TYPE pra_replication_mesure_reussie gauge"
} >"$tmp"

for flux in "${!chemins[@]}"; do
  if dernier="$(rclone lsjson "${chemins[$flux]}" --recursive --files-only --fast-list \
      --max-age "${fenetres[$flux]}" 2>/dev/null | jq -r '[.[].ModTime] | max // empty')" && [[ -n "$dernier" ]]; then
    printf 'pra_replication_dernier_objet_horodatage_secondes{flux="%s"} %s\n' "$flux" "$(date -d "$dernier" +%s)" >>"$tmp"
    printf 'pra_replication_mesure_reussie{flux="%s"} 1\n' "$flux" >>"$tmp"
  else
    printf 'pra_replication_mesure_reussie{flux="%s"} 0\n' "$flux" >>"$tmp"
  fi
done

chmod 0644 "$tmp"
mv "$tmp" "$sortie"
trap - EXIT
