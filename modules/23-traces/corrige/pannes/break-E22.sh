# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et programmes awk entre apostrophes
# break-E22.sh — M23-E22 « Panne : impossible de passer d'une trace à ses journaux »
#
# Les sources Grafana sont déclarées par le code dans plateforme/observabilite (M23-E08). Toutes les
# variantes sont un commit de Lucas sur le fichier qui les déclare (recherché sur main) :
#   1. Loki → Tempo : l'expression du champ dérivé (matcherRegex) cherche « traceid » au lieu de « trace_id » ;
#   2. Tempo → Loki : tracesToLogsV2.datasourceUid désigne une source qui n'existe pas (UID « …-ancien ») ;
#   3. Tempo → Loki : tracesToLogsV2.datasourceUid désigne la source Loki du locataire « plateforme » : les
#      journaux de MédiAgenda (locataire mediagenda) n'y sont pas.
# Contrôle sur place : la configuration servie par Grafana (/api/frontend/settings) a changé.
# Grafana relit les sources provisionnées soit par son sidecar, soit au redémarrage : si la modification
# n'apparaît pas après la synchronisation, le script redémarre le déploiement Grafana (sans perte de données).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m23-commun.sh
source "$WB_ROOT/modules/23-traces/corrige/pannes/_m23-commun.sh"

_e22_settings() { grafana_api "frontend/settings" 2>/dev/null; }

# _e22_fichier MOTIF — premier fichier YAML de plateforme/observabilite (main) qui contient MOTIF.
_e22_fichier() {
  local f
  for f in $(m23_gl_arbre "$_M23_DEPOT_OBS" "" | grep -E '\.ya?ml$'); do
    if m23_gl_fichier "$_M23_DEPOT_OBS" "$f" 2>/dev/null | grep -q -- "$1"; then
      printf '%s\n' "$f"
      return 0
    fi
  done
  return 1
}

_e22_uid_tempo_logs() {
  _e22_settings | jq -r '[.datasources[]? | select(.type == "tempo") | .jsonData.tracesToLogsV2.datasourceUid // empty][0] // empty'
}
_e22_regex_loki() {
  _e22_settings | jq -r '[.datasources[]? | select(.type == "loki") | .jsonData.derivedFields[]? | .matcherRegex // empty] | join(" ")'
}

_e22_grafana_redemarrer() {
  local d
  d="$(wb_kubectl -n supervision get deploy -l app.kubernetes.io/name=grafana -o name 2>/dev/null | head -n 1)"
  [[ -n "$d" ]] && wb_kubectl -n supervision rollout restart "$d" >/dev/null 2>&1 || true
}

# _e22_attendre_grafana 'condition bash' — attend que Grafana serve la configuration (redémarrage au besoin).
_e22_attendre_grafana() {
  m23_argo_rafraichir supervision "$_M23_TRACES" journaux
  m23_attendre 240 "$@" && return 0
  _e22_grafana_redemarrer
  m23_attendre 300 "$@"
}

_e22_regex_cassee() { [[ "$(_e22_regex_loki)" == *traceid* ]]; }
_e22_uid_vaut() { [[ "$(_e22_uid_tempo_logs)" == "$(m23_lire E22 uid-attendu)" ]]; }

