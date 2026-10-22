# shellcheck shell=bash
# shellcheck disable=SC2016  # scripts des Jobs entre apostrophes : développés DANS le pod, pas ici
# break-E34.sh — M21-E34 « Un diagnostic en temps limité » (CHRONO)
# À installer en modules/21-metriques/corrige/pannes/break-E34.sh (lancé par « lab/bin/break 21 34 »).
#
# Scénario : MédiAgenda en RECETTE se dégrade pendant que des « testeurs » s'en servent. Deux
# variantes, tirées au hasard ; dans les deux, un trafic témoin réaliste (Job trafic-recette dans
# wb-pannes, par la Gateway, comme un navigateur) tourne pour que les métriques aient de quoi montrer :
#   1. un « export des créneaux » lancé par un partenaire (Job export-creneaux, wb-pannes) interroge
#      /api/v1/creneaux en boucle, avec un praticien différent à chaque appel (le cache Valkey ne sert
#      à rien) : débit × 20, cache inutile, CPU de l'API et charge de PostgreSQL en hausse, latence ;
#   2. une session PostgreSQL (application_name « export-rapports ») ouvre une transaction et pose un
#      verrou SHARE sur la table rendez_vous, puis attend : les lectures passent, les CRÉATIONS de
#      rendez-vous attendent le verrou, puis les fils de l'API s'épuisent et tout ralentit.
# Bornes : tout s'arrête seul au bout de 75 min (activeDeadlineSeconds des Jobs, pg_sleep(4500)).
# Aucune donnée n'est supprimée (le trafic témoin CRÉE des rendez-vous fictifs « Patient Témoin »
# en recette ; ils restent). Aucun objet géré par Argo CD n'est modifié.
# Annulation (« --annuler ») : suppression des Jobs et du ConfigMap posés par la panne (étiquette
# medisphere.internal/panne=M21-E34), fin de la session « export-rapports ».
# Variables (lab/lab.env) : WB_M21_RECETTE_URL (défaut https://mediagenda-recette.apps.par1.medisphere.internal),
# WB_M21_IMAGE_CURL (défaut registry.par1.medisphere.internal/dockerhub/curlimages/curl:8.22.0),
# WB_RACINE_PKI, WB_K8S_ADMIN_KUBECONFIG.

# Chemin valable une fois installé dans corrige/pannes/ (quatre niveaux sous la racine du dépôt).
# shellcheck source=../../../../lab/lib/pannes-lib.sh disable=SC1091
source "$WB_ROOT/lab/lib/pannes-lib.sh"

_E34_NS=wb-pannes
_E34_RECETTE=mediagenda-recette
_E34_URL="${WB_M21_RECETTE_URL:-https://mediagenda-recette.apps.par1.medisphere.internal}"
_E34_IMAGE="${WB_M21_IMAGE_CURL:-registry.par1.medisphere.internal/dockerhub/curlimages/curl:8.22.0}"
_E34_RACINE="${WB_RACINE_PKI:-/usr/local/share/ca-certificates/medisphere-root-ca.crt}"
_E34_ETAT="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/M21-E34"
_E34_APPNAME=export-rapports
_E34_DUREE=4500

_e34_primaire() {
  wb_kubectl -n "$_E34_RECETTE" get clusters.postgresql.cnpg.io mediagenda-db \
    -o jsonpath='{.status.currentPrimary}' 2>/dev/null
}

# _e34_psql REQUÊTE — psql sur l'instance primaire (socket local, utilisateur postgres), sortie brute.
_e34_psql() {
  local p
  p="$(_e34_primaire)"
  [[ -n "$p" ]] || return 1
  wb_kubectl -n "$_E34_RECETTE" exec "$p" -c postgres -- psql -d mediagenda -XAtq -c "$1" 2>/dev/null
}

# _e34_job NOM SCRIPT_SH — Job borné dans wb-pannes, image curl, racine MédiSphère montée.
_e34_job() {
  local nom="$1" script="$2"
  wb_kubectl -n "$_E34_NS" apply -f - >/dev/null <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: $nom
  labels:
    medisphere.internal/panne: M21-E34
spec:
  activeDeadlineSeconds: $_E34_DUREE
  backoffLimit: 0
  ttlSecondsAfterFinished: 600
  template:
    metadata:
      labels:
        medisphere.internal/panne: M21-E34
        app.kubernetes.io/name: $nom
    spec:
      restartPolicy: Never
      priorityClassName: medisphere-essai
      securityContext:
        runAsNonRoot: true
        runAsUser: 100
        seccompProfile: {type: RuntimeDefault}
      containers:
        - name: client
          image: $_E34_IMAGE
          command: ["/bin/sh", "-c"]
          args:
            - |
$(printf '%s\n' "$script" | sed 's/^/              /')
          env:
            - {name: URL, value: "$_E34_URL"}
          resources:
            requests: {cpu: 20m, memory: 32Mi}
            limits: {cpu: 500m, memory: 64Mi}
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities: {drop: ["ALL"]}
          volumeMounts:
            - {name: racine, mountPath: /racine, readOnly: true}
      volumes:
        - name: racine
          configMap:
            name: racine-medisphere-e34
EOF
}

