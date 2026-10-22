# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E28.sh — M20-E28 « Sauvegarder et reconstruire Argo CD » (PLAT-2128)
# À lancer depuis adm01. Lecture seule : CronJob et Jobs de sauvegarde, StatefulSet du contrôleur,
# Deployments et pods applicatifs (dates de création), Applications (wb-checks) ; compartiment
# argocd-sauvegardes (identité argocd-sauvegardes : liste et 16 premiers octets d'un objet) ; API
# d'Argo CD avec le jeton ci-lecture ; GitLab (code et documentation sur main).

# shellcheck source=_m20-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m20-production.sh"

title "M20-E28 — Sauvegarder et reconstruire Argo CD"
require_cmd kubectl jq curl aws od
_m20p_init_tmp
check_cmd "l'API du cluster répond (readyz)" _m20p_joignable
_m20_e28_maintenant="$(date +%s)"

title "Sauvegarde automatique"
_m20_e28_cj="$(_m20p_json -n argocd get cronjob argocd-export)"
check_cmd "CronJob argocd-export présent et actif" _m20p_jq "$_m20_e28_cj" '(.spec.suspend // false) == false'
_m20_e28_succes="$(_m20p_epoch "$(jq -r '.status.lastSuccessfulTime // empty' <<<"$_m20_e28_cj" 2>/dev/null || true)" || true)"
check_output "dernière exécution réussie il y a moins de 26 h" '^ok$' \
  bash -c '[[ "$1" =~ ^[0-9]+$ ]] && (( $2 - $1 < 93600 )) && echo ok' _ "$_m20_e28_succes" "$_m20_e28_maintenant"
check_cmd "identité argocd-sauvegardes sur adm01 ($_M20P_S3_ENV, mode 600)" \
  bash -c '[[ -r "$1" && "$(stat -c %a "$1")" == 600 ]]' _ "$_M20P_S3_ENV"
_m20_e28_liste="$(_m20p_s3 s3api list-objects-v2 --bucket argocd-sauvegardes --prefix quotidien/ 2>/dev/null || echo null)"
_m20_e28_cle="$(jq -r '[.Contents[]?] | sort_by(.LastModified) | last | .Key // empty' <<<"$_m20_e28_liste" 2>/dev/null || true)"
_m20_e28_date="$(_m20p_epoch "$(jq -r '[.Contents[]?] | sort_by(.LastModified) | last | .LastModified // empty' <<<"$_m20_e28_liste" 2>/dev/null || true)" || true)"
check_output "objet quotidien/ de moins de 26 h dans argocd-sauvegardes (${_m20_e28_cle:-aucun})" '^ok$' \
  bash -c '[[ "$1" == *.gpg && "$2" =~ ^[0-9]+$ ]] && (( $3 - $2 < 93600 )) && echo ok' _ \
  "$_m20_e28_cle" "$_m20_e28_date" "$_m20_e28_maintenant"
if [[ -n "$_m20_e28_cle" ]]; then
  _m20_e28_t="$(_m20p_tmp)"
  _m20p_s3 s3api get-object --bucket argocd-sauvegardes --key "$_m20_e28_cle" --range bytes=0-15 \
    "$_m20_e28_t/entete" >/dev/null 2>&1 || true
  # Message OpenPGP chiffré : premier paquet « session chiffrée par clé publique » (étiquette 1),
  # en-tête ancien format 0x84/0x85/0x86 ou nouveau format 0xc1. Jamais du YAML en clair.
  check_output "l'objet est chiffré (paquet OpenPGP, pas de YAML en clair)" '^(84|85|86|c1)$' \
    bash -c 'od -An -tx1 -N1 "$1" 2>/dev/null | tr -d " \n"' _ "$_m20_e28_t/entete"
else
  check_cmd "l'objet est chiffré (aucun objet trouvé)" false
fi
check_cmd "plateforme/infra : politique du compartiment (DeleteObject refusé à argocd-sauvegardes)" \
  _m20p_fichier_contient plateforme/infra outils/s3/politique-argocd-sauvegardes.json 'DeleteObject' 'argocd-sauvegardes'

title "Reconstruction sans toucher aux charges"
_m20_e28_ctrl="$(_m20p_epoch "$(_m20p_json -n argocd get statefulset argocd-application-controller \
  | jq -r '.metadata.creationTimestamp // empty' 2>/dev/null || true)" || true)"
