# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S10.sh — F2-S10 « Des accès bornés pour AxiomDev » : personnes d'AxiomDev dans le seul groupe
# ext-axiomdev, principal Kerberos daté (≤ WB_F2_EXPIRATION_MAX_JOURS), OTP imposé par Keycloak, aucune
# règle HBAC qui les laisse entrer ; GitLab : utilisateurs externes, membres du seul projet mediagenda/api
# en Developer avec date d'expiration, main protégée (fusion et poussée Maintainer) ; Kubernetes : espace
# mediagenda-axiomdev (locataire mediagenda) avec un rôle limité, aucune autre liaison ; OpenBao : rien ;
# revue d'accès et runbook à jour. Après le départ (S12), les contrôles d'expiration et d'état actif
# sont remplacés par celui de l'absence de liaison (le départ se vérifie en S12). Lecture seule.

# shellcheck source=_f2-equipes.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f2-equipes.sh"

title "F2-S10 — Des accès bornés pour AxiomDev"
require_cmd jq curl kubectl ldapsearch date

_s10_g="$_f2b_groupe_axiom"
_s10_ns="$_f2b_ns_axiom"
_s10_re="^oidc:($_s10_g$(printf '|%s' "${_f2b_axiom_personnes[@]//./\\.}"))\$"
_s10_max=$(($(date +%s) + _f2b_expiration_max * 86400))
_s10_parti=1
for _s10_u in "${_f2b_axiom_personnes[@]}"; do
  _f2b_desactivee "$_s10_u" || _s10_parti=0
done

if ((_s10_parti)); then
  skip "accès bornés d'AxiomDev" "comptes désactivés : AxiomDev est parti, le contrôle du départ est lab/bin/check F2 12"
  check_output "aucune liaison RBAC (cluster ou espace) pour AxiomDev" '^0$' _f2b_liaisons_hors "" "$_s10_re"
  return 0
fi

# --- 1. Annuaire, Keycloak, HBAC ---------------------------------------------------------------------
_s10_groupe="$(_f2b_ldap "(&(objectClass=ipausergroup)(cn=$_s10_g))" member)"
check_cmd "annuaire : groupe $_s10_g présent" grep -q '^dn: ' <<<"$_s10_groupe"
for _s10_u in "${_f2b_axiom_personnes[@]}"; do
  check_cmd "annuaire : $_s10_u membre de $_s10_g" grep -qi "^member: uid=$_s10_u," <<<"$_s10_groupe"
  _s10_autres() {
    local g
    g="$(_f2b_groupes_ipa "$1")"
    [[ -n "$(_f2b_ldap_personne "$1" uid)" ]] || return 1
    ! grep -Evx "ipausers|$_s10_g" <<<"$g" | grep -q .
  }
  check_cmd "annuaire : $_s10_u n'appartient à aucun autre groupe" _s10_autres "$_s10_u"
  _s10_exp="$(_f2b_ldap_personne "$_s10_u" krbPrincipalExpiration | sed -n 's/^krbPrincipalExpiration: //Ip')"
  _s10_exp_ok() {
    local v="$1" t
    [[ "$v" =~ ^[0-9]{14}Z$ ]] || return 1
    t="$(date -u -d "${v:0:4}-${v:4:2}-${v:6:2} ${v:8:2}:${v:10:2}:${v:12:2}" +%s 2>/dev/null)" || return 1
    ((t > $(date +%s) && t <= _s10_max))
  }
  check_cmd "annuaire : principal de $_s10_u daté (dans le futur, à ${_f2b_expiration_max} j au plus)" _s10_exp_ok "$_s10_exp"
done

_s10_kc_id="$(keycloak_api "groups?search=$_s10_g&exact=true" 2>/dev/null | jq -r --arg g "$_s10_g" '[.. | objects | select(.name? == $g) | .id][0] // empty' 2>/dev/null)" || _s10_kc_id=""
if [[ -z "$_s10_kc_id" ]]; then
  check_cmd "Keycloak : groupe $_s10_g importé de l'annuaire (royaume medisphere)" false
else
  _s10_roles_kc() { keycloak_api "groups/$1/role-mappings/realm/composite" | jq -r '.[].name'; }
  check_output "Keycloak : $_s10_g porte le rôle second-facteur-obligatoire (OTP imposé)" '(^|[[:space:]])second-facteur-obligatoire($|[[:space:]])' \
    _s10_roles_kc "$_s10_kc_id"
fi

_s10_hbac="$(_f2b_ldap '(objectClass=ipaHBACRule)' cn ipaEnabledFlag memberUser userCategory)"
if ! grep -q '^dn: ' <<<"$_s10_hbac"; then
  skip "HBAC : aucune règle n'admet AxiomDev" "règles HBAC illisibles par le compte des checks (contrôle « ipa hbactest » à la main)"
else
  _s10_hbac_ok() {
    # Une règle par paragraphe LDIF : on refuse toute règle ACTIVE qui vise tout le monde ou AxiomDev.
    awk -v RS= -v g="$_s10_g" -v u="${_f2b_axiom_personnes[*]}" '
      BEGIN { n = split(u, us, " ") }
      /ipaEnabledFlag: TRUE/ {
        if ($0 ~ /userCategory: all/) bad = 1
        if ($0 ~ ("memberUser: cn=" g ",")) bad = 1
        for (i = 1; i <= n; i++) if ($0 ~ ("memberUser: uid=" us[i] ",")) bad = 1
      }
      END { exit bad }' <<<"$_s10_hbac"
  }
  check_cmd "HBAC : aucune règle active ne laisse entrer AxiomDev (ni allow_all ni règle à son nom)" _s10_hbac_ok
fi

# --- 2. GitLab ---------------------------------------------------------------------------------------
_s10_pid="$(gitlab_api "projects/$(_f2b_enc "$_f2b_projet_api")" 2>/dev/null | jq -r '.id // empty')" || _s10_pid=""
for _s10_u in "${_f2b_axiom_personnes[@]}"; do
  _s10_gu="$(_f2b_gitlab_utilisateur "$_s10_u")"
  if [[ -z "$_s10_gu" ]]; then
    check_cmd "GitLab : utilisateur $_s10_u présent" false
    continue
  fi
  check_cmd "GitLab : $_s10_u est un utilisateur externe" jq -e '.external == true' <<<"$_s10_gu"
  _s10_uid="$(jq -r .id <<<"$_s10_gu")"
  _s10_seul_api() {
    [[ "$(_f2b_gitlab_groupes_etrangers "$1")" == 0 ]] || return 1
    _f2b_gitlab_appartenances "$1" | jq -e --argjson p "${_s10_pid:-0}" \
      '[.[] | select(.source_type == "Project" and .source_id != $p)] | length == 0' >/dev/null 2>&1
  }
  check_cmd "GitLab : $_s10_u n'est membre d'aucun groupe (hors $_s10_g) ni d'aucun autre projet que $_f2b_projet_api" _s10_seul_api "$_s10_uid"
  if [[ "$(jq -r .state <<<"$_s10_gu")" != active ]]; then
    skip "GitLab : appartenance de $_s10_u à $_f2b_projet_api" "compte bloqué ou désactivé (départ, S12)"
    continue
  fi
  _s10_membre() {
    local m e t
    m="$(gitlab_api "projects/$_s10_pid/members/$1" 2>/dev/null)" || return 1
    jq -e '.access_level == 30' <<<"$m" >/dev/null || return 1
    e="$(jq -r '.expires_at // empty' <<<"$m")"
    [[ -n "$e" ]] || return 1
    t="$(date -u -d "$e" +%s 2>/dev/null)" || return 1
    ((t <= _s10_max))
  }
  check_cmd "GitLab : $_s10_u Developer de $_f2b_projet_api avec une date d'expiration (≤ ${_f2b_expiration_max} j)" _s10_membre "$_s10_uid"
done
_s10_protegee() {
  gitlab_api "projects/$_s10_pid/protected_branches/main" 2>/dev/null | jq -e '
    ([.push_access_levels[]?.access_level] | length > 0 and all(. >= 40 or . == 0))
    and ([.merge_access_levels[]?.access_level] | length > 0 and all(. >= 40 or . == 0))' >/dev/null 2>&1
}
check_cmd "GitLab : main de $_f2b_projet_api protégée (poussée et fusion réservées aux Maintainers)" _s10_protegee

# --- 3. Kubernetes -----------------------------------------------------------------------------------
check_cmd "espace $_s10_ns présent, rattaché au locataire mediagenda" \
  _f2b_kq '.metadata.labels["capsule.clastix.io/tenant"] == "mediagenda"' namespace "$_s10_ns"
check_cmd "$_s10_ns : un ResourceQuota borne l'espace" _f2b_kq '.items | length >= 1' -n "$_s10_ns" resourcequotas
_s10_rb_limite() {
  local rb roles cr
  rb="$(kube get rolebindings -n "$_s10_ns" -o json 2>/dev/null)" || return 1
  roles="$(kube get roles -n "$_s10_ns" -o json 2>/dev/null)" || return 1
  cr="$(kube get clusterroles -o json 2>/dev/null)" || return 1
  jq -n -e --argjson rb "$rb" --argjson ro "$roles" --argjson cr "$cr" --arg g "oidc:$_s10_g" '
    [$rb.items[] | select(any(.subjects[]?; .kind == "Group" and .name == $g))] as $l
    | ($l | length >= 1)
      and all($l[]; .roleRef.name as $n | .roleRef.kind as $k
        | (if $k == "Role" then [$ro.items[] | select(.metadata.name == $n)] else [$cr.items[] | select(.metadata.name == $n)] end) as $r
        | ($r | length == 1)
          and ($n | IN("admin", "edit", "cluster-admin") | not)
          and all($r[0].rules[]?;
                ((.resources // []) | any(. == "*" or . == "secrets" or . == "roles" or . == "rolebindings") | not)
                and ((.verbs // []) | any(. == "*" or . == "escalate" or . == "bind" or . == "impersonate") | not)))' >/dev/null 2>&1
}
check_cmd "$_s10_ns : oidc:$_s10_g lié à un rôle limité (ni Secrets, ni RBAC, ni joker)" _s10_rb_limite
check_output "aucune autre liaison RBAC (cluster ou autre espace) pour AxiomDev" '^0$' _f2b_liaisons_hors "$_s10_ns" "$_s10_re"

# --- 4. OpenBao, revue d'accès, documentation ---------------------------------------------------------
_s10_rc=0
_s10_pols="$(_f2b_bao_politiques_groupe "$_s10_g")" || _s10_rc=$?
case "$_s10_rc" in
  2) skip "OpenBao : aucun chemin pour $_s10_g" "groupes d'identité illisibles par le compte des checks" ;;
  1) check_cmd "OpenBao : aucun groupe d'identité ni politique pour $_s10_g" true ;;
  *) check_cmd "OpenBao : le groupe $_s10_g ne porte aucune politique (hors default)" \
       bash -c '! grep -Evx "default|" <<<"$1" | grep -q .' _ "$_s10_pols" ;;
esac
check_cmd "revue d'accès : modele.yml de $_f2b_projet_identite connaît $_s10_g" \
  _f2b_fichier_contient "$_f2b_projet_identite" outils/revue-acces/modele.yml "$_s10_g"
check_cmd "RB-329 : accueil et départ d'un prestataire (docs/accueil/runbooks)" \
  _f2b_doc "$_f2b_doc_dir"/runbooks '^RB-329' 'expiration' 'OTP|second facteur' 'HBAC' 'externe'
