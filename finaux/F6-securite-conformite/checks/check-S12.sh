# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S12.sh — F6-S12 « Investigation et éradication » (LIBRE) : chronologie datée et sourcée sur main,
# cause éradiquée (pod suspect supprimé après collecte, politique réseau et règle de bordure trop larges
# retirées), injection annulée (C2 détruit), recette saine, aucune alerte Falco active sur l'espace. Lecture seule.

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

# La règle de bordure ajoutée avec cette politique (variante 2) ne doit plus être active : toute règle
# active des passerelles est décrite dans leur configuration persistée (même contrôle qu'en S04).
for _s12_gw in $_f6c_passerelles; do
  _s12_rc=0
  _f6c_bordure_conforme "$_s12_gw" || _s12_rc=$?
  if ((_s12_rc == 2)); then
    skip "bordure $_s12_gw" "lecture impossible (SSH admin et sudo -n nft list)"
  else
    check_cmd "bordure $_s12_gw : aucune règle active absente de la configuration persistée (sortie vers le C2 fermée)" test "$_s12_rc" -eq 0
  fi
done

# --- Retour en service ------------------------------------------------------------------------------
check_cmd "$_s12_ns saine : Rollout mediagenda complet, un pod d'API sain hors quarantaine" _f6c_recette_api_saine "$_s12_ns"

# Le C2 n'existe plus (détruit à l'annulation) : plus de connexion possible.
check_cmd "c2-simule01 (VMID $_f6i_c2_vmid) détruit : plus de destination de connexion" _f6i_c2_absent

# Aucune alerte Falco active sur l'espace de la recette.
_s12_pas_alerte_falco() {
  local r
  r="$(am_api "alerts?active=true&filter=$(jq -rn --arg f "k8s_ns_name=\"$_s12_ns\"" '$f|@uri')" 2>/dev/null)" || return 1
  jq -e 'all(.[]?; (.labels.alertname // "") != "AlerteFalco" and (.labels.source // "") != "falco")' >/dev/null 2>&1 <<<"$r"
}
check_cmd "aucune alerte Falco active sur $_s12_ns" _s12_pas_alerte_falco

# --- Rotation des secrets exposés (trace écrite) ----------------------------------------------------
check_cmd "chronologie : rotation des secrets exposés consignée (jeton de compte de service / OpenBao)" \
  _f6i_inc_doc '^chronolog' 'rotation|renouvel|tourn' 'jeton|secret|openbao|compte de service'
