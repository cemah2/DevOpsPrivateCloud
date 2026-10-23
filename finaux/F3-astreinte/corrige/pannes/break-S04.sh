# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et expressions yq entre apostrophes
# break-S04.sh — F3-S04 « Lundi : pourquoi personne n'a été prévenu ? » (chaîne d'alerte)
#
# Incident EN CHAÎNE avec S03 : il s'injecte après la clôture de S03, mais pose l'état qu'aurait trouvé
# l'astreinte lundi matin (la chaîne d'alerte de MédiAgenda production était déjà muette). Le dead man's
# switch de mon01 (Watchdog, route « null » de l'alerte Watchdog, sondes du témoin) n'est jamais touché.
#   1. Route : commit de Lucas dans plateforme/observabilite (kps/values.yaml) qui ajoute EN TÊTE de
#      l'arbre une route equipe="mediagenda", environnement="prod" → récepteur "null" (« couper le bruit
#      pendant la reprise Flyway »), et qui « met à jour » les essais de routage
#      (alertmanager/routes-tests.txt) pour que la CI passe. Toute alerte de MédiAgenda prod s'arrête là.
#   2. Règle : commit de Lucas dans la règle MediagendaLatenceElevee (regles/…) : « for: 12h »
#      (« éviter les faux positifs du lundi matin ») ; l'alerte reste « pending » et ne part jamais.
#   3. Silence : silence de 7 jours créé par lucas.martin dans l'Alertmanager du cluster, matcher
#      equipe="mediagenda" (toutes les alertes de l'équipe, tous environnements), commentaire
#      « CHG-3303 reprise Flyway recette » : il ne visait que la recette.
# Variantes 1 et 2 : si la CI de plateforme/observabilite refuse la MR, la variante est sans effet et la
# suivante est essayée. Annulation : commit inverse si intact ; silence expiré s'il est encore actif.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_f3-commun.sh
source "$WB_ROOT/finaux/F3-astreinte/corrige/pannes/_f3-commun.sh"

_S04_OBS="${WB_F3_PROJET_OBSERVABILITE:-plateforme/observabilite}"
_S04_VALEURS="${WB_F3_FICHIER_KPS:-kps/values.yaml}"
_S04_TESTS="${WB_F3_FICHIER_ROUTES_TESTS:-alertmanager/routes-tests.txt}"
_S04_ALERTE=MediagendaLatenceElevee

# _s04_config_am — configuration chargée par l'Alertmanager du cluster (YAML).
_s04_config_am() { _f3p_am GET status 2>/dev/null | jq -r '.config.original // empty'; }

# _s04_regle_duree — « for » de la règle MediagendaLatenceElevee (prod) chargée dans Prometheus (secondes).
_s04_regle_duree() {
  prom_api "rules?type=alert" 2>/dev/null | jq -r --arg a "$_S04_ALERTE" \
    '[.data.groups[].rules[] | select(.name == $a) | select(.query | test("prod"))][0].duration // empty'
}

_s04_apps_obs() { _f3p_apps_du_depot "$_S04_OBS"; }

# --- Variante 1 : route vers « null » -------------------------------------------------------------------

