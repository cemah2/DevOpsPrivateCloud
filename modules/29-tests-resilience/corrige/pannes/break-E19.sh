# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # expressions sed, yq et jq entre apostrophes
# break-E19.sh — M29-E19 « Panne : un plan dangereux passe la CI »
#
# Plan de référence : ressources/E19-plan-dangereux/plan-dangereux.json (ou WB_M29_E19_PLAN), refusé
# AVANT la panne par les politiques de main de plateforme/politiques (rego/tofu/) avec les arguments de
# conftest de la CI de plateforme/infra (déduits du .gitlab-ci.yml de plateforme/infra et du composant
# validation de plateforme/ci-templates, ou imposés par WB_M29_CONFTEST_ARGS).
# La CI de plateforme/infra ne lit PAS main de plateforme/politiques : le composant validation clone
# l'étiquette épinglée par son entrée « politiques_ref » (M29-E10, « jamais une branche »). Pour que les
# variantes 1 et 2 atteignent vraiment la CI, Lucas fait ce que ferait un vrai mainteneur pressé : commit
# sur main de plateforme/politiques, étiquette suivante (vX.Y.Z+1), puis montée de politiques_ref dans
# plateforme/infra (second commit, clé d'état E19-infra). Sans entrée politiques_ref (CI qui suivrait
# main), le commit sur main suffit.
# Variantes (commits identifiables de Lucas, marqueur M29-E19) :
#   1. plateforme/politiques : les paquets Rego évalués par la CI sont renommés « brouillon.<paquet> »
#      (règles ET tests, références data.<paquet> comprises) : opa test reste vert, conftest --namespace
#      n'évalue plus rien. Le job des exemples du composant (tests_rego) passe au rouge sur main : Lucas a
#      poussé DIRECTEMENT (si main refuse la poussée directe, la variante est sans effet). Sans effet si
#      la CI utilise --all-namespaces ;
#   2. plateforme/politiques : « resource_changes » réécrit « resource_change » dans les règles, dans les
#      entrées simulées des tests ET dans les plans d'exemple de rego/exemples/ : opa test et le job des
#      exemples restent verts (les exemples ne sont plus de vrais plans), les règles ne se déclenchent
#      plus sur un vrai plan. Sans effet si un test lit un vrai plan hors de rego/ (le pipeline de la MR
#      échoue alors : la prévention d'E19 est déjà en place) ;
#   3. plateforme/infra : le modèle caché .plan (M05), que les jobs plan:* étendent et qui appelle
#      « !reference [.validation:conftest-plan, script] » (M29-E10), reçoit « allow_failure: true » dans
#      .gitlab-ci.yml : le job de plan échoue sur le refus de conftest, le pipeline passe. Sans effet si
#      .gitlab-ci.yml n'a pas de clé .plan.
# Le plan est évalué comme dans le job de plan : espaces de la CI, --data rego/donnees et un contexte
# {"contexte": {"etat": "socle", "etiquettes_mr": []}} (WB_M29_E19_ETAT) ; sans contexte, la règle
# « contexte absent » de M29-E03 refuserait tout et masquerait la panne.
# Vérification : localement (conftest et opa sur adm01), le plan n'est plus refusé par les politiques de
# l'étiquette que lit la CI (1, 2), ou la surcharge est sur main (3). Annulation : commits inverses si
# les fichiers sont encore dans l'état injecté (infra d'abord, puis politiques), puis retrait de
# l'étiquette posée par la panne si plateforme/infra ne l'utilise plus.

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
_E19_CLE_INFRA=E19-infra

