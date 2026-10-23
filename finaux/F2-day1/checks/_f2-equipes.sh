# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et commandes entre apostrophes
# _f2-equipes.sh — fonctions partagées par les vérifications des phases 3 à 5 du final F2
# (check-S07 à check-S14 : équipe Data, prestataire AxiomDev, recette Day 1). Sourcé, jamais lancé seul.
# Lecture seule : GitLab en GET (jeton read_api des checks), « kube » (wb-checks), Prometheus (Thanos
# Query), Grafana (Viewer), annuaire (ipa_ldap, compte système wb-checks), Keycloak (client wb-checks),
# OpenBao (AppRole wb-checks : métadonnées et politiques, jamais une valeur), Backstage (catalogue).
# Aucun contrôle ne lit une donnée de santé ni un Secret : l'extraction pseudonymisée de S07 est vue
# par les métriques que la base Data publie (requêtes personnalisées de CloudNativePG).
# Préfixe des fonctions : _f2b_.

_f2b_ns_data="${WB_F2_DATA_NS:-data-traitements}"
_f2b_cluster_data="${WB_F2_DATA_CLUSTER:-statistiques-db}"
_f2b_ns_axiom="${WB_F2_AXIOM_NS:-mediagenda-axiomdev}"
_f2b_groupe_axiom="${WB_F2_AXIOM_GROUPE:-ext-axiomdev}"
read -r -a _f2b_axiom_personnes <<<"${WB_F2_AXIOM_PERSONNES:-marc.vidal yanis.perrin}"
read -r -a _f2b_equipes <<<"${WB_F2_EQUIPES:-medivisio data}"
_f2b_projet_api="${WB_F2_PROJET_API:-mediagenda/api}"
_f2b_projet_doc="${WB_F2_PROJET_DOC:-plateforme/medisphere}"
_f2b_doc_dir="${WB_F2_DOC:-docs/accueil}"
_f2b_projet_outils="${WB_F2_PROJET_OUTILS:-plateforme/outils}"
_f2b_projet_identite="${WB_F2_PROJET_IDENTITE:-plateforme/identite}"
_f2b_expiration_max="${WB_F2_EXPIRATION_MAX_JOURS:-100}"
_f2b_tableau="${WB_F2_TABLEAU_CONSOMMATION:-plateforme-consommation-locataires}"
_f2b_fraicheur="${WB_F2_FRAICHEUR_S:-129600}" # 36 h : un traitement de nuit manqué se voit le lendemain

# --- GitLab (lecture) --------------------------------------------------------------------------------

_f2b_enc() { jq -rn --arg s "$1" '$s|@uri'; }

# _f2b_fichier PROJET CHEMIN [RÉF=main] — contenu du fichier sur la référence.
_f2b_fichier() {
  gitlab_api "projects/$(_f2b_enc "$1")/repository/files/$(_f2b_enc "$2")/raw?ref=$(_f2b_enc "${3:-main}")"
}

# _f2b_fichier_contient PROJET CHEMIN REGEX… — le fichier existe sur main et contient chaque motif
# (insensible à la casse).
_f2b_fichier_contient() {
  local c m p="$1" chemin="$2"
  shift 2
  c="$(_f2b_fichier "$p" "$chemin" 2>/dev/null)" || return 1
  [[ -n "$c" ]] || return 1
  for m in "$@"; do grep -Eqi -- "$m" <<<"$c" || return 1; done
}

# _f2b_arbre PROJET [DOSSIER] [RÉF=main] — chemins des fichiers (récursif).
_f2b_arbre() {
  local p page=1 r ref
  p="$(_f2b_enc "$1")"
  ref="$(_f2b_enc "${3:-main}")"
  while ((page <= 10)); do
    r="$(gitlab_api "projects/$p/repository/tree?ref=$ref&recursive=true&per_page=100&page=$page${2:+&path=$(_f2b_enc "$2")}" 2>/dev/null)" || return 0
    jq -r '.[]? | select(.type == "blob") | .path' <<<"$r"
    (($(jq 'length' <<<"$r" 2>/dev/null || echo 0) < 100)) && return 0
    page=$((page + 1))
  done
}

