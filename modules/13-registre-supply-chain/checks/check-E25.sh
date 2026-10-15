# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant
# check-E25.sh — M13-E25 « Mini-projet : registre MédiSphère v1 » (contrôle global, 1 à 2 minutes).
# Lecture seule : API Harbor (robot wb-checks), cosign verify-attestation depuis adm01, API GitLab,
# lectures SSH sur reg01, runner02, pve01 et pbs01, DNS.

# shellcheck source=_m13-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m13-expert.sh"

title "M13-E25 — Registre MédiSphère v1"
require_cmd jq curl openssl cosign dig

title "Harbor"
check_cmd "/api/v2.0/health : tous les composants « healthy »" _m13p_sante
check_cmd "version $_M13P_VERSION (WB_M13_HARBOR_VERSION)" _m13p_version_ok
check_cmd "certificat de $_M13P_REGISTRE_NOM : PKI MédiSphère, plus de 10 jours" _m13p_cert "$_M13P_REGISTRE_NOM" 443 10
_m13_e25_projets="$(_m13p_api "projects?page_size=100")" || _m13_e25_projets=""
for _p in medisphere plateforme bibliotheque charts; do
  check_cmd "projet $_p" _m13p_jq "$_m13_e25_projets" "any(.[]; .name == \"$_p\")"
done
for _p in dockerhub quay ghcr k8s; do
  check_cmd "cache $_p (projet relié à un endpoint amont)" _m13p_jq "$_m13_e25_projets" \
    "any(.[]; .name == \"$_p\" and ((.registry_id // 0) > 0))"
done
check_cmd "le cache dockerhub est utilisé (au moins un dépôt)" _m13p_jq "$_m13_e25_projets" \
  'any(.[]; .name == "dockerhub" and ((.repo_count // 0) > 0))'
check_cmd "ramasse-miettes planifié" bash -c 'jq -e "(.schedule.type // \"None\") != \"None\"" >/dev/null 2>&1 <<<"$1"' _ \
  "$(_m13p_api system/gc/schedule || true)"

title "Politiques de medisphere"
check_cmd "privé" _m13p_projet_meta medisphere public false
check_cmd "signature Cosign exigée" _m13p_projet_meta medisphere enable_content_trust_cosign true
check_cmd "images Critical refusées" _m13p_projet_meta medisphere severity critical
check_cmd "prévention active" _m13p_projet_meta medisphere prevent_vul true
check_cmd "analyse à la poussée" _m13p_projet_meta medisphere auto_scan true
check_cmd "règle de rétention attachée" bash -c 'jq -e "(.retention_id // \"\") | length > 0" >/dev/null 2>&1 <<<"$1"' _ "$(_m13p_meta medisphere || true)"
check_cmd "immuabilité des versions v*" bash -c \
  'jq -e "any(.[]?; (.disabled | not) and any(.tag_selectors[]?; .pattern | startswith(\"v\")))" >/dev/null 2>&1 <<<"$1"' _ \
  "$(_m13p_api projects/medisphere/immutabletagrules || true)"
check_cmd "aucun dépôt d'essai (essai-*)" _m13p_repos_motif_absents medisphere '(^|/)essai-'

title "Les quatre images"
declare -A _m13_e25_projet_git=([mediagenda-api]=mediagenda/api [medidoc]=medidoc/medidoc [medinotif]=medinotif/worker [legacy-rdv]=legacy/legacy-rdv)
# _m13_e25_bases PROJET_GIT — chaque FROM d'image externe du Dockerfile (ou Containerfile) vient de
# Harbor (bibliotheque ou un cache) et est épinglé par digest ; les étapes internes et scratch sont admises.
_m13_e25_bases() {
  local c f etapes
  for f in Dockerfile Containerfile; do
    c="$(_m13p_fichier_main "$1" "$f" 2>/dev/null)" && [[ -n "$c" ]] && break
  done
  [[ -n "$c" ]] || return 1
  etapes="$(sed -nE 's/^[[:space:]]*FROM[[:space:]]+.*[[:space:]]+[Aa][Ss][[:space:]]+([^[:space:]]+).*/\1/p' <<<"$c")"
  sed -nE 's/^[[:space:]]*FROM[[:space:]]+(--platform=[^[:space:]]+[[:space:]]+)?([^[:space:]]+).*/\2/p' <<<"$c" \
    | while read -r img; do
        [[ "$img" == scratch ]] && continue
        grep -qxF "$img" <<<"$etapes" && continue
        [[ "$img" =~ ^registry\.par1\.medisphere\.internal/(bibliotheque|dockerhub|quay|ghcr|k8s)/[^[:space:]]+@sha256:[0-9a-f]{64}$ ]] || exit 1
      done
}
for _a in "${_M13P_APPS[@]}"; do
  _m13_e25_art="$(_m13p_derniere_version medisphere "$_a")" || _m13_e25_art=""
  check_cmd "medisphere/$_a : une version v*" _m13p_jq "$_m13_e25_art" '.digest | startswith("sha256:")'
  check_cmd "… signée" _m13p_signee "$_m13_e25_art"
  check_cmd "… analysée, sans vulnérabilité critique" _m13p_sans_critique "$_m13_e25_art"
  _m13_e25_d="$(jq -r '.digest // empty' <<<"$_m13_e25_art" 2>/dev/null || true)"
  check_cmd "… SBOM SPDX attesté et vérifié par la clé MédiSphère" \
    _m13p_attestation_sbom "$_M13P_REGISTRE_NOM/medisphere/$_a@${_m13_e25_d:-sha256:absent}"
  check_cmd "… images de base tirées de Harbor et épinglées par digest (${_m13_e25_projet_git[$_a]})" \
    _m13_e25_bases "${_m13_e25_projet_git[$_a]}"
  check_cmd "… dernier pipeline de main réussi, avec le job verifier-signature" \
    _m13p_job_reussi "${_m13_e25_projet_git[$_a]}" verifier-signature
