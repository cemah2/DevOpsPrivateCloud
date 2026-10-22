# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E39.sh — M20-E39 « Panne : la dérive revient sans cesse »
#
# Deux écrivains se disputent le même champ ; Argo CD (selfHeal) remet Git, l'autre remet sa valeur :
#   1. HorizontalPodAutoscaler ajouté à l'overlay de dev (min 2) alors que Git fixe replicas: 1 et
#      que la différence de réplicas n'est pas ignorée (commit de Lucas) ;
#   2. seconde Application « labo-essai » (commit de Lucas dans plateforme/gitops) qui déploie les
#      mêmes objets que labo dans le même espace : les deux Applications se les arrachent
#      (annotation de suivi réécrite à chaque synchronisation) ;
#   3. CronJob « correcteur-memoire » dans wb-pannes (avec son compte de service et un Role dans
#      mediagenda-dev) qui remonte chaque minute la limite mémoire de l'API de dev : un déploiement
#      progressif à chaque minute, défait par Argo CD, refait par la tâche…
# Aucune variante ne supprime de données ; labo-essai ne porte pas de finaliseur (sa suppression
# n'emporte rien).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m20-commun.sh
source "$WB_ROOT/modules/20-gitops/corrige/pannes/_m20-commun.sh"

_E39_DOSSIER="${WB_M20_OVERLAY_DEV:-overlays/dev}"
_E39_KUSTO="$_E39_DOSSIER/kustomization.yaml"
_E39_APP_LABO="${WB_M20_APP_LABO:-labo}"
_E39_NS_PANNES=wb-pannes
_E39_NOM=correcteur-memoire
_E39_IMG_CURL="$_M20_REGISTRE/dockerhub/curlimages/curl:8.17.0"

# _e39_bataille APP — au moins deux synchronisations automatiques depuis l'injection.
_e39_bataille() {
  local debut
  debut="$(m20_lire E39 debut)"
  (($(m20_sync_auto_depuis "$1" "${debut:-0}") >= 2))
}

_e39_partage() {
  _e39_bataille "$_E39_APP_LABO" || m20_condition "$_E39_APP_LABO" 'SharedResourceWarning' ||
    m20_condition labo-essai 'SharedResourceWarning'
}

