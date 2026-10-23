# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-S06.sh — F2-S06 : panne, les premiers pas qui coincent
# À lancer depuis adm01. Lecture seule : cluster (wb-checks : Application, Deployment, ReplicaSets,
# ExternalSecret sans le Secret), GitLab (overlay de recette et documentation sur main).
# Vert quand la recette de MédiVisio est revenue PAR GIT, quelle que soit la variante injectée.

# shellcheck source=_f2-cadre.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f2-cadre.sh"

title "F2-S06 — Panne : les premiers pas qui coincent"
require_cmd jq curl kubectl

# _f2a_s06_rs_sains — aucun ReplicaSet de la recette du service ne signale d'échec de création.
_f2a_s06_rs_sains() {
  local rs
  rs="$(_f2a_k -n medivisio-recette get replicasets)"
  [[ -n "$rs" ]] && jq -e '(.items | length) > 0 and all(.items[] | select((.spec.replicas // 0) > 0); all(.status.conditions[]?; .type != "ReplicaFailure"))' >/dev/null 2>&1 <<<"$rs"
}
# _f2a_s06_es_sains — tous les ExternalSecret de la recette sont synchronisés, et ne lisent que kv/medivisio/recette/.
_f2a_s06_es_sains() {
  local es
  es="$(_f2a_k -n medivisio-recette get externalsecrets.external-secrets.io)"
  [[ -n "$es" ]] && jq -e '(.items | length) > 0
    and all(.items[]; any(.status.conditions[]?; .type == "Ready" and .status == "True"))
    and all(.items[] | (.spec.data[]?.remoteRef.key), (.spec.dataFrom[]?.extract.key); test("^(kv/)?(data/)?medivisio/recette/"))' >/dev/null 2>&1 <<<"$es"
}
# _f2a_s06_overlay_empreinte — l'overlay de recette (main) désigne l'image du service par empreinte.
_f2a_s06_overlay_empreinte() {
  local app chemin k
  app="$(_f2a_apps_vers medivisio-recette | jq -r --arg r "/${_F2A_P_DEPLOIEMENT}(\\.git)?$" \
    '[.[] | select((.spec.source.repoURL // "") | test($r))][0].spec.source.path // empty' 2>/dev/null || true)"
  chemin="${app:-overlays/recette}"
  k="$(_f2a_fichier "$_F2A_P_DEPLOIEMENT" "$chemin/kustomization.yaml")"
  [[ -n "$k" ]] && grep -Eq 'digest: *sha256:[0-9a-f]{64}' <<<"$k" && ! grep -Eq '^\s*newTag:' <<<"$k"
}

_f2a_s06_d="$(_f2a_deploy medivisio-recette)"
check_cmd "Argo CD : l'Application de recette (depuis $_F2A_P_DEPLOIEMENT) est Synced et Healthy" \
  _f2a_app_saine medivisio-recette "/${_F2A_P_DEPLOIEMENT}(\\.git)?$"
check_cmd "medivisio-recette : tous les réplicas du Deployment $_F2A_DEPLOIEMENT à jour et prêts" _f2a_deploy_pret "$_f2a_s06_d" 1
check_cmd "medivisio-recette : aucun ReplicaSet en échec de création (quota, admission)" _f2a_s06_rs_sains
check_cmd "medivisio-recette : ExternalSecret(s) synchronisés, chemins kv/medivisio/recette/ seulement" _f2a_s06_es_sains
check_cmd "medivisio-recette : image désignée par empreinte dans le Deployment ET dans l'overlay (Git)" \
  bash -c '[[ "$1" == 0 && "$2" == 0 ]]' _ "$(_f2a_image_par_empreinte "$_f2a_s06_d"; echo $?)" "$(_f2a_s06_overlay_empreinte; echo $?)"
check_cmd "$_F2A_URL_RECETTE/sante répond 200 depuis adm01" _f2a_url_200 "$_F2A_URL_RECETTE/sante"
check_cmd "docs : journal de diagnostic F2-S06 (journal/…F2-S06…)" _f2a_doc 'F2-S06' "cause" "correct|correction"
check_cmd "docs : RB-321 publié (premier déploiement bloqué)" _f2a_doc '^RB-321' "quota|kyverno|signature|externalsecret|secret"