check_output "StatefulSet du contrôleur lisible (date de création)" '^[0-9]+$' echo "$_m20_e28_ctrl"
# Preuve de la reconstruction : les CRD d'Argo CD (supprimées puis recréées, RB-201 §4.5) sont plus
# récentes que celles d'Argo Rollouts (M20-E15, jamais supprimées) ; sans reconstruction, c'est l'inverse.
_m20_e28_crd_app="$(_m20p_epoch "$(_m20p_json get crd applications.argoproj.io | jq -r '.metadata.creationTimestamp // empty' 2>/dev/null || true)" || true)"
_m20_e28_crd_ro="$(_m20p_epoch "$(_m20p_json get crd rollouts.argoproj.io | jq -r '.metadata.creationTimestamp // empty' 2>/dev/null || true)" || true)"
check_output "CRD applications.argoproj.io recréée après celles d'Argo Rollouts (reconstruction faite)" '^ok$' \
  bash -c '[[ "$1" =~ ^[0-9]+$ && "$2" =~ ^[0-9]+$ ]] && (( $1 > $2 )) && echo ok' _ "$_m20_e28_crd_app" "$_m20_e28_crd_ro"
_m20_e28_ro_prod="$(_m20p_epoch "$(_m20p_json -n mediagenda-prod get rollouts.argoproj.io mediagenda | jq -r '.metadata.creationTimestamp // empty' 2>/dev/null || true)" || true)"
check_output "mediagenda-prod : Rollout mediagenda antérieur à la reconstruction (non recréé)" '^ok$' \
  bash -c '[[ "$1" =~ ^[0-9]+$ && "$2" =~ ^[0-9]+$ ]] && (( $1 < $2 )) && echo ok' _ "$_m20_e28_ro_prod" "$_m20_e28_crd_app"
for _m20_e28_ns in mediagenda-dev mediagenda-recette mediagenda-prod; do
  _m20_e28_d="$(_m20p_epoch "$(_m20p_json -n "$_m20_e28_ns" get deployment mediagenda \
    | jq -r '.metadata.creationTimestamp // empty' 2>/dev/null || true)" || true)"
  check_output "$_m20_e28_ns : Deployment mediagenda antérieur à la reconstruction d'Argo CD (non recréé)" '^ok$' \
    bash -c '[[ "$1" =~ ^[0-9]+$ && "$2" =~ ^[0-9]+$ ]] && (( $1 < $2 )) && echo ok' _ "$_m20_e28_d" "$_m20_e28_ctrl"
done
_m20_e28_db="$(_m20p_json -n mediagenda-prod get pods -l cnpg.io/cluster=mediagenda-db)"
check_output "mediagenda-prod : pods de la base mediagenda-db antérieurs à la reconstruction" '^ok$' \
  bash -c 'n="$(jq --argjson c "$2" "[.items[] | (.metadata.creationTimestamp | fromdateiso8601) < \$c] | (length > 0 and all)" <<<"$1" 2>/dev/null)"; [[ "$n" == true ]] && echo ok' \
  _ "$_m20_e28_db" "${_m20_e28_ctrl:-0}"

title "Retour à l'état décrit par Git"
check_cmd "Application racine Synced/Healthy" _m20p_app_saine "$(_m20p_app racine)"
check_cmd "toutes les Applications du projet mediagenda Synced/Healthy" _m20p_jq \
  "$(_m20p_json -n argocd get applications.argoproj.io)" \
  '[.items[] | select(.spec.project == "mediagenda")] as $a | ($a | length) > 0
   and all($a[]; .status.sync.status == "Synced" and .status.health.status == "Healthy")'
# Le jeton de ci-lecture d'AVANT la reconstruction (fichier plus ancien que le contrôleur) est accepté :
# server.secretkey a bien été restauré.
_m20_e28_jeton_mtime="$(stat -c %Y "$_M20P_JETON" 2>/dev/null || true)"
check_output "le jeton argocd-checks.token date d'avant la reconstruction" '^ok$' \
  bash -c '[[ "$1" =~ ^[0-9]+$ && "$2" =~ ^[0-9]+$ ]] && (( $1 < $2 )) && echo ok' _ "$_m20_e28_jeton_mtime" "$_m20_e28_ctrl"
_m20_e28_api() { _m20p_argocd_api applications | jq -e '(.items | length) > 0' >/dev/null; }
check_cmd "… et l'API d'Argo CD l'accepte toujours" _m20_e28_api

title "Code et documentation"
check_cmd "plateforme/k8s : composants/argocd-sauvegarde/ sur main (CronJob argocd-export)" \
  _m20p_fichier_contient plateforme/k8s composants/argocd-sauvegarde/cronjob.yaml 'argocd-export' 'admin export'
check_cmd "RB-201 sur main (finaliseurs, --cascade=orphan, retour arrière)" \
  _m20p_doc docs/livraison/gitops/runbooks/RB-201-reconstruire-argo-cd.md 'finali' 'cascade=orphan' 'retour arri'
check_cmd "compte rendu de reconstruction sur main (RTO)" \
  _m20p_doc docs/livraison/gitops/tests/reconstruction-argo-cd.md 'RTO'
