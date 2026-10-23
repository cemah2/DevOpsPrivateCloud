# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes bash -c entre apostrophes
#
# check-E46.sh — M25-E46 « Mini-projet : les secrets de MédiSphère v1 » : contrôle global de la livraison
# secrets-v1 depuis adm01. Rien de provisoire ; coffre complet ; configuration en code ; identités ;
# secrets dans Kubernetes (aucun ExternalSecret en erreur, secrets-k8s.sh retiré) ; CI sans secret
# durable ; secrets courts (identifiants dynamiques en prod, PKI) ; sauvegarde et supervision ;
# documentation et étiquette. Lecture seule. Quelques minutes.

# shellcheck source=_m25-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m25-expert.sh"
# shellcheck source=_m25-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m25-operationnel.sh"

title "M25-E46 — Les secrets de MédiSphère v1 : contrôle global"
require_cmd curl jq kubectl openssl
_m25p_connexion

# --- 1. Rien de provisoire ------------------------------------------------------------------------------
title "M25-E46 — 1/7 Rien de provisoire"
_m25x_e46_ns_absent() { ! kube get namespace "$1" >/dev/null 2>&1; }
_m25x_e46_rb_present() { [[ -n "$(_m25p_doc_chemin "$_M25P_DOC" "$_M25P_RB" "RB-$1-[^/]*\\.md$")" ]]; }
check_cmd "aucune panne M25 encore marquée active" _m25x_aucune_panne
check_cmd "bao-essai (2251) détruite" _m25p_vm_absente 2251
check_cmd "bao-restauration (2252) détruite" _m25p_vm_absente 2252
check_cmd "aucun jeton racine vivant sur la grappe" _m25x_aucune_racine
_m25x_e46_absent_git() { ! gitlab_api "projects/$(_m25o_uri "$1")/repository/files/$(_m25o_uri "$2")?ref=main" >/dev/null 2>&1; }
check_cmd "plateforme/secrets : tofu/essais-m25.tf retiré" _m25x_e46_absent_git "$_M25P_SECRETS" tofu/essais-m25.tf
for _m25x_e46_ns in sealed-secrets essai-csi; do
  check_cmd "espace d'essai $_m25x_e46_ns retiré" _m25x_e46_ns_absent "$_m25x_e46_ns"
done

# --- 2. Le coffre ------------------------------------------------------------------------------------------
title "M25-E46 — 2/7 Le coffre"
_m25x_e46_descelles() {
  local n
  for n in "${_M25P_NOEUDS[@]}"; do
    _m25p_jq "$(_m25p_scellement "$n")" '.type == "transit" and .sealed == false' || return 1
  done
}
check_cmd "trois nœuds descellés par le seal transit" _m25x_e46_descelles
check_output "un seul nœud actif" '^1$' bash -c 'grep -c . <<<"$1"' _ "$(_m25p_actifs)"
check_cmd "autopilot sain, tolérance aux pannes ≥ 1" \
  _m25p_jq "$(_m25p_bao sys/storage/raft/autopilot/state)" '.data.healthy == true and .data.failure_tolerance >= 1'
check_cmd "$_M25P_KMS descellé" _m25p_jq "$(_m25p_scellement "$_M25P_KMS")" '.sealed == false'
check_cmd "version 2.7.1 sur la grappe (sys/health)" _m25p_jq "$(_m25p_sante "${_M25P_NOEUDS[0]}")" '.version | startswith("2.7.1")'
check_output "essai quotidien de l'auto-descellement : vert sur les ${#_M25P_NOEUDS[@]} nœuds" "^${#_M25P_NOEUDS[@]}$" \
  _m25p_valeur 'count(medisphere_openbao_kms_essai_ok == 1)'
check_output "jeton du seal renouvelé : plus de 3 jours de vie sur les ${#_M25P_NOEUDS[@]} nœuds" "^${#_M25P_NOEUDS[@]}$" \
  _m25p_valeur 'count(medisphere_openbao_kms_jeton_ttl_secondes > 259200)'
