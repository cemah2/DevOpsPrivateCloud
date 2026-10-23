#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# plateforme/k8s — outils/day0/10-gel.sh (F1-S07, CHG-3107)
# Gel de la plateforme AVANT la destruction de k8s-par1. Lancé depuis adm01, dans ~/src/k8s, avec
# l'ANCIEN cluster encore en service et ton contexte personnel (OIDC) ou admin.conf.
#
#   1. contrôle du filet (lab/bin/check F1 04 vert) ;
#   2. Argo CD arrêté (sinon l'auto-réparation remettrait des réplicas en recette) : geste noté ;
#   3. écritures arrêtées : API MédiAgenda (Rollouts) recette et prod à 0, portail à 0, CronJobs des
#      espaces applicatifs suspendus ; le HPA ne fait rien sur une cible à 0 réplica ;
#   4. files « notifications » vidées PAR LES CONSOMMATEURS (MédiNotif tourne encore) ;
#   5. compteurs du gel (rendez-vous, messages, ExternalSecrets, certificats) ;
#   6. dernier segment de WAL archivé, sauvegarde de base CNPG de chaque base, attente « completed ».
# Rien n'est supprimé. Relançable : chaque étape constate d'abord son état.
#
# Prérequis : kubectl + greffon « cnpg », jq, curl ; identifiants RabbitMQ des
# checks (~/.config/workbook/rabbitmq-checks.env, étiquette monitoring : lecture de la profondeur).

# shellcheck source=commun.sh
source "$(dirname "${BASH_SOURCE[0]}")/commun.sh"

PHASE=gel
WB="${WB_WORKBOOK:-$HOME/DevOpsPrivateCloud}"
BASES=(mediagenda-recette/mediagenda-db mediagenda-prod/mediagenda-db portail/portail-db)
RMQ_URL="${WB_RABBITMQ_URL:-https://rabbitmq.apps.par1.medisphere.internal}"
GEL_FICHIER="${GEL_FICHIER:-$HOME/day0/compteurs-gel.txt}"
FILES_GEL="${FILES_GEL:-$HOME/day0/files-gel.tsv}"

outils_requis kubectl jq curl
kubectl cnpg version >/dev/null || { echo "greffon kubectl cnpg absent" >&2; exit 1; }

controle_filet() {
  "$WB/lab/bin/check" F1 04
}

arreter_argocd() {
  # Le cluster va être détruit : Argo CD n'est pas redémarré ici (il renaît en S08).
  k -n argocd scale statefulset argocd-application-controller --replicas=0
  k -n argocd scale deployment argocd-applicationset-controller --replicas=0
  attendre 120 "contrôleur d'Argo CD arrêté" argocd_arrete
}
argocd_arrete() { [[ -z "$(k -n argocd get pods -l app.kubernetes.io/name=argocd-application-controller -o name)" ]]; }

arreter_ecritures() {
  local ns
  for ns in mediagenda-recette mediagenda-prod; do
    k -n "$ns" scale rollout mediagenda --replicas=0
  done
  k -n portail scale deployment portail --replicas=0
  for ns in mediagenda-recette mediagenda-prod portail; do
    k -n "$ns" get cronjobs -o name | while read -r cj; do
      k -n "$ns" patch "$cj" --type merge -p '{"spec":{"suspend":true}}' >/dev/null
    done
  done
  attendre 300 "plus aucun pod de l'API MédiAgenda" api_arretee
}
api_arretee() {
  local ns
  for ns in mediagenda-recette mediagenda-prod; do
    [[ -z "$(k -n "$ns" get pods -l app.kubernetes.io/name=mediagenda,app.kubernetes.io/component=api -o name)" ]] || return 1
  done
}