# _e19_rapatrier DOSSIER [RÉF=main] — copie locale de rego/ de plateforme/politiques à la référence.
_e19_rapatrier() {
  local dest="$1" ref="${2:-main}" c
  rm -rf -- "$dest"
  mkdir -p "$dest"
  while IFS= read -r c; do
    [[ "$c" == rego/* ]] || continue
    mkdir -p "$dest/$(dirname "$c")"
    m29_git_lire "$_E19_POL" "$c" "$ref" >"$dest/$c" 2>/dev/null || return 1
  done < <(m29_git_arbre "$_E19_POL" rego "$ref")
  [[ -d "$dest/rego/tofu" ]]
}

# _e19_ref_ci — étiquette de plateforme/politiques que lit la CI de plateforme/infra (entrée
# politiques_ref du composant validation, M29-E10) ; vide si la CI n'en épingle pas.
_e19_ref_ci() {
  m29_git_lire "$_E19_INFRA" .gitlab-ci.yml 2>/dev/null |
    yq -r '[.include[]? | select((.component // "") | test("/validation@")) | .inputs.politiques_ref // ""] | .[0] // ""' 2>/dev/null |
    grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' || true
}

# _e19_etiquette_suivante — vX.Y.(Z+1) après la plus haute étiquette vX.Y.Z de plateforme/politiques.
_e19_etiquette_suivante() {
  local d
  d="$(m29_api GET "projects/$(m29_enc "$_E19_POL")/repository/tags?per_page=100" 2>/dev/null |
    jq -r '.[]?.name' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1)"
  [[ -n "$d" ]] || return 1
  d="${d#v}"
  printf 'v%s.%s.%s\n' "${d%%.*}" "$(cut -d. -f2 <<<"$d")" "$(($(cut -d. -f3 <<<"$d") + 1))"
}

# _e19_publier — après le commit de Lucas sur main de plateforme/politiques : étiquette suivante, puis
# montée de politiques_ref dans plateforme/infra (commit de Lucas). Rien si la CI n'épingle pas.
_e19_publier() {
  local ref neuf tmp esc
  ref="$(_e19_ref_ci)"
  if [[ -z "$ref" ]]; then
    m29_journal E19 "plateforme/infra n'épingle pas politiques_ref : commit sur main seulement"
    return 0
  fi
  neuf="$(_e19_etiquette_suivante)" || return 1
  m29_api POST "projects/$(m29_enc "$_E19_POL")/repository/tags" --data-urlencode "tag_name=$neuf" \
    --data-urlencode "ref=main" --data-urlencode "message=Politiques $neuf : refonte des règles OpenTofu (Lucas, M29-E19)" >/dev/null || return 1
  m29_poser E19 etiquette "$neuf"
  m29_journal E19 "étiquette $neuf posée sur main de $_E19_POL"
  tmp="$(m29_etat E19)/infra-gitlab-ci.yml"
  m29_git_lire "$_E19_INFRA" .gitlab-ci.yml >"$tmp.orig" 2>/dev/null || return 1
  esc="${ref//./\\.}"
  sed -E "s/^([[:space:]]*politiques_ref:[[:space:]]*[\"']?)${esc}([\"']?)/\1${neuf}\2/" "$tmp.orig" >"$tmp"
  [[ "$(yq -r '[.include[]? | select((.component // "") | test("/validation@")) | .inputs.politiques_ref // ""] | .[0] // ""' "$tmp" 2>/dev/null)" == "$neuf" ]] || return 1
  m29_git_debut "$_E19_CLE_INFRA" "$_E19_INFRA"
  m29_git_fichier "$_E19_CLE_INFRA" .gitlab-ci.yml "$tmp"
  m29_git_valider "$_E19_CLE_INFRA" "ci: politiques $neuf (refonte des règles OpenTofu) (M29-E19)

Montée de l'étiquette des politiques, rien d'autre. -- Lucas" || return 1
}

# _e19_retirer_etiquette — retire l'étiquette posée par la panne si plateforme/infra ne la lit plus
# (après le commit inverse, ou après ta réparation par une étiquette corrigée).
_e19_retirer_etiquette() {
  local t
  t="$(m29_lire E19 etiquette)"
  [[ -n "$t" ]] || return 0
  if [[ "$(_e19_ref_ci)" == "$t" ]]; then
    wb_avert "plateforme/infra lit encore l'étiquette $t de $_E19_POL : étiquette gardée (corrige politiques_ref)"
    return 0
  fi
  if m29_api DELETE "projects/$(m29_enc "$_E19_POL")/repository/tags/$(m29_enc "$t")" >/dev/null 2>&1; then
    m29_journal E19 "étiquette $t retirée (posée par la panne, plus lue par la CI)"
  else
    wb_avert "étiquette $t de $_E19_POL non retirée (protégée ?) : plus lue par la CI, sans effet"
  fi
  m29_oublier E19 etiquette
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
  local d ref
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
  ref="$(_e19_ref_ci)"
  if [[ -n "$ref" ]]; then
    _e19_rapatrier "$(m29_etat E19)/ref" "$ref" || { echo "Étiquette $ref de $_E19_POL illisible (politiques_ref de $_E19_INFRA)." >&2; return 1; }
    if ! _e19_refuse "$(m29_etat E19)/ref"; then
      echo "La CI de $_E19_INFRA lit les politiques $ref, qui ne refusent PAS le plan de référence :" >&2
      echo "publie une étiquette de politiques à jour et monte politiques_ref avant cet exercice." >&2
      return 1
    fi
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
        # Règles, entrées simulées des tests ET plans d'exemple (rego/exemples/*.json) : le job des
        # exemples du composant validation reste vert, les exemples ne sont plus de vrais plans.
        while IFS= read -r f; do
          sed -i 's/resource_changes/resource_change/g' "$f"
        done < <(grep -rl 'resource_changes' "$apres/rego" --include='*.rego' --include='*.json')
        m29_poser E19 message "refactor(politiques): harmoniser le nom de l'entrée des règles OpenTofu (M29-E19)

Mocks des tests et exemples mis à jour, opa test vert. -- Lucas"
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
      # Variante 1 : le job des exemples du composant échouerait sur une MR : poussée directe seulement.
      if ((n == 1)); then
        m29_git_valider E19 "$(m29_lire E19 message)" direct || return $?
      else
        m29_git_valider E19 "$(m29_lire E19 message)" || return $?
      fi
      _e19_publier || return 1
      ;;
    3)
      local gci job=.plan tmp
      gci="$(m29_git_lire "$_E19_INFRA" .gitlab-ci.yml 2>/dev/null)" || return 10
      # Le modèle .plan doit exister ET appeler la vérification des plans (sinon rien ne refuse le plan).
      JOB="$job" yq -e '.[strenv(JOB)] | tostring | test("conftest")' <<<"$gci" >/dev/null 2>&1 || return 10
      [[ "$(JOB="$job" yq -r '.[strenv(JOB)].allow_failure // ""' <<<"$gci" 2>/dev/null)" == true ]] && return 10
      tmp="$d/gitlab-ci.yml"
      # Insertion d'UNE ligne sous « .plan: » (indentation de la ligne suivante) : le diff du commit ne
      # montre que la surcharge ; repli sur yq (qui reformate le fichier) si la forme est inattendue.
      awk '!fait && /^\.plan:[[:space:]]*(#.*)?$/ { print; dans = 1; next }
           dans && !fait && /^[[:space:]]+[^[:space:]#]/ { match($0, /^[[:space:]]+/); print substr($0, 1, RLENGTH) "allow_failure: true"; fait = 1 }
           { print }' <<<"$gci" >"$tmp"
      if [[ "$(JOB="$job" yq -r '.[strenv(JOB)].allow_failure // ""' "$tmp" 2>/dev/null)" != true ]]; then
        JOB="$job" yq '.[strenv(JOB)].allow_failure = true' <<<"$gci" >"$tmp" || return 10
      fi
      m29_poser E19 job "$job"
      m29_git_debut E19 "$_E19_INFRA"
      m29_git_fichier E19 .gitlab-ci.yml "$tmp"
      m29_git_valider E19 "ci: ne plus bloquer les MR sur les refus de conftest le temps de corriger les faux positifs (M29-E19)

Les jobs de plan restent visibles en orange. -- Lucas" || return $?
      ;;
  esac
  m29_journal E19 "variante $n posée"
}

_m29E19_defaire() {
  m29_git_annuler "$_E19_CLE_INFRA" || true
  m29_git_annuler E19 || true
  _e19_retirer_etiquette || true
}

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
      # Ce que lit la CI : l'étiquette posée (et politiques_ref monté), ou main si rien n'est épinglé.
      local t
      t="$(m29_lire E19 etiquette)"
      if [[ -n "$t" ]]; then
        [[ "$(_e19_ref_ci)" == "$t" ]] && m29_git_injecte "$_E19_CLE_INFRA" || return 1
      fi
      d="$(m29_etat E19)/verif"
      _e19_rapatrier "$d" "${t:-main}" || return 1
      ! _e19_refuse "$d"
      ;;
  esac
}

annuler_E19() {
  _m29E19_defaire
  rm -rf -- "$(m29_etat E19)/avant" "$(m29_etat E19)/apres" "$(m29_etat E19)/verif" "$(m29_etat E19)/ref"
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