_e34_preparer() {
  [[ -r "$_E34_RACINE" ]] || { wb_avert "racine MédiSphère introuvable : $_E34_RACINE"; return 1; }
  wb_kubectl get namespace "$_E34_NS" >/dev/null 2>&1 || { wb_avert "espace $_E34_NS absent (créé au M14)"; return 1; }
  [[ -n "$(_e34_primaire)" ]] || { wb_avert "cluster CNPG mediagenda-db introuvable en recette"; return 1; }
  install -d -m 700 "$_E34_ETAT"
  printf '%s\n' "$WB_VAR" > "$_E34_ETAT/variante"
  date -Is > "$_E34_ETAT/debut"
  wb_kubectl -n "$_E34_NS" create configmap racine-medisphere-e34 --from-file=ca.crt="$_E34_RACINE" \
    --dry-run=client -o yaml \
    | wb_kubectl label --local -f - -o yaml medisphere.internal/panne=M21-E34 \
    | wb_kubectl apply -f - >/dev/null
  # Trafic des testeurs : quelques praticiens (le cache sert), une liste, une création toutes les 10 s.
  _e34_job trafic-recette '
i=0
while true; do
  for p in dr-martin dr-durand dr-petit; do
    curl -s -o /dev/null -m 10 --cacert /racine/ca.crt "$URL/api/v1/creneaux?date=$(date -d @$(( $(date +%s) + 86400 )) +%Y-%m-%d)&praticien=$p"
  done
  curl -s -o /dev/null -m 10 --cacert /racine/ca.crt "$URL/api/v1/rendez-vous?limite=20"
  i=$((i + 1))
  if [ $((i % 5)) -eq 0 ]; then
    h=$(( (RANDOM % 8) + 8 )); m=$(( (RANDOM % 2) * 30 )); j=$(( (RANDOM % 20) + 2 ))
    jour=$(date -d @$(( $(date +%s) + j * 86400 )) +%Y-%m-%d)
    curl -s -o /dev/null -m 10 --cacert /racine/ca.crt -H "Content-Type: application/json" \
      -d "{\"patient\":\"Patient Témoin\",\"praticien\":\"dr-martin\",\"debut\":\"${jour}T$(printf %02d $h):$(printf %02d $m):00+01:00\"}" \
      "$URL/api/v1/rendez-vous"
  fi
  sleep 2
done'
}

panne_E34_v1() {
  _e34_preparer || return 1
  _e34_job export-creneaux '
for n in 1 2 3 4 5 6 7 8 9 10 11 12; do
  ( while true; do
      curl -s -o /dev/null -m 15 --cacert /racine/ca.crt \
        "$URL/api/v1/creneaux?date=$(date +%Y-%m-%d)&praticien=partenaire-$RANDOM$RANDOM"
    done ) &
done
wait'
}

panne_E34_v2() {
  _e34_preparer || return 1
  # Session lancée depuis adm01, détachée : un « export » qui garde son verrou 75 min.
  # kubectl SANS délai de requête (wb_kubectl coupe à 20 s, ce qui fermerait la session).
  local primaire
  primaire="$(_e34_primaire)"
  nohup kubectl --kubeconfig "${WB_K8S_ADMIN_KUBECONFIG:-$HOME/.kube/config}" \
    -n "$_E34_RECETTE" exec "$primaire" -c postgres -- \
    env PGAPPNAME="$_E34_APPNAME" psql -d mediagenda -Xq \
    -c "BEGIN; LOCK TABLE rendez_vous IN SHARE MODE; SELECT pg_sleep($_E34_DUREE); COMMIT;" \
    >/dev/null 2>&1 &
  printf '%s\n' "$!" > "$_E34_ETAT/session.pid"
  disown 2>/dev/null || true
}

verifier_E34() {
  local _essai
  for _essai in $(seq 1 24); do
    case "$WB_VAR" in
      1)
        if [[ "$(wb_kubectl -n "$_E34_NS" get pods -l app.kubernetes.io/name=export-creneaux \
              -o jsonpath='{.items[*].status.phase}' 2>/dev/null)" == *Running* ]]; then return 0; fi ;;
      2)
        if [[ "$(_e34_psql "SELECT count(*) FROM pg_locks l JOIN pg_stat_activity a USING (pid)
              WHERE a.application_name = '$_E34_APPNAME' AND l.mode = 'ShareLock' AND l.granted")" == 1 ]]; then return 0; fi ;;
    esac
    sleep 5
  done
  return 1
}

annuler_E34() {
  wb_kubectl -n "$_E34_NS" delete jobs,configmaps -l medisphere.internal/panne=M21-E34 \
    --ignore-not-found --wait=false >/dev/null 2>&1 || true
  if [[ -f "$_E34_ETAT/session.pid" ]]; then
    kill "$(cat "$_E34_ETAT/session.pid")" 2>/dev/null || true
    rm -f "$_E34_ETAT/session.pid"
  fi
  # Fin de la session côté serveur (idempotent : sans effet si elle n'existe plus).
  _e34_psql "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE application_name = '$_E34_APPNAME'" >/dev/null || true
  # $_E34_ETAT/variante est GARDÉ : le check de l'exercice s'en sert après l'annulation.
}

symptome_E34() {
  wb_symptome "INC-4834 — MédiAgenda (recette) : « c'est lent, et parfois ça ne répond plus »" \
    "Les testeurs de la recette se plaignent depuis quelques minutes : l'agenda met longtemps à" \
    "s'afficher, certaines prises de rendez-vous n'aboutissent pas. Personne n'a rien déployé." \
    "Règle du jour : diagnostic par les MÉTRIQUES seulement (Grafana, Thanos Query, Alertmanager," \
    "Pyrra). Pas de kubectl logs, describe ni exec, pas de SSH, pas de psql. Temps cible : 60 min." \
    "Le chronomètre démarre maintenant : note l'heure dans ton journal."
}

resume_E34() { echo "MédiAgenda (recette) lente, des prises de rendez-vous n'aboutissent pas"; }

if [[ -z "${WB_PANNES_LIB:-}" ]]; then main() { wb_main 21 E34 2 "$@"; }; fi
