# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # expressions jq et yq entre apostrophes
# break-S06.sh — F4-S06 « Panne : la montée qui bloque » (pendant une fenêtre de montée, Karim draine
# un nœud ; « le drain ne finit jamais » ou « plus aucun pod ne se crée »).
#
# Variantes :
#   1. PDB « maintenance-montee » à maxUnavailable: 0 posée à la main (par « Lucas ») sur une charge d'un
#      espace de RECETTE qui n'avait pas de PDB, et nœud qui porte un de ses pods cordonné (Karim a
#      interrompu un drain qui bouclait sur ce pod) → toute éviction refusée, le drain ne finit jamais ;
#   2. ValidatingWebhookConfiguration « medisphere-verification-montee » (failurePolicy: Fail) qui vise la
#      création des pods de mediagenda-recette, medinotif-recette et wb-essais et pointe vers un Service
#      sans point d'accès (wb-pannes/verification-montee) ; un pod de l'API de recette est supprimé pour
#      que le symptôme se voie → plus aucun pod ne se crée dans ces espaces ;
#   3. commit de Lucas dans mediagenda/deploiement (overlay recette SEULEMENT) qui ajoute une PDB en
#      policy/v1beta1 (API retirée depuis Kubernetes 1.25, jamais servie en 1.36) → l'Application Argo CD
#      de la recette passe en erreur de synchronisation. Si main refuse la poussée directe et que la MR
#      est arrêtée par le pipeline (composant « validation », M29), la variante est « sans effet » : on
#      passe à la suivante.
#
# Règles (CONVENTIONS §8, §11.10-11.11 ; PLAN §4.10 à §4.14) : contrôle préalable (lab sain) ; recette
# et wb-essais seulement ; jamais kube-system, argocd, kyverno, ni un espace *-prod ; aucun drain réel
# (pas de bascule CNPG en prod) ; chaque objet créé est sauvegardé « ABSENT » (wb_k8s_sauver) et supprimé
# par --annuler ; le commit est défait par un commit inverse seulement si le fichier est intact.
# État local : ~/.local/state/workbook/F4-S06/ (700) et ~/.local/state/workbook/k8s/F4-S06/.
# Outils requis sur adm01 : kubectl, jq, yq (mikefarah v4), curl. Jeton GitLab d'administration de
# l'apprenant (WB_GITLAB_ADMIN_TOKEN_FILE) pour la variante 3.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"

_S06_RECETTE=mediagenda-recette
_S06_NOTIF=medinotif-recette
_S06_API_SEL='app.kubernetes.io/name=mediagenda,app.kubernetes.io/component=api'
_S06_PDB=maintenance-montee
_S06_VWC=medisphere-verification-montee
_S06_SVC_NS=wb-pannes
_S06_SVC=verification-montee
_S06_DEPOT="${WB_F4_PROJET_DEPLOIEMENT:-mediagenda/deploiement}"
_S06_KUSTO="${WB_F4_FICHIER_KUSTO_RECETTE:-overlays/recette/kustomization.yaml}"
_S06_FICHIER_PDB="${_S06_KUSTO%/*}/pdb-maintenance.yaml"
_S06_GITLAB="${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}"
_S06_ETIQ='medisphere.internal/panne=F4-S06'

# ---------------------------------------------------------------------------
# État local
# ---------------------------------------------------------------------------
_s06_etat() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/F4-S06"
  mkdir -p "$d" && chmod 700 "$d"
  printf '%s\n' "$d"
}
_s06_poser() { printf '%s\n' "$2" >"$(_s06_etat)/$1"; }
_s06_lire() {
  local f
  f="$(_s06_etat)/$1"
  if [[ -f "$f" ]]; then cat "$f"; fi
}
_s06_oublier() { rm -f -- "$(_s06_etat)/$1"; }
_s06_journal() { printf '%s [F4-S06 variante %s] %s\n' "$(date -Is)" "${WB_VAR:-?}" "$*" >>"$(_s06_etat)/journal"; }