done

title "Renovate"
_m13_e25_mr_renovate() {
  gitlab_api "projects/${1//\//%2F}/merge_requests?author_username=renovate-bot&state=all&per_page=1" 2>/dev/null \
    | jq -e 'length > 0' >/dev/null
}
_m13_e25_renovate() {
  gitlab_api "projects/plateforme%2Frenovate/pipelines?source=schedule&per_page=1" 2>/dev/null \
    | jq -e '.[0].status == "success" and ((now - (.[0].updated_at | sub("\\.[0-9]+"; "") | sub("Z$"; "Z") | fromdateiso8601)) < 172800)' >/dev/null
}
check_cmd "plateforme/renovate : dernier pipeline planifié réussi, il y a moins de 48 h" _m13_e25_renovate
for _a in "${_M13P_APPS[@]}"; do
  _g="${_m13_e25_projet_git[$_a]}"
  check_cmd "Renovate a ouvert au moins une MR sur $_g" _m13_e25_mr_renovate "$_g"
done

title "Exploitation"
check_cmd "sauvegarde de reg01 réussie il y a moins de 26 h" _m13p_unite_recente reg01 wb-backup-harbor.service 26
check_cmd "pbs01 : archive des blobs de moins de 48 h (par1/registre)" _m13p_pbs_recent 'registre*.didx' 48
check_cmd "ms-verif-registre.timer actif sur adm01" systemctl is-active -q ms-verif-registre.timer
check_cmd "ms-verif-registre rend 0" timeout 120 /usr/local/bin/ms-verif-registre --quiet
check_cmd "test de restauration consigné (docs/registre/tests/restauration-harbor.md, RTO)" \
  _m13p_doc_main docs/registre/tests/restauration-harbor.md 'RTO'

title "Rien de provisoire"
check_cmd "la VM 2131 (reg02) n'existe plus" _m13p_vm_absente 2131
check_cmd "le nom reg02.par1.medisphere.internal ne résout plus" bash -c '[[ -z "$(dig +short reg02.par1.medisphere.internal A)" ]]'
_m13_e25_pas_endpoint_reg02() {
  local l
  l="$(_m13p_api 'registries?page_size=50')" || return 1
  jq -e 'type == "array" and ([.[] | select(.url | test("reg02"))] | length == 0)' >/dev/null 2>&1 <<<"$l"
}
check_cmd "aucun endpoint de réplication vers reg02 sur reg01" _m13_e25_pas_endpoint_reg02
_m13_e25_sans_reg02() {
  local c
  c="$(_m13p_fichier_main plateforme/ansible inventories/lab/group_vars/role_routeur/pare_feu.yml 2>/dev/null)" || return 1
  [[ -n "$c" ]] && ! grep -q '10\.10\.99\.31' <<<"$c"
}
check_cmd "matrice des flux : plus de règle vers reg02 (10.10.99.31)" _m13_e25_sans_reg02
check_cmd "matrice des flux : VLAN 40 → reg01 443 déclaré pour le module 14" \
  _m13p_fichier_motifs plateforme/ansible inventories/lab/group_vars/role_routeur/pare_feu.yml '10\.10\.40\.0/24' '10\.10\.20\.18'
check_cmd "projets des témoins (wb-sonde*) supprimés" _m13p_jq "$_m13_e25_projets" '[.[] | select(.name | startswith("wb-sonde"))] | length == 0'
check_ssh "runner02 : fichiers des témoins supprimés" "$_m13x_runner" \
  '! sudo -n test -e /etc/workbook/sonde-registre && ! sudo -n test -e /usr/local/sbin/wb-sonde-registre'
check_cmd "identité des pannes retirée d'adm01 (~/.config/workbook/harbor-pannes.env)" \
  test ! -e "${WB_HARBOR_PANNES_FILE:-$HOME/.config/workbook/harbor-pannes.env}"
check_cmd "aucune panne M13 active" _m13p_aucune_panne_active

title "Documentation et livraison"
for _f in architecture.md politiques.md replication.md sauvegarde.md caches.md alertes/CS-2026-0412.md; do
  check_cmd "docs/registre/$_f" _m13p_doc_main "docs/registre/$_f" '.'
done
check_cmd "caches.md prépare containerd (hosts.toml)" _m13p_doc_main docs/registre/caches.md 'hosts\.toml'
check_cmd "ADR-0130 publié" _m13p_doc_prefixe docs/registre/adr ADR-0130
for _r in RB-130 RB-131 RB-132 RB-133 RB-134 RB-135; do
  check_cmd "runbook $_r" _m13p_doc_prefixe docs/registre/runbooks "$_r"
done
check_cmd "clé publique Cosign publiée (docs/registre/cosign.pub)" _m13p_doc_main docs/registre/cosign.pub 'PUBLIC KEY'
for _g in plateforme/ansible plateforme/infra plateforme/outils plateforme/ci-templates plateforme/medisphere; do
  check_cmd "dernier pipeline de main réussi : $_g" _m13p_pipeline_ok "$_g"
done
check_cmd "étiquette registre-v1 sur plateforme/medisphere" gitlab_api "projects/plateforme%2Fmedisphere/repository/tags/registre-v1"