# _e39_replicas_ignores — l'Application de dev ignore déjà la différence de réplicas des Deployments.
_e39_replicas_ignores() {
  m20_app_jq "$_M20_APP_DEV" '[.spec.ignoreDifferences[]? | select(.kind == "Deployment")
    | select(((.jsonPointers // []) | index("/spec/replicas")) or ((.jqPathExpressions // []) | any(test("replicas"))))] | length > 0'
}

_e39_rendu_ok() {
  local d dir avant apres
  d="$(m20_copie "$_M20_DEPLOIEMENT")" || return 1
  dir="$d/$_E39_DOSSIER"
  avant="$(m20_rendu "$dir")"
  cp "$1" "$d/$_E39_KUSTO"
  cp "$3" "$d/$2"
  if ! kubectl kustomize "$dir" >/dev/null 2>&1; then rm -rf -- "$(dirname "$d")"; return 1; fi
  apres="$(m20_rendu "$dir")"
  rm -rf -- "$(dirname "$d")"
  [[ -z "$(comm -23 <(printf '%s\n' "$avant") <(printf '%s\n' "$apres"))" ]]
}

# _e39_correcteur LIMITE CONTENEUR — objets de la variante 3 (YAML sur la sortie standard).
_e39_correcteur() {
  cat <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: $_E39_NOM
  namespace: $_E39_NS_PANNES
  labels: {medisphere.internal/ticket: DEV-2139}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: $_E39_NOM
  namespace: $_M20_NS_DEV
  labels: {medisphere.internal/ticket: DEV-2139}
rules:
  - apiGroups: [apps]
    resources: [deployments]
    resourceNames: [mediagenda]
    verbs: [get, patch]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: $_E39_NOM
  namespace: $_M20_NS_DEV
  labels: {medisphere.internal/ticket: DEV-2139}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: $_E39_NOM
subjects:
  - kind: ServiceAccount
    name: $_E39_NOM
    namespace: $_E39_NS_PANNES
---
# Lucas, DEV-2139 : « l'API de dev se fait tuer par manque de mémoire, je remonte la limite en
# attendant que l'équipe corrige le chart ».
apiVersion: batch/v1
kind: CronJob
metadata:
  name: $_E39_NOM
  namespace: $_E39_NS_PANNES
  labels: {medisphere.internal/ticket: DEV-2139}
spec:
  schedule: "*/1 * * * *"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 1
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      backoffLimit: 0
      activeDeadlineSeconds: 50
      template:
        spec:
          serviceAccountName: $_E39_NOM
          restartPolicy: Never
          securityContext:
            runAsNonRoot: true
            runAsUser: 65534
            runAsGroup: 65534
            seccompProfile: {type: RuntimeDefault}
          containers:
            - name: correcteur
              image: $_E39_IMG_CURL
              command:
                - sh
                - -c
                - >-
                  curl -sS --fail --max-time 20
                  --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
                  -H "Authorization: Bearer \$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)"
                  -H "Content-Type: application/strategic-merge-patch+json"
                  -X PATCH
                  "https://kubernetes.default.svc/apis/apps/v1/namespaces/$_M20_NS_DEV/deployments/mediagenda?fieldManager=correcteur-lucas"
                  -d '{"spec":{"template":{"spec":{"containers":[{"name":"$2","resources":{"limits":{"memory":"$1"}}}]}}}}'
                  -o /dev/null && echo "limite mémoire remise à $1"
              resources:
                requests: {cpu: 10m, memory: 16Mi}
                limits: {memory: 32Mi}
              securityContext:
                allowPrivilegeEscalation: false
                readOnlyRootFilesystem: true
                capabilities: {drop: ["ALL"]}
EOF
}

_e39_corrige_vu() {
  wb_kubectl -n "$_M20_NS_DEV" get deploy mediagenda -o json 2>/dev/null |
    jq -e '[.metadata.managedFields[]? | select(.manager == "correcteur-lucas")] | length > 0' >/dev/null 2>&1 &&
    _e39_bataille "$_M20_APP_DEV"
}

_m20E39_une() {
  local n="$1" t f fichier actions spec conteneur lim actuelle
  m20_debut E39
  case "$n" in
    1)
      _e39_replicas_ignores && return 10
      wb_kubectl -n "$_M20_NS_DEV" get hpa -o json 2>/dev/null | jq -e '.items | length == 0' >/dev/null 2>&1 || return 10
      f="$(mktemp)"
      cat >"$f" <<'EOF'
# Mise à l'échelle automatique de l'API (DEV-2139) : au moins deux pods, comme en recette.
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: mediagenda
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: mediagenda
  minReplicas: 2
  maxReplicas: 3
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
EOF
      t="$(mktemp)"
      m20_brut "$_M20_DEPLOIEMENT" "$_E39_KUSTO" >"$t" || { rm -f "$t" "$f"; return 1; }
      yq -i '.resources += ["hpa.yaml"]' "$t" || { rm -f "$t" "$f"; return 10; }
      _e39_rendu_ok "$t" "$_E39_DOSSIER/hpa.yaml" "$f" || { rm -f "$t" "$f"; return 10; }
      actions="[$(m20_action update "$_E39_KUSTO" "$t"),$(m20_action create "$_E39_DOSSIER/hpa.yaml" "$f")]"
      rm -f "$t" "$f"
      m20_commit_lucas E39 "$_M20_DEPLOIEMENT" "lucas/dev-hpa" \
        "feat(dev): mise à l'échelle automatique de l'API" \
        "DEV-2139 : HPA de 2 à 3 pods sur le CPU, pour reproduire la recette en dev." "$actions" || return $?
      m20_rafraichir "$_M20_APP_DEV"
      m20_attendre 300 _e39_bataille "$_M20_APP_DEV" || { _e39_defaire 1; return 10; }
      ;;
    2)
      m20_app_saine "$_E39_APP_LABO" || return 10
      m20_app "labo-essai" >/dev/null && return 10
      fichier="$(m20_chercher "$_M20_GITOPS" '^[[:space:]]*name:[[:space:]]*labo[[:space:]]*$' | while read -r f; do
        m20_brut "$_M20_GITOPS" "$f" | yq -e 'select((.kind == "Application" or .kind == "ApplicationSet") and .metadata.name == "labo")' >/dev/null 2>&1 && printf '%s\n' "$f"
      done | head -n 1)"
      [[ -n "$fichier" ]] || return 10
      spec="$(m20_app "$_E39_APP_LABO" | jq -c '{project: .spec.project, destination: .spec.destination}
        + (if .spec.sources then {sources: .spec.sources} else {source: .spec.source} end)
        + {syncPolicy: {automated: {prune: false, selfHeal: true}}}')" || return 1
      t="$(mktemp)"
      m20_brut "$_M20_GITOPS" "$fichier" >"$t" || { rm -f "$t"; return 1; }
      {
        printf -- '---\n# Copie de labo pour mes essais de paramètres (Lucas, DEV-2139). À supprimer après.\n'
        jq -n --arg ns "$_M20_NS" --argjson s "$spec" '{apiVersion: "argoproj.io/v1alpha1", kind: "Application",
          metadata: {name: "labo-essai", namespace: $ns}, spec: $s}' | yq -P -o yaml
      } >>"$t"
      actions="[$(m20_action update "$fichier" "$t")]"
      rm -f "$t"
      m20_commit_lucas E39 "$_M20_GITOPS" "lucas/labo-essai" \
        "feat(labo): copie de labo pour mes essais" \
        "DEV-2139 : je teste des réglages sans toucher à l'Application labo." "$actions" || return $?
      m20_rafraichir racine applications
      m20_attendre 300 _e39_partage || { _e39_defaire 2; return 10; }
      ;;
    3)
      conteneur="$(wb_kubectl -n "$_M20_NS_DEV" get deploy mediagenda -o json 2>/dev/null | jq -r '.spec.template.spec.containers[0].name // empty')"
      [[ -n "$conteneur" ]] || return 10
      actuelle="$(wb_kubectl -n "$_M20_NS_DEV" get deploy mediagenda -o json | jq -r '.spec.template.spec.containers[0].resources.limits.memory // ""')"
      lim=384Mi
      [[ "$actuelle" == "$lim" ]] && lim=448Mi
      if ! wb_kubectl get namespace "$_E39_NS_PANNES" >/dev/null 2>&1; then
        wb_kubectl create namespace "$_E39_NS_PANNES" >/dev/null || return 1
        wb_kubectl label namespace "$_E39_NS_PANNES" pod-security.kubernetes.io/enforce=restricted >/dev/null || true
      fi
      _e39_correcteur "$lim" "$conteneur" | wb_kubectl apply --dry-run=server -f - >/dev/null 2>&1 || return 10
      _e39_correcteur "$lim" "$conteneur" | wb_kubectl apply -f - >/dev/null || { _e39_defaire 3; return 1; }
      m20_ecrire E39 correcteur pose
      m20_journal E39 "CronJob $_E39_NOM posé (limite mémoire $lim toutes les minutes)"
      m20_attendre 300 _e39_corrige_vu || { _e39_defaire 3; return 10; }
      ;;
  esac
  m20_journal E39 "variante $n posée"
}

