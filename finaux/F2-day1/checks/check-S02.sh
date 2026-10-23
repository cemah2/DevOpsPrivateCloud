# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-S02.sh — F2-S02 : une équipe en un changement
# À lancer depuis adm01. Lecture seule. Vérifie les RÉSULTATS pour chaque équipe de WB_F2_EQUIPES
# (défaut : medivisio data), quelle que soit la façon de les produire, plus les noms fixés par le final
# (projet plateforme/equipes, fichier equipes/<equipe>.yaml) et les livrables écrits.
# Sources : GitLab (jeton des checks), annuaire (LDAP, compte système wb-checks), cluster (wb-checks :
# Tenants, espaces, quotas, AppProjects ; jamais un Secret), OpenBao (AppRole wb-checks : politiques et
# rôles, jamais une valeur), Backstage (catalogue), Grafana (Viewer), Alertmanager (configuration active).

# shellcheck source=_f2-cadre.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f2-cadre.sh"

title "F2-S02 — Une équipe en un changement"
require_cmd jq curl kubectl ldapsearch

_F2A_BASE_LDAP="${WB_IPA_BASE:-dc=par1,dc=medisphere,dc=internal}"

# --- Contrôles élémentaires (appelés par check_cmd dans le shell courant) -----------------------------

_f2a_s02_nb_membres_ldap() {  # GROUPE MIN
  local n
  n="$(ipa_ldap "(&(objectClass=ipausergroup)(cn=$1))" member 2>/dev/null | grep -c '^member: uid=' || true)"
  ((n >= $2))
}
_f2a_s02_aucun_verrouille() {  # GROUPE
  ! ipa_ldap "(&(objectClass=inetOrgPerson)(memberOf=cn=$1,cn=groups,cn=accounts,$_F2A_BASE_LDAP)(nsAccountLock=TRUE))" uid 2>/dev/null | grep -q '^uid:'
}
_f2a_s02_aucun_hbac() {  # GROUPE — ni règle active qui cite le groupe, ni allow_all active
  local r
  r="$(ipa_ldap "(&(objectClass=ipahbacrule)(ipaEnabledFlag=TRUE)(|(memberUser=cn=$1,cn=groups,cn=accounts,$_F2A_BASE_LDAP)(cn=allow_all)))" cn 2>/dev/null)" || return 1
  ! grep -q '^cn:' <<<"$r"
}
_f2a_s02_groupe_gitlab() { gitlab_api "groups/$(_f2a_enc "$1")" >/dev/null 2>&1; }
_f2a_s02_maintainer() {  # GROUPE IDENTIFIANT
  local n
  n="$(_f2a_niveau_membre "$1" "$2")"
  ((n >= 40 && n < 50))
}
_f2a_s02_developer_sans_owner() {  # GROUPE
  gitlab_api "groups/$(_f2a_enc "$1")/members?per_page=100" 2>/dev/null | jq -e 'any(.[]; .access_level == 30)
    and ([.[] | select(.access_level == 50 and (.username | test("^(svc-|root$|group_|project_)") | not))] | length == 0)' >/dev/null 2>&1
}
_f2a_s02_quota_limites() {  # ESPACE
  kube -n "$1" get resourcequotas -o json 2>/dev/null |
    jq -e 'any(.items[]; .spec.hard["requests.cpu"] and .spec.hard["requests.memory"] and .spec.hard["limits.memory"])' >/dev/null 2>&1 &&
    kube -n "$1" get limitranges -o json 2>/dev/null | jq -e '.items | length > 0' >/dev/null 2>&1
}
_f2a_s02_secretstore() {  # ESPACE
  kube -n "$1" get secretstores.external-secrets.io -o json 2>/dev/null |
    jq -e --arg r "eso-$1" 'any(.items[]; .spec.provider.vault.auth.kubernetes.role == $r)' >/dev/null 2>&1
}
_f2a_s02_role_eso() {  # ESPACE
  bao_api "auth/k8s-par1/role/eso-$1" 2>/dev/null |
    jq -e --arg n "$1" '.data.bound_service_account_namespaces == [$n] and .data.bound_service_account_names == ["eso"]' >/dev/null 2>&1
}
_f2a_s02_politiques_bornees() {  # EQUIPE — politiques du groupe externe : uniquement kv/<equipe>/ (hors ci/)
  local e="$1" gb p texte chemins
  gb="$(bao_api "identity/group/name/$e" 2>/dev/null)" || return 1
  [[ -n "$(jq -r '.data.policies[]?' <<<"$gb")" ]] || return 1
  for p in $(jq -r '.data.policies[]?' <<<"$gb"); do
    texte="$(bao_api "sys/policies/acl/$p" 2>/dev/null | jq -r '.data.policy // ""')" || return 1
    [[ -n "$texte" ]] || return 1
    chemins="$(grep -Eo 'path "[^"]+"' <<<"$texte" | sed 's/^path "//; s/"$//')"
    while IFS= read -r c; do
      [[ -z "$c" || "$c" == "sys/capabilities-self" ]] && continue
      [[ "$c" =~ ^kv/(data|metadata|delete|undelete)/$e/ ]] || return 1
      [[ "$c" =~ ^kv/[a-z]+/$e/ci(/|$) ]] && return 1
    done <<<"$chemins"
  done
  return 0
}
_f2a_s02_groupe_catalogue() {  # EQUIPE
  backstage_api "catalog/entities/by-name/group/default/$1" 2>/dev/null |
    jq -e 'any(.relations[]?; .type == "hasMember")' >/dev/null 2>&1
}
_f2a_s02_dossier_grafana() { grafana_api "folders/$1" >/dev/null 2>&1; }
_f2a_s02_utilisateurs_historiques() {
  kube get capsuleconfigurations.capsule.clastix.io default -o json 2>/dev/null |
    jq -e '[.spec.users[]?.name] as $u | ($u | index("oidc:mediagenda")) and ($u | index("oidc:medidoc"))' >/dev/null 2>&1
}

# --- Le mécanisme et ses livrables --------------------------------------------------------------------
check_cmd "projet GitLab $_F2A_P_EQUIPES" _f2a_projet_existe "$_F2A_P_EQUIPES"
check_cmd "$_F2A_P_EQUIPES : CI définie (.gitlab-ci.yml sur main)" \
  _f2a_contient "$(_f2a_fichier "$_F2A_P_EQUIPES" .gitlab-ci.yml)" "stages|script"
check_cmd "docs : capacite.md (allouable, requests réservées, budgets)" \
  _f2a_contient "$(_f2a_fichier plateforme/medisphere "$_F2A_DOC/capacite.md")" "allouable" "request" "budget|quota"
check_cmd "docs : ADR-0320 publié (adr/ADR-0320-…)" _f2a_doc '^ADR-0320' "statut|status" "décision|decision"
check_cmd "docs : RB-320 publié (accueillir, modifier, retirer)" _f2a_doc '^RB-320' "arriv|accueil" "départ|retir"

_f2a_s02_tenants="$(_f2a_k get tenants.capsule.clastix.io)"
_f2a_s02_ns="$(_f2a_k get namespaces)"
_f2a_s02_projets="$(_f2a_k -n argocd get appprojects.argoproj.io)"
_f2a_s02_am="$(_f2a_am_config)"

for _f2a_s02_e in $_F2A_EQUIPES; do
  echo "  -- équipe $_f2a_s02_e"
  _f2a_s02_f="$(_f2a_fichier "$_F2A_P_EQUIPES" "equipes/$_f2a_s02_e.yaml")"
  check_cmd "$_F2A_P_EQUIPES : equipes/$_f2a_s02_e.yaml (kind Equipe, metadata.nom $_f2a_s02_e, personnes)" \
    _f2a_contient "$_f2a_s02_f" "kind: *Equipe" "nom: *$_f2a_s02_e\b" "personnes:"

  # Annuaire
  check_cmd "annuaire : groupe $_f2a_s02_e avec au moins deux membres" _f2a_s02_nb_membres_ldap "$_f2a_s02_e" 2
  check_cmd "annuaire : aucun membre de $_f2a_s02_e désactivé" _f2a_s02_aucun_verrouille "$_f2a_s02_e"
  check_cmd "annuaire : aucune règle HBAC active n'ouvre de machine à $_f2a_s02_e (ni allow_all)" _f2a_s02_aucun_hbac "$_f2a_s02_e"

  # GitLab
  check_cmd "GitLab : groupe $_f2a_s02_e" _f2a_s02_groupe_gitlab "$_f2a_s02_e"
  _f2a_s02_resp="$(sed -n 's/^ *responsable: *\([a-z.]*\).*/\1/p' <<<"$_f2a_s02_f" | head -n1)"
  if [[ -n "$_f2a_s02_resp" ]]; then
    check_cmd "GitLab : $_f2a_s02_resp (responsable) Maintainer de $_f2a_s02_e" _f2a_s02_maintainer "$_f2a_s02_e" "$_f2a_s02_resp"
  else
    skip "GitLab : responsable Maintainer de $_f2a_s02_e" "responsable illisible dans equipes/$_f2a_s02_e.yaml"
  fi
  check_cmd "GitLab : un Developer au moins dans $_f2a_s02_e, aucune personne Owner" _f2a_s02_developer_sans_owner "$_f2a_s02_e"

  # Capsule
  check_cmd "Capsule : locataire $_f2a_s02_e actif, propriétaire oidc:$_f2a_s02_e" _f2a_json "$_f2a_s02_tenants" \
    "any(.items[]; .metadata.name == \"$_f2a_s02_e\" and .status.state == \"Active\"
       and any(.spec.owners[]?; .name == \"oidc:$_f2a_s02_e\"))"
  check_cmd "Capsule : $_f2a_s02_e a un budget global et des classes de priorité bornées (défaut posé)" _f2a_json "$_f2a_s02_tenants" \
    "any(.items[]; .metadata.name == \"$_f2a_s02_e\"
       and any(.spec.rules[]?; (has(\"namespaceSelector\") | not) and ((.quota // []) | length > 0))
       and ((.spec.priorityClasses.allowed // []) | length > 0) and (.spec.priorityClasses.default // \"\") != \"\")"
  case "$_f2a_s02_e" in
    data)
      check_cmd "Capsule : data autorise medisphere-lot, pas medisphere-critique" _f2a_json "$_f2a_s02_tenants" \
        'any(.items[]; .metadata.name == "data" and (.spec.priorityClasses.allowed | index("medisphere-lot"))
           and (.spec.priorityClasses.allowed | index("medisphere-critique") | not))'
      _f2a_s02_attendus="data-traitements" ;;
    medivisio)
      check_cmd "Capsule : medivisio autorise medisphere-critique (production)" _f2a_json "$_f2a_s02_tenants" \
        'any(.items[]; .metadata.name == "medivisio" and (.spec.priorityClasses.allowed | index("medisphere-critique")))'
      _f2a_s02_attendus="medivisio-dev medivisio-recette medivisio-prod" ;;
    *)
      _f2a_s02_attendus="$(jq -r --arg e "$_f2a_s02_e" '.items[]? | select(.metadata.labels["capsule.clastix.io/tenant"] == $e
        and (.metadata.labels["medisphere.internal/environnement"] // "") != "") | .metadata.name' <<<"$_f2a_s02_ns" 2>/dev/null || true)" ;;
  esac
  [[ -n "$_f2a_s02_attendus" ]] || check_cmd "Kubernetes : au moins un environnement pour $_f2a_s02_e" false
  for _f2a_s02_n in $_f2a_s02_attendus; do
    check_cmd "espace $_f2a_s02_n : rattaché à $_f2a_s02_e (étiquette et référence de propriétaire), PSA restricted" \
      _f2a_json "$_f2a_s02_ns" "any(.items[]; .metadata.name == \"$_f2a_s02_n\"
        and .metadata.labels[\"capsule.clastix.io/tenant\"] == \"$_f2a_s02_e\"
        and .metadata.labels[\"pod-security.kubernetes.io/enforce\"] == \"restricted\"
        and any(.metadata.ownerReferences[]?; .kind == \"Tenant\" and .name == \"$_f2a_s02_e\"))"
    check_cmd "espace $_f2a_s02_n : ResourceQuota (requests.cpu, requests.memory, limits.memory) et LimitRange" \
      _f2a_s02_quota_limites "$_f2a_s02_n"
    check_cmd "espace $_f2a_s02_n : SecretStore lié au rôle eso-$_f2a_s02_n" _f2a_s02_secretstore "$_f2a_s02_n"
    check_cmd "coffre : rôle k8s-par1 eso-$_f2a_s02_n limité au compte eso de $_f2a_s02_n" _f2a_s02_role_eso "$_f2a_s02_n"
  done

  # Argo CD
  check_cmd "Argo CD : AppProject $_f2a_s02_e — dépôts du groupe, ses espaces seulement, rien de cluster, quotas interdits" \
    _f2a_json "$_f2a_s02_projets" "any(.items[]; .metadata.name == \"$_f2a_s02_e\"
      and ((.spec.sourceRepos // []) | length > 0)
      and all(.spec.sourceRepos[]; startswith(\"https://git01.par1.medisphere.internal/$_f2a_s02_e/\"))
      and ((.spec.destinations // []) | length > 0)
      and all(.spec.destinations[]; (.namespace // \"\") | startswith(\"$_f2a_s02_e-\"))
      and ((.spec.clusterResourceWhitelist // []) | length == 0)
      and any(.spec.namespaceResourceBlacklist[]?; .kind == \"ResourceQuota\"))"

  # Coffre, portail, Grafana, alertes
  check_cmd "coffre : groupe externe $_f2a_s02_e, politiques limitées à kv/$_f2a_s02_e/ (jamais ci/)" \
    _f2a_s02_politiques_bornees "$_f2a_s02_e"
  check_cmd "portail : entité Group $_f2a_s02_e au catalogue, avec des membres" _f2a_s02_groupe_catalogue "$_f2a_s02_e"
  check_cmd "Grafana : dossier d'UID $_f2a_s02_e" _f2a_s02_dossier_grafana "$_f2a_s02_e"
  if grep -Eq "alertes: *true" <<<"$_f2a_s02_f"; then
    check_cmd "Alertmanager : route equipe=$_f2a_s02_e vers $_f2a_s02_e@medisphere.internal (configuration active)" \
      _f2a_route_equipe "$_f2a_s02_e" "$_f2a_s02_am"
  else
    skip "Alertmanager : route de $_f2a_s02_e" "aucun environnement « alertes: true » dans le fichier"
  fi
done

# --- Les équipes historiques n'ont rien perdu ---------------------------------------------------------
echo "  -- équipes historiques"
check_cmd "Capsule : locataires mediagenda, medidoc, medinotif toujours actifs" _f2a_json "$_f2a_s02_tenants" \
  '[.items[] | select(.metadata.name | IN("mediagenda", "medidoc", "medinotif")) | select(.status.state == "Active")] | length == 3'
check_cmd "Capsule : oidc:mediagenda et oidc:medidoc toujours utilisateurs Capsule" _f2a_s02_utilisateurs_historiques
