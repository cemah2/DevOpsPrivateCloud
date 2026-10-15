# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E21.sh — M17-E21 « Panne : la production déploie la mauvaise image »
#
# Dans ~/src/mediagenda-deploiement, la panne crée une branche locale « lucas/… » partie de HEAD, y
# commite au nom de Lucas Martin, APPLIQUE la prod depuis cette branche (kubectl apply --server-side -k
# overlays/prod, comme en M17-E09), puis remet la copie de travail sur sa branche d'origine.
# Rien n'est poussé, « main » n'est pas touchée. Variantes :
#   1. un « images: » ajouté à overlays/prod/kustomization.yaml (« essai de la nouvelle version »),
#      avec la version de la recette : les transformateurs de l'overlay passent APRÈS le component
#      « livraison », l'image de la recette l'emporte sur livraison.yaml (exige recette ≠ prod) ;
#   2. le component « debogage » inclus dans la prod (avant « livraison ») : journaux en DEBUG, format
#      texte, cache des créneaux réduit.
# Annulation (si la prod est encore dans l'état posé) : application de overlays/prod depuis
# origin/main (copie exportée par git archive), puis suppression de la branche si elle n'a pas bougé.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m17-commun.sh
source "$WB_ROOT/modules/17-packaging/corrige/pannes/_m17-commun.sh"

_E21_NS=mediagenda-prod
_E21_KUS="overlays/prod/kustomization.yaml"
_E21_IMAGE="registry.par1.medisphere.internal/medisphere/mediagenda-api"

_e21_version() { # _e21_version ENV — data.version du livraison.yaml de l'overlay (copie de travail)
  yq -r '.data.version // ""' "$_M17_DEPLOIEMENT/overlays/$1/livraison.yaml" 2>/dev/null
}

_e21_deploy() { wb_kubectl get deployment mediagenda -n "$_E21_NS" -o json 2>/dev/null; }

_e21_tag() {
  _e21_deploy | jq -r '.spec.template.spec.containers[] | select(.name == "api") | .image' 2>/dev/null | sed -E 's/.*:([^:/]+)$/\1/'
}

_e21_niveau() {
  _e21_deploy | jq -r '.spec.template.spec.containers[] | select(.name == "api") | .env[]? | select(.name == "MEDIAGENDA_LOG_LEVEL") | .value' 2>/dev/null
}

# _e21_appliquer DOSSIER — applique l'overlay prod du DOSSIER (racine d'un arbre mediagenda/deploiement).
_e21_appliquer() {
  wb_kubectl apply --server-side -k "$1/overlays/prod" >/dev/null 2>&1
}

# _e21_appliquer_main — applique overlays/prod de origin/main (ou main) sans toucher à la copie de travail.
_e21_appliquer_main() {
  local d ref rc=0
  ref=origin/main
  git -C "$_M17_DEPLOIEMENT" rev-parse --verify --quiet "$ref" >/dev/null || ref=main
  d="$(mktemp -d)" || return 1
  if git -C "$_M17_DEPLOIEMENT" archive "$ref" | tar -x -C "$d"; then
    _e21_appliquer "$d" || rc=1
  else
    rc=1
  fi
  rm -rf -- "$d"
  return "$rc"
}

_mE21_une() {
  local v="$1" rec prod br msg origine
  rec="$(_e21_version recette)"
  prod="$(_e21_version prod)"
  case "$v" in
    1)
      [[ -n "$rec" && -n "$prod" && "$rec" != "$prod" ]] || return 10
      yq -i ".images = [{\"name\": \"$_E21_IMAGE\", \"newTag\": \"$rec\"}]" "$_M17_DEPLOIEMENT/$_E21_KUS" || return 1
      br="lucas/essai-version-prod"; msg="chore(prod): essai de la nouvelle version avant le comité"
      m17_ecrire E21 attendu "$rec"
      ;;
    2)
      [[ -d "$_M17_DEPLOIEMENT/components/debogage" ]] || return 10
      yq -e '.components | index("../../components/debogage")' "$_M17_DEPLOIEMENT/$_E21_KUS" >/dev/null 2>&1 && return 10
      yq -i '.components |= (.[0:-1] + ["../../components/debogage"] + .[-1:])' "$_M17_DEPLOIEMENT/$_E21_KUS" || return 1
      br="lucas/diagnostic-prod"; msg="chore(prod): journaux détaillés pour le diagnostic du ticket INC-4405"
      ;;
  esac
  if git -C "$_M17_DEPLOIEMENT" rev-parse --verify --quiet "refs/heads/$br" >/dev/null; then
    git -C "$_M17_DEPLOIEMENT" checkout --quiet -- .
    return 10
  fi
  m17_branche_lucas "$_M17_DEPLOIEMENT" "$br" "$msg" || { git -C "$_M17_DEPLOIEMENT" checkout --quiet -- . 2>/dev/null || true; return 1; }
  _e21_appliquer "$_M17_DEPLOIEMENT" || { wb_avert "application de la prod depuis $br impossible"; return 1; }
  # Lucas est revenu sur la branche d'origine après avoir appliqué.
  read -r _ _ origine _ <<<"$(m17_lire E21 git)"
  git -C "$_M17_DEPLOIEMENT" switch --quiet "$origine" 2>/dev/null || git -C "$_M17_DEPLOIEMENT" switch --quiet --detach "$origine" 2>/dev/null || true
  m17_journal E21 "prod appliquée depuis la branche $br ($msg)"
}

