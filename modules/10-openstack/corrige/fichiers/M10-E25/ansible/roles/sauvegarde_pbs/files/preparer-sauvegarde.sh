#!/usr/bin/env bash
# preparer-sauvegarde.sh — à lancer en root sur osctl01 (M10-E25). Source : plateforme/openstack
# (outils/) ; installé en /usr/local/sbin par le rôle sauvegarde_pbs quand l'élément openstack est actif.
#
# Extrait et PRÉPARE (mariabackup --prepare) la dernière sauvegarde complète prise par Kolla, dans
# un conteneur jetable lancé avec la MÊME image que le conteneur « mariadb », sans réseau et sans
# accès aux données en service (seul le volume mariadb_backup est monté).
#
# Usage : preparer-sauvegarde.sh verifier   prépare dans /backup/verif-<horodatage>, contrôle, efface
#         preparer-sauvegarde.sh preparer   prépare dans /backup/restore/full et le CONSERVE
#                                           (étape 1 de la restauration, voir sauvegarde-restauration.md)
# Code retour : 0 si la sauvegarde est restaurable (préparation réussie et bases attendues présentes).
set -euo pipefail

usage() { echo "Usage : $0 verifier|preparer" >&2; exit 2; }
[[ $# -eq 1 ]] || usage
mode="$1"
[[ $EUID -eq 0 ]] || { echo "à lancer en root sur osctl01" >&2; exit 1; }

# Bases qu'une sauvegarde complète du plan de contrôle DOIT contenir (services activés au M10).
BASES_ATTENDUES=(keystone glance nova nova_api nova_cell0 neutron cinder placement heat octavia)

image="$(docker inspect -f '{{.Config.Image}}' mariadb)"
racine="$(docker volume inspect -f '{{.Mountpoint}}' mariadb_backup)"
[[ -r "$racine/last_full_file" ]] || { echo "aucune sauvegarde complète (last_full_file absent)" >&2; exit 1; }
dernier="$(<"$racine/last_full_file")"          # chemin vu du conteneur : /backup/full-…/….gz

case "$mode" in
  verifier) cible="/backup/verif-$(date +%Y%m%d-%H%M%S)" ;;
  preparer) cible=/backup/restore/full ;;
  *) usage ;;
esac

echo "image    : $image"
echo "source   : $dernier"
echo "cible    : $cible"
debut=$(date +%s)
docker run --rm --name mariabackup-preparation --network none \
  -v mariadb_backup:/backup "$image" \
  bash -c "set -euo pipefail
           rm -rf '$cible'; mkdir -p '$cible'
           gunzip -c '$dernier' | mbstream -x -C '$cible'
           mariabackup --prepare --target-dir '$cible'"
echo "préparation : $(( $(date +%s) - debut )) s"

hote="$racine/${cible#/backup/}"
ok=1
# Fichier d'état de la préparation : mariadb_backup_checkpoints (MariaDB récent) ou
# xtrabackup_checkpoints (ancien nom).
if grep -hqs 'backup_type *= *full-prepared' "$hote/mariadb_backup_checkpoints" "$hote/xtrabackup_checkpoints"; then
  echo "état      : full-prepared"
else
  echo "état      : préparation NON confirmée (fichier *_checkpoints)" >&2; ok=0
fi
for b in "${BASES_ATTENDUES[@]}"; do
  if [[ -d "$hote/$b" ]]; then printf 'base      : %-12s présente\n' "$b"
  else printf 'base      : %-12s ABSENTE\n' "$b" >&2; ok=0; fi
done

if [[ "$mode" == verifier ]]; then
  rm -rf -- "$hote"
  echo "copie de vérification effacée"
fi
if (( ok )); then
  echo "RÉSULTAT : sauvegarde restaurable"
else
  echo "RÉSULTAT : sauvegarde NON restaurable" >&2
  exit 1
fi
