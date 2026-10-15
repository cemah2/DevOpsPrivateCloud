# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E04.sh — M17-E04 « Kustomize : une base et des overlays » : dépôt mediagenda/deploiement,
# recette gérée par Kustomize. Lecture seule.

# shellcheck source=_m17-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m17-decouverte.sh"

title "M17-E04 — Kustomize : une base et des overlays"
require_cmd jq kubectl curl

for _e04_f in base/kustomization.yaml overlays/dev/kustomization.yaml overlays/recette/kustomization.yaml overlays/essai/kustomization.yaml; do
  check_cmd "mediagenda/deploiement (main) : $_e04_f" _m17d_gl_existe mediagenda/deploiement "$_e04_f"
done
if command -v kustomize >/dev/null 2>&1; then
  _e04_k="$(_m17d_extraire "$_m17d_deploiement_clone" .)" || _e04_k=""
  if [[ -n "$_e04_k" ]]; then
    for _e04_o in dev recette; do
      check_cmd "kustomize build overlays/$_e04_o (origin/main)" kustomize build "$_e04_k/overlays/$_e04_o"
    done
  else
    skip "kustomize build des overlays" "clone $_m17d_deploiement_clone absent"
  fi
fi

_e04_d="$(_m17d_obj mediagenda-recette deploy mediagenda)"
check_cmd "recette : Deployment mediagenda hors de toute release Helm" _m17d_hors_helm "$_e04_d"
check_cmd "recette : étiquette medisphere.fr/environnement=recette (objet et pods)" _m17d_jq "$_e04_d" \
  '.metadata.labels["medisphere.fr/environnement"] == "recette" and .spec.template.metadata.labels["medisphere.fr/environnement"] == "recette"'
check_cmd "recette : l'étiquette d'environnement n'est pas dans le sélecteur" _m17d_jq "$_e04_d" \
  '.spec.selector.matchLabels | has("medisphere.fr/environnement") | not'
check_cmd "recette : au moins deux réplicas prêts" _m17d_pret "$_e04_d" 2
_e04_cm="$(jq -r '[.spec.template.spec.containers[] | select(.name == "api") | .envFrom[]?.configMapRef.name // empty
          | select(test("^mediagenda-parametres-[a-z0-9]{6,}$"))][0] // ""' <<<"$_e04_d" 2>/dev/null)" || _e04_cm=""
check_output "recette : l'API lit une ConfigMap générée mediagenda-parametres-<empreinte>" '^mediagenda-parametres-' echo "$_e04_cm"
_e04_cmj=""
[[ -n "$_e04_cm" ]] && _e04_cmj="$(_m17d_obj mediagenda-recette configmap "$_e04_cm")"
check_cmd "recette : la ConfigMap $_e04_cm existe" test -n "$_e04_cmj"
_e04_r="$(_m17d_obj mediagenda-recette httproute mediagenda)"
check_cmd "recette : la route publie mediagenda-recette.$_m17d_domaine" _m17d_jq "$_e04_r" \
  ".spec.hostnames | index(\"mediagenda-recette.$_m17d_domaine\") != null"
check_cmd "https://mediagenda-recette.$_m17d_domaine/sante répond 200" _m17d_sante "https://mediagenda-recette.$_m17d_domaine/sante"
_e04_db="$(_m17d_obj mediagenda-recette cluster.postgresql.cnpg.io mediagenda-db)"
_e04_base_ancienne() {
  local tb tc
  tb="$(jq -r '.metadata.creationTimestamp // ""' <<<"$_e04_db")" || return 1
  tc="$(jq -r '.metadata.creationTimestamp // ""' <<<"$_e04_cmj")" || return 1
  [[ -n "$tb" && -n "$tc" && "$tb" < "$tc" ]]
}
check_cmd "recette : la base mediagenda-db est antérieure à la reprise (non recréée)" _e04_base_ancienne
