# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # expressions sed, yq et jq entre apostrophes
# break-E19.sh — M29-E19 « Panne : un plan dangereux passe la CI »
#
# Plan de référence : ressources/E19-plan-dangereux/plan-dangereux.json (ou WB_M29_E19_PLAN), refusé
# AVANT la panne par les politiques de main de plateforme/politiques (rego/tofu/) avec les arguments de
# conftest de la CI de plateforme/infra (déduits du .gitlab-ci.yml de plateforme/infra et du composant
# validation de plateforme/ci-templates, ou imposés par WB_M29_CONFTEST_ARGS).
# Variantes (commit identifiable de Lucas, marqueur M29-E19) :
#   1. plateforme/politiques : les paquets Rego évalués par la CI sont renommés « brouillon.<paquet> »
#      (règles ET tests, références data.<paquet> comprises) : opa test reste vert, conftest --namespace
#      n'évalue plus rien. Sans effet si la CI utilise --all-namespaces ;
#   2. plateforme/politiques : « resource_changes » réécrit « resource_change » dans les règles ET dans
#      les entrées simulées des tests : opa test reste vert, les règles ne se déclenchent plus sur un vrai
#      plan. Sans effet si un test lit un vrai plan (opa test passe alors au rouge) ;
#   3. plateforme/infra : le modèle caché .plan (M05), que les jobs plan:* étendent et qui appelle
#      « !reference [.validation:conftest-plan, script] » (M29-E10), reçoit « allow_failure: true » dans
#      .gitlab-ci.yml : le job de plan échoue sur le refus de conftest, le pipeline passe. Sans effet si
#      .gitlab-ci.yml n'a pas de clé .plan.
# Le plan est évalué comme dans le job de plan : espaces de la CI, --data rego/donnees et un contexte
# {"contexte": {"etat": "socle", "etiquettes_mr": []}} (WB_M29_E19_ETAT) ; sans contexte, la règle
# « contexte absent » de M29-E03 refuserait tout et masquerait la panne.
# Vérification : localement (conftest et opa sur adm01), le plan n'est plus refusé (1, 2), ou la surcharge
# est sur main (3). Annulation : commit inverse si les fichiers sont encore dans l'état injecté.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m29-commun.sh
source "$WB_ROOT/modules/29-tests-resilience/corrige/pannes/_m29-commun.sh"

_E19_POL="${WB_M29_PROJET_POLITIQUES:-plateforme/politiques}"
_E19_INFRA="${WB_M29_PROJET_INFRA:-plateforme/infra}"
_E19_CI="${WB_M29_PROJET_CI_TEMPLATES:-plateforme/ci-templates}"
_E19_COMPOSANT="${WB_M29_COMPOSANT_VALIDATION:-templates/validation/template.yml}"
_E19_PLAN="${WB_M29_E19_PLAN:-$WB_ROOT/modules/29-tests-resilience/ressources/E19-plan-dangereux/plan-dangereux.json}"
_E19_ETAT="${WB_M29_E19_ETAT:-socle}"

