# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S07.sh — F2-S07 « Des bases en libre-service pour l'équipe Data » : Cluster CNPG de l'équipe
# sain, archivé par le plugin Barman Cloud, sauvegarde de base récente ; sauvegarde imposée par une
# politique d'admission ; extraction pseudonymisée chargée cette nuit (métriques publiées par la base
# Data : nombre de lignes, âge du chargement, noms des colonnes), sans colonne identifiante ; aucune
# liaison réseau, RBAC, ESO ni OpenBao entre Data et les bases de MédiAgenda.
# Lecture seule : kube (wb-checks), Prometheus, OpenBao (métadonnées et texte des politiques).

# shellcheck source=_f2-equipes.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f2-equipes.sh"

title "F2-S07 — Des bases en libre-service pour l'équipe Data"
require_cmd jq curl kubectl

_s07_ns="$_f2b_ns_data"
_s07_cl="$_f2b_cluster_data"

# --- 1. La base de l'équipe --------------------------------------------------------------------------
check_cmd "$_s07_ns : Cluster $_s07_cl sain (« Cluster in healthy state »)" \
  _f2b_kq '.status.phase == "Cluster in healthy state"' -n "$_s07_ns" clusters.postgresql.cnpg.io "$_s07_cl"
check_cmd "$_s07_cl : WAL archivés par le plugin Barman Cloud (isWALArchiver)" \
  _f2b_kq '[.spec.plugins[]? | select(.name == "barman-cloud.cloudnative-pg.io" and (.isWALArchiver // false))] | length == 1' \
  -n "$_s07_ns" clusters.postgresql.cnpg.io "$_s07_cl"