_s04_v1_poser() {
  local d
  d="$(_f3p_etat S04)/v1"
  mkdir -p "$d"
  _f3p_gl_fichier "$_S04_OBS" "$_S04_VALEURS" >"$d/values.orig" 2>/dev/null || return 10
  yq -e '.alertmanager.config.route.routes | length > 0' "$d/values.orig" >/dev/null 2>&1 || return 10
  yq '.alertmanager.config.route.routes = [{"receiver": "null", "matchers": ["equipe = \"mediagenda\"", "environnement = \"prod\""]}] + .alertmanager.config.route.routes' \
    "$d/values.orig" >"$d/values.neuf" || return 1
  if _f3p_gl_fichier "$_S04_OBS" "$_S04_TESTS" >"$d/tests.orig" 2>/dev/null; then
    awk -F'|' 'BEGIN {OFS = "|"}
      /^[[:space:]]*#/ || NF < 2 {print; next}
      $2 ~ /equipe=mediagenda/ && $2 ~ /environnement=prod/ {
        w = length($1); r = "null"; while (length(r) < w) r = r " "; $1 = r; print; next }
      {print}' "$d/tests.orig" >"$d/tests.neuf"
    _f3p_commit S04 v1 "$_S04_OBS" "fix(alertmanager): couper le bruit de MédiAgenda prod pendant la reprise Flyway

Les alertes de prod partent pendant les migrations, on les coupe le temps
de la reprise (je remets après). Essais de routage mis à jour. -- Lucas" lucas \
      "$_S04_VALEURS" "$d/values.neuf" "$_S04_TESTS" "$d/tests.neuf" || return $?
  else
    _f3p_commit S04 v1 "$_S04_OBS" "fix(alertmanager): couper le bruit de MédiAgenda prod pendant la reprise Flyway" lucas \
      "$_S04_VALEURS" "$d/values.neuf" || return $?
  fi
  # shellcheck disable=SC2046  # une Application par ligne
  _f3p_rafraichir $(_s04_apps_obs)
  _f3p_attendre 600 _s04_v1_constat || return 10
}
_s04_v1_constat() {
  _s04_config_am | yq -e '.route.routes[0].receiver == "null"
    and (.route.routes[0].matchers // [] | map(test("environnement")) | any)
    and (.route.routes[0].matchers // [] | map(test("mediagenda")) | any)' - >/dev/null 2>&1
}

# --- Variante 2 : « for » démesuré --------------------------------------------------------------------

_s04_v2_poser() {
  local d chemin dur
  d="$(_f3p_etat S04)/v2"
  mkdir -p "$d"
  dur="$(_s04_regle_duree)"
  [[ "$dur" =~ ^[0-9]+$ ]] && ((dur <= 3600)) || return 10
  chemin="$(_f3p_gl_chercher "$_S04_OBS" "alert: $_S04_ALERTE" | grep -E '^regles/.*\.ya?ml$' | grep -v '/tests/' | head -n 1)"
  [[ -n "$chemin" ]] || return 10
  _f3p_ecrire S04 v2-chemin "$chemin"
  _f3p_gl_fichier "$_S04_OBS" "$chemin" >"$d/regle.orig" || return 1
  A="$_S04_ALERTE" yq '(.spec.groups[].rules[] | select(.alert == strenv(A)) | select(.expr | test("prod")) | .for) = "12h"' \
    "$d/regle.orig" >"$d/regle.neuf" || return 1
  cmp -s "$d/regle.orig" "$d/regle.neuf" && return 10
  _f3p_commit S04 v2 "$_S04_OBS" "fix(regles): MediagendaLatenceElevee moins nerveuse

Elle sonne tous les lundis matin à l'ouverture des cabinets, c'est du bruit. -- Lucas" lucas \
    "$chemin" "$d/regle.neuf" || return $?
  # shellcheck disable=SC2046
  _f3p_rafraichir $(_s04_apps_obs)
  _f3p_attendre 600 _s04_v2_constat || return 10
}
_s04_v2_constat() {
  local dur
  dur="$(_s04_regle_duree)"
  [[ "$dur" =~ ^[0-9]+$ ]] && ((dur >= 43200))
}

# --- Variante 3 : silence trop large ------------------------------------------------------------------

_s04_v3_poser() {
  local corps id
  corps="$(jq -n --arg debut "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg fin "$(date -u -d '+7 days' +%Y-%m-%dT%H:%M:%SZ)" '{
    matchers: [{name: "equipe", value: "mediagenda", isRegex: false, isEqual: true}],
    startsAt: $debut, endsAt: $fin, createdBy: "lucas.martin",
    comment: "CHG-3303 reprise Flyway recette (Lucas) — on coupe le temps de la reprise"}')"
  id="$(_f3p_am POST silences "$corps" | jq -r '.silenceID // empty')" || id=""
  [[ -n "$id" ]] || return 1
  _f3p_ecrire S04 v3-silence "$id"
  _f3p_journal S04 "silence $id (equipe=mediagenda, 7 jours) créé au nom de lucas.martin"
}
_s04_v3_constat() {
  local id
  id="$(_f3p_lire S04 v3-silence)"
  [[ -n "$id" ]] && _f3p_am GET "silence/$id" | jq -e '.status.state == "active"' >/dev/null 2>&1
}
_s04_v3_defaire() {
  local id
  id="$(_f3p_lire S04 v3-silence)"
  if [[ -n "$id" ]] && _s04_v3_constat; then
    _f3p_am DELETE "silence/$id" >/dev/null 2>&1 || wb_avert "silence $id à expirer à la main (amtool silence expire $id)"
    _f3p_journal S04 "silence $id expiré"
  fi
  _f3p_oublier S04 v3-silence
}

# --- Mécanique commune ------------------------------------------------------------------------------------

_f3p_S04_une() {
  case "$1" in
    1) _s04_v1_poser ;;
    2) _s04_v2_poser ;;
    3) _s04_v3_poser ;;
  esac
}
_f3p_S04_defaire() {
  case "$1" in
    1) _f3p_retablir S04 v1 ;;
    2) _f3p_retablir S04 v2 ;;
    3) _s04_v3_defaire ;;
  esac
}

_s04_injecter() {
  _f3p_preparer S04 || return 1
  _s04_config_am | grep -q . || { echo "Configuration de l'Alertmanager du cluster illisible : $_F3P_REFUS" >&2; return 1; }
  if [[ "$1" != 3 ]]; then echo "Les variantes passent par un commit et la synchronisation d'Argo CD : jusqu'à 15 min…"; fi
  _f3p_essayer S04 3 "$1"
}

panne_S04_v1() { _s04_injecter 1; }
panne_S04_v2() { _s04_injecter 2; }
panne_S04_v3() { _s04_injecter 3; }

verifier_S04() {
  case "$(_f3p_lire S04 variante)" in
    1) _s04_v1_constat ;;
    2) _s04_v2_constat ;;
    3) _s04_v3_constat ;;
    *) return 1 ;;
  esac
}

annuler_S04() {
  local v
  for v in 1 2 3; do _f3p_S04_defaire "$v" || true; done
  # shellcheck disable=SC2046
  _f3p_rafraichir $(_s04_apps_obs 2>/dev/null || true)
  _f3p_oublier S04 variante
}

resume_S04() { echo "aucune alerte reçue pendant la lenteur de MédiAgenda (production)"; }

symptome_S04() {
  _f3p_symptome S04 INC-5904 "Ticket INC-5904 — De : Claire Morel — lundi 11 h 30" \
    "« L'incident de ce matin est clos, merci. Mais les cabinets ont souffert 40 minutes et ni" \
    "l'astreinte ni l'équipe de Julien n'ont reçu la moindre alerte : c'est le support qui nous a" \
    "prévenus. Julien confirme qu'il n'a rien reçu non plus, et le témoin de mon01 n'a rien dit." \
    "Je veux comprendre pourquoi la supervision n'a rien vu, ou rien dit, et que ce soit réparé" \
    "aujourd'hui, avec la preuve que la prochaine fois quelqu'un sera prévenu. »" \
    "Temps cible : 1 h 30."
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main F3 S04 3 "$@"; }
fi
