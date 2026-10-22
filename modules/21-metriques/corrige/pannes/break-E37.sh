# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq/yq entre apostrophes
# break-E37.sh — M21-E37 « Panne : les tableaux de bord sont vides »
#
# Toutes les variantes passent par une MR de lucas.martin dans plateforme/observabilite :
#   1. tableaux/ : variable de requête d'un tableau (« label_values(…, namespace) ») réécrite sur une
#      étiquette qui n'existe pas (kubernetes_namespace, « comme dans l'ancien Grafana d'InfoGér ») :
#      la liste déroulante est vide, tous les panneaux qui l'utilisent aussi ;
#   2. regles/ : règle d'enregistrement utilisée par un tableau renommée (« :taux » → « :rate ») sans
#      mettre à jour les tableaux : « No data » ;
#   3. valeurs de kps : UID de la source de données Prometheus de Grafana changé (« UID parlant ») :
#      les tableaux qui citent l'ancien UID en dur affichent « Datasource … was not found » (variante
#      retenue seulement si un tableau cite l'UID en dur) ;
#   4. valeurs de kps : URL de la source de données repointée de Thanos Query vers un Prometheus
#      (Service sans tête prometheus-operated) : plus de données au-delà de la rétention locale, plus
#      de sous-échantillonnage (retenue seulement s'il existe des données de plus de 16 jours).
# Annulation : MR inverse, seulement si la marque est encore dans le fichier.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m21-commun.sh
source "$WB_ROOT/modules/21-metriques/corrige/pannes/_m21-commun.sh"

_E37_VAR=""
_E37_ANCIEN=""
_E37_NOUVEAU=""
_E37_URL_REPLIQUE="http://prometheus-operated.supervision.svc:9090/"
_E37_RE='label_values\((?<a>.*),\s*(?<l>[A-Za-z_][A-Za-z0-9_]*)\)'
_E37_RE_INV='label_values\((?<a>.*),\s*kubernetes_(?<l>[A-Za-z0-9_]+)\)'

