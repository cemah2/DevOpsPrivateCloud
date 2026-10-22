# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq/yq entre apostrophes
# break-E40.sh — M21-E40 « Panne : l'alerte sonne sans arrêt »
#
# Le témoin TemoinFileAttenteHaute (gravite=critique, equipe=plateforme : il va à l'astreinte) est
# silencieux au repos. Chaque variante change le comportement de la file témoin ET casse un réglage :
#   1. file en « pics » (45 s au-dessus du seuil toutes les 3 min) et « for: 5m » retiré de la règle
#      témoin (PrometheusRule temoin-metriques de wb-pannes, modifiée sur place par « Lucas », qui
#      voulait « être prévenu plus vite ») : l'alerte s'allume et s'éteint toutes les 3 minutes ;
#   2. file haute en continu (incident connu, ticket ouvert) et MR de Lucas sur les valeurs de kps :
#      repeat_interval: 1m sur la route de l'astreinte : un rappel à chaque group_interval ;
#   3. toutes les files hautes 20 min sur 30 (dix alertes : 2 pods × 5 files) et MR de Lucas :
#      group_by: [alertname, pod, file] sur la route de l'astreinte : dix courriels par épisode au lieu
#      d'un, et autant de résolutions.
# Annulation : file témoin au calme ; règle témoin restaurée si « for » manque encore ; MR inverse
# seulement là où la valeur de la panne est encore en place.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m21-commun.sh
source "$WB_ROOT/modules/21-metriques/corrige/pannes/_m21-commun.sh"

_E40_REGLE=TemoinFileAttenteHaute
_E40_GROUPE='["alertname","pod","file"]'

# _e40_recepteur — récepteur de l'astreinte pour une alerte critique de la plateforme.
_e40_recepteur() {
  local t r=""
  if command -v amtool >/dev/null; then
    t="$(mktemp)"
    m21_am_config >"$t"
    r="$(amtool config routes test --config.file="$t" gravite=critique equipe=plateforme alertname="$_E40_REGLE" 2>/dev/null |
      tr ',' '\n' | grep -m1 -i astreinte)" || r=""
    rm -f "$t"
  fi
  printf '%s\n' "${r:-astreinte-mail}"
}

# _e40_noeuds VALEURS_JSON RÉCEPTEUR — chemins (JSON) des routes qui mènent au récepteur.
_e40_noeuds() {
  jq -c --arg r "$2" '[path(.alertmanager.config.route | .. | select(type == "object" and .receiver == $r))][]' <<<"$1"
}

_e40_t2() {
  local c p
  c="$(cat)"
  while read -r p; do
    [[ -n "$p" ]] || continue
    c="$(P="$p" yq 'setpath((strenv(P) | from_json) + ["repeat_interval"]; "1m")' <<<"$c")"
  done < <(_e40_noeuds "$(yq -o=json '.' <<<"$c")" "$(m21_lire E40 recepteur)")
  printf '%s\n' "$c"
}
_e40_t3() {
  local c p f
  c="$(cat)"
  f="$(m21_etat E40)/group_by.yaml"
  printf '[alertname, pod, file]\n' >"$f"
  while read -r p; do
    [[ -n "$p" ]] || continue
    c="$(P="$p" F="$f" yq 'setpath((strenv(P) | from_json) + ["group_by"]; load(strenv(F)))' <<<"$c")"
  done < <(_e40_noeuds "$(yq -o=json '.' <<<"$c")" "$(m21_lire E40 recepteur)")
  printf '%s\n' "$c"
}
# _e40_inverse CHAMP 'valeur de panne (JSON)' — remet les valeurs d'origine (mémorisées) des routes
# qui portent encore la valeur de la panne.
_e40_inverse() {
  local champ="$1" panne="$2" c j e p orig f
  c="$(cat)"
  j="$(yq -o=json '.' <<<"$c")"
  f="$(m21_etat E40)/orig.yaml"
  while read -r e; do
    [[ -n "$e" ]] || continue
    p="$(jq -c --arg c "$champ" '.p + [$c]' <<<"$e")"
    jq -e --argjson p "$p" --argjson v "$panne" 'getpath($p) == $v' >/dev/null 2>&1 <<<"$j" || continue
    orig="$(jq -c --arg c "$champ" '.[$c]' <<<"$e")"
    if [[ "$orig" == null ]]; then
      c="$(P="$p" yq 'delpaths([strenv(P) | from_json])' <<<"$c")"
    else
      yq -p=json -o=yaml '. style="flow"' <<<"$orig" >"$f"
      c="$(P="$p" F="$f" yq 'setpath(strenv(P) | from_json; load(strenv(F)))' <<<"$c")"
    fi
  done < <(jq -c '.[]' <<<"$(m21_lire E40 origines)")
  rm -f "$f"
  printf '%s\n' "$c"
}
_e40_i2() { _e40_inverse repeat_interval '"1m"'; }
_e40_i3() { _e40_inverse group_by "$_E40_GROUPE"; }