# _f2b_doc DOSSIER MOTIF_NOM REGEX… — un fichier de plateforme/medisphere sous DOSSIER (main) dont le
# nom correspond à MOTIF_NOM contient chaque motif.
_f2b_doc() {
  local d="$1" motif="$2" f
  shift 2
  while IFS= read -r f; do
    [[ -n "$f" && "${f##*/}" =~ $motif ]] || continue
    _f2b_fichier_contient "$_f2b_projet_doc" "$f" "$@" && return 0
  done < <(_f2b_arbre "$_f2b_projet_doc" "$d")
  return 1
}

# _f2b_doc_sections FICHIER NB REGEX… — le document (chemin exact dans plateforme/medisphere) a au moins
# NB titres de section et contient chaque motif.
_f2b_doc_sections() {
  local f="$1" nb="$2" c
  shift 2
  c="$(_f2b_fichier "$_f2b_projet_doc" "$f" 2>/dev/null)" || return 1
  (($(grep -Ec '^#{2,3} ' <<<"$c") >= nb)) || return 1
  _f2b_fichier_contient "$_f2b_projet_doc" "$f" "$@"
}

# _f2b_pipeline_ok PROJET — le dernier pipeline de main a réussi.
_f2b_pipeline_ok() {
  gitlab_api "projects/$(_f2b_enc "$1")/pipelines?ref=main&per_page=1" 2>/dev/null |
    jq -e '.[0].status == "success"' >/dev/null 2>&1
}

# _f2b_etiquette PROJET NOM — l'étiquette existe.
_f2b_etiquette() {
  gitlab_api "projects/$(_f2b_enc "$1")/repository/tags/$(_f2b_enc "$2")" 2>/dev/null |
    jq -e '.name' >/dev/null 2>&1
}

# _f2b_gitlab_utilisateur IDENTIFIANT — JSON de l'utilisateur GitLab (vide s'il n'existe pas). Le jeton
# des checks appartient à un administrateur : les champs « external », « state » sont visibles.
_f2b_gitlab_utilisateur() {
  gitlab_api "users?username=$(_f2b_enc "$1")" 2>/dev/null | jq -c '.[0] // empty' 2>/dev/null
}

# _f2b_gitlab_appartenances ID — appartenances directes (groupes et projets) de l'utilisateur, JSON.
_f2b_gitlab_appartenances() {
  gitlab_api "users/$1/memberships?per_page=100" 2>/dev/null
}

# _f2b_gitlab_groupes_etrangers ID — nombre de groupes GitLab dont l'utilisateur est membre direct, SAUF
# le groupe propre de l'équipe externe (ext-axiomdev : créé par l'équipe en code, il ne contient aucun
# projet de MédiSphère). Vide en cas d'erreur.
_f2b_gitlab_groupes_etrangers() {
  local propre
  propre="$(gitlab_api "groups/$(_f2b_enc "$_f2b_groupe_axiom")" 2>/dev/null | jq -r '.id // 0')" || propre=0
  _f2b_gitlab_appartenances "$1" | jq --argjson g "${propre:-0}" '[.[] | select(.source_type == "Namespace" and .source_id != $g)] | length' 2>/dev/null
}

# --- Kubernetes (wb-checks) --------------------------------------------------------------------------

# _f2b_kq 'filtre jq' ARGS… — 0 si « kube get ARGS -o json » satisfait le filtre.
_f2b_kq() {
  local f="$1"
  shift
  kube get "$@" -o json 2>/dev/null | jq -e "$f" >/dev/null 2>&1
}