_e39_defaire() {
  local n="$1" a
  case "$n" in
    1 | 2)
      m20_defaire_commits E39
      if [[ "$n" == 2 ]]; then
        m20_rafraichir racine applications
        # Si l'Application parente n'élague pas, labo-essai reste : on la retire sans cascade.
        sleep 30
        a="$(m20_app labo-essai)" || a=""
        if [[ -n "$a" ]] && jq -e '(.metadata.annotations["argocd.argoproj.io/tracking-id"] // "") | test("^(racine|applications):")' >/dev/null 2>&1 <<<"$a"; then
          wb_kubectl -n "$_M20_NS" patch applications.argoproj.io labo-essai --type json \
            -p '[{"op":"remove","path":"/metadata/finalizers"}]' >/dev/null 2>&1 || true
          wb_kubectl -n "$_M20_NS" delete applications.argoproj.io labo-essai --wait=false >/dev/null 2>&1 || true
        fi
        m20_rafraichir hard "$_E39_APP_LABO"
      else
        m20_rafraichir hard "$_M20_APP_DEV"
      fi
      ;;
    3)
      if [[ -n "$(m20_lire E39 correcteur)" ]]; then
        wb_kubectl -n "$_E39_NS_PANNES" delete cronjob "$_E39_NOM" --ignore-not-found >/dev/null 2>&1 || true
        wb_kubectl -n "$_E39_NS_PANNES" delete jobs -l "batch.kubernetes.io/cronjob-name=$_E39_NOM" --ignore-not-found >/dev/null 2>&1 || true
        wb_kubectl -n "$_M20_NS_DEV" delete rolebinding "$_E39_NOM" --ignore-not-found >/dev/null 2>&1 || true
        wb_kubectl -n "$_M20_NS_DEV" delete role "$_E39_NOM" --ignore-not-found >/dev/null 2>&1 || true
        wb_kubectl -n "$_E39_NS_PANNES" delete serviceaccount "$_E39_NOM" --ignore-not-found >/dev/null 2>&1 || true
        m20_oublier E39 correcteur
      fi
      m20_rafraichir "$_M20_APP_DEV"
      ;;
  esac
}

