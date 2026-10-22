# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # bash -c entre apostrophes
# check-E23.sh — M22-E23 « Astreinte : enquête par les journaux » : post-mortem INC-4923 rédigé, avec
# l'enquête (compte de service, exec, preuves), droits du compte de service retirés, aucune panne M22
# encore active, puis toutes les vérifications de M22-E19 à M22-E22. Lecture seule.

# shellcheck source=_m22-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m22-expert.sh"

title "M22-E23 — Astreinte : enquête par les journaux"

_m22_e23_pm_fichier() {
  _m22p_arbre plateforme/medisphere docs/kubernetes/post-mortems | grep -E 'INC-4923' | head -n 1
}
_m22_e23_pm_contient() {
  local f
  f="$(_m22_e23_pm_fichier)"
  [[ -n "$f" ]] && _m22p_fichier_contient plateforme/medisphere "$f" "$@"
}
check_cmd "post-mortem INC-4923 publié (main, docs/kubernetes/post-mortems/)" bash -c '[[ -n "$1" ]]' _ "$(_m22_e23_pm_fichier)"
check_cmd "post-mortem : chronologie, causes, détection, actions" \
  _m22_e23_pm_contient '^#+ .*[Cc]hronologie' '^#+ .*[Cc]auses?' '^#+ .*[Dd][ée]tection' '^#+ .*[Aa]ctions'
check_cmd "post-mortem : le compte de service et le geste sont identifiés (outillage-recette, exec)" \
  _m22_e23_pm_contient 'outillage-recette' 'exec'
check_cmd "post-mortem : preuves tirées des journaux (requêtes LogQL sur les locataires mediagenda et audit)" \
  _m22_e23_pm_contient '\{[^}]*namespace' 'audit' 'rendez-vous supprim'
check_cmd "post-mortem : aucun secret ni jeton recopié" \
  bash -c '! grep -Eq "eyJhbGciOi|PRIVATE KEY|glpat-" <<<"$1"' _ "$(f="$(_m22_e23_pm_fichier)"; [[ -n "$f" ]] && _m22p_fichier_main plateforme/medisphere "$f" 2>/dev/null)"

if _m22x_api_repond; then
  _m22_e23_droits_retires() {
    ! kube -n mediagenda-recette get rolebinding outillage-recette >/dev/null 2>&1 &&
      ! kube -n mediagenda-recette get rolebindings -o json 2>/dev/null |
        jq -e '[.items[].subjects[]? | select(.kind == "ServiceAccount" and .namespace == "wb-pannes")] | length > 0' >/dev/null 2>&1
  }
  check_cmd "aucun compte de service de wb-pannes n'a plus de droits dans mediagenda-recette" _m22_e23_droits_retires
else
  skip "droits du compte de service" "l'API ne répond pas au compte des checks"
fi
check_cmd "aucune panne M22 encore marquée active (lab/bin/break)" _m22x_aucune_panne_active

_m22_e23_dir="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=check-E19.sh
source "$_m22_e23_dir/check-E19.sh"
# shellcheck source=check-E20.sh
source "$_m22_e23_dir/check-E20.sh"
# shellcheck source=check-E21.sh
source "$_m22_e23_dir/check-E21.sh"
# shellcheck source=check-E22.sh
source "$_m22_e23_dir/check-E22.sh"