# --- variante 1 : variable de tableau ----------------------------------------------------------
_e37_t1() {
  jq --indent 2 --arg v "$_E37_VAR" --arg re "$_E37_RE" '
    def casse: if type == "string" then sub($re; "label_values(\(.a), kubernetes_\(.l))") else . end;
    (.templating.list[] | select(.name == $v)) |= (
      (if has("definition") then .definition |= casse else . end)
      | (if (.query | type) == "object" then .query.query |= casse else .query |= casse end))'
}
_e37_i1() {
  jq --indent 2 --arg v "$_E37_VAR" --arg re "$_E37_RE_INV" '
    def repare: if type == "string" then sub($re; "label_values(\(.a), \(.l))") else . end;
    (.templating.list[] | select(.name == $v)) |= (
      (if has("definition") then .definition |= repare else . end)
      | (if (.query | type) == "object" then .query.query |= repare else .query |= repare end))'
}
# _e37_choisir_tableau — « chemin variable » d'un tableau de tableaux/ qui a une variable label_values
# rafraîchie au chargement (préférence aux tableaux de MédiAgenda).
_e37_choisir_tableau() {
  local p t v liste
  t="$(mktemp)"
  liste="$(m21_git_arbre "$_M21_PROJ_OBS" tableaux | grep -E '\.json$')" || liste=""
  while read -r p; do
    m21_git_lire "$_M21_PROJ_OBS" "$p" >"$t" 2>/dev/null || continue
    v="$(jq -r '[.templating.list[]? | select(.type == "query" and (.refresh // 0) != 0)
                 | select(((.definition // "") + (if (.query | type) == "object" then .query.query else (.query // "") end))
                          | test("label_values\\(.*,\\s*[A-Za-z_][A-Za-z0-9_]*\\)") and (test("kubernetes_") | not))
                 | .name][0] // empty' "$t" 2>/dev/null)"
    if [[ -n "$v" ]]; then
      rm -f "$t"
      printf '%s %s\n' "$p" "$v"
      return 0
    fi
  done < <(grep -i mediagenda <<<"$liste"; grep -vi mediagenda <<<"$liste")
  rm -f "$t"
  return 1
}
_e37_cm_contient() {
  wb_kubectl -n "$_M21_SUP" get configmaps -l "${2:-grafana_dashboard=1}" -o json 2>/dev/null | grep -qF -- "$1"
}

# --- variante 2 : règle d'enregistrement --------------------------------------------------------
_e37_t2() { sed -E "s/^([[:space:]-]*record:[[:space:]]*['\"]?)${_E37_ANCIEN}(['\"]?[[:space:]]*)$/\1${_E37_NOUVEAU}\2/"; }
_e37_i2() { sed -E "s/^([[:space:]-]*record:[[:space:]]*['\"]?)${_E37_NOUVEAU}(['\"]?[[:space:]]*)$/\1${_E37_ANCIEN}\2/"; }
# _e37_choisir_regle — « fichier ancien_nom » : règle d'enregistrement citée par un tableau.
_e37_choisir_regle() {
  local p t tab r
  t="$(mktemp -d)"
  while read -r p; do
    m21_git_lire "$_M21_PROJ_OBS" "$p" >>"$t/tableaux" 2>/dev/null || true
  done < <(m21_git_arbre "$_M21_PROJ_OBS" tableaux | grep -E '\.json$')
  while read -r p; do
    [[ "$p" =~ \.ya?ml$ ]] || continue
    m21_git_lire "$_M21_PROJ_OBS" "$p" >"$t/regle" 2>/dev/null || continue
    while read -r r; do
      [[ "$r" =~ ^[a-zA-Z_][a-zA-Z0-9_:]*:[a-zA-Z0-9_]+$ ]] || continue
      if grep -qF -- "$r" "$t/tableaux" 2>/dev/null; then
        tab="$p $r"
        break 2
      fi
    done < <(yq '.spec.groups[].rules[].record // ""' "$t/regle" 2>/dev/null | grep -v '^$')
  done < <(m21_git_arbre "$_M21_PROJ_OBS" regles)
  rm -rf -- "$t"
  [[ -n "${tab:-}" ]] && printf '%s\n' "$tab"
}

# --- variantes 3 et 4 : source de données de Grafana (valeurs de kps) ----------------------------
_e37_t3() {
  A="$_E37_ANCIEN" N="$_E37_NOUVEAU" yq '
    (.grafana.sidecar | select(has("datasources")) | .datasources | select(.uid == strenv(A) or (.uid == null and strenv(A) == "prometheus" and has("enabled"))) | .uid) = strenv(N)
    | (.grafana | select(has("additionalDataSources")) | .additionalDataSources[] | select(.uid == strenv(A)) | .uid) = strenv(N)'
}
_e37_i3() {
  A="$_E37_NOUVEAU" N="$_E37_ANCIEN" yq '
    (.grafana.sidecar | select(has("datasources")) | .datasources | select(.uid == strenv(A)) | .uid) = strenv(N)
    | (.grafana | select(has("additionalDataSources")) | .additionalDataSources[] | select(.uid == strenv(A)) | .uid) = strenv(N)'
}
_e37_t4() {
  N="$_E37_URL_REPLIQUE" yq '
    (.grafana.sidecar | select(has("datasources")) | .datasources | select((.url // "") | test("thanos")) | .url) = strenv(N)
    | (.grafana | select(has("additionalDataSources")) | .additionalDataSources[] | select(.isDefault == true and ((.url // "") | test("thanos"))) | .url) = strenv(N)'
}
_e37_i4() {
  A="$_E37_URL_REPLIQUE" N="$_E37_ANCIEN" yq '
    (.grafana.sidecar | select(has("datasources")) | .datasources | select(.url == strenv(A)) | .url) = strenv(N)
    | (.grafana | select(has("additionalDataSources")) | .additionalDataSources[] | select(.url == strenv(A)) | .url) = strenv(N)'
}
_e37_uid_defaut() {
  grafana_api frontend/settings 2>/dev/null | jq -r '[.datasources[] | select(.isDefault == true)][0].uid // empty'
}
_e37_uid_absent() { ! grafana_api frontend/settings 2>/dev/null | jq -e --arg u "$1" '[.datasources[] | select(.uid == $u)] | length > 0' >/dev/null; }
# _e37_tableau_uid_en_dur UID — titre d'un tableau qui cite cet UID en dur (sinon code 1).
_e37_tableau_uid_en_dur() {
  local u t
  while read -r u; do
    t="$(grafana_api "dashboards/uid/$u" 2>/dev/null | jq -r --arg x "$1" '
      if [.dashboard | .. | objects | select(.uid? == $x)] | length > 0 then .dashboard.title else empty end' 2>/dev/null)"
    if [[ -n "$t" ]]; then printf '%s\n' "$t"; return 0; fi
  done < <(grafana_api 'search?type=dash-db&limit=500' 2>/dev/null | jq -r '.[].uid')
  return 1
}

_e37_regle_vue() { [[ "$(m21_prom_nb "count($_E37_NOUVEAU)")" -gt 0 ]]; }

_e37_charger() {
  read -r _E37_VAR _E37_ANCIEN _E37_NOUVEAU <<<"$(m21_lire E37 parametres)"
  [[ "$_E37_VAR" == - ]] && _E37_VAR=""
  [[ "$_E37_ANCIEN" == - ]] && _E37_ANCIEN=""
  [[ "$_E37_NOUVEAU" == - ]] && _E37_NOUVEAU=""
  return 0
}

_m21E37_une() {
  local n="$1" f l p r
  m21_ecrire E37 variante "$n"
  f="$(m21_git_valeurs_kps 2>/dev/null)" || f=""
  case "$n" in
    1)
      l="$(_e37_choisir_tableau)" || return 10
      read -r p _E37_VAR <<<"$l"
      m21_ecrire E37 parametres "$_E37_VAR - -"
      m21_git_transformer E37 fichier "$_M21_PROJ_OBS" "$p" \
        "fix(tableaux): variable alignée sur les étiquettes de l'ancien Grafana (M21-E37)" _e37_t1 || return
      m21_attendre 180 _e37_cm_contient "kubernetes_" || { _e37_defaire 1; return 10; }
      sleep 60 # rechargement par le sidecar de Grafana
      ;;
    2)
      l="$(_e37_choisir_regle)" || return 10
      read -r p _E37_ANCIEN <<<"$l"
      [[ -n "$_E37_ANCIEN" ]] || return 10
      if [[ "$_E37_ANCIEN" == *:taux* ]]; then _E37_NOUVEAU="${_E37_ANCIEN/:taux/:rate}"; else _E37_NOUVEAU="${_E37_ANCIEN}_v2"; fi
      m21_ecrire E37 parametres "- $_E37_ANCIEN $_E37_NOUVEAU"
      m21_git_transformer E37 fichier "$_M21_PROJ_OBS" "$p" \
        "refactor(regles): noms des règles d'enregistrement en anglais (M21-E37)" _e37_t2 || return
      m21_attendre 300 _e37_regle_vue || { _e37_defaire 2; return 10; }
      ;;
    3)
      [[ -n "$f" ]] || return 10
      _E37_ANCIEN="$(_e37_uid_defaut)"
      [[ -n "$_E37_ANCIEN" ]] || return 10
      r="$(_e37_tableau_uid_en_dur "$_E37_ANCIEN")" || return 10
      _E37_NOUVEAU=thanos-query
      [[ "$_E37_ANCIEN" == thanos-query ]] && _E37_NOUVEAU=thanos
      m21_ecrire E37 parametres "- $_E37_ANCIEN $_E37_NOUVEAU"
      m21_ecrire E37 tableau "$r"
      m21_git_transformer E37 fichier "$_M21_PROJ_OBS" "$f" \
        "refactor(grafana): UID parlant pour la source Thanos (M21-E37)" _e37_t3 || return
      m21_attendre 300 _e37_uid_absent "$_E37_ANCIEN" || { _e37_defaire 3; return 10; }
      ;;
    4)
      [[ -n "$f" ]] || return 10
      [[ "$(m21_prom_nb 'count(up offset 16d)')" -gt 0 ]] || return 10
      _E37_ANCIEN="$(m21_git_lire "$_M21_PROJ_OBS" "$f" | yq '.grafana.sidecar.datasources.url // ([.grafana.additionalDataSources[]? | select(.isDefault == true) | .url][0]) // ""')"
      [[ "$_E37_ANCIEN" == *thanos* ]] || return 10
      m21_ecrire E37 parametres "- $_E37_ANCIEN -"
      m21_git_transformer E37 fichier "$_M21_PROJ_OBS" "$f" \
        "perf(grafana): source de données au plus près de Prometheus (M21-E37)" _e37_t4 || return
      m21_attendre 300 _e37_cm_contient prometheus-operated grafana_datasource=1 || { _e37_defaire 4; return 10; }
      ;;
  esac
  m21_journal E37 "variante $n posée"
}

_e37_defaire() {
  _e37_charger
  case "$1" in
    1) [[ -n "$_E37_VAR" ]] && m21_git_defaire E37 fichier _e37_i1 "revert(tableaux): variable rétablie (M21-E37, annulation)" ;;
    2) [[ -n "$_E37_NOUVEAU" ]] && m21_git_defaire E37 fichier _e37_i2 "revert(regles): nom de règle rétabli (M21-E37, annulation)" ;;
    3) [[ -n "$_E37_NOUVEAU" ]] && m21_git_defaire E37 fichier _e37_i3 "revert(grafana): UID de la source rétabli (M21-E37, annulation)" ;;
    4) [[ -n "$_E37_ANCIEN" ]] && m21_git_defaire E37 fichier _e37_i4 "revert(grafana): source repointée vers Thanos Query (M21-E37, annulation)" ;;
  esac
  return 0
}

