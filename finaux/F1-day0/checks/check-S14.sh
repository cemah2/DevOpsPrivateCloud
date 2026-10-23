# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes « bash -c » et filtres jq entre apostrophes
# check-S14.sh — F1-S14 « Recette Day 0 » : contrôle global.
# Rejoue, chacun dans son propre processus (lab/bin/check, mêmes variables de lab/lab.env), les
# contrôles d'entrée des finaux et ceux du final F1, puis les sondes du socle sur adm01, l'absence de
# panne active et d'essai restant, la documentation et l'étiquette day0-v1. Lecture seule. Compte 20 à
# 40 minutes. Un contrôle rejoué qui échoue affiche ses lignes [KO].
#
# Variable : WB_F1_S14_CONTROLES — liste « module exercice » séparés par des virgules ; défaut :
#   « 29 25, 28 25, 27 25, 26 46, 25 46, 24 46, F1 02, F1 05, F1 06, F1 07, F1 08, F1 09, F1 10,
#     F1 11, F1 12, F1 13 ». Toute réduction de cette liste est une décision écrite dans recette-day0.md.

# shellcheck source=_f1-cluster.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f1-cluster.sh"

title "F1-S14 — Recette Day 0 (contrôle global)"
require_cmd kubectl jq curl ssh

_f1_s14_liste="${WB_F1_S14_CONTROLES:-29 25, 28 25, 27 25, 26 46, 25 46, 24 46, F1 02, F1 05, F1 06, F1 07, F1 08, F1 09, F1 10, F1 11, F1 12, F1 13}"

# _f1_s14_rejouer MODULE EXERCICE — lance lab/bin/check dans un processus séparé ; en cas d'échec,
#   affiche les lignes [KO] (sans couleurs) sous la ligne de bilan.
_f1_s14_rejouer() {
  local sortie rc=0
  sortie="$(timeout 1800 "$_f1c_racine/lab/bin/check" "$1" "$2" </dev/null 2>&1)" || rc=$?
  if ((rc != 0)); then
    sed -E 's/\x1b\[[0-9;]*m//g' <<<"$sortie" | grep -E '\[KO\]|\[!!\]' | head -n 8 | sed 's/^ */           ↳ /' >&2 || true
  fi
  return "$rc"
}

IFS=',' read -r -a _f1_s14_ctl <<<"$_f1_s14_liste"
for _f1_s14_c in "${_f1_s14_ctl[@]}"; do
  read -r _f1_s14_m _f1_s14_e <<<"$_f1_s14_c"
  [[ -n "${_f1_s14_m:-}" && -n "${_f1_s14_e:-}" ]] || continue
  if _f1_s14_rejouer "$_f1_s14_m" "$_f1_s14_e"; then
    check_cmd "lab/bin/check $_f1_s14_m $_f1_s14_e" true
  else
    check_cmd "lab/bin/check $_f1_s14_m $_f1_s14_e (lignes en échec ci-dessus)" false
  fi
done

# --- Sondes du socle (adm01) ---------------------------------------------------------------------------
check_cmd "ms-verif-services réussit sur adm01 (M06-E29)" timeout 180 /usr/local/bin/ms-verif-services --quiet
check_cmd "ms-verif-sauvegardes réussit sur adm01 (M02)" timeout 120 /usr/local/bin/ms-verif-sauvegardes

# --- Rien d'ouvert ------------------------------------------------------------------------------------------
check_cmd "aucune panne marquée active (modules ni finaux)" \
  bash -c '[[ -z "$(find "${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives" -mindepth 1 -maxdepth 1 2>/dev/null)" ]]'
_f1_s14_vms="$(_f1c_pve 'pvesh get /cluster/resources --type vm --output-format json')"
check_cmd "aucune VM d'essai du final dans la plage 3100-3199" \
  jq -e '[.[]? | select(.vmid >= 3100 and .vmid <= 3199)] | length == 0' <<<"${_f1_s14_vms:-null}"
if _f1c_api_repond && _f1c_lit policyexceptions.policies.kyverno.io; then
  check_cmd "toutes les PolicyException de Kyverno ont une échéance (spec.expiresAt)" _f1c_kq \
    '[.items[] | select((.spec.expiresAt // "") == "")] | length == 0' policyexceptions.policies.kyverno.io -A
fi

# --- Documentation et étiquette -----------------------------------------------------------------------------
check_cmd "docs/day0/recette-day0.md : contrôles, écarts légitimes, variables adaptées, décision" \
  _f1c_doc '^recette-day0\.md$' 'lab/bin/check' '29 25' 'F1' '[ée]cart' 'variable|WB_'
_f1_s14_tag() {
  gitlab_api "projects/$(_f1c_enc "$_f1c_projet_doc")/repository/tags/day0-v1" 2>/dev/null | jq -e '.name == "day0-v1"' >/dev/null 2>&1
}
check_cmd "étiquette day0-v1 posée sur $_f1c_projet_doc" _f1_s14_tag
_f1_s14_tag_apres_recette() {
  local t d
  t="$(gitlab_api "projects/$(_f1c_enc "$_f1c_projet_doc")/repository/tags/day0-v1" 2>/dev/null | jq -r '.commit.id // empty' 2>/dev/null)" || return 1
  [[ -n "$t" ]] || return 1
  d="$(_f1c_doc_chemin '^recette-day0\.md$')" || return 1
  # recette-day0.md existe déjà dans l'arbre de l'étiquette : l'étiquette est posée APRÈS la recette.
  gitlab_api "projects/$(_f1c_enc "$_f1c_projet_doc")/repository/files/$(_f1c_enc "$d")?ref=$t" >/dev/null 2>&1
}
check_cmd "day0-v1 posée après la publication de recette-day0.md (le document est dans l'étiquette)" _f1_s14_tag_apres_recette
