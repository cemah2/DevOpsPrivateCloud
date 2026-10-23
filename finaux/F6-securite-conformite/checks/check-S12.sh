# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S12.sh — F6-S12 « Investigation et éradication » (LIBRE) : chronologie datée et sourcée sur main,
# cause éradiquée (pod suspect supprimé après collecte, politique réseau trop large retirée), plus de
# connexion vers le C2, recette saine, aucune alerte Falco active sur l'espace. Lecture seule.

# shellcheck source=_f6-incident.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f6-incident.sh"

title "F6-S12 — Investigation et éradication (INC-6211)"
require_cmd jq kubectl curl

# --- Chronologie et portée (sur main) ---------------------------------------------------------------
check_cmd "chronologie.md sur main : événements datés, sourcés, avec empreintes des preuves" \
  _f6i_inc_doc '^chronolog' 'INC-6211' 'falco|tetragon|audit|hubble' 'sha256|empreinte|SHA256'
check_cmd "chronologie : portée (établi / non établi, aboutissement de la connexion sortante)" \
  _f6i_inc_doc '^chronolog' '(é|e)tabli' 'hubble|c2|c2-simule01|forwarded|dropped'

# --- Éradication ------------------------------------------------------------------------------------
# La politique réseau trop large injectée (variante 2) ne doit plus exister dans l'espace.
_s12_ns="${_f6i_recette_ns}"
_s12_np_absente() {
  ! kube -n "$_s12_ns" get networkpolicy legacy-sortie-large >/dev/null 2>&1
}
check_cmd "politique réseau trop large (legacy-sortie-large) retirée de $_s12_ns" _s12_np_absente

# Le pod suspect noté par l'injection a été supprimé (éradication après collecte).
_s12_pod="$(_f6i_etat pod 2>/dev/null || true)"
if [[ -z "$_s12_pod" ]]; then
  skip "pod suspect éradiqué après collecte" "injection annulée ou non lancée : rien dans l'état local"
else
  _s12_pod_absent() { ! kube -n "$_s12_ns" get pod "$_s12_pod" >/dev/null 2>&1; }
  check_cmd "pod suspect $_s12_ns/$_s12_pod supprimé (éradication après collecte)" _s12_pod_absent
fi

# --- Retour en service ------------------------------------------------------------------------------
_s12_recette_saine() {
  kube -n "$_s12_ns" get deployments -o json 2>/dev/null \
    | jq -e '(.items | length) > 0 and all(.items[]; (.status.availableReplicas // 0) >= (.spec.replicas // 1))' >/dev/null 2>&1
}
check_cmd "mediagenda-recette saine (tous les Deployments disponibles)" _s12_recette_saine

# Le C2 n'existe plus (détruit à l'annulation) : plus de connexion possible.
check_cmd "c2-simule01 (VMID $_f6i_c2_vmid) détruit : plus de destination de connexion" _f6i_c2_absent

# Aucune alerte Falco active sur l'espace de la recette.
_s12_pas_alerte_falco() {
  am_api "alerts?active=true&filter=$(jq -rn --arg f "k8s_ns_name=$_s12_ns" '$f|@uri')" 2>/dev/null \
    | jq -e 'all(.[]?; (.labels.source // "") != "falco")' >/dev/null 2>&1
}
check_cmd "aucune alerte Falco active sur $_s12_ns" _s12_pas_alerte_falco

# --- Rotation des secrets exposés (trace écrite) ----------------------------------------------------
check_cmd "chronologie : rotation des secrets exposés consignée (jeton de compte de service / OpenBao)" \
  _f6i_inc_doc '^chronolog' 'rotation|renouvel|tourn' 'jeton|secret|openbao|compte de service'