panne_E37_v1() { m21_preparer && m21_essayer E37 4 1; }
panne_E37_v2() { m21_preparer && m21_essayer E37 4 2; }
panne_E37_v3() { m21_preparer && m21_essayer E37 4 3; }
panne_E37_v4() { m21_preparer && m21_essayer E37 4 4; }

verifier_E37() {
  _e37_charger
  case "$WB_VAR" in
    1) _e37_cm_contient "kubernetes_" ;;
    2) _e37_regle_vue ;;
    3) _e37_uid_absent "$_E37_ANCIEN" ;;
    4) _e37_cm_contient prometheus-operated grafana_datasource=1 ;;
  esac
}

annuler_E37() {
  local v="${WB_VAR:-}"
  [[ "$v" =~ ^[1-4]$ ]] || v="$(m21_lire E37 variante)"
  [[ -n "$v" ]] && _e37_defaire "$v"
  m21_oublier E37 variante
  m21_oublier E37 parametres
  m21_oublier E37 tableau
  m21_journal E37 "annulation"
}

resume_E37() {
  case "${WB_VAR:-}" in
    4) echo "Les tableaux de capacité sur 30 et 90 jours n'ont plus de courbes au-delà de deux semaines." ;;
    3) echo "Le tableau « $(m21_lire E37 tableau) » affiche des panneaux en erreur de source de données." ;;
    *) echo "Des panneaux des tableaux de bord MédiAgenda affichent « No data » depuis la dernière MR de Lucas." ;;
  esac
}

symptome_E37() {
  local l
  case "${WB_VAR:-}" in
    4) l="Les tableaux de capacité sur 30 et 90 jours s'arrêtent à deux semaines ; la vue « 6 mois » est vide." ;;
    3) l="Le tableau « $(m21_lire E37 tableau) » n'affiche plus que des panneaux en erreur." ;;
    *) l="Plusieurs panneaux de nos tableaux affichent « No data » ; l'application tourne normalement." ;;
  esac
  wb_symptome "Ticket INC-4837 — De : Julien Petit" \
    "$l" \
    "Lucas a fusionné une MR « de rangement » dans plateforme/observabilite tout à l'heure." \
    "Claire présente ces tableaux au comité de direction demain matin." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 21 37"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 21 E37 4 "$@"; }
fi