_s06_attendre() {
  local max="$1" t=0
  shift
  while ((t < max)); do
    if "$@"; then return 0; fi
    sleep 10
    t=$((t + 10))
  done
  "$@"
}

# ---------------------------------------------------------------------------
# Contrôle préalable : le lab doit être sain
# ---------------------------------------------------------------------------
_s06_api_pretes() {
  wb_kubectl -n "$_S06_RECETTE" get pods -l "$_S06_API_SEL" -o json 2>/dev/null |
    jq '[.items[] | select(.metadata.deletionTimestamp == null) | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))] | length' 2>/dev/null || echo 0
}

_s06_app_recette() {
  wb_kubectl -n argocd get applications.argoproj.io -o json 2>/dev/null |
    jq -r --arg ns "$_S06_RECETTE" '[.items[] | select(.spec.destination.namespace == $ns) | .metadata.name][0] // empty'
}

_s06_app_saine() {
  wb_kubectl -n argocd get applications.argoproj.io "$1" -o json 2>/dev/null |
    jq -e '.status.sync.status == "Synced" and .status.health.status == "Healthy"' >/dev/null 2>&1
}

_s06_sain() {
  local c a
  for c in kubectl jq yq curl; do
    command -v "$c" >/dev/null 2>&1 || { echo "outil manquant sur adm01 : $c" >&2; return 1; }
  done
  yq --version 2>/dev/null | grep -q mikefarah || { echo "yq de mikefarah (v4) attendu sur adm01" >&2; return 1; }
  wb_kubectl get --raw /readyz >/dev/null 2>&1 || { echo "L'API de k8s-par1 ne répond pas avec $WB_K8S_ADMIN_KUBECONFIG." >&2; return 1; }
  wb_kubectl get nodes -o json 2>/dev/null | jq -e '(.items | length) >= 6 and all(.items[]; (.spec.unschedulable // false) == false
      and any(.status.conditions[]; .type == "Ready" and .status == "True"))' >/dev/null 2>&1 ||
    { echo "Tous les nœuds doivent être Ready et aucun cordonné avant l'injection (fin de S04/S05 ?)." >&2; return 1; }
  if (($(_s06_api_pretes) < 2)); then
    echo "Il faut au moins deux pods prêts de l'API MédiAgenda en recette." >&2
    return 1
  fi
  a="$(_s06_app_recette)"
  if [[ -z "$a" ]] || ! _s06_app_saine "$a"; then
    echo "L'Application Argo CD de $_S06_RECETTE doit être Synced/Healthy." >&2
    return 1
  fi
  _s06_poser app "$a"
  if wb_kubectl get validatingwebhookconfiguration "$_S06_VWC" >/dev/null 2>&1; then
    echo "Une configuration $_S06_VWC existe déjà : lance d'abord lab/bin/break F4 6 --annuler." >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Variante 1 : PDB qui interdit toute éviction + nœud cordonné
# ---------------------------------------------------------------------------

