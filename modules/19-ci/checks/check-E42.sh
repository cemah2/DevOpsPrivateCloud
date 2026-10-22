# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E42.sh — M19-E42 « Panne : le job est tué en cours de route » : limites mémoire et disque des
# jobs raisonnables, aucune politique de mutation qui raccourcit la vie des pods de job, aucune charge
# prioritaire qui préempte les jobs, dernier canari vert, RB-195, panne close. Lecture seule.

# shellcheck source=_m19-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m19-expert.sh"

title "M19-E42 — Les jobs vont au bout"
require_cmd jq kubectl curl

if _m19x_api_repond; then
  _m19_e42_m="$(_m19x_toml_valeur memory_limit)"
  if [[ -n "$_m19_e42_m" ]]; then
    _m19_e42_au_moins() { (($(_m19x_mio "$1") >= $2)); }
    check_cmd "gabarit du runner : memory_limit des jobs ≥ 256 Mio ($_m19_e42_m)" _m19_e42_au_moins "$_m19_e42_m" 256
  else
    skip "memory_limit des jobs" "absent du gabarit (limites par défaut du LimitRange de ci-jobs)"
  fi
  _m19_e42_e="$(_m19x_toml_valeur ephemeral_storage_limit)"
  if [[ -n "$_m19_e42_e" ]]; then
    _m19_e42_au_moins_e() { (($(_m19x_mio "$1") >= 1024)); }
    check_cmd "gabarit du runner : ephemeral_storage_limit des jobs ≥ 1 Gio ($_m19_e42_e)" _m19_e42_au_moins_e "$_m19_e42_e"
  else
    skip "ephemeral_storage_limit des jobs" "absent du gabarit"
  fi
  if kube get mutatingadmissionpolicies.admissionregistration.k8s.io >/dev/null 2>&1; then
    check_cmd "aucune MutatingAdmissionPolicy qui impose activeDeadlineSeconds" \
      _m19x_kq '[.items[] | select(any(.spec.mutations[]?; (.applyConfiguration.expression // .jsonPatch.expression // "") | test("activeDeadlineSeconds")))] | length == 0' \
      mutatingadmissionpolicies.admissionregistration.k8s.io
  else
    skip "MutatingAdmissionPolicies" "non lisibles par le compte des checks"
  fi
  _m19_e42_pas_de_demo() { ! kube -n wb-pannes-ci get deploy reindexation-nocturne -o json 2>/dev/null | jq -e '.spec.replicas > 0' >/dev/null 2>&1; }
  check_cmd "aucun Deployment « reindexation-nocturne » prioritaire (wb-pannes-ci)" _m19_e42_pas_de_demo
  check_cmd "pods de job de ci-jobs : PriorityClass medisphere-ci (préemptibles, et les seuls)" \
    _m19x_kq 'all(.items[] | select(.metadata.name | startswith("runner-")); .spec.priorityClassName == "medisphere-ci")' -n ci-jobs pods
else
  skip "objets Kubernetes" "l'API de k8s-par1 ne répond pas au compte des checks"
fi
if _m19x_temoin_existe; then
  check_cmd "témoin : dernier canari de main allé au bout (« CANARI terminé »)" _m19x_canari_trace 'CANARI terminé'
else
  skip "témoin $_m19x_temoin" "absent : il est créé à la première injection (lab/bin/break 19 42)"
fi
_m19_e42_rb() { _m19x_doc_contient 'RB-195*.md' 'OOMKilled' && _m19x_doc_contient 'RB-195*.md' 'préempt'; }
check_cmd "RB-195 : section sur les jobs tués (OOMKilled, délai, éviction, préemption)" _m19_e42_rb
check_cmd "panne M19-E42 close (lab/bin/break 19 42 --annuler après réparation)" _m19x_aucune_panne_active E42
