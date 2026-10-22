# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # expressions perl, CEL et jq entre apostrophes
# break-E42.sh — M19-E42 « Panne : le job est tué en cours de route »
#
# Le canari du témoin occupe 120 Mio de mémoire et 100 Mio de disque dans /tmp pendant 45 s.
# Variantes :
#   1. gabarit TOML du runner k8s-par1 : memory_limit (conteneur build) abaissé à 64Mi → OOMKilled ;
#   2. MutatingAdmissionPolicy (admissionregistration.k8s.io/v1, GA en 1.36) de Lucas qui impose
#      activeDeadlineSeconds: 30 à tous les pods de ci-jobs (« tuer les jobs zombies ») → le pod
#      passe en Failed (DeadlineExceeded) au bout de 30 s ;
#   3. gabarit TOML : ephemeral_storage_limit (conteneur build) à 50Mi → éviction par le kubelet ;
#   4. Deployment « reindexation-nocturne » de Lucas (espace wb-pannes-ci, PriorityClass
#      medisphere-critique) qui demande la mémoire libre du nœud où tourne le canari : l'ordonnanceur
#      préempte le pod de job (PriorityClass medisphere-ci, la plus basse).
# Vérification : un pipeline du témoin, le job canari échoue (variante 4 : événement Preempted).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m19-commun.sh
source "$WB_ROOT/modules/19-ci/corrige/pannes/_m19-commun.sh"

_E42_MAP=ci-jobs-delai-maximal
_E42_DEMO=reindexation-nocturne

# _e42_toml_cle CLÉ VALEUR — programme perl : remplace la clé dans [runners.kubernetes] ou l'y ajoute.
_e42_toml_cle() {
  printf 's{^(\\s*)%s\\s*=\\s*"[^"]*"}{${1}%s = "%s"}m or s{^(\\s*)\\[runners\\.kubernetes\\]\\s*$}{${1}[runners.kubernetes]\\n${1}  %s = "%s"}m' \
    "$1" "$1" "$2" "$1" "$2"
}

_e42_map() {
  cat <<EOF
apiVersion: admissionregistration.k8s.io/v1
kind: MutatingAdmissionPolicy
metadata:
  name: $_E42_MAP
  labels: {medisphere.internal/auteur: lucas.martin}
  annotations: {medisphere.internal/ticket: "PLAT-2042 tuer les jobs zombies (Lucas)"}
spec:
  matchConstraints:
    resourceRules:
      - apiGroups: [""]
        apiVersions: ["v1"]
        operations: ["CREATE"]
        resources: ["pods"]
  failurePolicy: Ignore
  reinvocationPolicy: Never
  mutations:
    - patchType: ApplyConfiguration
      applyConfiguration:
        expression: >
          Object{
            spec: Object.spec{
              activeDeadlineSeconds: 30
            }
          }
---
apiVersion: admissionregistration.k8s.io/v1
kind: MutatingAdmissionPolicyBinding
metadata:
  name: $_E42_MAP
  labels: {medisphere.internal/auteur: lucas.martin}
spec:
  policyName: $_E42_MAP
  matchResources:
    namespaceSelector:
      matchLabels: {kubernetes.io/metadata.name: $_M19_NS_JOBS}
EOF
}

# _e42_demo NŒUD MÉMOIRE — Deployment de Lucas qui réserve MÉMOIRE (Mi) sur NŒUD, priorité haute.
_e42_demo() {
  cat <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: $_M19_NS_DEMO
  labels:
    pod-security.kubernetes.io/enforce: restricted
    medisphere.internal/role: pannes-workbook
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $_E42_DEMO
  namespace: $_M19_NS_DEMO
  labels: {app.kubernetes.io/name: $_E42_DEMO, medisphere.internal/auteur: lucas.martin}
spec:
  replicas: 1
  selector: {matchLabels: {app.kubernetes.io/name: $_E42_DEMO}}
  template:
    metadata: {labels: {app.kubernetes.io/name: $_E42_DEMO}}
    spec:
      priorityClassName: medisphere-critique
      nodeSelector: {kubernetes.io/hostname: $1}
      automountServiceAccountToken: false
      securityContext: {runAsNonRoot: true, runAsUser: 65534, seccompProfile: {type: RuntimeDefault}}
      containers:
        - name: reindexation
          image: $_M19_REGISTRE/dockerhub/library/busybox:1.37
          command: ["sh", "-c", "echo réindexation prioritaire; sleep 86400"]
          resources: {requests: {cpu: 10m, memory: ${2}Mi}, limits: {cpu: 50m, memory: ${2}Mi}}
          securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}}
