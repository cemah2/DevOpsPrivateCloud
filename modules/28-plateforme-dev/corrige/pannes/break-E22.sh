# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et expressions sed entre apostrophes
# break-E22.sh — M28-E22 « Panne : le portail ne crée plus de services ».
#
# Variantes (aucun secret n'est touché : le jeton de svc-portail reste valide) :
#   1. droits de svc-portail réduits à Reporter (20) dans le groupe GitLab medidoc (ou, à défaut, le
#      premier groupe d'équipe où il est au moins Developer) : publish:gitlab répond 403 ; ancien
#      niveau mémorisé, remis à l'annulation si le niveau est encore 20 ;
#   2. commit de Lucas dans plateforme/portail-modeles (modeles/nouveau-service/template.yaml) : la
#      première action « publish:gitlab » renommée « publish:gitlab:projet » (action inexistante) ;
#   3. commit de Lucas dans le même fichier : l'hôte du premier repoUrl changé en
#      gitlab.par1.medisphere.internal (aucune intégration GitLab configurée pour cet hôte).
# Constat des variantes 2 et 3 : l'entité Template relue par le catalogue (jeton des checks).
# Annulation : niveau d'origine rétabli ; commit inverse si le fichier n'a pas bougé.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m28-commun.sh
source "$WB_ROOT/modules/28-plateforme-dev/corrige/pannes/_m28-commun.sh"

_E22_PROJET=plateforme/portail-modeles
_E22_MODELE=modeles/nouveau-service/template.yaml

_e22_modele_catalogue() { backstage_api "catalog/entities/by-name/template/default/nouveau-service" 2>/dev/null; }

_e22_sain() {
  m28_outils || return 1
  if ! _e22_modele_catalogue | jq -e '[.spec.steps[].action] | index("publish:gitlab") != null' >/dev/null 2>&1; then
    echo "Le modèle nouveau-service n'est pas lisible au catalogue, ou n'utilise pas publish:gitlab (lab/bin/check 28 22)." >&2
    return 1
  fi
  if ! wb_kubectl -n portail get deploy portail -o json 2>/dev/null | jq -e '(.status.readyReplicas // 0) >= 1' >/dev/null; then
    echo "Le portail n'a aucun réplica prêt : répare d'abord (RB-284)." >&2
    return 1
  fi
}

_e22_id_svc() { m28_api GET "users?username=svc-portail" | jq -r '.[0].id // empty'; }
_e22_niveau() { m28_api GET "groups/$(_m28_enc "$1")/members/$2" 2>/dev/null | jq -r '.access_level // empty'; }

_e22_v1_effective() {
  local g id
  g="$(m28_lire E22 groupe)"
  id="$(m28_lire E22 id)"
  [[ -n "$g" && -n "$id" && "$(_e22_niveau "$g" "$id")" == 20 ]]
}
_e22_v2_effective() {
  _e22_modele_catalogue | jq -e '[.spec.steps[].action] | index("publish:gitlab:projet") != null' >/dev/null 2>&1
}
_e22_v3_effective() {
  _e22_modele_catalogue | jq -e '[.spec.steps[].input.repoUrl? // empty | tostring | select(test("^gitlab\\."))] | length > 0' >/dev/null 2>&1
}

_e22_sans_effet() {
  m28_git_annuler E22 || true
  return 10
}

_m28E22_une() {
  local n="$1" id g niv
  case "$n" in
    1)
      id="$(_e22_id_svc)"
      [[ -n "$id" ]] || return 10
      for g in medidoc mediagenda medinotif; do
        niv="$(_e22_niveau "$g" "$id")"
        if [[ "$niv" =~ ^[0-9]+$ ]] && ((niv >= 30)); then break; fi
        niv=""
      done
      [[ -n "$niv" ]] || return 10
      m28_poser E22 groupe "$g"
      m28_poser E22 id "$id"
      m28_poser E22 niveau-origine "$niv"
      m28_api PUT "groups/$(_m28_enc "$g")/members/$id" --data-urlencode "access_level=20" >/dev/null || return 1
      m28_journal E22 "svc-portail : niveau $niv → 20 dans le groupe $g"
      _e22_v1_effective || return 1
      ;;
    2 | 3)
      m28_git_lire "$_E22_PROJET" "$_E22_MODELE" >/dev/null 2>&1 || return 10
      if ((n == 2)); then
        _m28_transformer() { sed '0,/action: publish:gitlab$/s//action: publish:gitlab:projet/'; }
        m28_git_modifier E22 "$_E22_PROJET" "$_E22_MODELE" "refactor(nouveau-service): nom d'action plus explicite (M28-E22)

-- Lucas" || return $?
        m28_attendre 600 _e22_v2_effective || _e22_sans_effet || return $?
      else
        _m28_transformer() { sed '0,/repoUrl: git01\.par1\.medisphere\.internal?/s//repoUrl: gitlab.par1.medisphere.internal?/'; }
        m28_git_modifier E22 "$_E22_PROJET" "$_E22_MODELE" "chore(nouveau-service): nom d'hôte GitLab « parlant » (M28-E22)

-- Lucas" || return $?
        m28_attendre 600 _e22_v3_effective || _e22_sans_effet || return $?
      fi
      ;;
  esac
  m28_journal E22 "variante $n posée"
}

panne_E22_v1() { _e22_sain && m28_essayer E22 3 1; }
panne_E22_v2() { _e22_sain && m28_essayer E22 3 2; }
panne_E22_v3() { _e22_sain && m28_essayer E22 3 3; }

verifier_E22() {
  case "$WB_VAR" in
    1) _e22_v1_effective ;;
    2) _e22_v2_effective ;;
    3) _e22_v3_effective ;;
    *) return 1 ;;
  esac
}

annuler_E22() {
  local g id niv
  g="$(m28_lire E22 groupe)"
  id="$(m28_lire E22 id)"
  niv="$(m28_lire E22 niveau-origine)"
  if [[ -n "$g" && -n "$id" && -n "$niv" ]]; then
    if [[ "$(_e22_niveau "$g" "$id")" == 20 ]]; then
      m28_api PUT "groups/$(_m28_enc "$g")/members/$id" --data-urlencode "access_level=$niv" >/dev/null 2>&1 ||
        wb_avert "niveau de svc-portail dans $g non rétabli : remets-le à $niv à la main"
    fi
    m28_oublier E22 groupe
    m28_oublier E22 id
    m28_oublier E22 niveau-origine
  fi
  m28_git_annuler E22 || true
  m28_journal E22 "annulation"
}

resume_E22() { echo "Le modèle « nouveau service » du portail échoue pour toutes les équipes."; }

symptome_E22() {
  wb_symptome "Ticket INC-5522 — De : Julien Petit" \
    "Le modèle « nouveau service » du portail ne marche plus : l'équipe MédiDoc a voulu créer un" \
    "service ce matin, la tâche échoue (rien n'est créé, ou à moitié). La semaine dernière, tout allait" \
    "bien. Le catalogue et la documentation s'affichent normalement." \
    "" \
    "Essaie sur un nom fictif (medidoc-essai-inc5522) et supprime ce que tu crées." \
    "Temps cible : 30 min. Contrôle : lab/bin/check 28 22"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 28 E22 3 "$@"; }
fi