# rmq CHEMIN — GET sur l'API de gestion de RabbitMQ avec le compte des checks (monitoring).
rmq() {
  local RABBITMQ_USER="" RABBITMQ_PASSWORD=""
  # shellcheck disable=SC1090,SC1091
  source "$HOME/.config/workbook/rabbitmq-checks.env"
  curl -sf --max-time 10 -K <(printf 'user = "%s:%s"\n' "$RABBITMQ_USER" "$RABBITMQ_PASSWORD") "$RMQ_URL/api/$1"
}
# profondeur VHOST — messages (prêts + non acquittés) de la file notifications.
profondeur() { rmq "queues/$1/notifications" | jq -r '.messages'; }
files_vides() {
  local v
  for v in medinotif-recette medinotif-prod; do [[ "$(profondeur "$v")" == 0 ]] || return 1; done
}
vider_files() {
  # MédiNotif consomme ; en recette, KEDA le remonte de 0 dès qu'un message attend.
  attendre 900 "files notifications vides (consommées)" files_vides
}

compter() {
  local ns n
  {
    printf 'gel du\t%s\n' "$(date -Is)"
    for ns in mediagenda-prod mediagenda-recette; do
      n="$(kcnpg psql mediagenda-db -n "$ns" -- -d mediagenda -Atc 'SELECT count(*) FROM rendez_vous;')"
      printf 'rendez-vous (%s)\t%s\n' "${ns#mediagenda-}" "$n"
    done
    printf 'messages en file (medinotif-recette, medinotif-prod)\t%s, %s\n' \
      "$(profondeur medinotif-recette)" "$(profondeur medinotif-prod)"
    printf 'ExternalSecrets\t%s\n' "$(k get externalsecrets.external-secrets.io -A -o name | wc -l)"
    printf 'certificats (cert-manager)\t%s\n' "$(k get certificates.cert-manager.io -A -o name | wc -l)"
  } >"$GEL_FICHIER"
  # Topologie de la messagerie au gel (vhost, file, type, arguments) : comparée après la reconstruction.
  rmq queues | jq -r '.[] | [.vhost, .name, .type, (.arguments | tojson)] | @tsv' | sort >"$FILES_GEL"
  cat "$GEL_FICHIER"
}

# sauvegarde_apres_gel ESPACE/CLUSTER — segment de WAL courant forcé à l'archive, puis sauvegarde de base.
sauvegarde_apres_gel() {
  local ns="${1%/*}" c="${1#*/}" base nom
  base=postgres
  [[ "$c" == portail-db ]] && base=portail
  kcnpg psql "$c" -n "$ns" -- -d "$base" -Atc 'SELECT pg_switch_wal();' >/dev/null
  nom="$c-gel-$(date +%Y%m%d%H%M)"
  k apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: $nom
  namespace: $ns
  labels:
    medisphere.internal/changement: CHG-3107
spec:
  cluster:
    name: $c
  method: plugin
  pluginConfiguration:
    name: barman-cloud.cloudnative-pg.io
EOF
  attendre 1800 "sauvegarde $ns/$nom completed" sauvegarde_terminee "$ns" "$nom"
}
sauvegarde_terminee() { [[ "$(k -n "$1" get backups.postgresql.cnpg.io "$2" -o jsonpath='{.status.phase}')" == completed ]]; }

etape "$PHASE" "contrôle du filet (F1-S04)" controle_filet
confirmer "Le gel coupe MédiAgenda (recette et production) et le portail. Nadia a-t-elle prévenu les centres ?"
geste "$PHASE" "Argo CD (contrôleurs d'applications et d'ApplicationSets) arrêté à la main pour le gel"
etape "$PHASE" "arrêt d'Argo CD" arreter_argocd
etape "$PHASE" "arrêt des écritures (API, portail, CronJobs)" arreter_ecritures
etape "$PHASE" "files notifications vidées par MédiNotif" vider_files
etape "$PHASE" "compteurs du gel" compter
for b in "${BASES[@]}"; do
  etape "$PHASE" "WAL archivé et sauvegarde de base après le gel : $b" sauvegarde_apres_gel "$b"
done
jalon "$PHASE" "gel terminé" "compteurs dans $GEL_FICHIER — à ajouter à docs/day0/reference-avant.md (section Gel)"
