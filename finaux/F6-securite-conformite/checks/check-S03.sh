# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S03.sh — F6-S03 « La revue des accès » (LIBRE) : revue publiée (docs/conformite/revue-acces/
# AAAA-MM.md) couvrant les neuf systèmes, outil reproductible dans plateforme/outils, et plus aucun accès
# résiduel d'AxiomDev (annuaire, GitLab, Kubernetes, Argo CD). Lecture seule.

# shellcheck source=_f6-conformite.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f6-conformite.sh"

title "F6-S03 — La revue des accès"
require_cmd curl jq

_f6_s03_revue() {
  _f6c_doc revue-acces '^[0-9]{4}-(0[1-9]|1[0-2])\.md$' 'FreeIPA|annuaire' 'Keycloak' 'GitLab' 'Proxmox' \
    'Kubernetes|RBAC' 'OpenBao' 'Harbor' 'Argo ?CD' 'Grafana'
}
check_cmd "revue-acces/AAAA-MM.md (main) : les neuf systèmes sont couverts" _f6_s03_revue
_f6_s03_decisions() {
  _f6c_doc revue-acces '^[0-9]{4}-(0[1-9]|1[0-2])\.md$' 'd(é|e)cision' 'orphelin' 'axiomdev|marc\.vidal|yanis\.perrin' \
    'responsable|propri(é|e)taire' '(é|e)ch(é|e)ance'
}
check_cmd "revue des accès : comptes orphelins (dont AxiomDev) avec décision, responsable et échéance" _f6_s03_decisions
_f6_s03_outil() { _f6c_arbre "$_f6c_outils" bin | grep -Eq '^bin/ms-[a-z-]*acces'; }
check_cmd "plateforme/outils (main) : outil de revue des accès (bin/ms-…acces…) versionné" _f6_s03_outil

# --- AxiomDev : plus aucun accès résiduel --------------------------------------------------------------
_f6_s03_ipa_verrouille() {
  local u="$1" r
  r="$(ipa_ldap "(uid=$u)" nsAccountLock 2>/dev/null)" || return 2
  [[ -n "$r" ]] || return 0                                   # compte absent : rien à revoir
  grep -qi '^nsAccountLock: TRUE' <<<"$r"
}
_f6_s03_gitlab_bloque() {
  local u="$1" e
  e="$(gitlab_api "users?username=$(_f6c_enc "$u")" 2>/dev/null | jq -r '.[0].state // "absent"')" || return 2
  [[ "$e" != active ]]
}
for _f6_s03_u in $_f6c_externes; do
  _f6_s03_rc=0
  _f6_s03_ipa_verrouille "$_f6_s03_u" || _f6_s03_rc=$?
  if ((_f6_s03_rc == 2)); then
    skip "annuaire : $_f6_s03_u" "lecture LDAP impossible (ipa-checks.env)"
  else
    check_cmd "annuaire : le compte de $_f6_s03_u (AxiomDev) est désactivé" test "$_f6_s03_rc" -eq 0
  fi
  check_cmd "GitLab : le compte de $_f6_s03_u (AxiomDev) n'est pas actif" _f6_s03_gitlab_bloque "$_f6_s03_u"
done

if ! _f6c_api_repond; then
  skip "Kubernetes et Argo CD" "l'API ne répond pas au compte des checks"
else
  _f6_s03_re="$(tr ' ' '|' <<<"$_f6c_externes")|ext-axiomdev"
  _f6_s03_liaisons() {
    kube get clusterrolebindings,rolebindings -A -o json 2>/dev/null |
      jq -e --arg r "$_f6_s03_re" '[.items[] | .subjects[]? | select(.name | test($r))] | length == 0' >/dev/null 2>&1
  }
  check_cmd "Kubernetes : aucune liaison RBAC vers AxiomDev (personnes ou groupe ext-axiomdev)" _f6_s03_liaisons
  _f6_s03_espace_absent() { local r; r="$(kube get namespace mediagenda-axiomdev 2>&1 || true)"; grep -q NotFound <<<"$r"; }
  check_cmd "Kubernetes : l'espace mediagenda-axiomdev n'existe plus" _f6_s03_espace_absent
  _f6_s03_argocd() {
    local p
    p="$(kube get configmap argocd-rbac-cm -n argocd -o json 2>/dev/null | jq -r '.data // {} | to_entries[] | .value')" || return 2
    ! grep -Eq "ext-axiomdev|$(tr ' ' '|' <<<"$_f6c_externes")" <<<"$p"
  }
  _f6_s03_rc=0
  _f6_s03_argocd || _f6_s03_rc=$?
  if ((_f6_s03_rc == 2)); then
    skip "Argo CD : politique RBAC" "le compte des checks ne lit pas argocd-rbac-cm"
  else
    check_cmd "Argo CD : la politique RBAC ne cite plus AxiomDev" test "$_f6_s03_rc" -eq 0
  fi
fi
