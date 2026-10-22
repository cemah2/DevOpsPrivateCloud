# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E29.sh — M20-E29 « Fenêtres de synchronisation et gel des changements » (CHG-2129)
# À lancer depuis adm01. Lecture seule : syncWindows des AppProjects (wb-checks) ; documentation sur main.
# Les motifs d'applications et d'espaces des fenêtres sont évalués comme Argo CD les évalue (globs).

# shellcheck source=_m20-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m20-production.sh"

title "M20-E29 — Fenêtres de synchronisation et gel des changements"
require_cmd kubectl jq
check_cmd "l'API du cluster répond (readyz)" _m20p_joignable

# _m20_e29_vise FENETRE_JSON APPLICATION ESPACE — la fenêtre sélectionne l'Application (par nom ou par
# espace de destination ; les clusters ne sont pas utilisés ici).
_m20_e29_vise() {
  local f="$1" app="$2" ns="$3" motif
  while IFS= read -r motif; do
    [[ -n "$motif" ]] || continue
    # shellcheck disable=SC2053  # motif volontairement non quoté : correspondance glob
    [[ "$app" == $motif ]] && return 0
  done < <(jq -r '.applications[]?' <<<"$f" 2>/dev/null)
  while IFS= read -r motif; do
    [[ -n "$motif" ]] || continue
    # shellcheck disable=SC2053
    [[ "$ns" == $motif ]] && return 0
  done < <(jq -r '.namespaces[]?' <<<"$f" 2>/dev/null)
  return 1
}

# _m20_e29_regle_hebdo FENETRE_JSON — deny, vendredi 16:00, 64 h, Europe/Paris, synchronisation manuelle.
_m20_e29_regle_hebdo() {
  local d
  _m20p_jq "$1" '.kind == "deny" and (.timeZone // "") == "Europe/Paris" and (.manualSync // false) == true
                 and ((.schedule // "") | test("^0 16 \\* \\* (5|FRI|Fri|fri)$"))' || return 1
  d="$(_m20p_duree_s "$(jq -r '.duration // ""' <<<"$1")")" || return 1
  [[ "$d" == 230400 ]]
}

for _m20_e29_p in mediagenda medidoc; do
  title "AppProject $_m20_e29_p"
  _m20_e29_fen="$(_m20p_projet "$_m20_e29_p" | jq -c '.spec.syncWindows // []' 2>/dev/null || echo '[]')"
  _m20_e29_ok_hebdo() {
    local f
    while IFS= read -r f; do
      _m20_e29_regle_hebdo "$f" && _m20_e29_vise "$f" "$1-prod" "$1-prod" \
        && ! _m20_e29_vise "$f" "$1-dev" "$1-dev" && ! _m20_e29_vise "$f" "$1-recette" "$1-recette" && return 0
    done < <(jq -c '.[]' <<<"$_m20_e29_fen" 2>/dev/null)
    return 1
  }
  check_cmd "fenêtre deny vendredi 16:00 + 64 h (Europe/Paris), manualSync, sur $_m20_e29_p-prod et pas sur dev/recette" \
    _m20_e29_ok_hebdo "$_m20_e29_p"
  _m20_e29_aucune_essai() {
    local f
    while IFS= read -r f; do
      _m20p_jq "$f" '.kind == "deny"' || continue
      _m20_e29_vise "$f" "$1-dev" "$1-dev" && return 1
      _m20_e29_vise "$f" "$1-recette" "$1-recette" && return 1
    done < <(jq -c '.[]' <<<"$_m20_e29_fen" 2>/dev/null)
    return 0
  }
  check_cmd "aucune fenêtre deny (d'essai) sur $_m20_e29_p-dev ni $_m20_e29_p-recette" _m20_e29_aucune_essai "$_m20_e29_p"
done

title "Documentation"
check_cmd "docs/livraison/gitops/politique-changements.md sur main (règle, gel, dérogation, limites)" \
  _m20p_doc docs/livraison/gitops/politique-changements.md 'manualSync' 'gel' 'd(e|é)rogation' 'rollouts'
