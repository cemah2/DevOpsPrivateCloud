# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S11.sh — F2-S11 « Panne : le prestataire voit trop de choses » : plus aucun accès d'AxiomDev hors
# de son périmètre (groupes GitLab, liaisons RBAC hors de mediagenda-axiomdev, groupes de l'annuaire
# autres que ext-axiomdev) ; une règle d'admission refuse désormais toute liaison d'un groupe oidc:ext-*
# hors des espaces prévus ; la revue d'accès compare AxiomDev à son modèle ; la panne est close.
# Lecture seule.

# shellcheck source=_f2-equipes.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f2-equipes.sh"

title "F2-S11 — Le prestataire ne voit plus que son périmètre"
require_cmd jq curl kubectl ldapsearch

_s11_g="$_f2b_groupe_axiom"
_s11_re="^oidc:($_s11_g$(printf '|%s' "${_f2b_axiom_personnes[@]//./\\.}"))\$"

for _s11_u in "${_f2b_axiom_personnes[@]}"; do
  _s11_gu="$(_f2b_gitlab_utilisateur "$_s11_u")"
  if [[ -z "$_s11_gu" ]]; then
    check_cmd "GitLab : utilisateur $_s11_u présent" false
  else
    _s11_sans_groupe() { [[ "$(_f2b_gitlab_groupes_etrangers "$1")" == 0 ]]; }
    check_cmd "GitLab : $_s11_u n'est membre d'aucun groupe autre que $_s11_g (héritage vers d'autres projets)" \
      _s11_sans_groupe "$(jq -r .id <<<"$_s11_gu")"
  fi
  _s11_ipa() {
    [[ -n "$(_f2b_ldap_personne "$1" uid)" ]] || return 1
    ! _f2b_groupes_ipa "$1" | grep -Evx "ipausers|$_s11_g" | grep -q .
  }
  check_cmd "annuaire : $_s11_u n'appartient qu'à $_s11_g" _s11_ipa "$_s11_u"
done
check_output "Kubernetes : aucune liaison RBAC d'AxiomDev hors de $_f2b_ns_axiom" '^0$' \
  _f2b_liaisons_hors "$_f2b_ns_axiom" "$_s11_re"

_s11_garde() {
  local j
  j="$(kube get validatingpolicies.policies.kyverno.io -o json 2>/dev/null)" || j='{"items":[]}'
  jq -e 'any(.items[]; (.spec | tostring | test("oidc:ext-"))
                       and ((.spec.validationActions // []) | index("Deny")) != null
                       and any(.spec.matchConstraints.resourceRules[]?; (.resources // []) | any(. == "rolebindings" or . == "clusterrolebindings")))' \
    <<<"$j" >/dev/null 2>&1 && return 0
  j="$(kube get validatingadmissionpolicies.admissionregistration.k8s.io -o json 2>/dev/null)" || return 1
  jq -e 'any(.items[]; (.spec | tostring | test("oidc:ext-"))
                       and any(.spec.matchConstraints.resourceRules[]?; (.resources // []) | any(. == "rolebindings" or . == "clusterrolebindings")))' \
    <<<"$j" >/dev/null 2>&1
}
check_cmd "admission : une politique refuse les liaisons RBAC de oidc:ext-* hors des espaces prévus" _s11_garde
# Après le départ (S12), le périmètre d'AxiomDev est retiré de modele.yml et seul le groupe (vide) y
# reste déclaré : on n'exige plus que le projet ou l'espace y figurent (la recette relance ce check).
_s11_parti=1
for _s11_u in "${_f2b_axiom_personnes[@]}"; do
  _f2b_desactivee "$_s11_u" || _s11_parti=0
done
if ((_s11_parti)); then
  check_cmd "revue d'accès : modele.yml déclare encore le groupe $_s11_g (départ fait)" \
    _f2b_fichier_contient "$_f2b_projet_identite" outils/revue-acces/modele.yml "$_s11_g"
else
  check_cmd "revue d'accès : modele.yml décrit le périmètre de $_s11_g (projet, espace)" \
    _f2b_fichier_contient "$_f2b_projet_identite" outils/revue-acces/modele.yml "$_s11_g" "$_f2b_ns_axiom|${_f2b_projet_api//\//.}"
fi
check_cmd "panne F2-S11 close (lab/bin/break F2 11 --annuler après réparation)" _f2b_aucune_panne_active S11