check_cmd "audit d'OpenBao présent dans Loki (locataire audit, 24 h)" \
  bash -c '[[ "${1:-0}" =~ ^[0-9]+$ && "$1" -ge 1 ]]' _ "$(_m25p_loki_nb '{service="openbao"}' 24h)"

# --- 3. Configuration en code et identités -----------------------------------------------------------------
title "M25-E46 — 3/7 Configuration en code et identités"
check_cmd "plateforme/secrets : dernier pipeline de main réussi" _m25o_pipeline_vert "$_M25P_SECRETS"
check_cmd "plateforme/secrets : test des politiques en CI" _m25o_contient "$_M25P_SECRETS" .gitlab-ci.yml 'tester-politiques'
check_cmd "méthodes d'authentification oidc/, gitlab/, k8s-par1/, approle/ actives" \
  _m25p_jq "$(_m25p_bao sys/auth)" '(.data // .) as $a | all(["oidc/", "gitlab/", "k8s-par1/", "approle/"][]; $a[.] != null)'
_m25x_e46_ci_protege() {
  local roles r
  roles="$(_m25p_bao 'auth/gitlab/role?list=true' | jq -r '.data.keys[]? // empty' 2>/dev/null | grep '^ci-' || true)"
  [[ -n "$roles" ]] || return 1
  while IFS= read -r r; do
    _m25p_jq "$(_m25p_bao "auth/gitlab/role/$r")" \
      '.data.bound_claims.ref_protected == "true" or .data.bound_claims.ref_protected == ["true"]' || return 1
  done <<<"$roles"
}
check_cmd "rôles JWT ci-* : tous exigent une référence protégée" _m25x_e46_ci_protege
_m25x_e46_vars_ok() {
  local cible vars rc=0 interdites='(PASSWORD|PASSWD|MOT_DE_PASSE|SECRET|TOKEN|PRIVATE_KEY|ACCESS_KEY)'
  for cible in "groups:mediagenda" "groups:medidoc" "projects:mediagenda/api" "projects:medidoc/medidoc"; do
    vars="$(_m25o_variables "${cible%%:*}" "${cible#*:}")" || rc=$?
    ((rc == 2)) && return 2
    grep -Eiv '^(CI_|OPENBAO_|BAO_ADDR$|BAO_ROLE$)' <<<"$vars" | grep -Eqi "$interdites" && return 1
  done
  return 0
}
_m25x_e46_rc=0
_m25x_e46_vars_ok >/dev/null 2>&1 || _m25x_e46_rc=$?
if ((_m25x_e46_rc == 2)); then
  skip "variables de CI des équipes sans secret durable" "le jeton des checks n'a pas le droit de les lister"
else
  check_cmd "variables de CI de mediagenda et medidoc : aucun nom de mot de passe, jeton ou clé" test "$_m25x_e46_rc" -eq 0
fi

# --- 4. Secrets dans Kubernetes ------------------------------------------------------------------------------
title "M25-E46 — 4/7 Secrets dans Kubernetes"
check_cmd "ClusterSecretStore openbao prêt" _m25o_objet_pret clustersecretstores.external-secrets.io openbao
check_cmd "aucun ExternalSecret en erreur dans le cluster" \
  _m25o_json "$(_m25o_k get externalsecrets.external-secrets.io -A -o json)" '
  (.items | length) > 0 and ([.items[] | select(([.status.conditions[]? | select(.type == "Ready" and .status == "True")] | length) == 0)] | length) == 0'
check_cmd "plateforme/k8s : outils/secrets-k8s.sh retiré" _m25x_e46_absent_git plateforme/k8s outils/secrets-k8s.sh
for _m25x_e46_ns in velero ceph-csi; do
  check_cmd "couche de base : au moins un ExternalSecret dans $_m25x_e46_ns" \
    _m25o_json "$(_m25o_k get externalsecrets.external-secrets.io -n "$_m25x_e46_ns" -o json)" '(.items | length) > 0'
done

# --- 5. Secrets courts -----------------------------------------------------------------------------------------
title "M25-E46 — 5/7 Secrets courts"
check_cmd "prod : générateur VaultDynamicSecret mediagenda-api (chemin creds de prod)" \
  _m25o_json "$(_m25o_k get vaultdynamicsecrets.generators.external-secrets.io -n mediagenda-prod -o json)" '
  any(.items[]; .metadata.name == "mediagenda-api" and (.spec.path | test("db-mediagenda/creds/mediagenda-api-prod$")))'
check_cmd "prod : au moins un bail mediagenda-api-prod actif" \
  bash -c '[[ "${1:-0}" =~ ^[0-9]+$ && "$1" -ge 1 ]]' _ "$(_m25o_baux db-mediagenda/creds/mediagenda-api-prod)"
check_cmd "PKI : medidoc-mtls prêt" _m25x_certificat_pret medidoc-recette medidoc-mtls
check_cmd "PKI : mediagenda-mtls prêt" _m25x_certificat_pret mediagenda-recette mediagenda-mtls
check_cmd "PKI : CRL publiée valable encore au moins 6 h" _m25x_crl_marge 21600
check_cmd "signature : clé transit cosign-medisphere non exportable" \
  _m25p_jq "$(_m25p_bao transit/keys/cosign-medisphere)" '.data.exportable == false'
check_cmd "clé publique Cosign publiée (docs/registre/cosign.pub)" _m25p_fichier "$_M25P_DOC" docs/registre/cosign.pub

# --- 6. Sauvegarde et supervision --------------------------------------------------------------------------------
title "M25-E46 — 6/7 Sauvegarde et supervision"
for _m25x_e46_r in 'vault_core_unsealed' 'vault_core_active' 'vault_audit_log_request_failure' 'medisphere_openbao_kms_essai_' 'certmanager_certificate_ready_status'; do
  check_cmd "alerte chargée sur $_m25x_e46_r" _m25x_regle_presente "$_m25x_e46_r"
done
_m25x_e46_instantane() {
  local a t
  a="$(_m25p_actifs | head -n 1)"
  [[ -n "$a" ]] || return 1
  t="$(_m25p_ssh_sortie "$a" 'stat -c %Y /var/lib/openbao-instantane/dernier-succes')"
  [[ "$t" =~ ^[0-9]+$ ]] && (($(date +%s) - t < 7200))
}
check_cmd "instantané Raft de moins de 2 h (trace du dernier succès sur le nœud actif)" _m25x_e46_instantane

# --- 7. Documentation et livraison -------------------------------------------------------------------------------
title "M25-E46 — 7/7 Documentation et livraison"
_m25x_e46_inv="$(_m25p_fichier "$_M25P_DOC" docs/securite/secrets/inventaire-secrets.md || true)"
check_output "inventaire-secrets.md : colonne d'état de la migration" '\| *[ÉE]tat *\|' printf '%s\n' "$_m25x_e46_inv"
check_cmd "inventaire-secrets.md : aucune valeur de secret" _m25x_sans_secret "$_m25x_e46_inv"
for _m25x_e46_rb in 250 251 252 253 254 255; do
  check_cmd "runbook RB-$_m25x_e46_rb sur main" _m25x_e46_rb_present "$_m25x_e46_rb"
done
for _m25x_e46_d in adr/ADR-0250-coffre.md adr/ADR-0251-chiffrement-etcd.md politique-rotation.md analyses/sous-le-capot-openbao.md; do
  check_cmd "docs/securite/secrets/$_m25x_e46_d sur main" _m25p_fichier "$_M25P_DOC" "docs/securite/secrets/$_m25x_e46_d"
done
check_cmd "secrets-v1.md : limites assumées et ce que consomme le M26" \
  _m25p_doc "$_M25P_DOC" docs/securite/secrets 'secrets-v1\.md$' 30 '(limites|non couvert|ne couvre pas)' 'M26' 'cosign'
_m25x_e46_etiquette() { gitlab_api "projects/$(_m25o_uri "$_M25P_DOC")/repository/tags/secrets-v1" >/dev/null 2>&1; }
check_cmd "étiquette secrets-v1 posée sur plateforme/medisphere" _m25x_e46_etiquette