# _s06_candidat — « espace pod nœud clé=valeur[,clé=valeur] » : un pod en marche d'un espace de recette,
# sur un travailleur, géré par un ReplicaSet ou un StatefulSet, qu'AUCUNE PDB existante ne couvre (sinon
# l'éviction échouerait pour une autre raison : plusieurs PDB sur un même pod).
_s06_candidat() {
  local ns pods pdbs
  for ns in "$_S06_RECETTE" "$_S06_NOTIF"; do
    pods="$(wb_kubectl -n "$ns" get pods -o json 2>/dev/null)" || continue
    pdbs="$(wb_kubectl -n "$ns" get pdb -o json 2>/dev/null)" || pdbs='{"items":[]}'
    jq -r --arg ns "$ns" --argjson pdbs "$pdbs" '
      def couvert(l): any($pdbs.items[]; (.spec.selector.matchExpressions // []) != []
          or ((.spec.selector.matchLabels // {}) | to_entries | all(.key as $k | .value as $v | l[$k] == $v)));
      [.items[] | select(.status.phase == "Running" and .metadata.deletionTimestamp == null)
        | select(any(.metadata.ownerReferences[]?; .kind == "ReplicaSet" or .kind == "StatefulSet"))
        | (.metadata.labels // {}) as $l
        | select(couvert($l) | not)
        | select(($l["app.kubernetes.io/name"] // "") != "")
        | "\($ns) \(.metadata.name) \(.spec.nodeName) app.kubernetes.io/name=\($l["app.kubernetes.io/name"])\(
            if ($l["app.kubernetes.io/component"] // "") != "" then ",app.kubernetes.io/component=" + $l["app.kubernetes.io/component"] else "" end)"
      ] | first // empty' <<<"$pods" 2>/dev/null | grep . && return 0
  done
  return 1
}

_s06_v1() {
  local l ns pod noeud sel role
  l="$(_s06_candidat)" || { wb_avert "aucune charge de recette sans PDB : variante 1 sans effet ici"; return 10; }
  read -r ns pod noeud sel <<<"$l"
  role="$(wb_kubectl get node "$noeud" -o json 2>/dev/null | jq -r '.metadata.labels | has("node-role.kubernetes.io/control-plane")')"
  [[ "$role" == false ]] || return 10
  _s06_poser v1 "$ns $pod $noeud $sel"
  wb_k8s_sauver poddisruptionbudget "$_S06_PDB" "$ns"
  {
    printf 'apiVersion: policy/v1\nkind: PodDisruptionBudget\nmetadata:\n  name: %s\n  namespace: %s\n' "$_S06_PDB" "$ns"
    printf '  labels:\n    medisphere.internal/auteur: lucas.martin\n    medisphere.internal/panne: F4-S06\n'
    printf '  annotations:\n    medisphere.internal/note: "Protège la recette pendant la montée (Lucas)"\n'
    printf 'spec:\n  maxUnavailable: 0\n  selector:\n    matchLabels:\n'
    tr ',' '\n' <<<"$sel" | awk -F= '{ printf "      %s: \"%s\"\n", $1, $2 }'
  } | wb_kubectl apply -f - >/dev/null || return 1
  _s06_journal "PDB $ns/$_S06_PDB (maxUnavailable 0, $sel)"
  wb_kubectl cordon "$noeud" >/dev/null || return 1
  _s06_poser noeud "$noeud"
  _s06_journal "nœud $noeud cordonné (drain interrompu par Karim)"
  _s06_attendre 60 _s06_v1_effective || return 1
}

_s06_v1_effective() {
  local ns pod noeud sel
  read -r ns pod noeud sel <<<"$(_s06_lire v1)"
  [[ -n "${noeud:-}" ]] || return 1
  wb_kubectl -n "$ns" get pdb "$_S06_PDB" -o json 2>/dev/null |
    jq -e '(.status.expectedPods // 0) >= 1 and (.status.disruptionsAllowed // 1) == 0' >/dev/null 2>&1 || return 1
  wb_kubectl get node "$noeud" -o json 2>/dev/null | jq -e '.spec.unschedulable == true' >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Variante 2 : webhook de validation « Fail » sans point d'accès
# ---------------------------------------------------------------------------
_s06_v2() {
  local pod
  wb_k8s_sauver namespace "$_S06_SVC_NS"
  wb_k8s_sauver service "$_S06_SVC" "$_S06_SVC_NS"
  wb_k8s_sauver validatingwebhookconfiguration "$_S06_VWC"
  if ! wb_kubectl get namespace "$_S06_SVC_NS" >/dev/null 2>&1; then
    wb_kubectl create namespace "$_S06_SVC_NS" >/dev/null || return 1
    wb_kubectl label namespace "$_S06_SVC_NS" "$_S06_ETIQ" >/dev/null || true
  fi
  cat <<EOF | wb_kubectl apply -f - >/dev/null || return 1
apiVersion: v1
kind: Service
metadata:
  name: $_S06_SVC
  namespace: $_S06_SVC_NS
  labels: {medisphere.internal/auteur: lucas.martin, medisphere.internal/panne: F4-S06}
spec:
  # Aucun sélecteur et aucun EndpointSlice : le Service n'a pas de point d'accès.
  ports:
    - {name: https, port: 443, targetPort: 8443, protocol: TCP}
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: $_S06_VWC
  labels: {medisphere.internal/auteur: lucas.martin, medisphere.internal/panne: F4-S06}
  annotations:
    medisphere.internal/note: "Contrôle des pods pendant la montée (essai de Lucas, à retirer après la fenêtre)"
webhooks:
  - name: pods.verification-montee.medisphere.internal
    admissionReviewVersions: [v1]
    sideEffects: None
    failurePolicy: Fail
    timeoutSeconds: 5
    clientConfig:
      service: {namespace: $_S06_SVC_NS, name: $_S06_SVC, path: /valider, port: 443}
    namespaceSelector:
      matchExpressions:
        - {key: kubernetes.io/metadata.name, operator: In, values: [$_S06_RECETTE, $_S06_NOTIF, wb-essais]}
    rules:
      - {operations: [CREATE], apiGroups: [""], apiVersions: [v1], resources: [pods], scope: Namespaced}
EOF
  _s06_journal "webhook $_S06_VWC → $_S06_SVC_NS/$_S06_SVC (sans point d'accès)"
  sleep 5
  _s06_v2_effective || return 1
  # Symptôme visible : un pod de l'API de recette disparaît et ne revient pas.
  pod="$(wb_kubectl -n "$_S06_RECETTE" get pods -l "$_S06_API_SEL" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)" || pod=""
  if [[ -n "$pod" ]]; then
    wb_kubectl -n "$_S06_RECETTE" delete pod "$pod" --wait=false >/dev/null 2>&1 || true
    _s06_journal "pod $pod supprimé (le ReplicaSet ne peut plus le recréer)"
  fi
}

# Une création de pod conforme à « restricted » est refusée par le webhook (essai à blanc côté serveur).
_s06_v2_effective() {
  local sortie
  sortie="$(cat <<EOF | wb_kubectl create --dry-run=server -f - 2>&1
apiVersion: v1
kind: Pod
metadata: {name: f4-s06-essai, namespace: wb-essais}
spec:
  securityContext: {runAsNonRoot: true, runAsUser: 65532, seccompProfile: {type: RuntimeDefault}}
  containers:
    - name: essai
      image: registry.par1.medisphere.internal/dockerhub/library/busybox:1.37
      command: ["true"]
      resources: {requests: {cpu: 10m, memory: 16Mi}, limits: {cpu: 50m, memory: 32Mi}}
      securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: [ALL]}}
EOF
)" && return 1
  grep -q 'verification-montee' <<<"$sortie"
}

# ---------------------------------------------------------------------------
# Variante 3 : API retirée dans un manifeste Git (commit de Lucas, overlay recette)
# ---------------------------------------------------------------------------
_s06_enc() { jq -rn --arg s "$1" '$s|@uri'; }

_s06_api() {
  local m="$1" p="$2" f t
  shift 2
  f="${WB_GITLAB_ADMIN_TOKEN_FILE:-$HOME/.config/workbook/gitlab-admin.token}"
  [[ -r "$f" ]] || { wb_avert "jeton d'administration GitLab illisible : $f"; return 1; }
  t="$(tr -d '[:space:]' <"$f")"
  curl -sf --max-time 30 -X "$m" -H @<(printf 'PRIVATE-TOKEN: %s\n' "$t") "$_S06_GITLAB/api/v4/$p" "$@"
}

_s06_git_lire() { _s06_api GET "projects/$(_s06_enc "$1")/repository/files/$(_s06_enc "$2")/raw?ref=${3:-main}"; }

# _s06_commit BRANCHE "message" FICHIER_ACTIONS — commit au nom de Lucas ; affiche le sha.
_s06_commit() {
  local corps
  corps="$(jq -n --arg b "$1" --arg m "$2" --slurpfile a "$3" \
    '{branch: $b, commit_message: $m, author_name: "Lucas Martin", author_email: "lucas.martin@medisphere.internal", actions: $a[0]}')"
  _s06_api POST "projects/$(_s06_enc "$_S06_DEPOT")/repository/commits" \
    -H 'Content-Type: application/json' --data-binary "$corps" | jq -r '.id // empty'
}

# _s06_pousser "message" FICHIER_ACTIONS — sur main si accepté, sinon branche + MR fusionnée après son
# pipeline (≤ 15 min). Code 10 si le pipeline refuse (la validation a fait son travail).
_s06_pousser() {
  local msg="$1" actions="$2" sha br p iid etat i
  sha="$(_s06_commit main "$msg" "$actions" 2>/dev/null)" || sha=""
  [[ -n "$sha" ]] && return 0
  p="$(_s06_enc "$_S06_DEPOT")"
  br="lucas/f4-s06-$(date +%s)"
  _s06_api POST "projects/$p/repository/branches" --data-urlencode "branch=$br" --data-urlencode "ref=main" >/dev/null || return 1
  sha="$(_s06_commit "$br" "$msg" "$actions")" || sha=""
  [[ -n "$sha" ]] || return 1
  iid="$(_s06_api POST "projects/$p/merge_requests" --data-urlencode "source_branch=$br" --data-urlencode "target_branch=main" \
    --data-urlencode "title=${msg%%$'\n'*}" --data-urlencode "remove_source_branch=true" | jq -r '.iid // empty')" || iid=""
  [[ -n "$iid" ]] || return 1
  sleep 5
  _s06_api PUT "projects/$p/merge_requests/$iid/merge" --data-urlencode "auto_merge=true" >/dev/null 2>&1 ||
    _s06_api PUT "projects/$p/merge_requests/$iid/merge" --data-urlencode "merge_when_pipeline_succeeds=true" >/dev/null 2>&1 || true
  for ((i = 0; i < 60; i++)); do
    etat="$(_s06_api GET "projects/$p/merge_requests/$iid" | jq -r '.state // empty')" || etat=""
    [[ "$etat" == merged ]] && return 0
    [[ "$etat" == closed ]] && break
    sleep 15
  done
  _s06_api PUT "projects/$p/merge_requests/$iid" --data-urlencode "state_event=close" >/dev/null 2>&1 || true
  _s06_api DELETE "projects/$p/repository/branches/$(_s06_enc "$br")" >/dev/null 2>&1 || true
  wb_avert "la MR de Lucas n'a pas été fusionnée (pipeline de validation ?) : variante 3 sans effet ici"
  return 10
}

_s06_pdb_v1beta1() {
  cat <<'EOF'
# PDB pour la montée : l'API de recette ne doit pas tomber pendant les drains. -- Lucas
# (copiée du dossier d'exploitation d'InfoGér)
apiVersion: policy/v1beta1
kind: PodDisruptionBudget
metadata:
  name: mediagenda-maintenance
spec:
  maxUnavailable: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: mediagenda
      app.kubernetes.io/component: api
EOF
}

_s06_v3() {
  local d actions rc=0
  d="$(_s06_etat)"
  _s06_git_lire "$_S06_DEPOT" "$_S06_KUSTO" >"$d/kusto.orig" 2>/dev/null || { wb_avert "$_S06_KUSTO introuvable"; return 10; }
  if _s06_git_lire "$_S06_DEPOT" "$_S06_FICHIER_PDB" >/dev/null 2>&1; then
    wb_avert "$_S06_FICHIER_PDB existe déjà dans $_S06_DEPOT"
    return 10
  fi
  yq '.resources += ["pdb-maintenance.yaml"]' "$d/kusto.orig" >"$d/kusto.neuf" || return 10
  _s06_pdb_v1beta1 >"$d/pdb.neuf"
  actions="$d/actions.json"
  jq -n --arg k "$_S06_KUSTO" --rawfile kc "$d/kusto.neuf" --arg p "$_S06_FICHIER_PDB" --rawfile pc "$d/pdb.neuf" \
    '[{action: "update", file_path: $k, content: $kc}, {action: "create", file_path: $p, content: $pc}]' >"$actions"
  chmod 600 "$d"/kusto.* "$d"/pdb.neuf "$actions"
  _s06_pousser "chore(recette): PDB de l'API pour les drains de la montée (F4-S06)

Repris du dossier d'InfoGér, ça évitera de couper la recette pendant la fenêtre. -- Lucas" "$actions" || rc=$?
  ((rc == 0)) || return "$rc"
  _s06_poser git injecte
  _s06_journal "commit de Lucas sur $_S06_DEPOT ($_S06_FICHIER_PDB, policy/v1beta1)"
  wb_kubectl -n argocd annotate applications.argoproj.io "$(_s06_lire app)" argocd.argoproj.io/refresh=hard --overwrite >/dev/null 2>&1 || true
  _s06_attendre 420 _s06_v3_effective || return 1
}

_s06_v3_effective() {
  wb_kubectl -n argocd get applications.argoproj.io "$(_s06_lire app)" -o json 2>/dev/null |
    jq -e '(.status | tostring) as $s | ($s | test("v1beta1|PodDisruptionBudget"))
      and (any(.status.conditions[]?; .type | test("Error")) or ((.status.operationState.phase // "") | test("Failed|Error")))' >/dev/null 2>&1
}

# Le commit est défait seulement si les deux fichiers sont encore dans l'état injecté.
_s06_v3_defaire() {
  local d actions
  [[ "$(_s06_lire git)" == injecte ]] || return 0
  d="$(_s06_etat)"
  if cmp -s <(_s06_git_lire "$_S06_DEPOT" "$_S06_KUSTO" 2>/dev/null) "$d/kusto.neuf" &&
    cmp -s <(_s06_git_lire "$_S06_DEPOT" "$_S06_FICHIER_PDB" 2>/dev/null) "$d/pdb.neuf"; then
    actions="$d/inverse.json"
    jq -n --arg k "$_S06_KUSTO" --rawfile kc "$d/kusto.orig" --arg p "$_S06_FICHIER_PDB" \
      '[{action: "update", file_path: $k, content: $kc}, {action: "delete", file_path: $p}]' >"$actions"
    if _s06_pousser "Revert du commit de Lucas (lab/bin/break F4 6 --annuler, F4-S06)" "$actions"; then
      _s06_journal "annulation : commit inverse sur $_S06_DEPOT"
    else
      wb_avert "commit inverse impossible sur $_S06_DEPOT : remets les fichiers à la main (copies : $d)"
      return 0
    fi
  else
    _s06_journal "annulation : $_S06_DEPOT déjà corrigé depuis la panne, rien à défaire"
  fi
  rm -f -- "$d"/kusto.* "$d"/pdb.neuf "$d"/actions.json "$d"/inverse.json
  _s06_oublier git
}

# ---------------------------------------------------------------------------
# Essai des variantes : une variante « sans effet » (code 10) passe la main à la suivante.
# ---------------------------------------------------------------------------
_s06_une() {
  case "$1" in
    1) _s06_v1 ;;
    2) _s06_v2 ;;
    3) _s06_v3 ;;
  esac
}

_s06_defaire_tout() {
  local n
  _s06_v3_defaire || true
  n="$(_s06_lire noeud)"
  if [[ -n "$n" ]]; then
    wb_kubectl uncordon "$n" >/dev/null 2>&1 || true
    _s06_journal "nœud $n remis en service"
    _s06_oublier noeud
  fi
  wb_k8s_restaurer || wb_avert "restauration partielle des objets Kubernetes (voir ~/.local/state/workbook/k8s/F4-S06)"
  _s06_oublier v1
  local a
  a="$(_s06_lire app)"
  [[ -n "$a" ]] && wb_kubectl -n argocd annotate applications.argoproj.io "$a" argocd.argoproj.io/refresh=hard --overwrite >/dev/null 2>&1
  return 0
}

_s06_essayer() {
  local depart="$1" i n rc
  _s06_sain || return 1
  for ((i = 0; i < 3; i++)); do
    n=$(((depart - 1 + i) % 3 + 1))
    WB_VAR="$n"
    rc=0
    _s06_une "$n" || rc=$?
    ((rc == 0)) && return 0
    _s06_defaire_tout
    ((rc == 10)) || return 1
  done
  wb_avert "aucune variante de F4-S06 n'a d'effet sur ce lab"
  return 1
}

panne_S06_v1() { _s06_essayer 1; }
panne_S06_v2() { _s06_essayer 2; }
panne_S06_v3() { _s06_essayer 3; }

verifier_S06() {
  case "$WB_VAR" in
    1) _s06_v1_effective ;;
    2) _s06_v2_effective ;;
    3) _s06_v3_effective ;;
    *) return 1 ;;
  esac
}

annuler_S06() {
  _s06_defaire_tout
  _s06_journal "annulation terminée"
}

resume_S06() {
  case "$WB_VAR" in
    1) echo "Pendant la montée, le drain d'un travailleur ne se termine jamais." ;;
    2) echo "Pendant la montée, plus aucun pod ne se crée en recette." ;;
    *) echo "Pendant la montée, Argo CD signale la recette de MédiAgenda en erreur." ;;
  esac
}

