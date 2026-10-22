# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # expressions yq et jq entre apostrophes
# break-E41.sh — M19-E41 « Panne : les pipelines ne se déclenchent plus »
#
# Cible : le projet témoin formation/ci-pannes. Variantes :
#   1. Lucas publie une version du composant canari dont workflow:rules ne garde que les pipelines de
#      MR et d'étiquettes (« plus de pipelines en double ») et la fait consommer : plus aucun pipeline
#      de branche, donc plus rien sur main ;
#   2. chemin du fichier de configuration CI du projet changé (.gitlab/ci/pipeline.yml, inexistant) ;
#   3. fonction CI/CD désactivée dans le projet (builds_access_level=disabled) ;
#   4. le compte de Lucas, propriétaire du pipeline planifié canari-quotidien, est bloqué (fin de stage
#      anticipée) : le pipeline planifié ne tourne plus. --annuler réactive toujours le compte de Lucas
#      (les pannes suivantes du workbook en ont besoin).
# Vérification (1 à 3) : un commit de Lucas sur main ne crée aucun pipeline en 60 s.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m19-commun.sh
source "$WB_ROOT/modules/19-ci/corrige/pannes/_m19-commun.sh"

_E41_CHEMIN=.gitlab/ci/pipeline.yml

_e41_projet() { m19_api GET "projects/$(m19_enc "$_M19_TEMOIN")"; }

_e41_planifie() {
  m19_api GET "projects/$(m19_enc "$_M19_TEMOIN")/pipeline_schedules?per_page=100" |
    jq -c '[.[] | select(.description == "canari-quotidien")][0] // empty'
}

# _e41_commit_sans_pipeline — Lucas ajoute une ligne au README ; aucun pipeline ne doit apparaître.
_e41_commit_sans_pipeline() {
  local d sha
  d="$(m19_etat E41)"
  m19_brut "$_M19_TEMOIN" README.md main >"$d/README.md" || return 1
  printf '\n<!-- canari : vérification du %s -->\n' "$(date -Is)" >>"$d/README.md"
  sha="$(m19_commit --lucas "$_M19_TEMOIN" main "docs: note de vérification du canari (M19-E41)" \
    "$(jq -s '.' <(m19_action update README.md "$d/README.md"))")" || sha=""
  rm -f -- "$d/README.md"
  [[ -n "$sha" ]] || return 1
  m19_pas_de_pipeline "$sha" 60
}

_m19E41_une() {
  local n="$1" pid p s uid
  m19_debut E41
  pid="$(m19_temoin_id)" || return 1
  case "$n" in
    1)
      m19_canari_publier E41 "feat(canari): plus de pipelines en double (MR et étiquettes seulement)" \
        '(select(documentIndex == 1) | .workflow.rules) = [{"if": "$CI_PIPELINE_SOURCE == \"merge_request_event\""}, {"if": "$CI_COMMIT_TAG"}]' >/dev/null || return $?
      ;;
    2)
      p="$(_e41_projet)" || return 1
      m19_ecrire E41 config-orig "$(jq -r '.ci_config_path // ""' <<<"$p")"
      m19_api PUT "projects/$pid" --data-urlencode "ci_config_path=$_E41_CHEMIN" >/dev/null || return 1
      ;;
    3)
      p="$(_e41_projet)" || return 1
      [[ "$(jq -r '.builds_access_level' <<<"$p")" != disabled ]] || return 10
      m19_ecrire E41 builds-orig "$(jq -r '.builds_access_level' <<<"$p")"
      m19_api PUT "projects/$pid" --data-urlencode "builds_access_level=disabled" >/dev/null || return 1
      ;;
    4)
      s="$(_e41_planifie)" || s=""
      [[ -n "$s" ]] && [[ "$(jq -r '.owner.username // empty' <<<"$s")" == "$_M19_LUCAS" ]] || return 10
      uid="$(m19_lucas_id)"
      [[ -n "$uid" ]] || return 10
      m19_api POST "users/$uid/block" >/dev/null || return 1
      m19_ecrire E41 lucas-bloque "$uid"
      m19_journal E41 "variante 4 : compte $_M19_LUCAS bloqué"
      m19_api GET "users/$uid" | jq -e '.state == "blocked"' >/dev/null || { _e41_defaire 4; return 10; }
      return 0
      ;;
  esac
  m19_journal E41 "variante $n posée"
  _e41_commit_sans_pipeline || { _e41_defaire "$n"; return 10; }
  m19_journal E41 "variante $n constatée"
}