# _f2b_liaisons_hors ESPACE_PERMIS REGEX_SUJET — nombre de liaisons RBAC (ClusterRoleBinding, et
# RoleBinding hors de ESPACE_PERMIS) dont un sujet User/Group correspond à REGEX_SUJET. Vide si illisible.
_f2b_liaisons_hors() {
  local permis="$1" re="$2" crb rb
  crb="$(kube get clusterrolebindings -o json 2>/dev/null)" || return 1
  rb="$(kube get rolebindings -A -o json 2>/dev/null)" || return 1
  jq -n --argjson c "$crb" --argjson r "$rb" --arg p "$permis" --arg re "$re" '
    [($c.items[]), ($r.items[] | select(.metadata.namespace != $p))
     | select(any(.subjects[]?; (.kind == "User" or .kind == "Group") and (.name | test($re))))] | length'
}

# _f2b_aucune_panne_active SXX… — aucune des pannes listées n'est marquée active sur adm01.
_f2b_aucune_panne_active() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives" e
  for e in "$@"; do
    [[ ! -e "$d/F2-$e" ]] || return 1
  done
}

# --- Prometheus (Thanos Query) -----------------------------------------------------------------------

# _f2b_prom_val 'PromQL' — première valeur du résultat (vide si aucun).
_f2b_prom_val() {
  prom_requete "$1" 2>/dev/null | jq -r '.data.result[0].value[1] // empty' 2>/dev/null
}

# _f2b_prom_non_vide 'PromQL' — la requête renvoie au moins une série.
_f2b_prom_non_vide() {
  prom_requete "$1" 2>/dev/null | jq -e '.status == "success" and (.data.result | length) > 0' >/dev/null 2>&1
}

# _f2b_prom_inferieur 'PromQL' SEUIL — la première valeur existe et est < SEUIL.
_f2b_prom_inferieur() {
  local v
  v="$(_f2b_prom_val "$1")"
  [[ -n "$v" ]] && awk -v v="$v" -v s="$2" 'BEGIN { exit !(v + 0 < s + 0) }'
}

# _f2b_prom_superieur 'PromQL' SEUIL — la première valeur existe et est > SEUIL.
_f2b_prom_superieur() {
  local v
  v="$(_f2b_prom_val "$1")"
  [[ -n "$v" ]] && awk -v v="$v" -v s="$2" 'BEGIN { exit !(v + 0 > s + 0) }'
}

# --- Annuaire (ipa_ldap, compte système wb-checks) ----------------------------------------------------

_f2b_ldap() { ipa_ldap "$@" 2>/dev/null || true; }

# _f2b_ldap_personne UID ATTRIBUTS… — LDIF de la personne (vide si absente ou illisible).
_f2b_ldap_personne() {
  local u="$1"
  shift
  _f2b_ldap "(&(objectClass=person)(uid=$u))" "$@"
}

# _f2b_desactivee UID — la personne existe et nsAccountLock vaut TRUE.
_f2b_desactivee() {
  _f2b_ldap_personne "$1" nsAccountLock | grep -qi '^nsAccountLock: TRUE'
}

# _f2b_groupes_ipa UID — noms courts des groupes dont la personne est membre directe (memberOf).
_f2b_groupes_ipa() {
  _f2b_ldap_personne "$1" memberOf | sed -n 's/^memberOf: cn=\([^,]*\),cn=groups,cn=accounts,.*/\1/Ip'
}

# --- OpenBao (métadonnées) ---------------------------------------------------------------------------

# _f2b_bao_politiques_groupe GROUPE — politiques du groupe d'identité (une par ligne) ; code 2 si le
# groupe est illisible (droits du compte des checks), code 1 s'il n'existe pas.
_f2b_bao_politiques_groupe() {
  local r
  r="$(bao_api "identity/group/name/$1" 2>/dev/null)" || {
    bao_api "identity/group/name/" >/dev/null 2>&1 || return 2
    return 1
  }
  jq -r '.data.policies[]?' <<<"$r"
}

# _f2b_bao_texte_politique NOM — texte HCL de la politique ACL.
_f2b_bao_texte_politique() {
  bao_api "sys/policies/acl/$1" 2>/dev/null | jq -r '.data.policy // empty'
}