check_cmd "$_s07_cl : classe ceph-rbd, requests et limite mémoire déclarées, superutilisateur désactivé" \
  _f2b_kq '(.spec.storage.storageClass // "") == "ceph-rbd"
           and ((.spec.resources.requests.memory // "") != "") and ((.spec.resources.limits.memory // "") != "")
           and ((.spec.enableSuperuserAccess // false) == false)' \
  -n "$_s07_ns" clusters.postgresql.cnpg.io "$_s07_cl"
_s07_planifiee() {
  kube get scheduledbackups.postgresql.cnpg.io -n "$_s07_ns" -o json 2>/dev/null |
    jq -e --arg c "$_s07_cl" '[.items[] | select(.spec.cluster.name == $c and ((.spec.suspend // false) | not))] | length >= 1' >/dev/null 2>&1
}
check_cmd "$_s07_cl : une ScheduledBackup active vise la base" _s07_planifiee
_s07_backup_recent() {
  kube get backups.postgresql.cnpg.io -n "$_s07_ns" -o json 2>/dev/null |
    jq -e --arg c "$_s07_cl" --argjson f "$_f2b_fraicheur" '
      any(.items[]; .spec.cluster.name == $c and .status.phase == "completed"
          and ((.status.stoppedAt // "1970-01-01T00:00:00Z") | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) > (now - $f))' >/dev/null 2>&1
}
check_cmd "$_s07_cl : une sauvegarde de base réussie depuis moins de 36 h" _s07_backup_recent

# --- 2. La sauvegarde imposée par la plateforme ------------------------------------------------------
_s07_politique() {
  local j
  j="$(kube get validatingpolicies.policies.kyverno.io -o json 2>/dev/null)" || j='{"items":[]}'
  jq -e 'any(.items[];
      (.spec.validationActions // [] | index("Deny")) != null
      and any(.spec.matchConstraints.resourceRules[]?;
              ((.apiGroups // []) | index("postgresql.cnpg.io")) != null
              and ((.resources // []) | index("clusters")) != null))' <<<"$j" >/dev/null 2>&1 && return 0
  # Variante native (ValidatingAdmissionPolicy, GA en 1.36) acceptée.
  j="$(kube get validatingadmissionpolicies.admissionregistration.k8s.io -o json 2>/dev/null)" || return 1
  jq -e 'any(.items[];
      any(.spec.matchConstraints.resourceRules[]?;
          ((.apiGroups // []) | index("postgresql.cnpg.io")) != null
          and ((.resources // []) | index("clusters")) != null))' <<<"$j" >/dev/null 2>&1
}
check_cmd "politique d'admission en refus sur les Cluster CloudNativePG (sauvegarde obligatoire)" _s07_politique

# --- 3. L'extraction pseudonymisée (métriques de la base Data, aucune donnée lue) --------------------
_s07_sel="namespace=\"$_s07_ns\""
if ! _f2b_prom_non_vide "cnpg_stats_extraction_lignes{$_s07_sel}"; then
  check_cmd "métrique cnpg_stats_extraction_lignes publiée par la base Data (requêtes personnalisées)" false
else
  check_cmd "extraction chargée : table non vide" \
    _f2b_prom_superieur "max(cnpg_stats_extraction_lignes{$_s07_sel})" 0
  check_cmd "extraction chargée depuis moins de 36 h" \
    _f2b_prom_inferieur "min(cnpg_stats_extraction_age_secondes{$_s07_sel})" "$_f2b_fraicheur"
fi
_s07_colonnes="$(prom_requete "max by (colonne) (cnpg_stats_extraction_colonnes_presente{$_s07_sel})" 2>/dev/null |
  jq -r '.data.result[]?.metric.colonne // empty' 2>/dev/null | sort -u)" || _s07_colonnes=""
if [[ -z "$_s07_colonnes" ]]; then
  check_cmd "métrique cnpg_stats_extraction_colonnes_presente publiée (liste des colonnes)" false
else
  check_cmd "colonnes : au moins un pseudonyme (nom en *pseudo*)" grep -q 'pseudo' <<<"$_s07_colonnes"
  _s07_interdites() {
    ! grep -Eiq '^(id|patient|praticien|nom|prenom|debut|cree_le|naissance|date_naissance)$|contact|motif|telephone|courriel|mail|adresse|nir|secu' \
      <<<"$(grep -v 'pseudo' <<<"$_s07_colonnes")"
  }
  check_cmd "colonnes : aucune colonne identifiante ni texte libre (patient, contact, motif, horodatage exact…)" _s07_interdites
fi

# --- 4. Aucune liaison entre Data et les bases de MédiAgenda ----------------------------------------
_s07_sortie_data() {
  local np cnp
  np="$(kube get networkpolicies -n "$_s07_ns" -o json 2>/dev/null)" || return 1
  cnp="$(kube get ciliumnetworkpolicies.cilium.io -n "$_s07_ns" -o json 2>/dev/null)" || cnp='{"items":[]}'
  jq -n --argjson a "$np" --argjson b "$cnp" -e \
    '[($a.items[], $b.items[]) | (.spec.egress // []) + ([.specs[]?.egress // []] | add // []) | tostring | select(test("mediagenda"))] | length == 0' >/dev/null
}
check_cmd "$_s07_ns : aucune règle réseau de sortie vers un espace mediagenda-*" _s07_sortie_data
_s07_entree_mediagenda() {
  local ns np cnp
  for ns in mediagenda-prod mediagenda-secours mediagenda-recette; do
    np="$(kube get networkpolicies -n "$ns" -o json 2>/dev/null)" || np='{"items":[]}'
    cnp="$(kube get ciliumnetworkpolicies.cilium.io -n "$ns" -o json 2>/dev/null)" || cnp='{"items":[]}'
    jq -n --argjson a "$np" --argjson b "$cnp" --arg d "$_s07_ns" -e \
      '[($a.items[], $b.items[]) | (.spec.ingress // []) + ([.specs[]?.ingress // []] | add // []) | tostring
        | select(test($d) or test("tenant[^}]*\"data\""))] | length == 0' >/dev/null || return 1
  done
}
check_cmd "mediagenda-prod, -secours, -recette : aucune règle réseau d'entrée depuis Data" _s07_entree_mediagenda
_s07_rbac() {
  kube get rolebindings -A -o json 2>/dev/null | jq -e --arg d "$_s07_ns" '
    [.items[] | select(.metadata.namespace | startswith("mediagenda-"))
     | select(any(.subjects[]?; (.name == "oidc:data") or (.kind == "ServiceAccount" and .namespace == $d)))] | length == 0' >/dev/null 2>&1
}
check_cmd "aucune liaison RBAC du groupe data ni d'un compte de $_s07_ns dans un espace mediagenda-*" _s07_rbac
_s07_eso() {
  local j
  j="$(kube get externalsecrets.external-secrets.io,secretstores.external-secrets.io -n "$_s07_ns" -o json 2>/dev/null)" || return 1
  jq -e '[.items[] | .spec | tostring | select(test("mediagenda"))] | length == 0' <<<"$j" >/dev/null 2>&1
}
check_cmd "$_s07_ns : aucun ExternalSecret ni SecretStore qui vise un secret de MédiAgenda" _s07_eso

_s07_rc=0
_s07_pols="$(_f2b_bao_politiques_groupe data)" || _s07_rc=$?
case "$_s07_rc" in
  2) skip "OpenBao : politiques du groupe data" "groupes d'identité illisibles par le compte des checks" ;;
  1) check_cmd "OpenBao : groupe d'identité « data » présent (S02)" false ;;
  *)
    _s07_bao() {
      local p t vu=0
      while IFS= read -r p; do
        [[ -n "$p" && "$p" != default ]] || continue
        t="$(_f2b_bao_texte_politique "$p")"
        grep -q 'mediagenda' <<<"$t" && return 1
        grep -q 'db-data/creds/' <<<"$t" && vu=1
      done <<<"$_s07_pols"
      ((vu == 1))
    }
    check_cmd "OpenBao : le groupe data obtient des identifiants dynamiques db-data, rien sous mediagenda" _s07_bao
    ;;
esac
