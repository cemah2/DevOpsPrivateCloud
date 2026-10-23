# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-S04.sh — F2-S04 : MédiVisio, du modèle au premier déploiement
# À lancer depuis adm01. Lecture seule : catalogue Backstage, GitLab, Harbor (robot en lecture), cluster
# (wb-checks), Argo CD (objets Application), GET sur l'adresse de dev, documentation sur main.

# shellcheck source=_f2-cadre.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f2-cadre.sh"

title "F2-S04 — MédiVisio : du modèle au premier déploiement"
require_cmd jq curl kubectl

# --- Catalogue et projets -----------------------------------------------------------------------------
_f2a_s04_comp="$(backstage_api "catalog/entities/by-name/component/default/$_F2A_COMPOSANT" 2>/dev/null || true)"
check_cmd "portail : Component $_F2A_COMPOSANT au catalogue, propriétaire medivisio" \
  _f2a_json "$_f2a_s04_comp" '(.spec.owner // "") | test("^(group:)?(default/)?medivisio$")'
check_cmd "portail : $_F2A_COMPOSANT documenté (annotation backstage.io/techdocs-ref)" \
  _f2a_json "$_f2a_s04_comp" '(.metadata.annotations["backstage.io/techdocs-ref"] // "") != ""'
check_cmd "GitLab : projet $_F2A_P_CODE (créé par le modèle : catalog-info.yaml présent)" \
  _f2a_contient "$(_f2a_fichier "$_F2A_P_CODE" catalog-info.yaml)" "kind: *Component" "$_F2A_COMPOSANT"
check_cmd "GitLab : projet $_F2A_P_DEPLOIEMENT" _f2a_projet_existe "$_F2A_P_DEPLOIEMENT"

# --- Déploiement en dev -------------------------------------------------------------------------------
_f2a_s04_d="$(_f2a_deploy medivisio-dev)"
check_cmd "medivisio-dev : Deployment $_F2A_DEPLOIEMENT exécute l'image $_F2A_IMAGE" \
  _f2a_json "$_f2a_s04_d" "any(.spec.template.spec.containers[]; .image | contains(\"/$_F2A_IMAGE\"))"
check_cmd "medivisio-dev : image désignée par son empreinte (@sha256:…), jamais par une étiquette" \
  _f2a_image_par_empreinte "$_f2a_s04_d"
check_cmd "medivisio-dev : tous les réplicas à jour et prêts" _f2a_deploy_pret "$_f2a_s04_d" 1
check_cmd "Argo CD : l'Application qui livre medivisio-dev depuis $_F2A_P_DEPLOIEMENT est Synced et Healthy" \
  _f2a_app_saine medivisio-dev "/${_F2A_P_DEPLOIEMENT}(\\.git)?$"

# --- Signature de l'image déployée (Harbor) -----------------------------------------------------------
_f2a_s04_dig="$(_f2a_empreinte "$_f2a_s04_d")"
if [[ -n "$_f2a_s04_dig" ]]; then
  _f2a_s04_proj="${_F2A_IMAGE%%/*}"
  _f2a_s04_depot="${_F2A_IMAGE#*/}"
  _f2a_s04_art="$(harbor_api "projects/$_f2a_s04_proj/repositories/$(_f2a_enc "$(_f2a_enc "$_f2a_s04_depot")")/artifacts/$_f2a_s04_dig?with_accessory=true" 2>/dev/null || true)"
  check_cmd "Harbor : l'image déployée ($_f2a_s04_dig) porte une signature Cosign" \
    _f2a_json "$_f2a_s04_art" 'any(.accessories[]?; .type == "signature.cosign")'
else
  check_cmd "Harbor : empreinte de l'image déployée lisible" false
fi

# --- L'adresse répond ----------------------------------------------------------------------------------
check_cmd "$_F2A_URL_DEV/sante répond 200 depuis adm01" _f2a_url_200 "$_F2A_URL_DEV/sante"

# --- Mesure et décision ---------------------------------------------------------------------------------
check_cmd "docs : mesure du délai jusqu'au premier déploiement (mesures/, avec un délai et les interventions)" \
  _f2a_doc 'medivisio.*(premier|deploiement)|premier-deploiement' "délai|delai" "intervention|plateforme"
check_cmd "docs : ADR-0321 publié" _f2a_doc '^ADR-0321' "décision|decision"