_e41_defaire() {
  local n="$1" pid p uid
  pid="$(m19_temoin_id 2>/dev/null)" || pid=""
  case "$n" in
    1) m19_temoin_retablir E41 ;;
    2)
      if [[ -n "$pid" ]] && [[ "$(_e41_projet | jq -r '.ci_config_path // ""')" == "$_E41_CHEMIN" ]]; then
        m19_api PUT "projects/$pid" --data-urlencode "ci_config_path=$(m19_lire E41 config-orig)" >/dev/null || wb_avert "chemin de configuration CI non rétabli"
      fi
      m19_oublier E41 config-orig
      ;;
    3)
      p="$(m19_lire E41 builds-orig)"
      if [[ -n "$pid" && -n "$p" ]] && [[ "$(_e41_projet | jq -r '.builds_access_level')" == disabled ]]; then
        m19_api PUT "projects/$pid" --data-urlencode "builds_access_level=$p" >/dev/null || wb_avert "CI/CD du témoin non réactivée"
      fi
      m19_oublier E41 builds-orig
      ;;
    4)
      uid="$(m19_lire E41 lucas-bloque)"
      [[ -n "$uid" ]] || uid="$(m19_lucas_id 2>/dev/null)"
      if [[ -n "$uid" ]] && m19_api GET "users/$uid" 2>/dev/null | jq -e '.state == "blocked"' >/dev/null 2>&1; then
        m19_api POST "users/$uid/unblock" >/dev/null || wb_avert "compte $_M19_LUCAS toujours bloqué : débloque-le (Admin > Users)"
      fi
      m19_oublier E41 lucas-bloque
      ;;
  esac
}

panne_E41_v1() { m19_preparer && m19_essayer E41 4 1; }
panne_E41_v2() { m19_preparer && m19_essayer E41 4 2; }
panne_E41_v3() { m19_preparer && m19_essayer E41 4 3; }
panne_E41_v4() { m19_preparer && m19_essayer E41 4 4; }

verifier_E41() {
  case "${WB_VAR:-}" in
    1) m19_brut "$_M19_TEMOIN" .gitlab-ci.yml main | grep -q "canari@$(m19_lire E41 canari-version)" ;;
    2) [[ "$(_e41_projet | jq -r '.ci_config_path // ""')" == "$_E41_CHEMIN" ]] ;;
    3) [[ "$(_e41_projet | jq -r '.builds_access_level')" == disabled ]] ;;
    4) m19_api GET "users/$(m19_lire E41 lucas-bloque)" | jq -e '.state == "blocked"' >/dev/null ;;
    *) return 1 ;;
  esac
}

annuler_E41() {
  case "${WB_VAR:-}" in
    [1-4]) _e41_defaire "$WB_VAR" ;;
    *) local v; for v in 1 2 3 4; do _e41_defaire "$v"; done ;;
  esac
  m19_oublier E41 canari-version
  m19_oublier E41 debut
  m19_journal E41 "annulation"
}

resume_E41() {
  case "${WB_VAR:-}" in
    4) echo "Le pipeline planifié canari-quotidien (formation/ci-pannes) n'a pas tourné cette nuit." ;;
    *) echo "Les commits poussés sur main de formation/ci-pannes ne déclenchent plus aucun pipeline." ;;
  esac
}

symptome_E41() {
  case "${WB_VAR:-}" in
    4)
      wb_symptome "Ticket INC-4641 — De : Nadia Roussel" \
        "Le canari quotidien (pipeline planifié « canari-quotidien » de formation/ci-pannes) n'a" \
        "pas tourné cette nuit, ni la précédente : aucun pipeline de source « schedule ». Le" \
        "planning est toujours actif dans l'interface. Personne n'a touché au projet, à part les" \
        "RH qui ont clôturé quelques comptes en fin de semaine. Remets-le en route proprement." \
        "" \
        "Temps cible : 30 min. Contrôle : lab/bin/check 19 41"
      ;;
    *)
      wb_symptome "Ticket INC-4641 — De : Julien Petit" \
        "Les commits poussés sur main du canari (formation/ci-pannes) ne déclenchent plus aucun" \
        "pipeline : pas d'erreur, pas de pipeline en échec, rien. Le dernier commit de Lucas est là," \
        "mais l'onglet Pipelines ne bouge plus. Retrouve pourquoi, sans casser ce qui est voulu." \
        "" \
        "Temps cible : 30 min. Contrôle : lab/bin/check 19 41"
      ;;
  esac
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 19 E41 4 "$@"; }
fi