# _e19_rapatrier DOSSIER — copie locale de rego/ de plateforme/politiques (main).
_e19_rapatrier() {
  local dest="$1" c
  rm -rf -- "$dest"
  mkdir -p "$dest"
  while IFS= read -r c; do
    [[ "$c" == rego/* ]] || continue
    mkdir -p "$dest/$(dirname "$c")"
    m29_git_lire "$_E19_POL" "$c" >"$dest/$c" 2>/dev/null || return 1
  done < <(m29_git_arbre "$_E19_POL" rego)
  [[ -d "$dest/rego/tofu" ]]
}

# _e19_args — arguments d'espaces de conftest de la CI, un par ligne (« --all-namespaces » ou
# « --namespace » puis le nom) ; rien = espace « main » par défaut.
_e19_args() {
  local texte n
  if [[ -n "${WB_M29_CONFTEST_ARGS:-}" ]]; then
    tr ' ' '\n' <<<"$WB_M29_CONFTEST_ARGS" | grep -v '^$'
    return 0
  fi
  texte="$(m29_git_lire "$_E19_INFRA" .gitlab-ci.yml 2>/dev/null; m29_git_lire "$_E19_CI" "$_E19_COMPOSANT" 2>/dev/null)"
  if grep -q -- '--all-namespaces' <<<"$texte"; then
    echo --all-namespaces
    return 0
  fi
  # --namespace X / --namespace=X / -n X littéraux, puis entrées « …namespace…: X » (chaîne ou liste)
  {
    grep -oE -- '--namespace[= ]+[A-Za-z0-9_.]+' <<<"$texte" | sed -E 's/--namespace[= ]+//'
    m29_git_lire "$_E19_INFRA" .gitlab-ci.yml 2>/dev/null |
      yq -r '[.include[]? | .inputs? // {} | to_entries[] | select(.key | test("namespace")) | .value] | flatten | .[]' 2>/dev/null |
      sed -E 's/[, ]+/\n/g'
  } | grep -E '^[A-Za-z0-9_.]+$' | sort -u | while IFS= read -r n; do
    printf -- '--namespace\n%s\n' "$n"
  done
}

# _e19_espaces — noms des espaces évalués par la CI (« main » si aucun n'est donné), vide si tous.
_e19_espaces() {
  local -a a
  mapfile -t a < <(_e19_args)
  if printf '%s\n' "${a[@]}" | grep -qx -- '--all-namespaces'; then return 0; fi
  if ((${#a[@]} == 0)); then echo main; return 0; fi
  printf '%s\n' "${a[@]}" | grep -v -- '^--namespace$'
}

# _e19_refuse DOSSIER — le plan est refusé (au moins un FAIL) par les politiques de DOSSIER/rego/tofu
# avec les arguments de la CI.
_e19_refuse() {
  local -a a donnees=()
  local sortie rc=0 ctx
  mapfile -t a < <(_e19_args)
  ctx="$(m29_etat E19)/contexte.json"
  jq -n --arg e "$_E19_ETAT" '{contexte: {etat: $e, etiquettes_mr: []}}' >"$ctx" || return 1
  [[ -d "$1/rego/donnees" ]] && donnees=(--data "$1/rego/donnees")
  sortie="$(conftest test --no-color -p "$1/rego/tofu" "${a[@]}" "${donnees[@]}" --data "$ctx" "$_E19_PLAN" 2>&1)" || rc=$?
  ((rc != 0)) && grep -q 'FAIL' <<<"$sortie" && ! grep -q 'contexte absent' <<<"$sortie"
}

# _e19_opa_ok DOSSIER — opa test vert sur les racines explicites (rego/tofu et rego/donnees, comme le
# composant validation : « opa test rego » chargerait aussi les plans d'exemple JSON de rego/exemples/
# comme des données et échouerait sur un conflit de fusion).
_e19_opa_ok() {
  local -a r=("$1/rego/tofu")
  [[ -d "$1/rego/donnees" ]] && r+=("$1/rego/donnees")
  opa test "${r[@]}" >/dev/null 2>&1
}

_e19_sain() {
  local d
  m29_outils opa conftest || return 1
  [[ -r "$_E19_PLAN" ]] || { echo "plan de référence illisible : $_E19_PLAN" >&2; return 1; }
  d="$(m29_etat E19)/avant"
  _e19_rapatrier "$d" || { echo "rego/tofu/ introuvable sur main de $_E19_POL (M29-E03)." >&2; return 1; }
  if ! _e19_refuse "$d"; then
    echo "Le plan de référence n'est PAS refusé par les politiques de main avec les arguments de la CI :" >&2
    echo "rien n'est cassé, mais tes politiques (M29-E03) ne couvrent pas ce plan. Complète-les, ou désigne" >&2
    echo "un plan qu'elles refusent par WB_M29_E19_PLAN, puis relance." >&2
    return 1
  fi
}

_m29E19_une() {
  local n="$1" d avant apres f p pnew esc fic
  d="$(m29_etat E19)"
  avant="$d/avant"
  apres="$d/apres"
  rm -rf -- "$apres"
  cp -a "$avant" "$apres"
  case "$n" in
    1|2)
      local -a espaces modifies=()
      if ((n == 1)); then
        mapfile -t espaces < <(_e19_espaces)
        ((${#espaces[@]} > 0)) || return 10 # --all-namespaces : renommer ne cache rien
        for p in "${espaces[@]}"; do
          grep -rlqE "^package[[:space:]]+${p//./\\.}[[:space:]]*$" "$apres/rego/tofu" 2>/dev/null || continue
          pnew="brouillon.$p"
          esc="${p//./\\.}"
          while IFS= read -r f; do
            sed -E -i "s/^package[[:space:]]+${esc}[[:space:]]*$/package ${pnew}/; s/data\\.${esc}([^A-Za-z0-9_]|$)/data.${pnew}\\1/g" "$f"
          done < <(grep -rlE "^package[[:space:]]+${esc}[[:space:]]*$|data\\.${esc}([^A-Za-z0-9_]|$)" "$apres/rego" --include='*.rego')
        done
        m29_poser E19 message "refactor(politiques): ranger les règles OpenTofu dans brouillon.* pendant la refonte (M29-E19)

Les tests opa passent toujours. -- Lucas"
      else
        grep -rlq 'resource_changes' "$apres/rego" --include='*.rego' || return 10
        while IFS= read -r f; do
          sed -i 's/resource_changes/resource_change/g' "$f"
        done < <(grep -rl 'resource_changes' "$apres/rego" --include='*.rego')
        m29_poser E19 message "refactor(politiques): harmoniser le nom de l'entrée des règles OpenTofu (M29-E19)

Mocks des tests mis à jour, opa test vert. -- Lucas"
      fi
      # Effet attendu : opa test toujours vert (s'il l'était), plan plus refusé.
      if _e19_opa_ok "$avant" && ! _e19_opa_ok "$apres"; then return 10; fi
      _e19_refuse "$apres" && return 10
      m29_git_debut E19 "$_E19_POL"
      while IFS= read -r fic; do
        modifies+=("$fic")
        m29_git_fichier E19 "${fic#"$apres"/}" "$fic"
      done < <(LC_ALL=C diff -rq "$avant" "$apres" | sed -nE 's/^Files .* and (.*) differ$/\1/p')
      ((${#modifies[@]} > 0)) || return 10
      m29_git_valider E19 "$(m29_lire E19 message)" || return $?
      ;;
    3)
      local gci job=.plan tmp
      gci="$(m29_git_lire "$_E19_INFRA" .gitlab-ci.yml 2>/dev/null)" || return 10
      # Le modèle .plan doit exister ET appeler la vérification des plans (sinon rien ne refuse le plan).
      JOB="$job" yq -e '.[strenv(JOB)] | tostring | test("conftest")' <<<"$gci" >/dev/null 2>&1 || return 10
      [[ "$(JOB="$job" yq -r '.[strenv(JOB)].allow_failure // ""' <<<"$gci" 2>/dev/null)" == true ]] && return 10
      tmp="$d/gitlab-ci.yml"
      JOB="$job" yq '.[strenv(JOB)].allow_failure = true' <<<"$gci" >"$tmp" || return 10
      m29_poser E19 job "$job"
      m29_git_debut E19 "$_E19_INFRA"
      m29_git_fichier E19 .gitlab-ci.yml "$tmp"
      m29_git_valider E19 "ci: ne plus bloquer les MR sur les refus de conftest le temps de corriger les faux positifs (M29-E19)

Les jobs de plan restent visibles en orange. -- Lucas" || return $?
      ;;
  esac
  m29_journal E19 "variante $n posée"
}

_m29E19_defaire() { m29_git_annuler E19 || true; }

panne_E19_v1() { _e19_sain && m29_essayer E19 3 1; }
panne_E19_v2() { _e19_sain && m29_essayer E19 3 2; }
panne_E19_v3() { _e19_sain && m29_essayer E19 3 3; }

verifier_E19() {
  local d
  m29_git_injecte E19 || return 1
  case "$WB_VAR" in
    3)
      [[ "$(m29_git_lire "$_E19_INFRA" .gitlab-ci.yml 2>/dev/null | JOB="$(m29_lire E19 job)" yq -r '.[strenv(JOB)].allow_failure' 2>/dev/null)" == true ]]
      ;;
    *)
      d="$(m29_etat E19)/verif"
      _e19_rapatrier "$d" || return 1
      ! _e19_refuse "$d"
      ;;
  esac
}

annuler_E19() {
  _m29E19_defaire
  rm -rf -- "$(m29_etat E19)/avant" "$(m29_etat E19)/apres" "$(m29_etat E19)/verif"
  m29_oublier E19 message
  m29_oublier E19 job
  m29_journal E19 "annulation"
}

resume_E19() {
  echo "Le plan de référence qui supprime nbx01 n'est plus refusé par la chaîne de validation de plateforme/infra."
}

symptome_E19() {
  wb_symptome "Ticket SEC-3019 — De : Sophie Laurent" \
    "En préparant l'audit, j'ai rejoué notre plan de référence (ressources/E19-plan-dangereux/," \
    "il supprime nbx01 et crée une VM sans étiquette) à travers la chaîne de validation de" \
    "plateforme/infra : il passe. Il était refusé le mois dernier, j'ai la capture. Une MR de ce" \
    "genre aurait donc pu être fusionnée. Je veux savoir depuis quand, pourquoi, et la preuve" \
    "que ça ne peut plus arriver sans qu'on le voie." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 29 19"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 29 E19 3 "$@"; }
fi