_m23E22_une() {
  local n="$1" f tmp ancien neuf
  tmp="$(m23_etat E22)/tmp"
  mkdir -p "$tmp"
  case "$n" in
    1)
      f="$(_e22_fichier derivedFields)" || return 10
      m23_gl_fichier "$_M23_DEPOT_OBS" "$f" >"$tmp/orig.yaml" || return 1
      grep -q 'matcherRegex:.*trace_id' "$tmp/orig.yaml" || return 10
      # Le champ dérivé de la source du locataire mediagenda (le premier du fichier à défaut).
      if grep -q 'name:.*[Mm]ediagenda' "$tmp/orig.yaml"; then
        awk '/name:.*[Mm]ediagenda/ { dans = 1 } dans && !fait && /matcherRegex:.*trace_id/ { sub(/trace_id/, "traceid"); fait = 1 } { print }' "$tmp/orig.yaml" >"$tmp/neuf.yaml"
      else
        awk '!fait && /matcherRegex:.*trace_id/ { sub(/trace_id/, "traceid"); fait = 1 } { print }' "$tmp/orig.yaml" >"$tmp/neuf.yaml"
      fi
      cmp -s "$tmp/orig.yaml" "$tmp/neuf.yaml" && return 10
      m23_commit E22 v1 "$_M23_DEPOT_OBS" "grafana : champ dérivé Loki aligné sur la convention OpenTelemetry" "$f" "$tmp/neuf.yaml" || return 1
      _e22_attendre_grafana _e22_regex_cassee || { _e22_defaire 1; return 10; }
      ;;
    2 | 3)
      f="$(_e22_fichier tracesToLogsV2)" || return 10
      m23_gl_fichier "$_M23_DEPOT_OBS" "$f" >"$tmp/orig.yaml" || return 1
      ancien="$(awk '/tracesToLogsV2:/ { dans = 1 } dans && /datasourceUid:/ { sub(/.*datasourceUid:[[:space:]]*/, ""); gsub(/["'\''[:space:]]/, ""); print; exit }' "$tmp/orig.yaml")"
      [[ -n "$ancien" ]] || return 10
      if [[ "$n" == 2 ]]; then
        neuf="$ancien-ancien"
      else
        neuf="$(_e22_settings | jq -r '[.datasources[]? | select(.type == "loki" and (.name | test("plateforme"; "i"))) | .uid][0] // empty')"
        [[ -n "$neuf" && "$neuf" != "$ancien" ]] || return 10
      fi
      NEUF="$neuf" awk '/tracesToLogsV2:/ { dans = 1 }
        dans && !fait && /datasourceUid:/ { match($0, /^[[:space:]]*/); print substr($0, 1, RLENGTH) "datasourceUid: \"" ENVIRON["NEUF"] "\""; fait = 1; next }
        { print }' "$tmp/orig.yaml" >"$tmp/neuf.yaml"
      m23_ecrire E22 uid-attendu "$neuf"
      m23_commit E22 "v$n" "$_M23_DEPOT_OBS" "grafana : source des journaux de la vue trace mise à jour" "$f" "$tmp/neuf.yaml" || return 1
      _e22_attendre_grafana _e22_uid_vaut || { _e22_defaire "$n"; return 10; }
      ;;
  esac
  m23_debut E22
  m23_journal E22 "variante $n posée"
}

_e22_defaire() {
  local n="$1"
  if m23_commit_actif E22 "v$n"; then
    m23_retablir E22 "v$n" || true
    m23_argo_rafraichir supervision "$_M23_TRACES" journaux
    _e22_grafana_redemarrer
  else
    m23_oublier E22 "git-v$n"
  fi
}

panne_E22_v1() { m23_preparer && m23_essayer E22 3 1; }
panne_E22_v2() { m23_preparer && m23_essayer E22 3 2; }
panne_E22_v3() { m23_preparer && m23_essayer E22 3 3; }

verifier_E22() {
  case "$WB_VAR" in
    1) m23_commit_actif E22 v1 && _e22_regex_cassee ;;
    2 | 3) m23_commit_actif E22 "v$WB_VAR" && _e22_uid_vaut ;;
    *) return 1 ;;
  esac
}

annuler_E22() {
  case "${WB_VAR:-}" in
    [1-3]) _e22_defaire "$WB_VAR" ;;
    *) local v; for v in 1 2 3; do _e22_defaire "$v"; done ;;
  esac
  m23_oublier E22 uid-attendu
  m23_oublier E22 debut
  m23_oublier E22 tmp
  m23_journal E22 "annulation"
}

resume_E22() {
  echo "Depuis une trace de MédiAgenda, le bouton « Logs for this span » ne mène plus aux journaux (ou à des journaux vides)."
}

symptome_E22() {
  wb_symptome "Ticket INC-5022 — De : Nadia Roussel" \
    "Pendant l'incident de cette nuit, impossible de passer d'une trace à ses journaux : depuis une span" \
    "de MédiAgenda, le lien vers les journaux n'ouvre rien d'utile (erreur, ou requête qui ne renvoie rien)," \
    "et depuis une ligne de journal le lien vers la trace a parfois disparu. La semaine dernière ça marchait :" \
    "c'était tout l'intérêt de M23-E08. Lucas a « rangé » des sources de données." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 23 22"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 23 E22 3 "$@"; }
fi