EOF
}

# _e42_pod_canari — « pod nœud demande_mémoire_Mi » du pod de job du témoin en cours dans ci-jobs.
_e42_pod_canari() {
  local pid
  pid="$(m19_temoin_id)" || return 1
  wb_kubectl -n "$_M19_NS_JOBS" get pods -o json 2>/dev/null | jq -r --arg p "-project-$pid-" '
    def mio: if test("Gi$") then (sub("Gi$"; "") | tonumber * 1024) elif test("Mi$") then (sub("Mi$"; "") | tonumber)
             elif test("Ki$") then (sub("Ki$"; "") | tonumber / 1024) else (tonumber / 1048576) end;
    [.items[] | select((.metadata.name | contains($p)) and .status.phase == "Running")
     | "\(.metadata.name) \(.spec.nodeName) \([.spec.containers[].resources.requests.memory // "0" | mio] | add | floor)"][0] // empty'
}

# _e42_memoire_libre NŒUD — mémoire allouable moins demandes des pods non terminés (Mi).
_e42_memoire_libre() {
  local alloc dem
  alloc="$(wb_kubectl get node "$1" -o json | jq -r '.status.allocatable.memory
    | if test("Ki$") then (sub("Ki$"; "") | tonumber / 1024) elif test("Mi$") then (sub("Mi$"; "") | tonumber)
      elif test("Gi$") then (sub("Gi$"; "") | tonumber * 1024) else (tonumber / 1048576) end | floor')"
  dem="$(wb_kubectl get pods -A --field-selector "spec.nodeName=$1,status.phase!=Succeeded,status.phase!=Failed" -o json | jq -r '
    def mio: if test("Gi$") then (sub("Gi$"; "") | tonumber * 1024) elif test("Mi$") then (sub("Mi$"; "") | tonumber)
             elif test("Ki$") then (sub("Ki$"; "") | tonumber / 1024) elif test("G$") then (sub("G$"; "") | tonumber * 953.674)
             elif test("M$") then (sub("M$"; "") | tonumber * 0.953674) else (tonumber / 1048576) end;
    [.items[].spec.containers[].resources.requests.memory // "0" | mio] | add // 0 | floor')"
  echo $((alloc - dem))
}

_m19E42_une() {
  local n="$1" pl st id pod noeud dem libre t=0
  m19_debut E42
  case "$n" in
    1) m19_toml_modifier E42 "$(_e42_toml_cle memory_limit 64Mi)" || return $? ;;
    3) m19_toml_modifier E42 "$(_e42_toml_cle ephemeral_storage_limit 50Mi)" || return $? ;;
    2)
      _e42_map | wb_kubectl apply --dry-run=server -f - >/dev/null 2>&1 || return 10
      _e42_map | wb_kubectl apply -f - >/dev/null || return 1
      m19_ecrire E42 map 1
      sleep 10
      ;;
    4)
      wb_kubectl get priorityclass medisphere-critique medisphere-ci >/dev/null 2>&1 || return 10
      pl="$(m19_temoin_lancer)" || return 1
      while ((t < 240)); do
        read -r pod noeud dem < <(_e42_pod_canari) || true
        [[ -n "${pod:-}" ]] && break
        sleep 5
        t=$((t + 5))
      done
      [[ -n "${pod:-}" ]] || return 10
      libre="$(_e42_memoire_libre "$noeud")"
      ((libre >= 0)) || libre=0
      m19_ecrire E42 demo "$noeud"
      _e42_demo "$noeud" $((libre + (dem > 64 ? dem / 2 : 32))) | wb_kubectl apply -f - >/dev/null || { _e42_defaire 4; return 10; }
      m19_journal E42 "variante 4 : $_E42_DEMO posé sur $noeud ($pod demandait ${dem} Mi)"
      read -r st id < <(m19_attendre_job "$_M19_TEMOIN" "$pl" canari 300)
      if [[ "$st" == success ]] || ! m19_evenement_depuis E42 "$_M19_NS_JOBS" '^Preempt'; then _e42_defaire 4; return 10; fi
      m19_journal E42 "variante 4 constatée"
      return 0
      ;;
  esac
  m19_journal E42 "variante $n posée"
  read -r st id < <(m19_temoin_cycle 420)
  if [[ "$st" == success ]]; then _e42_defaire "$n"; return 10; fi
  m19_journal E42 "variante $n constatée (job $id : $st)"
}

