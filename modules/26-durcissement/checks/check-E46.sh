# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et motifs bash -c entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E46.sh — M26-E46 « Mini-projet : MédiSphère durcie v1 » : contrôle global de la livraison
# durcissement-v1 depuis adm01. Couverture, admission, détection, chiffrement, conformité, documentation,
# étiquette. Lecture seule. Quelques minutes.
# shellcheck source=_m26-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m26-expert.sh"

title "M26-E46 — MédiSphère durcie v1 : contrôle global"
require_cmd jq yq kubectl curl git

# --- 1. Rien de provisoire -----------------------------------------------------------------------------
title "M26-E46 — 1/6 Rien de provisoire"
_e46_vm_env_detruites() {
  remote "${WB_PVE_HOST:-pve01}" 'pvesh get /cluster/resources --type vm --output-format json' 2>/dev/null |
    jq -e '[.[] | select(.vmid == 2261 or .vmid == 2262)] | length == 0' >/dev/null 2>&1
}
check_cmd "aucune panne M26 encore marquée active" _m26x_aucune_panne_active
check_cmd "le témoin d'incident (wb-mineur) n'est plus là" _m26x_absent deployment wb-mineur "$_m26x_ns_pannes"
check_cmd "les VMs d'essai durci-deb (2261) et durci-rocky (2262) sont détruites" _e46_vm_env_detruites

# --- 2. Conformité mesurée -----------------------------------------------------------------------------
title "M26-E46 — 2/6 Conformité mesurée"
_e46_conformite_exposee() { local v; v="$(_m26x_conformite_val 'count(medisphere_conformite_score)')"; [[ -n "$v" ]] && [[ "${v%.*}" -ge 1 ]]; }
_e46_score_cible() {
  local v; v="$(_m26x_conformite_val 'min(medisphere_conformite_score{referentiel=~".*cis.*l1.*|.*cis_l1.*"})')"
  [[ -n "$v" ]] && awk -v x="$v" 'BEGIN{exit !((x>=85 && x<=100) || (x>=0.85 && x<=1))}'
}
_e46_analyse_fraiche() {
  local t; t="$(_m26x_conformite_val 'time() - max(medisphere_conformite_derniere_analyse_secondes)')"
  [[ -z "$t" ]] || awk -v x="$t" 'BEGIN{exit !(x < 691200)}'
}
check_cmd "métrique de conformité exposée (medisphere_conformite_score)" _e46_conformite_exposee
check_cmd "score CIS niveau 1 ≥ 85 % hors exceptions" _e46_score_cible
check_cmd "registre des exceptions présent et commité (exceptions.md)" _m26x_doc_commite "docs/securite/durcissement/exceptions.md"
check_cmd "analyse de conformité récente (< 8 jours)" _e46_analyse_fraiche

# --- 3. Admission --------------------------------------------------------------------------------------
title "M26-E46 — 3/6 Admission"
_e46_ns_restricted() { [[ "$(_m26x_psa_enforce "$1")" == restricted ]]; }
_e46_signature_deny() {
  _m26x_kq '[.items[]? | select(.metadata.name | test("signature")) | select((.spec.validationActions // []) | index("Deny"))] | length > 0' \
    imagevalidatingpolicies.policies.kyverno.io
}
_e46_registres_deny() {
  _m26x_kq '[.items[]? | select(.metadata.name | test("registre")) | select((.spec.validationActions // []) | index("Deny"))] | length > 0' \
    validatingpolicies.policies.kyverno.io && _m26x_vp_sans_exemption_groupe
}
_e46_pas_privileged() {
  local n
  for n in mediagenda-dev mediagenda-recette mediagenda-prod medidoc-dev medidoc-recette; do
    [[ "$(_m26x_psa_enforce "$n")" == privileged ]] && return 1
  done
  return 0
}
for ns in mediagenda-recette mediagenda-prod medidoc-recette; do
  check_cmd "espace $ns en PSA restricted" _e46_ns_restricted "$ns"
