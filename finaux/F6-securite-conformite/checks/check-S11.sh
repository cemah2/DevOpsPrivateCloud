# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S11.sh — F6-S11 « Panne : un conteneur compromis » (INC-6211) : Falco et Tetragon en place,
# quarantaine intacte, pod suspect (noté par l'injection) isolé (quarantaine, sorti de son contrôleur,
# derrière aucun Service) sans redémarrage, service de la recette rétabli, dossier INC-6211 ouvert avec
# qualification et escalade, un courriel d'état parti (Mailpit). Lecture seule.

# shellcheck source=_f6-incident.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f6-incident.sh"

title "F6-S11 — Conteneur compromis : détecté, qualifié, confiné (INC-6211)"
require_cmd jq kubectl curl

# --- Détection et confinement en place --------------------------------------------------------------
_s11_falco="$(kube -n falco get daemonsets -o json 2>/dev/null || echo '{}')"
check_cmd "Falco tourne sur tous les nœuds (espace falco)" \
  _f6i_json "$_s11_falco" '(.items | length) > 0 and all(.items[]; .status.desiredNumberScheduled > 0
    and (.status.numberReady // 0) == .status.desiredNumberScheduled)'
_s11_tetra="$(kube -n tetragon get daemonsets -o json 2>/dev/null || echo '{}')"
check_cmd "Tetragon tourne sur tous les nœuds (espace tetragon)" \
  _f6i_json "$_s11_tetra" '(.items | length) > 0 and all(.items[]; .status.desiredNumberScheduled > 0
    and (.status.numberReady // 0) == .status.desiredNumberScheduled)'
_s11_q="$(kube get ciliumclusterwidenetworkpolicies.cilium.io quarantaine -o json 2>/dev/null || echo '{}')"
check_cmd "politique de quarantaine intacte (sélecteur medisphere.internal/quarantaine=oui, toute sortie refusée)" \
  _f6i_json "$_s11_q" '.spec.endpointSelector.matchLabels["medisphere.internal/quarantaine"] == "oui"
    and any(.spec.egressDeny[]?; (.toEntities // []) | index("all") != null)'

# --- Pod suspect ------------------------------------------------------------------------------------
_s11_ns="$(_f6i_etat espace 2>/dev/null || true)"
_s11_pod="$(_f6i_etat pod 2>/dev/null || true)"
if [[ -z "$_s11_pod" ]]; then
  skip "pod suspect isolé (quarantaine, hors contrôleur, hors Service)" "injection close ou non lancée : rien dans l'état local"
  skip "service de mediagenda-recette rétabli" "injection close ou non lancée"
else
  _s11_p="$(kube -n "$_s11_ns" get pod "$_s11_pod" -o json 2>/dev/null || true)"
  _s11_isole() {
    [[ -n "$_s11_p" ]] || return 1   # supprimé trop tôt = perte de preuve (non conforme en S11)
    _f6i_json "$_s11_p" '.metadata.labels["medisphere.internal/quarantaine"] == "oui"
      and ([.metadata.ownerReferences[]? | select(.kind == "ReplicaSet" or .kind == "StatefulSet")] | length) == 0' || return 1
    ! kube -n "$_s11_ns" get endpointslices.discovery.k8s.io -o json 2>/dev/null |
      jq -e --arg p "$_s11_pod" 'any(.items[]?.endpoints[]?; .targetRef.name? == $p)' >/dev/null 2>&1
  }
  check_cmd "pod suspect $_s11_ns/$_s11_pod : en quarantaine, sorti de son contrôleur, derrière aucun Service (non supprimé)" _s11_isole
  _s11_redemarrages() {
    local avant
    avant="$(_f6i_etat redemarrages 2>/dev/null || true)"
    [[ -n "$_s11_p" && -n "$avant" ]] || return 1
    jq -e --argjson a "$avant" '([.status.containerStatuses[]? | .restartCount] | add // 0) == $a' >/dev/null 2>&1 <<<"$_s11_p"
  }
  check_cmd "pod suspect : aucun redémarrage de ses conteneurs depuis l'injection (preuves vivantes intactes)" _s11_redemarrages
  check_cmd "$_s11_ns rétabli : le Rollout mediagenda est complet et un pod d'API sain, hors quarantaine, sert" \
    _f6c_recette_api_saine "$_s11_ns"
fi

# --- Dossier d'incident et escalade -----------------------------------------------------------------
check_cmd "dossier INC-6211 : ouverture et qualification ([décision]) consignées" \
  _f6i_inc_doc 'chronolog|journal' 'INC-6211' 'd(é|e)cision|\[d(é|e)cision\]'
check_cmd "dossier INC-6211 : escalade à la RSSI (Sophie Laurent) et au DPO (Thomas Renaud)" \
  _f6i_inc_doc 'chronolog|journal' 'sophie|rssi' 'thomas|dpo'

# --- Un courriel d'état parti (Mailpit) -------------------------------------------------------------
_s11_courriel() {
  mailpit_api "search?query=$(jq -rn --arg s 'INC-6211' '$s|@uri')" 2>/dev/null \
    | jq -e '(.messages_count // 0) > 0' >/dev/null 2>&1
}
check_cmd "au moins un courriel d'état INC-6211 dans Mailpit" _s11_courriel
