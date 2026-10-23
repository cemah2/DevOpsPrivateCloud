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
  local r
  r="$(kube -n "$_s12_ns" get networkpolicy legacy-sortie-large -o name 2>&1)" && return 1
  grep -qiE 'not ?found' <<<"$r"   # API injoignable ≠ politique absente
}
check_cmd "politique réseau trop large (legacy-sortie-large) retirée de $_s12_ns" _s12_np_absente

# Le pod suspect noté par l'injection a été supprimé (éradication après collecte). L'annulation garde
# l'espace, le pod, le vecteur et le compte de service dans l'état local pour ce contrôle.
_s12_pod="$(_f6i_etat pod 2>/dev/null || true)"
_s12_vecteur="$(_f6i_etat vecteur 2>/dev/null || true)"
if [[ -z "$_s12_pod" ]]; then
  _ko "état local de l'injection absent (~/.local/state/workbook/F6-S11/) : lance F6-S11 (lab/bin/break F6 11) depuis ce poste"
else
  _s12_pod_absent() {
    local r
    r="$(kube -n "$_s12_ns" get pod "$_s12_pod" -o name 2>&1)" && return 1
    grep -qiE 'not ?found' <<<"$r"
  }
  check_cmd "pod suspect $_s12_ns/$_s12_pod supprimé (éradication après collecte)" _s12_pod_absent
fi

# Variante 1 (jeton de compte de service) : le compte a été supprimé et recréé (nouvel UID), ce qui
# invalide tous les jetons émis pour l'ancien.
if [[ "$_s12_vecteur" == jeton* ]]; then
  _s12_sa="$(_f6i_etat compte 2>/dev/null || true)"
  _s12_sa_uid="$(_f6i_etat compte-uid 2>/dev/null || true)"
  _s12_sa_renouvele() {
    local uid
    [[ -n "$_s12_sa" && -n "$_s12_sa_uid" ]] || return 1
    uid="$(kube -n "$_s12_ns" get serviceaccount "$_s12_sa" -o jsonpath='{.metadata.uid}' 2>/dev/null)" || return 1
    [[ -n "$uid" && "$uid" != "$_s12_sa_uid" ]]
  }
  check_cmd "compte de service $_s12_ns/${_s12_sa:-?} renouvelé (nouvel UID : jetons de l'ancien invalidés)" _s12_sa_renouvele
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

# Le C2 n'existe plus et l'injection est annulée (dernier geste de S12, après le relevé des journaux du C2).
check_cmd "c2-simule01 (VMID $_f6i_c2_vmid) détruit : plus de destination de connexion" _f6i_c2_absent
_s12_annulee() { [[ -n "$(_f6i_etat annule 2>/dev/null || true)" ]]; }
check_cmd "injection annulée (lab/bin/break F6 11 --annuler, après le relevé des journaux du C2)" _s12_annulee

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