done
check_cmd "Kyverno : exiger-signature-medisphere en refus sur recette/prod" _e46_signature_deny
check_cmd "Kyverno : registres-autorises en refus, sans exemption des administrateurs" _e46_registres_deny
check_cmd "aucun espace applicatif en privileged" _e46_pas_privileged
check_cmd "Application Argo CD « politiques » Synced/Healthy" _m26x_app_ok politiques
check_cmd "Application Argo CD « kyverno » Synced/Healthy" _m26x_app_ok kyverno
check_cmd "pipeline de main de plateforme/politiques vert" _m26x_pipeline_main_vert plateforme/politiques

# --- 4. Détection --------------------------------------------------------------------------------------
title "M26-E46 — 4/6 Détection à l'exécution"
_e46_falco_couvre() {
  _m26x_kq '.status.desiredNumberScheduled == (.status.numberReady // 0) and .status.desiredNumberScheduled > 1' -n "$_m26x_ns_falco" daemonset falco
}
_e46_loki_audit() { loki_requete '{service=~"falco|tetragon|auditd"}' audit 6h 2>/dev/null | jq -e '.status == "success"' >/dev/null 2>&1; }
check_cmd "Falco couvre tous les nœuds" _e46_falco_couvre
check_cmd "Application Argo CD « falco » Synced/Healthy" _m26x_app_ok falco
check_cmd "Application Argo CD « tetragon » Synced/Healthy" _m26x_app_ok tetragon
check_cmd "journaux de sécurité dans Loki (locataire audit)" _e46_loki_audit

# --- 5. Chiffrement et kubelets ------------------------------------------------------------------------
title "M26-E46 — 5/6 Chiffrement et kubelets"
_e46_wireguard() { kube -n kube-system get configmap cilium-config -o jsonpath='{.data.enable-wireguard}' 2>/dev/null | grep -q true; }
_e46_csr_ok() {
  _m26x_kq '[.items[]? | select(.spec.signerName == "kubernetes.io/kubelet-serving") | select((.status.conditions // []) | (any(.type == "Approved") | not))] | length == 0' \
    certificatesigningrequests.certificates.k8s.io
}
_e46_noeuds_ready() {
  _m26x_kq '[.items[] | select((.status.conditions[] | select(.type == "Ready") | .status) != "True")] | length == 0' nodes
}
check_cmd "chiffrement WireGuard activé (cilium-config enable-wireguard)" _e46_wireguard
check_cmd "aucune CSR de service de kubelet en attente" _e46_csr_ok
check_cmd "tous les nœuds Ready" _e46_noeuds_ready

# --- 6. Documentation et livraison ---------------------------------------------------------------------
title "M26-E46 — 6/6 Documentation et livraison"
_e46_etiquette() { gitlab_api 'projects/plateforme%2Fmedisphere/repository/tags/durcissement-v1' >/dev/null 2>&1; }
_e46_depot_propre() { (cd "$_m26x_depot" 2>/dev/null && [[ -z "$(git status --porcelain -- docs/securite/durcissement)" ]]); }
check_cmd "ADR-0260 présente et commitée" _m26x_doc_existe '^docs/securite/durcissement/adr/ADR-0260[^/]*\.md$'
check_cmd "modèle de menace (modele-menace.md)" _m26x_doc_existe '^docs/securite/durcissement/modele-menace\.md$'
check_cmd "référentiels retenus (referentiels.md)" _m26x_doc_existe '^docs/securite/durcissement/referentiels\.md$'
for rb in 260 261 262 263 264 265; do
  check_cmd "runbook RB-$rb présent" _m26x_doc_existe "^docs/securite/durcissement/runbooks/RB-$rb-[^/]*\\.md$"
done
check_cmd "fiche de livraison durcissement-v1.md (couvert / non couvert)" \
  _m26x_doc_contient 'docs/securite/durcissement/durcissement-v1.md' '^#+ .*(non couvert|limites|ne couvre pas)'
check_cmd "étiquette durcissement-v1 posée sur plateforme/medisphere" _e46_etiquette
check_cmd "dépôt de documentation local sans modification en attente" _e46_depot_propre