panne_E39_v1() { m20_preparer "$_M20_APP_DEV" && m20_essayer E39 3 1; }
panne_E39_v2() { m20_preparer "$_M20_APP_DEV" && m20_essayer E39 3 2; }
panne_E39_v3() { m20_preparer "$_M20_APP_DEV" && m20_essayer E39 3 3; }

verifier_E39() {
  case "${WB_VAR:-}" in
    1) _e39_bataille "$_M20_APP_DEV" ;;
    2) _e39_partage ;;
    3) _e39_corrige_vu ;;
    *) return 1 ;;
  esac
}

annuler_E39() {
  case "${WB_VAR:-}" in
    [1-3]) _e39_defaire "$WB_VAR" ;;
    *) _e39_defaire 3; _e39_defaire 2; m20_rafraichir hard "$_M20_APP_DEV" ;;
  esac
  m20_oublier E39 debut
  m20_journal E39 "annulation"
}

resume_E39() {
  case "${WB_VAR:-}" in
    2) echo "L'application labo se resynchronise toute seule en boucle, sans que personne ne pousse rien." ;;
    *) echo "Les pods de MédiAgenda dev sont recréés en boucle ; Argo CD montre une synchronisation automatique toutes les quelques minutes." ;;
  esac
}

symptome_E39() {
  case "${WB_VAR:-}" in
    2)
      wb_symptome "Ticket INC-4739 — De : Karim Benali" \
        "L'historique de l'application labo se remplit de synchronisations automatiques alors que" \
        "personne ne pousse rien sur formation/gitops-labo, et son statut passe sans arrêt de Synced" \
        "à OutOfSync. Quelque chose réécrit les objets de labo. Trouve qui, et fais cesser la" \
        "bataille sans désactiver l'auto-réparation." \
        "" \
        "Temps cible : 45 min. Contrôle : lab/bin/check 20 39"
      ;;
    *)
      wb_symptome "Ticket INC-4739 — De : Julien Petit" \
        "En dev, les pods de l'API sont recréés en boucle : nos tests tombent sur des connexions" \
        "coupées. Dans Argo CD, mediagenda-dev repasse OutOfSync et se resynchronise toute seule à" \
        "intervalles de plus en plus longs. Lucas assure qu'il « n'a rien cassé, juste aidé »." \
        "Trouve qui se bat avec Argo CD, et fais cesser la bataille sans désactiver l'auto-réparation." \
        "" \
        "Temps cible : 45 min. Contrôle : lab/bin/check 20 39"
      ;;
  esac
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 20 E39 3 "$@"; }
fi