_e21_injecter() {
  m17_outils git kubectl yq jq || return 1
  m17_git_propre "$_M17_DEPLOIEMENT" || return 1
  [[ -f "$_M17_DEPLOIEMENT/$_E21_KUS" ]] || { wb_avert "$_M17_DEPLOIEMENT/$_E21_KUS introuvable (overlay prod, M17-E09)"; return 1; }
  [[ -n "$(_e21_deploy)" ]] || { wb_avert "aucun Deployment mediagenda dans $_E21_NS : livre d'abord la prod (M17-E09)"; return 1; }
  # La prod doit correspondre à main avant la panne.
  wb_k8s_sauver deployment mediagenda "$_E21_NS"
  m17_essayer E21 2 "$1"
}

panne_E21_v1() { _e21_injecter 1; }
panne_E21_v2() { _e21_injecter 2; }

verifier_E21() {
  case "${WB_VAR:-}" in
    1) [[ "$(_e21_tag)" == "$(m17_lire E21 attendu)" ]] ;;
    2) [[ "$(_e21_niveau)" == DEBUG ]] ;;
    *) return 1 ;;
  esac
}

annuler_E21() {
  local casse=0
  case "${WB_VAR:-}" in
    1) [[ -n "$(m17_lire E21 attendu)" && "$(_e21_tag)" == "$(m17_lire E21 attendu)" ]] && casse=1 ;;
    2) [[ "$(_e21_niveau)" == DEBUG ]] && casse=1 ;;
    *) casse=1 ;;
  esac
  if ((casse)); then
    _e21_appliquer_main || wb_avert "annulation : la prod n'a pas pu être réappliquée depuis main (kubectl apply --server-side -k overlays/prod)"
    m17_journal E21 "annulation : prod réappliquée depuis main"
  fi
  m17_branche_annuler E21
  rm -rf "${XDG_STATE_HOME:-$HOME/.local/state}/workbook/k8s/$WB_EX"
  m17_oublier E21 attendu
}

resume_E21() {
  case "${WB_VAR:-}" in
    1) echo "La production tourne la version de la recette, que le comité n'a pas encore approuvée." ;;
    *) echo "La production écrit des journaux en DEBUG au format texte, sans changement approuvé." ;;
  esac
}

symptome_E21() {
  case "${WB_VAR:-}" in
    1)
      wb_symptome "Ticket INC-4421 — De : Sophie Laurent" \
        "Contrôle de conformité de 9 h : mediagenda-prod tourne l'image $(_e21_tag), alors que le comité" \
        "de changement a approuvé $(_e21_version prod) pour la production. Aucune MR n'a été fusionnée sur" \
        "overlays/prod. Je veux savoir ce qui tourne, depuis quand, d'où ça vient, et que la prod revienne" \
        "à la version approuvée." \
        "" \
        "Temps cible : 30 min. Contrôle : lab/bin/check 17 21"
      ;;
    *)
      wb_symptome "Ticket INC-4421 — De : Sophie Laurent" \
        "Contrôle de conformité de 9 h : les journaux de mediagenda-prod sont en DEBUG et au format texte," \
        "que notre collecte JSON rejette, et l'API répond plus lentement aux créneaux. Rien de cela n'a été" \
        "approuvé, aucune MR n'a été fusionnée sur overlays/prod. Je veux savoir ce qui tourne, depuis quand," \
        "d'où ça vient, et que la prod revienne à ce qui a été approuvé." \
        "" \
        "Temps cible : 30 min. Contrôle : lab/bin/check 17 21"
      ;;
  esac
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 17 E21 2 "$@"; }
fi