_e40_regle_sans_for() {
  wb_kubectl -n "$_M21_NS" get prometheusrules.monitoring.coreos.com temoin-metriques -o json 2>/dev/null |
    jq -e --arg a "$_E40_REGLE" '[.spec.groups[].rules[] | select(.alert == $a) | has("for")] | length > 0 and all(. == false)' >/dev/null 2>&1
}
_e40_config_contient() { m21_am_config | yq -o=json '.' 2>/dev/null | jq -e "$1" >/dev/null 2>&1; }
_e40_effet() {
  case "$1" in
    1) _e40_regle_sans_for ;;
    2) _e40_config_contient '[.. | objects | select(.repeat_interval? == "1m")] | length > 0' ;;
    3) _e40_config_contient "[.. | objects | select(.group_by? == $_E40_GROUPE)] | length > 0" ;;
  esac
}

_m21E40_une() {
  local n="$1" f v
  m21_ecrire E40 variante "$n"
  case "$n" in
    1)
      m21_sauver_objet E40 prometheusrules.monitoring.coreos.com temoin-metriques "$_M21_NS"
      wb_kubectl -n "$_M21_NS" get prometheusrules.monitoring.coreos.com temoin-metriques -o json |
        jq --arg a "$_E40_REGLE" '
          del(.metadata.resourceVersion, .metadata.managedFields)
          | .metadata.annotations["medisphere.internal/modifie-par"] = "lucas.martin"
          | (.spec.groups[].rules[] | select(.alert == $a)) |= del(.for)' |
        wb_kubectl replace -f - >/dev/null || return 1
      m21_temoin_etat '.mode_file = "pics"' || return 1
      ;;
    2 | 3)
      f="$(m21_git_valeurs_kps)" || return 10
      m21_ecrire E40 recepteur "$(_e40_recepteur)"
      v="$(m21_git_lire "$_M21_PROJ_OBS" "$f" | yq -o=json '.' 2>/dev/null)" || return 10
      m21_ecrire E40 origines "$(jq -c --arg r "$(m21_lire E40 recepteur)" '
        [path(.alertmanager.config.route | .. | select(type == "object" and .receiver == $r)) as $p
         | {p: $p, repeat_interval: (getpath($p).repeat_interval // null), group_by: (getpath($p).group_by // null)}]' <<<"$v")"
      [[ "$(m21_lire E40 origines | jq 'length')" -gt 0 ]] || return 10
      if ((n == 2)); then
        m21_git_transformer E40 valeurs "$_M21_PROJ_OBS" "$f" \
          "fix(alertmanager): l'astreinte doit être relancée tant que ce n'est pas réglé (M21-E40)" _e40_t2 || return
        m21_temoin_etat '.mode_file = "continu"' || return 1
      else
        m21_git_transformer E40 valeurs "$_M21_PROJ_OBS" "$f" \
          "feat(alertmanager): un courriel par pod pour savoir où regarder (M21-E40)" _e40_t3 || return
        m21_temoin_etat '.mode_file = "episodes"' || return 1
      fi
      ;;
  esac
  m21_journal E40 "variante $n posée"
  m21_attendre 300 _e40_effet "$n" || { _e40_defaire "$n"; return 10; }
}

_e40_defaire() {
  case "$1" in
    1)
      if _e40_regle_sans_for; then
        m21_restaurer_objet E40 prometheusrules.monitoring.coreos.com temoin-metriques "$_M21_NS"
      else
        m21_oublier_objet E40 prometheusrules.monitoring.coreos.com temoin-metriques "$_M21_NS"
      fi
      ;;
    2) m21_git_defaire E40 valeurs _e40_i2 "revert(alertmanager): repeat_interval de l'astreinte rétabli (M21-E40, annulation)" ;;
    3) m21_git_defaire E40 valeurs _e40_i3 "revert(alertmanager): regroupement de l'astreinte rétabli (M21-E40, annulation)" ;;
  esac
  return 0
}

panne_E40_v1() { m21_preparer && m21_essayer E40 3 1; }
panne_E40_v2() { m21_preparer && m21_essayer E40 3 2; }
panne_E40_v3() { m21_preparer && m21_essayer E40 3 3; }

verifier_E40() { _e40_effet "$WB_VAR"; }

annuler_E40() {
  local v="${WB_VAR:-}"
  [[ "$v" =~ ^[1-3]$ ]] || v="$(m21_lire E40 variante)"
  [[ -n "$v" ]] && _e40_defaire "$v"
  m21_temoin_etat '.mode_file = "calme"' 2>/dev/null || wb_avert "file témoin non remise au calme"
  m21_oublier E40 variante
  m21_oublier E40 origines
  m21_oublier E40 recepteur
  m21_journal E40 "annulation"
}

resume_E40() { echo "L'astreinte reçoit des dizaines de courriels TemoinFileAttenteHaute pour le même problème."; }

symptome_E40() {
  wb_symptome "Ticket INC-4840 — De : Nadia Roussel" \
    "Ma boîte astreinte@ se remplit de courriels TemoinFileAttenteHaute (service de rappels témoin," \
    "wb-pannes) : des dizaines dans l'heure, pour ce qui est visiblement le même problème. À ce" \
    "rythme, je vais finir par ne plus les lire, et c'est comme ça qu'on rate la vraie. Lucas a" \
    "« amélioré la réactivité » de quelque chose. Je veux UN courriel utile par problème." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 21 40"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 21 E40 3 "$@"; }
fi
