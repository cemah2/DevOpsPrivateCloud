# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et expressions régulières entre apostrophes
#
# check-E39.sh — M24-E39 « Panne : les droits d'Argo CD sont faux » : argocd-rbac-cm lit les groupes
# (scopes), n'a aucun rôle par défaut, et sa politique est celle de releases/argocd/policy.csv sur main
# de plateforme/k8s (hors commentaires et lignes vides) ; seul role:plateforme-admin hérite de
# role:admin ; la revendication groups est en noms courts ; alerte sur les écritures dans la
# configuration d'Argo CD chargée (ruler, locataire audit) ; pipeline de main vert ; RB-246 ; journal ;
# panne close. Lecture seule (kube : ConfigMap argocd-rbac-cm ; keycloak_api ; Loki ; GitLab).

# shellcheck source=_m24-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m24-expert.sh"

title "M24-E39 — Panne : les droits d'Argo CD sont faux"
require_cmd jq curl kubectl

# _m24x_e39_normaliser — politique Casbin sans commentaires, lignes vides ni espaces autour des virgules, triée.
_m24x_e39_normaliser() {
  sed -E 's/#.*$//; s/[[:space:]]*,[[:space:]]*/,/g; s/^[[:space:]]+//; s/[[:space:]]+$//' | grep -v '^$' | sort || true
}

# _m24x_e39_admin_seul POLITIQUE — politique normalisée non vide où seul role:plateforme-admin hérite de role:admin.
_m24x_e39_admin_seul() {
  [[ -n "$1" ]] && ! awk -F, '$1 == "g" && $3 == "role:admin" && $2 != "role:plateforme-admin" { t = 1 } END { exit !t }' <<<"$1"
}

_m24x_e39_rbac="$(kube -n argocd get configmap argocd-rbac-cm -o json 2>/dev/null || true)"
if [[ -z "$_m24x_e39_rbac" ]]; then
  _ko "Argo CD : ConfigMap argocd-rbac-cm illisible avec le compte des checks"
else
  check_cmd "argocd-rbac-cm : groupes lus dans la revendication groups (scopes), aucun rôle par défaut (policy.default vide)" \
    _m24d_json "$_m24x_e39_rbac" '((.data.scopes // "") | test("groups")) and ((.data["policy.default"] // "") == "")'
  _m24x_e39_en_place="$(jq -r '.data["policy.csv"] // ""' <<<"$_m24x_e39_rbac" | _m24x_e39_normaliser)"
  _m24x_e39_depot="$(_m24d_contenu_main plateforme/k8s releases/argocd/policy.csv | _m24x_e39_normaliser)"
  if [[ -z "$_m24x_e39_depot" ]]; then
    _ko "plateforme/k8s : releases/argocd/policy.csv illisible sur main (référence de la politique)"
  else
    check_cmd "argocd-rbac-cm : policy.csv identique à releases/argocd/policy.csv de main (aucune dérive)" \
      test "$_m24x_e39_en_place" == "$_m24x_e39_depot"
  fi
  check_cmd "policy.csv : seul role:plateforme-admin hérite de role:admin ; plateforme-admins reçoit role:plateforme-admin" \
    _m24p_tous "$_m24x_e39_en_place" '^g,role:plateforme-admin,role:admin$' '^g,plateforme-admins,role:plateforme-admin$'
  check_cmd "policy.csv : aucun autre sujet ne reçoit role:admin" _m24x_e39_admin_seul "$_m24x_e39_en_place"
fi
check_cmd "Portée groupes : mappeur groups en noms courts (chemin complet désactivé)" _m24x_noms_courts

check_cmd "Ruler de Loki (audit) : une alerte sur les écritures dans la configuration d'Argo CD (argocd-rbac-cm)" \
  _m24x_ruler_qui audit 'argocd-rbac-cm'
check_output "plateforme/k8s : dernier pipeline de main réussi (tests de la politique RBAC compris)" '^success$' \
  _m24d_pipeline_main plateforme/k8s
check_cmd "RB-246 sur main : section « droits faux dans un service »" _m24x_section "$(_m24x_rb246)" 'droit|autoris|groupes'
check_cmd "Journal de diagnostic M24-E39 sur main (docs/socle/journal/)" _m24x_journal E39
check_cmd "Panne M24-E39 close (lab/bin/break 24 39 --annuler après réparation)" _m24x_panne_close E39
