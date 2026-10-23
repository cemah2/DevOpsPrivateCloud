#!/usr/bin/env bash
# copier-donnees-legacy.sh — copie des données de Legacy-RDV de legacy-rdv01 vers un espace Kubernetes
# (F4-S12 en recette ; repris par bascule-legacy-rdv.sh en production, F4-S13). Depuis adm01.
#
#   copier-donnees-legacy.sh --espace legacy-rdv-recette [--base] [--pieces] [--depuis "AAAA-MM-JJ HH:MM:SS"]
#     --base     vidage logique de la table rendez_vous (la table sessions n'existe pas sur la VM) ;
#     --pieces   pièces jointes (flux tar : dates de modification conservées, la purge s'en sert) ;
#     --depuis D ne copier que les pièces modifiées depuis D (rattrapage de la bascule) ;
#     sans --base ni --pieces : les deux.
#
# Aucun fichier intermédiaire : tout passe dans des tuyaux SSH → kubectl exec, compressé ; le mot de
# passe de la cible ne passe jamais par une ligne de commande (lu dans l'environnement du pod).
# Prérequis : SSH admin@legacy-rdv01 (sudo) ; kubectl avec ton identité (plateforme-admins) ; l'espace
# a une MariaDB « legacy-rdv-db » prête et le Deployment « legacy-rdv » (pour monter le PVC).
# ⚠️ --base REMPLACE la table rendez_vous de la cible (DROP TABLE du vidage) : jamais sur une
# production qui a déjà reçu des rendez-vous (contrôle ci-dessous).
# shellcheck disable=SC2016,SC2029  # $MARIADB_ROOT_PASSWORD s'étend DANS le pod ; le filtre find, côté adm01 (voulu)
set -euo pipefail

VM=admin@legacy-rdv01.par1.medisphere.internal
espace="" base=0 pieces=0 depuis=""
while (($#)); do
  case "$1" in
    --espace) espace="${2:-}"; shift 2 ;;
    --base) base=1; shift ;;
    --pieces) pieces=1; shift ;;
    --depuis) depuis="${2:-}"; shift 2 ;;
    *) echo "usage : $0 --espace ESPACE [--base] [--pieces] [--depuis 'AAAA-MM-JJ HH:MM:SS']" >&2; exit 2 ;;
  esac
done
[[ "$espace" =~ ^legacy-rdv-(recette|prod)$ ]] || { echo "espace attendu : legacy-rdv-recette ou legacy-rdv-prod" >&2; exit 2; }
((base + pieces)) || { base=1; pieces=1; }
dire() { printf '>> %s\n' "$*"; }

POD_DB="$(kubectl -n "$espace" get pods -l app.kubernetes.io/instance=legacy-rdv-db -o name | grep -v metrics | head -n 1)"
[[ -n "$POD_DB" ]] || { echo "pod de la base introuvable dans $espace" >&2; exit 1; }
# sql_cible "requête" — exécutée dans le pod MariaDB, en root (mot de passe lu DANS le pod).
sql_cible() {
  kubectl -n "$espace" exec -i "$POD_DB" -c mariadb -- \
    sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" exec mariadb -uroot -N -B legacy_rdv' <<<"$1"
}
compter_vm() { ssh "$VM" "sudo mariadb -N -B -e 'SELECT COUNT(*) FROM legacy_rdv.rendez_vous'"; }

if ((base)); then
  if [[ "$espace" == legacy-rdv-prod ]]; then
    n="$(sql_cible 'SELECT COUNT(*) FROM rendez_vous' 2>/dev/null || echo 0)"
    if [[ "$n" != 0 ]] && [[ "${FORCER_PROD:-}" != oui ]]; then
      echo "la production contient déjà $n rendez-vous : refus (FORCER_PROD=oui seulement pendant la fenêtre de bascule)" >&2
      exit 1
    fi
  fi
  dire "vidage logique de legacy_rdv.rendez_vous (legacy-rdv01) -> $espace"
  # --tz-utc (défaut) : TIMESTAMP écrits en UTC et relus correctement ; DATETIME copiés tels quels.
  # --hex-blob : sans objet ici (aucun BLOB) mais sans risque ; utf8mb4 explicite.
  ssh "$VM" "sudo mariadb-dump --single-transaction --default-character-set=utf8mb4 --hex-blob \
      --add-drop-table legacy_rdv rendez_vous | gzip -1" \
    | kubectl -n "$espace" exec -i "$POD_DB" -c mariadb -- \
        sh -c 'gunzip | MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot --default-character-set=utf8mb4 legacy_rdv'
  dire "rendez-vous : legacy-rdv01 = $(compter_vm) ; $espace = $(sql_cible 'SELECT COUNT(*) FROM rendez_vous')"
fi

if ((pieces)); then
  dire "pièces jointes (legacy-rdv01:/var/www/legacy-rdv/uploads) -> PVC legacy-rdv-pieces de $espace${depuis:+ (depuis $depuis)}"
  filtre="-type f -name '*.*' ! -name LISEZMOI.txt"
  [[ -n "$depuis" ]] && filtre="$filtre -newermt '$depuis'"
  ssh "$VM" "cd /var/www/legacy-rdv/uploads && sudo find . $filtre -print0 | sudo tar --null -T - -czf -" \
    | kubectl -n "$espace" exec -i deploy/legacy-rdv -c web -- \
        tar -C /var/www/legacy-rdv/uploads -xzf - --no-same-owner --no-same-permissions
  dire "fichiers : legacy-rdv01 = $(ssh "$VM" "sudo find /var/www/legacy-rdv/uploads -type f ! -name LISEZMOI.txt | wc -l") ; $espace = $(kubectl -n "$espace" exec deploy/legacy-rdv -c web -- sh -c 'find /var/www/legacy-rdv/uploads -type f ! -name LISEZMOI.txt | wc -l')"
fi