_e42_defaire() {
  local n="$1"
  case "$n" in
    1 | 3) m19_toml_retablir E42 ;;
    2)
      if [[ -n "$(m19_lire E42 map)" ]]; then
        wb_kubectl delete mutatingadmissionpolicybindings.admissionregistration.k8s.io "$_E42_MAP" --ignore-not-found >/dev/null 2>&1 || true
        wb_kubectl delete mutatingadmissionpolicies.admissionregistration.k8s.io "$_E42_MAP" --ignore-not-found >/dev/null 2>&1 || true
      fi
      m19_oublier E42 map
      ;;
    4)
      if [[ -n "$(m19_lire E42 demo)" ]]; then
        wb_kubectl -n "$_M19_NS_DEMO" delete deploy "$_E42_DEMO" --ignore-not-found >/dev/null 2>&1 || true
      fi
      m19_oublier E42 demo
      ;;
  esac
}

panne_E42_v1() { m19_preparer && m19_essayer E42 4 1; }
panne_E42_v2() { m19_preparer && m19_essayer E42 4 2; }
panne_E42_v3() { m19_preparer && m19_essayer E42 4 3; }
panne_E42_v4() { m19_preparer && m19_essayer E42 4 4; }

verifier_E42() {
  case "${WB_VAR:-}" in
    1) m19_toml "$(m19_lire E42 toml-cm)" | grep -Eq '^\s*memory_limit\s*=\s*"64Mi"' ;;
    3) m19_toml "$(m19_lire E42 toml-cm)" | grep -Eq '^\s*ephemeral_storage_limit\s*=\s*"50Mi"' ;;
    2) wb_kubectl get mutatingadmissionpolicies.admissionregistration.k8s.io "$_E42_MAP" >/dev/null 2>&1 ;;
    4) wb_kubectl -n "$_M19_NS_DEMO" get deploy "$_E42_DEMO" >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

annuler_E42() {
  case "${WB_VAR:-}" in
    [1-4]) _e42_defaire "$WB_VAR" ;;
    *) local v; for v in 1 2 3 4; do _e42_defaire "$v"; done ;;
  esac
  m19_oublier E42 debut
  m19_journal E42 "annulation"
}

resume_E42() { echo "Le job du canari (formation/ci-pannes) est tué en cours d'exécution, sans erreur dans son script."; }

symptome_E42() {
  wb_symptome "Ticket INC-4642 — De : Julien Petit" \
    "Le job du canari (formation/ci-pannes) meurt en plein milieu : il démarre, affiche ses" \
    "premières lignes, puis le journal s'arrête net et le job passe en échec, sans erreur de" \
    "notre script. Chez nous, les tests d'intégration ont le même comportement depuis hier." \
    "Lucas a fait « de l'optimisation de ressources » sur le cluster. Trouve qui tue le job." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 19 42"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 19 E42 4 "$@"; }
fi