symptome_S06() {
  case "$WB_VAR" in
    1)
      wb_symptome "Ticket INC-6006 — De : Karim Benali" \
        "Fenêtre de montée, travailleur suivant : le drain de $(_s06_lire noeud) ne finit jamais, il" \
        "tourne en rond depuis vingt minutes. Je l'ai interrompu ; le nœud est resté cordonné." \
        "La fenêtre se ferme dans une heure : je veux comprendre avant de relancer quoi que ce" \
        "soit, et que la montée reprenne sans rien casser en recette." \
        "" \
        "Temps cible : 45 min. Contrôle : lab/bin/check F4 6"
      ;;
    2)
      wb_symptome "Ticket INC-6006 — De : Karim Benali" \
        "Pendant la fenêtre, plus aucun pod ne se crée en recette : l'API de MédiAgenda a perdu une" \
        "réplique et ne la retrouve pas, et Nadia n'arrive même plus à lancer un pod de test dans" \
        "wb-essais. Le reste du cluster a l'air normal. Je ne relance aucun drain tant qu'on ne sait pas." \
        "" \
        "Temps cible : 45 min. Contrôle : lab/bin/check F4 6"
      ;;
    *)
      wb_symptome "Ticket INC-6006 — De : Karim Benali" \
        "Juste avant de drainer le travailleur suivant, Argo CD affiche la recette de MédiAgenda en" \
        "erreur. Personne n'a touché à la recette ce matin… enfin, à part le « petit ajout pour la" \
        "montée » de Lucas. On ne continue pas avec une recette qui ne se synchronise plus." \
        "" \
        "Temps cible : 30 min. Contrôle : lab/bin/check F4 6"
      ;;
  esac
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main F4 S06 3 "$@"; }
fi
