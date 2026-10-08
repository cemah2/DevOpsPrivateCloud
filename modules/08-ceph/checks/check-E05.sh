# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E05.sh — M08-E05 : Pools répliqués et groupes de placement
# À lancer depuis adm01. Lecture seule : commandes « ceph » d'observation sur le nœud _admin,
# API GitLab en GET.

# shellcheck source=_m08-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m08-decouverte.sh"

title "M08-E05 — Pools répliqués et groupes de placement"
require_cmd jq curl

# Fonctions de ce check (définies AVANT leur premier appel).
_m08d_e05_regle_hote() {
  [[ -n "$1" ]] || return 1
  _m08d_ceph "osd crush rule dump -f json" \
    | jq -e --argjson id "$1" '.[] | select(.rule_id == $id) | [.steps[] | select(.op | test("choose")) | .type]
        | (index("host") != null) or (index("rack") != null)' >/dev/null 2>&1
}
_m08d_e05_sans_objet_essai() {
  local liste
  liste="$(remote "$_M08D_ADMIN" "sudo -n rados -p rbd-test ls" 2>/dev/null)" || return 1
  ! grep -q '^essai-' <<<"$liste"
}
_m08d_e05_sans_alerte_pg() {
  local sante
  sante="$(_m08d_ceph "health -f json")"
  [[ -n "$sante" ]] || return 1
  ! jq -r '(.checks // {}) | keys[]' <<<"$sante" \
    | grep -Eq '^(POOL_APP_NOT_ENABLED|POOL_TOO_FEW_PGS|POOL_TOO_MANY_PGS|TOO_FEW_PGS|TOO_MANY_PGS)$'
}

_m08d_e05_pools="$(_m08d_ceph "osd pool ls detail -f json")"

# --- 1. Le pool rbd-test --------------------------------------------------------------------------
check_cmd "Pool rbd-test présent" _m08d_json "$_m08d_e05_pools" '[.[] | select(.pool_name == "rbd-test")] | length == 1'
check_cmd "rbd-test : 3 copies, écriture refusée sous 2 (size 3, min_size 2)" _m08d_json "$_m08d_e05_pools" \
  '.[] | select(.pool_name == "rbd-test") | .size == 3 and .min_size == 2'
check_cmd "rbd-test : autoscaler des PG actif (on)" _m08d_json "$_m08d_e05_pools" \
  '.[] | select(.pool_name == "rbd-test") | .pg_autoscale_mode == "on"'
check_cmd "rbd-test : application « rbd » déclarée" _m08d_json "$_m08d_e05_pools" \
  '.[] | select(.pool_name == "rbd-test") | .application_metadata | has("rbd")'
check_cmd "rbd-test : nombre de PG en puissance de 2" _m08d_json "$_m08d_e05_pools" \
  '.[] | select(.pool_name == "rbd-test") | .pg_num as $p | ($p > 0) and ([range(0; 13)] | map(pow(2; .)) | index($p) != null)'
_m08d_e05_regle="$(jq -r '.[] | select(.pool_name == "rbd-test") | .crush_rule' <<<"$_m08d_e05_pools" 2>/dev/null || true)"
# Après M08-E14, rbd-test passe sur ssd-baie (domaine de panne : la baie, qui contient les hôtes).
check_cmd "rbd-test : règle CRUSH dont le domaine de panne est l'hôte (ou la baie, après E14)" _m08d_e05_regle_hote "$_m08d_e05_regle"

# --- 2. Les essais ont été nettoyés ------------------------------------------------------------------
check_cmd "Pool d'essai « essai-pg » supprimé" _m08d_json "$_m08d_e05_pools" '[.[] | select(.pool_name == "essai-pg")] | length == 0'
check_output "Verrou de suppression des pools reposé (mon_allow_pool_delete = false)" '^false$' \
  _m08d_ceph "config get mon mon_allow_pool_delete"
check_cmd "Aucun objet d'essai « rados » laissé dans rbd-test (objets essai-*)" _m08d_e05_sans_objet_essai

# --- 3. Santé ---------------------------------------------------------------------------------------
check_cmd "Tous les PG « active+clean »" _m08d_json "$(_m08d_ceph "-s -f json")" \
  '(.pgmap.pgs_by_state // []) as $e | ($e | length) == 1 and $e[0].state_name == "active+clean"'
check_cmd "Aucune alerte « pool sans application » ni « trop/pas assez de PG »" _m08d_e05_sans_alerte_pg
check_output "Cluster en HEALTH_OK" '^HEALTH_OK$' _m08d_sante

# --- 4. Le code ----------------------------------------------------------------------------------------
check_cmd "plateforme/ceph (main) : outils/pool-repliquee.sh" _m08d_fichier_main plateforme/ceph outils/pool-repliquee.sh
