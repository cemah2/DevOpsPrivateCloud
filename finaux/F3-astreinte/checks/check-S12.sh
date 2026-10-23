# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016,SC2031  # filtres jq entre apostrophes ; sous-shell des preuves (variables lues seulement)
# check-S12.sh — F3-S12 « Vendredi : alerte Falco en production » (INC-5912) : Falco et la politique de
# quarantaine en place ; le pod suspect (noté par l'injection) est soit isolé (étiquette de quarantaine,
# sorti de son contrôleur, plus derrière aucun Service), soit supprimé APRÈS le dépôt des preuves ; le
# service de l'espace est rétabli ; des preuves avec leurs empreintes sont dans preuves/INC-5912/ ; la
# main courante porte la qualification (décision) et l'escalade à la RSSI ; trace de l'incident.
# Lecture seule : kube, état local de l'injection (lecture), S3 en liste (identité de lecture), GitLab.

# shellcheck source=_f3-fin.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f3-fin.sh"

title "F3-S12 — Alerte Falco qualifiée, confinée, preuves préservées (INC-5912)"
require_cmd jq kubectl curl aws

_f3s_sante

# --- Outils de détection et de confinement ------------------------------------------------------------------
_s12_falco="$(_f3f_k -n falco get daemonsets -o json)"
check_cmd "Falco tourne sur tous les nœuds (espace falco)" \
  _f3f_json "$_s12_falco" '(.items | length) > 0 and all(.items[]; .status.desiredNumberScheduled > 0
    and (.status.numberReady // 0) == .status.desiredNumberScheduled)'
_s12_q="$(_f3f_k get ciliumclusterwidenetworkpolicies.cilium.io quarantaine -o json)"
check_cmd "politique de quarantaine intacte (sélecteur medisphere.internal/quarantaine=oui, toute sortie refusée)" \
  _f3f_json "$_s12_q" '.spec.endpointSelector.matchLabels["medisphere.internal/quarantaine"] == "oui"
    and any(.spec.egressDeny[]?; (.toEntities // []) | index("all") != null)'

# --- Preuves ---------------------------------------------------------------------------------------------
# _s12_preuves — liste récursive de s3://preuves/INC-5912/ avec l'identité de LECTURE (ou de dépôt).
_s12_preuves() {
  local f="${WB_F3_S12_PREUVES_ENV:-$HOME/.config/workbook/s3-preuves-lecture.env}"
  [[ -r "$f" ]] || f="$HOME/.config/workbook/s3-preuves-depot.env"
  [[ -r "$f" ]] || return 0
  (
    set -a
    # shellcheck disable=SC1090
    source "$f"
    set +a
    aws --endpoint-url "$_f3f_s3" s3 ls --recursive s3://preuves/INC-5912/ 2>/dev/null
  ) || true
}
_s12_liste="$(_s12_preuves)"
check_cmd "preuves déposées dans s3://preuves/INC-5912/ (au moins trois pièces)" \
  test "$(grep -c . <<<"$_s12_liste" || true)" -ge 3
check_cmd "preuves accompagnées de leurs empreintes (SHA256SUMS ou *.sha256)" \
  grep -Eiq '(SHA256SUMS|\.sha256)$' <<<"$_s12_liste"

# --- Pod suspect -----------------------------------------------------------------------------------------
_s12_ns="$(_f3f_etat S12 espace)"
_s12_pod="$(_f3f_etat S12 pod)"
if [[ -z "$_s12_pod" ]]; then
  skip "pod suspect isolé ou supprimé après collecte" "injection close ou non lancée : rien à lire dans l'état local"
  skip "service de l'espace touché rétabli" "injection close ou non lancée"
else
  _s12_p="$(_f3f_k -n "$_s12_ns" get pod "$_s12_pod" -o json)"
  _s12_isole() {
    # Supprimé : seulement si les preuves sont déposées (contrôle précédent) — sinon c'est une perte de preuve.
    if [[ -z "$_s12_p" ]]; then
      [[ "$(grep -c . <<<"$_s12_liste" || true)" -ge 3 ]]
      return
    fi
    _f3f_json "$_s12_p" '.metadata.labels["medisphere.internal/quarantaine"] == "oui"
      and ([.metadata.ownerReferences[]? | select(.kind == "ReplicaSet" or .kind == "StatefulSet")] | length) == 0' || return 1
    # Plus derrière aucun Service : aucune EndpointSlice de l'espace ne le référence.
    ! _f3f_k -n "$_s12_ns" get endpointslices.discovery.k8s.io -o json |
      jq -e --arg p "$_s12_pod" 'any(.items[]?.endpoints[]?; .targetRef.name? == $p)' >/dev/null 2>&1
  }
  check_cmd "pod suspect $_s12_ns/$_s12_pod : en quarantaine et sorti de son contrôleur (ou supprimé après dépôt des preuves)" _s12_isole
  case "$_s12_ns" in
    mediagenda-recette)
      check_cmd "MédiAgenda recette rétabli : $_f3f_recette/pret répond 200" test "$(_f3f_code "$_f3f_recette/pret")" = 200
      ;;
    *)
      _s12_dep="$(_f3f_k -n "$_s12_ns" get deployments -o json)"
      check_cmd "$_s12_ns : tous les Deployments disponibles (un pod sain a remplacé le suspect)" \
        _f3f_json "$_s12_dep" '(.items | length) > 0 and all(.items[]; (.status.availableReplicas // 0) >= (.spec.replicas // 1))'
      ;;
  esac
fi

# --- Qualification, escalade, trace -------------------------------------------------------------------------
check_cmd "main courante : qualification de l'alerte consignée (entrée [décision] de INC-5912)" \
  test "$(_f3s_compter INC-5912 décision)" -ge 1
check_cmd "main courante : escalade à la RSSI (Sophie Laurent) consignée pour INC-5912" \
  _f3f_journal_cite INC-5912 'sophie|rssi'
check_cmd "main courante : isolement et collecte consignés (quarantaine, preuves, empreintes)" \
  _f3f_journal_cite INC-5912 'quarantaine|isol'
_f3s_trace INC-5912 2
