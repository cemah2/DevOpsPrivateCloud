# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E34.sh — M16-E34 « Restaurer la base de MédiAgenda en temps limité » (à lancer à T3)
# Lecture seule : vérité de référence enregistrée par l'injection (~/.local/state/workbook/M16-E34),
# rendez-vous lus par l'API publiée (GET), Cluster mediagenda-db (identité, timeline, archivage),
# clusters temporaires, documentation (API GitLab). Aucune donnée de patient n'est affichée.

# shellcheck source=_m16-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m16-production.sh"

title "M16-E34 — Restaurer la base de MédiAgenda en temps limité"
require_cmd jq kubectl curl date

_m16_e34_d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/M16-E34"
if [[ ! -s "$_m16_e34_d/etat.json" || ! -s "$_m16_e34_d/supprimes.json" ]]; then
  check_cmd "injection de l'incident faite (lab/bin/break 16 34) et vérité de référence présente" false
  return 0
fi
_m16_e34_etat="$(cat "$_m16_e34_d/etat.json")"
_m16_e34_conflit="$(jq -r .id_conflit <<<"$_m16_e34_etat")"

# _m16_e34_meme_instant A B — deux horodatages désignent la même seconde.
_m16_e34_meme_instant() {
  local a b
  a="$(date -u -d "$1" +%s 2>/dev/null)" || return 1
  b="$(date -u -d "$2" +%s 2>/dev/null)" || return 1
  [[ "$a" == "$b" ]]
}

# _m16_e34_identique LIGNE_JSON — le rendez-vous est servi par l'API avec le même contenu.
_m16_e34_identique() {
  local attendu="$1" id servi
  id="$(jq -r .id <<<"$attendu")"
  servi="$(_m16p_api "/api/v1/rendez-vous/$id")" || return 1
  jq -e -n --argjson a "$attendu" --argjson s "$servi" \
    '$a.patient == $s.patient and $a.praticien == $s.praticien and $a.duree_minutes == $s.duree_minutes and $a.motif == $s.motif' \
    >/dev/null || return 1
  _m16_e34_meme_instant "$(jq -r .debut <<<"$attendu")" "$(jq -r .debut <<<"$servi")" || return 1
  _m16_e34_meme_instant "$(jq -r .cree_le <<<"$attendu")" "$(jq -r .cree_le <<<"$servi")"
}

title "Exigences 1 à 3 : rendez-vous"
_m16_e34_ko=0
_m16_e34_n=0
while read -r _m16_e34_l; do
  [[ -n "$_m16_e34_l" ]] || continue
  _m16_e34_n=$((_m16_e34_n + 1))
  _m16_e34_identique "$_m16_e34_l" || _m16_e34_ko=$((_m16_e34_ko + 1))
done < <(jq -c --argjson c "$_m16_e34_conflit" '.[] | select(.id != $c)' "$_m16_e34_d/supprimes.json")
check_cmd "les $_m16_e34_n rendez-vous supprimés (hors conflit) sont de retour, mêmes identifiants et contenu" \
  test "$_m16_e34_ko" -eq 0
check_cmd "le rendez-vous en conflit ($_m16_e34_conflit) n'a pas été réinséré" \
  bash -c '[[ "$1" == 404 ]]' _ "$(_m16p_api_code "/api/v1/rendez-vous/$_m16_e34_conflit")"
_m16_e34_ko=0
while read -r _m16_e34_id; do
  [[ -n "$_m16_e34_id" ]] || continue
  [[ "$(_m16p_api_code "/api/v1/rendez-vous/$_m16_e34_id")" == 200 ]] || _m16_e34_ko=$((_m16_e34_ko + 1))
done <"$_m16_e34_d/apres.ids"
check_cmd "les rendez-vous pris après l'incident sont tous présents" test "$_m16_e34_ko" -eq 0

title "Exigences 4 à 6 : base de production, archives, nettoyage"
_m16_e34_db="$(_m16p_kj clusters.postgresql.cnpg.io "$_M16P_BASE" -n "$_M16P_RECETTE")"
check_cmd "mediagenda-db est le même objet Cluster qu'à T0 (ni remplacé, ni recréé)" \
  _m16p_jq "$_m16_e34_db" '.metadata.uid == $u' --arg u "$(jq -r .cluster_uid <<<"$_m16_e34_etat")"
check_cmd "mediagenda-db n'a ni basculé ni été restauré (même timeline qu'à T0)" \
  _m16p_jq "$_m16_e34_db" '.status.timelineID == $t' --argjson t "$(jq .timeline <<<"$_m16_e34_etat")"
check_cmd "mediagenda-db sain" _m16p_cluster_sain "$_M16P_RECETTE" "$_M16P_BASE"
check_cmd "mediagenda-db : archivage continu actif" _m16p_archivage_actif "$_M16P_RECETTE" "$_M16P_BASE"
_m16_e34_inj="$(jq -r .injection <<<"$_m16_e34_etat")"
for _m16_e34_ns in "$_M16P_RECETTE" wb-restauration wb-essais; do
  check_cmd "$_m16_e34_ns : aucun Cluster créé pour l'enquête ne subsiste" \
    _m16p_jq "$(_m16p_kj clusters.postgresql.cnpg.io -n "$_m16_e34_ns")" \
    'all(.items[]?; (.metadata.creationTimestamp | fromdateiso8601) < ($i | fromdateiso8601))' --arg i "$_m16_e34_inj"
done
check_cmd "aucun fichier d'extraction ne traîne dans ~/m16/e34" \
  bash -c '[[ -z "$(find "$1" -maxdepth 1 -type f -name "extraction*" 2>/dev/null)" ]]' _ "$HOME/m16/e34"

title "Exigences 7 et 8 : compte rendu et runbook"
_m16_e34_cr() {
  local c chemin
  chemin="$(gitlab_api "projects/plateforme%2Fmedisphere/repository/tree?ref=main&path=docs%2Fkubernetes%2Fstockage%2Ftests&per_page=100" 2>/dev/null \
    | jq -r '[.[]? | select(.name | startswith("chrono-pitr-")) | .path] | sort | last // empty')" || return 1
  [[ -n "$chemin" ]] || return 1
  c="$(_m16p_fichier_main plateforme/medisphere "$chemin" 2>/dev/null)" || return 1
  # Le conflit est cité par son identifiant ; aucun nom de patient (les patients de l'injection
  # s'appellent « Patient E34-… »).
  grep -qw -- "$_m16_e34_conflit" <<<"$c" && ! grep -q 'Patient E34' <<<"$c"
}
check_cmd "compte rendu tests/chrono-pitr-*.md : conflit cité par identifiant, aucun nom de patient" _m16_e34_cr
check_cmd "RB-162 sur main de plateforme/medisphere" _m16p_doc_prefixe docs/kubernetes/stockage RB-162 'targetTime|instant'
