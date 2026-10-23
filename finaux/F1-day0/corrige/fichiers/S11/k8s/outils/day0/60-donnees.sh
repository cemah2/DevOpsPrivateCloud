#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# plateforme/k8s — outils/day0/60-donnees.sh (F1-S11, PLAT-3111)
# Remise des données sur le cluster reconstruit. Prérequis : 50-argocd.sh terminé (seules
# mediagenda-recette, mediagenda-prod et portail attendent), MR de récupération FUSIONNÉES dans
# plateforme/k8s (recette, portail, secours) et mediagenda/deploiement (prod), compteurs du gel
# (~/day0/compteurs-gel.txt, ~/day0/files-gel.tsv, 10-gel.sh). Dans ~/src/k8s, avec ton contexte OIDC.
#
#   1. recette et portail : Clusters appliqués (exception écrite du M27), récupération, attente ;
#   2. production : synchronisation SÉLECTIVE de la base seule (le Job de migrations, hook Sync vague −1,
#      et l'API ne doivent pas courir avant elle), attente ;
#   3. comptage AVANT réouverture : rendez-vous de prod et de recette contre le gel ;
#   4. autorités des nouvelles bases copiées pour OpenBao (plateforme/ansible, MR, playbook) ;
#   5. sauvegardes de base neuves (archives sous les nouveaux serverName) ;
#   6. réplica de secours recréé sur l'archive de la nouvelle prod ;
#   7. messagerie : topologie comparée au gel, export des définitions ;
#   8. production synchronisée en entier : RÉOUVERTURE (à annoncer par Nadia).
# Chaque étape attend son résultat ; un écart arrête le script (rien n'est rouvert sur un écart).

# shellcheck source=../../../../S07/k8s/outils/day0/commun.sh
source "$(dirname "${BASH_SOURCE[0]}")/commun.sh"

PHASE=donnees
K8S="$DAY0_SRC/k8s"
ANSIBLE="$DAY0_SRC/ansible"
GEL_FICHIER="${GEL_FICHIER:-$HOME/day0/compteurs-gel.txt}"
FILES_GEL="${FILES_GEL:-$HOME/day0/files-gel.tsv}"
RMQ_URL="${WB_RABBITMQ_URL:-https://rabbitmq.apps.par1.medisphere.internal}"

outils_requis kubectl argocd jq curl git uv
argocd account get-user-info >/dev/null 2>&1 || { echo "CLI argocd non connectée : argocd login argocd.apps.par1.medisphere.internal --sso" >&2; exit 1; }
kubectl cnpg version >/dev/null
[[ -s "$GEL_FICHIER" && -s "$FILES_GEL" ]] || { echo "compteurs du gel absents ($GEL_FICHIER, $FILES_GEL)" >&2; exit 1; }
cd "$K8S"

sain() { [[ "$(k -n "$1" get clusters.postgresql.cnpg.io "$2" -o jsonpath='{.status.phase}' 2>/dev/null)" == "Cluster in healthy state" ]]; }

recette_portail() {
  k apply --server-side --field-manager=plateforme-k8s -f espaces/mediagenda-recette/50-mediagenda-db.yaml
  k apply --server-side --field-manager=plateforme-k8s -f espaces/portail/60-portail-db-sauvegarde.yaml
  k apply --server-side --field-manager=plateforme-k8s -f espaces/portail/50-portail-db.yaml
  attendre 3600 "recette : récupération de mediagenda-db" sain mediagenda-recette mediagenda-db
  attendre 3600 "portail : récupération de portail-db" sain portail portail-db
}

prod_base_seule() {
  # Synchronisation SÉLECTIVE : la base, son magasin d'objets et ses identifiants S3 (noms du corrigé
  # du M27-E15 ; ajoute les tiens). Le reste de l'Application attend l'étape 8.
  argocd app sync mediagenda-prod \
    --resource postgresql.cnpg.io:Cluster:mediagenda-db \
    --resource barmancloud.cnpg.io:ObjectStore:cnpg-s3 \
    --resource external-secrets.io:ExternalSecret:cnpg-s3
  attendre 3600 "production : récupération de mediagenda-db" sain mediagenda-prod mediagenda-db
}

# compte ESPACE — rendez-vous dans la base de l'espace.
compte() { kpsql mediagenda-db -n "$1" -- -d mediagenda -Atc 'SELECT count(*) FROM rendez_vous;'; }
# NB : la recette (synchronisation automatique) tourne déjà sur sa base récupérée ; ses tâches
#   planifiées et tests de charge sont revenus avec Git. Un écart en RECETTE s'explique d'abord par
#   leurs écritures depuis la récupération (horodatage des lignes) avant de conclure à une perte.
comparer() {
  local env gel apres ko=0
  for env in prod recette; do
    gel="$(awk -F'\t' -v e="rendez-vous ($env)" '$1 == e { print $2 }' "$GEL_FICHIER")"
    apres="$(compte "mediagenda-$env")"
    printf '| rendez-vous (%s) | %s | %s |\n' "$env" "$gel" "$apres"
    [[ -n "$gel" && "$gel" == "$apres" ]] || ko=1
  done
  ((ko == 0)) || { echo "ÉCART de rendez-vous : on ne rouvre pas. Voir RB-162 (récupération à un instant donné)." >&2; return 1; }
}

