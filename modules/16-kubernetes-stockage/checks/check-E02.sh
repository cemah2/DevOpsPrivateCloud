# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E02.sh — M16-E02 : volumes éphémères, emptyDir et hostPath
# À lancer depuis adm01. Lecture seule : objets Kubernetes lus avec wb-checks.
# (Le compte de lignes de /tmp/couche et /travail/journal se vérifie avec kubectl exec, que les
# vérifications ne s'autorisent pas : seul le redémarrage du conteneur est contrôlé ici.)

# shellcheck source=_m16-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m16-decouverte.sh"

title "M16-E02 — Volumes éphémères, emptyDir et hostPath"
require_cmd jq kubectl

_m16d_e02_pod="$(_m16d_kj get pod e02-ephemere -n wb-essais)"

# --- 1. Le pod et ses trois volumes -------------------------------------------------------------------
check_cmd "wb-essais/e02-ephemere existe et tourne" _m16d_json "$_m16d_e02_pod" '.status.phase == "Running"'
check_cmd "volume travail : emptyDir sur disque, sizeLimit 200Mi" _m16d_json "$_m16d_e02_pod" \
  '.spec.volumes[] | select(.name == "travail") | .emptyDir | (.medium // "") == "" and .sizeLimit == "200Mi"'
check_cmd "volume cache : emptyDir en mémoire, sizeLimit 32Mi" _m16d_json "$_m16d_e02_pod" \
  '.spec.volumes[] | select(.name == "cache") | .emptyDir | .medium == "Memory" and .sizeLimit == "32Mi"'
check_cmd "volume config : projected (ConfigMap e02-config, API descendante, jeton audience wb-essais, 600 s)" \
  _m16d_json "$_m16d_e02_pod" '
    .spec.volumes[] | select(.name == "config") | .projected.sources as $s
    | ($s | any(.configMap.name == "e02-config"))
      and ($s | any(has("downwardAPI")))
      and ($s | any(.serviceAccountToken.audience == "wb-essais" and .serviceAccountToken.expirationSeconds == 600))'
check_cmd "ConfigMap wb-essais/e02-config présente" _m16d_json "$(_m16d_kj get configmap e02-config -n wb-essais)" \
  '.metadata.name == "e02-config"'
check_cmd "contexte de sécurité compatible restricted (non root, capacités retirées, seccomp)" \
  _m16d_json "$_m16d_e02_pod" '
    (.spec.securityContext.runAsNonRoot == true)
    and ((.spec.securityContext.seccompProfile.type // "") == "RuntimeDefault"
         or all(.spec.containers[]; (.securityContext.seccompProfile.type // "") == "RuntimeDefault"))
    and all(.spec.containers[]; .securityContext.allowPrivilegeEscalation == false
                                and ((.securityContext.capabilities.drop // []) | index("ALL")))'
check_cmd "le conteneur app a redémarré au moins une fois (RESTARTS ≥ 1)" _m16d_json "$_m16d_e02_pod" \
  '.status.containerStatuses[] | select(.name == "app") | .restartCount >= 1'

# --- 2. Ménage ---------------------------------------------------------------------------------------
check_cmd "le pod e02-gourmand n'existe plus" _m16d_absent pod e02-gourmand -n wb-essais
check_cmd "l'espace wb-privilegie n'existe plus" _m16d_absent namespace wb-privilegie

# --- 3. Pas de hostPath dans les espaces du workbook et des applications -------------------------------
_m16d_e02_tous="$(_m16d_kj get pods -A)"
check_cmd "aucun pod de wb-* ni de mediagenda-* ne monte un volume hostPath" _m16d_json "$_m16d_e02_tous" '
  [.items[] | select(.metadata.namespace | test("^(wb-|mediagenda-)"))
            | select(any(.spec.volumes[]?; has("hostPath")))] | length == 0'
check_cmd "wb-essais n'est pas en Pod Security « privileged » (enforce baseline ou restricted)" \
  _m16d_json "$(_m16d_kj get namespace wb-essais)" \
  '.metadata.labels["pod-security.kubernetes.io/enforce"] as $e | ($e == "baseline" or $e == "restricted")'
