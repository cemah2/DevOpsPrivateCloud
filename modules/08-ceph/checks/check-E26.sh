# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées par bash -c (valeurs en paramètres)
#
# check-E26.sh — M08-E26 « Mettre à jour Ceph sans interruption »
# Lecture seule : versions des démons (orch ps, ceph versions), état de l'orchestrateur, modes de
# l'autoscaler, binaire cephadm des hôtes (« cephadm version »), santé, documentation et code (GitLab).

# shellcheck source=_m08-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m08-production.sh"

title "M08-E26 — Mettre à jour Ceph sans interruption"
require_cmd jq curl
_m08p_charger
check_cmd "le cluster répond depuis $_M08P_ADMIN (ceph status)" _m08p_joignable

title "Versions"
check_cmd "orchestrateur : démons Ceph (mon, mgr, osd, mds, rgw, crash) en $_M08P_VERSION" \
  _m08p_jq _M08P_PS "[.[] | select(.daemon_type | test(\"^(mon|mgr|osd|mds|rgw|crash)$\"))] | length > 0 and all(.[]; (.version // \"\") == \"$_M08P_VERSION\")"
check_cmd "ceph versions : une seule version, $_M08P_VERSION" bash -c \
  'jq -e --arg v "$2" "(.overall // {}) | keys | length == 1 and (.[0] | contains(\"ceph version \" + \$v + \" \"))" >/dev/null <<<"$1"' \
  _ "$(_m08p_json versions)" "$_M08P_VERSION"
check_cmd "aucune mise à jour en cours ou en pause" bash -c \
  'jq -e "(.in_progress // false) == false and ((.is_paused // false) == false)" >/dev/null <<<"$1"' _ "$(_m08p_json 'orch upgrade status')"
for _m08_e26_h in $(_m08p_hotes_orch 2>/dev/null || printf '%s ' "${_M08P_NOEUDS[@]}"); do
  check_ssh_output "$_m08_e26_h : commande cephadm (paquet) en $_M08P_VERSION" "$_m08_e26_h" "${_M08P_VERSION//./\\.}" \
    'sudo -n cephadm version 2>&1 | head -n 3'
done

title "Après la mise à jour"
check_cmd "l'autoscaler est de nouveau actif sur tous les pools" \
  _m08p_jq _M08P_POOLS 'length > 0 and all(.[]; .pg_autoscale_mode == "on")'
check_cmd "aucun contrôle de santé actif hors de la famille AUTH_INSECURE_* (traités en E27)" \
  _m08p_seuls_controles '^AUTH_INSECURE_'
check_cmd "le nouveau type de clé cephx est accepté par les moniteurs (aes256k)" bash -c \
  'grep -q aes256k <<<"$1"' _ "$(_m08p_json 'mon dump' | jq -c '.auth_allowed_ciphers // empty' 2>/dev/null)"
check_cmd "aucune mise en sourdine permanente ou sans durée" _m08p_sourdines_temporaires

title "Code et documentation"
check_cmd "plateforme/ansible : image quay.io/ceph/ceph:v$_M08P_VERSION décrite sur main (ceph_image)" \
  _m08p_recherche_main plateforme/ansible "quay.io/ceph/ceph:v$_M08P_VERSION"
check_cmd "plateforme/ansible : dernier pipeline de main réussi" _m08p_pipeline_ok plateforme/ansible
check_cmd "RB-082 sur main de plateforme/medisphere (docs/stockage/runbooks)" \
  _m08p_doc_prefixe docs/stockage/runbooks RB-082