autorites_openbao() {
  local env
  for env in recette prod; do
    k -n "mediagenda-$env" get secret mediagenda-db-ca -o jsonpath='{.data.ca\.crt}' | base64 -d \
      >"$ANSIBLE/files/openbao/postgresql/mediagenda-$env-ca.crt"
  done
  (cd "$ANSIBLE" && git switch -C "day0/autorites-cnpg-$(date +%Y%m%d)" &&
    git add files/openbao/postgresql/ &&
    git commit -m "fix(openbao): autorités des bases CNPG reconstruites (PLAT-3111, CHG-3107)" &&
    git push -u origin HEAD)
  echo "Fais fusionner la MR de plateforme/ansible, puis appuie sur Entrée (le playbook coffre.yml suit)."
  read -r _
  (cd "$ANSIBLE" && git switch main && git pull --ff-only &&
    uv run ansible-playbook playbooks/coffre.yml --limit role_coffre --check --diff &&
    uv run ansible-playbook playbooks/coffre.yml --limit role_coffre)
}

# sauvegarder ESPACE CLUSTER — sauvegarde de base immédiate, attente « completed » (greffon cnpg 1.30 :
#   --method plugin exige --plugin-name).
sauvegarder() {
  local nom
  nom="$2-day0-$(date +%Y%m%d%H%M)"
  kcnpg backup "$2" -n "$1" --method plugin --plugin-name barman-cloud.cloudnative-pg.io --backup-name "$nom"
  attendre 3600 "sauvegarde $1/$nom" sauvegarde_terminee "$1" "$nom"
}
sauvegarde_terminee() { [[ "$(k -n "$1" get backups.postgresql.cnpg.io "$2" -o jsonpath='{.status.phase}')" == completed ]]; }
sauvegardes() {
  sauvegarder mediagenda-prod mediagenda-db
  sauvegarder mediagenda-recette mediagenda-db
  sauvegarder portail portail-db
}

secours() {
  k apply --server-side --field-manager=plateforme-k8s -f espaces/mediagenda-secours/60-cnpg-s3.yaml
  k apply --server-side --field-manager=plateforme-k8s -f espaces/mediagenda-secours/50-mediagenda-db-secours.yaml
  attendre 3600 "secours : réplica sain" sain mediagenda-secours mediagenda-db-secours
}

rmq() {
  local RABBITMQ_USER="" RABBITMQ_PASSWORD=""
  # shellcheck disable=SC1090,SC1091
  source "$HOME/.config/workbook/rabbitmq-checks.env"
  curl -sf --max-time 10 -K <(printf 'user = "%s:%s"\n' "$RABBITMQ_USER" "$RABBITMQ_PASSWORD") "$RMQ_URL/api/$1"
}
messagerie() {
  local d
  d="$(diff <(rmq queues | jq -r '.[] | [.vhost, .name, .type, (.arguments | tojson)] | @tsv' | sort) "$FILES_GEL" || true)"
  if [[ -n "$d" ]]; then
    printf 'Topologie de la messagerie différente du gel :\n%s\n' "$d" >&2
    return 1
  fi
  k -n messagerie create job --from=cronjob/export-definitions "export-day0-$(date +%s)"
}

reouverture() {
  argocd app sync mediagenda-prod
  argocd app wait mediagenda-prod --health --sync --timeout 1800
}

etape "$PHASE" "recette et portail : récupération" recette_portail
etape "$PHASE" "production : base seule (synchronisation sélective)" prod_base_seule
etape "$PHASE" "comparaison au gel (avant réouverture)" comparer
etape "$PHASE" "autorités des bases pour OpenBao" autorites_openbao
etape "$PHASE" "sauvegardes de base neuves" sauvegardes
etape "$PHASE" "réplica de secours" secours
etape "$PHASE" "messagerie : topologie et export" messagerie
confirmer "Rouvrir MédiAgenda en production (synchronisation complète) ? Nadia est-elle prête à l'annoncer ?"
etape "$PHASE" "RÉOUVERTURE de la production" reouverture
jalon "$PHASE" "fin de la coupure" "à annoncer par Nadia ; compléter docs/day0/donnees-apres.md ; lab/bin/check F1 11"
