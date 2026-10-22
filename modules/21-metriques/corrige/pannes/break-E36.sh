# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq/yq entre apostrophes
# break-E36.sh — M21-E36 « Panne : l'alerte ne part plus »
#
# Chaque variante déclenche d'abord l'« essai mensuel de la chaîne d'alerte » des témoins (ConfigMap
# temoin-etat de wb-pannes : essai = 1, annotation medisphere.internal/essai-depuis) : les alertes
# EssaiChaineAlerteCritique (gravite=critique, equipe=plateforme) et EssaiChaineAlerteAvertissement
# deviennent actives et la critique devrait arriver par courriel à l'astreinte. Puis :
#   1. MR de Lucas sur les valeurs de kube-prometheus-stack (plateforme/observabilite) : faute de
#      frappe dans les matchers de la route qui mène au récepteur de l'astreinte (critique → critque) :
#      l'alerte tombe dans la route par défaut, l'astreinte ne reçoit rien ;
#   2. même fichier : smarthost « passé au port de soumission » (…:25 → …:587, où Mailpit n'écoute
#      pas) : tous les envois échouent ;
#   3. même fichier : règle d'inhibition ajoutée à l'envers (source avertissement → cible critique,
#      equal: [equipe]) : l'essai avertissement inhibe l'essai critique ;
#   4. silence de 30 jours sur equipe="plateforme", posé « par erreur » par lucas.martin pendant une
#      maintenance (API d'Alertmanager du cluster, pas Git).
# Les variantes 1 à 3 supposent la configuration d'Alertmanager dans les valeurs (.alertmanager.config,
# M21-E06) ; sinon elles sont « sans effet » et la 4 s'applique.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m21-commun.sh
source "$WB_ROOT/modules/21-metriques/corrige/pannes/_m21-commun.sh"

_E36_ESSAI=EssaiChaineAlerteCritique
_E36_RECEPTEUR=""
_E36_SMTP='smtp.par1.medisphere.internal'

# _e36_recepteur — récepteur de l'essai critique d'après la configuration chargée (amtool), sinon
# astreinte-mail (M21-E16).
_e36_recepteur() {
  local t r=""
  if command -v amtool >/dev/null; then
    t="$(mktemp)"
    m21_am_config >"$t"
    r="$(amtool config routes test --config.file="$t" gravite=critique equipe=plateforme alertname="$_E36_ESSAI" 2>/dev/null |
      tr ',' '\n' | grep -m1 -i astreinte)" || r=""
    rm -f "$t"
  fi
  printf '%s\n' "${r:-astreinte-mail}"
}

_e36_t1() {
  R="$_E36_RECEPTEUR" yq '
    (.alertmanager.config.route | .. | select(tag == "!!map" and .receiver == strenv(R) and has("matchers")) | .matchers[]) |= sub("critique"; "critque")
    | (.alertmanager.config.route | .. | select(tag == "!!map" and .receiver == strenv(R)) | select(has("match")) | .match[]) |= sub("critique"; "critque")'
}
_e36_i1() {
  yq '(.alertmanager.config.route | .. | select(tag == "!!map" and has("matchers")) | .matchers[]) |= sub("critque"; "critique")
      | (.alertmanager.config.route | .. | select(tag == "!!map" and has("match")) | .match[]) |= sub("critque"; "critique")'
}
_e36_t2() { yq '(.alertmanager.config | .. | select(tag == "!!str" and test("^smtp\.par1\.medisphere\.internal:25$"))) |= "smtp.par1.medisphere.internal:587"'; }
_e36_i2() { yq '(.alertmanager.config | .. | select(tag == "!!str" and test("^smtp\.par1\.medisphere\.internal:587$"))) |= "smtp.par1.medisphere.internal:25"'; }
_e36_t3() {
  yq '.alertmanager.config.route as $r | select($r != null)
      | .alertmanager.config.inhibit_rules += [{"source_matchers": ["gravite=\"avertissement\""], "target_matchers": ["gravite=\"critique\""], "equal": ["equipe"]}]
      | .alertmanager.config.inhibit_rules[-1] head_comment = "PLAT-2236 (Lucas) : pas de doublon avertissement + critique pour la même équipe"'
}
_e36_i3() {
  yq 'del(.alertmanager.config.inhibit_rules[] | select((.source_matchers | length) == 1 and .source_matchers[0] == "gravite=\"avertissement\""
                                                    and (.target_matchers | length) == 1 and .target_matchers[0] == "gravite=\"critique\""))'
}

_e36_alerte() { m21_am_alerte "$_E36_ESSAI"; }
_e36_essai_vu() { _e36_alerte | jq -e 'length > 0' >/dev/null 2>&1; }
_e36_effet() {
  case "$1" in
    1) _e36_alerte | jq -e --arg r "$(m21_lire E36 recepteur)" 'length > 0 and all(.[]; [.receivers[].name] | index($r) == null)' >/dev/null 2>&1 ;;
    2) m21_am_config | grep -q "${_E36_SMTP//./\\.}:587" ;;
    3) _e36_alerte | jq -e 'length > 0 and any(.[]; (.status.inhibitedBy // []) | length > 0)' >/dev/null 2>&1 ;;
    4) _e36_alerte | jq -e 'length > 0 and any(.[]; (.status.silencedBy // []) | length > 0)' >/dev/null 2>&1 ;;
  esac
}

_e36_essai() {
  m21_temoin_etat '.essai = 1' || return 1
  wb_kubectl -n "$_M21_NS" annotate configmap temoin-etat "medisphere.internal/essai-depuis=$(m21_maintenant)" --overwrite >/dev/null
}

_m21E36_une() {
  local n="$1" f corps id fin
  m21_ecrire E36 variante "$n"
  case "$n" in
    1 | 2 | 3)
      f="$(m21_git_valeurs_kps)" || return 10
      if ((n == 1)); then
        _E36_RECEPTEUR="$(_e36_recepteur)"
        m21_ecrire E36 recepteur "$_E36_RECEPTEUR"
        m21_git_transformer E36 valeurs "$_M21_PROJ_OBS" "$f" \
          "fix(alertmanager): matchers de la route d'astreinte simplifiés (M21-E36)" _e36_t1 || return
      elif ((n == 2)); then
        m21_git_transformer E36 valeurs "$_M21_PROJ_OBS" "$f" \
          "feat(alertmanager): envoi par le port de soumission 587 (M21-E36)" _e36_t2 || return
      else
        m21_git_transformer E36 valeurs "$_M21_PROJ_OBS" "$f" \
          "feat(alertmanager): inhibition des doublons avertissement/critique (M21-E36)" _e36_t3 || return
      fi
      ;;
    4)
      fin="$(date -u -d '+30 days' +%Y-%m-%dT%H:%M:%S.000Z)"
      corps="$(jq -nc --arg d "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" --arg f "$fin" '{
        matchers: [{name: "equipe", value: "plateforme", isRegex: false, isEqual: true}],
        startsAt: $d, endsAt: $f, createdBy: "lucas.martin",
        comment: "CHG-2236 maintenance de gw02 : on coupe le bruit pendant l intervention (Lucas)"}')"
      id="$(m21_am POST silences -H 'Content-Type: application/json' --data "$corps" | jq -r '.silenceID // empty')" || id=""
      [[ -n "$id" ]] || return 1
      m21_ecrire E36 silence "$id"
      ;;
  esac
  m21_journal E36 "variante $n posée"
  _e36_essai || { _e36_defaire "$n"; return 1; }
  m21_attendre 420 _e36_essai_vu || { _e36_defaire "$n"; return 10; }
  m21_attendre 300 _e36_effet "$n" || { _e36_defaire "$n"; return 10; }
}

_e36_defaire() {
  local n="$1" id s
  case "$n" in
    1) m21_git_defaire E36 valeurs _e36_i1 "revert(alertmanager): matchers de la route d'astreinte rétablis (M21-E36, annulation)" ;;
    2) m21_git_defaire E36 valeurs _e36_i2 "revert(alertmanager): smarthost rétabli (M21-E36, annulation)" ;;
    3) m21_git_defaire E36 valeurs _e36_i3 "revert(alertmanager): inhibition inversée retirée (M21-E36, annulation)" ;;
    4)
      id="$(m21_lire E36 silence)"
      if [[ -n "$id" ]]; then
        s="$(m21_am GET "silence/$id" 2>/dev/null)" || s=""
        if jq -e '.status.state == "active" and .createdBy == "lucas.martin"' >/dev/null 2>&1 <<<"$s"; then
          m21_am DELETE "silence/$id" >/dev/null 2>&1 || wb_avert "silence $id non expiré"
        fi
      fi
      m21_oublier E36 silence
      ;;
  esac
}

_e36_fin_essai() {
  m21_temoin_etat '.essai = 0' 2>/dev/null || true
  wb_kubectl -n "$_M21_NS" annotate configmap temoin-etat medisphere.internal/essai-depuis- >/dev/null 2>&1 || true
}

panne_E36_v1() { m21_preparer && m21_essayer E36 4 1; }
panne_E36_v2() { m21_preparer && m21_essayer E36 4 2; }
panne_E36_v3() { m21_preparer && m21_essayer E36 4 3; }
panne_E36_v4() { m21_preparer && m21_essayer E36 4 4; }

verifier_E36() { _e36_effet "$WB_VAR"; }

annuler_E36() {
  local v="${WB_VAR:-}"
  [[ "$v" =~ ^[1-4]$ ]] || v="$(m21_lire E36 variante)"
  [[ -n "$v" ]] && _e36_defaire "$v"
  m21_oublier E36 variante
  _e36_fin_essai
  m21_oublier E36 recepteur
  m21_journal E36 "annulation"
}

resume_E36() { echo "L'essai de la chaîne d'alerte (EssaiChaineAlerteCritique) est actif depuis 10 min ; l'astreinte n'a rien reçu."; }

symptome_E36() {
  wb_symptome "Ticket INC-4836 — De : Nadia Roussel" \
    "J'ai lancé l'essai mensuel de la chaîne d'alerte à $(date +%H:%M) (alerte EssaiChaineAlerteCritique," \
    "témoins de wb-pannes). Elle est bien active dans Prometheus, mais rien n'est arrivé dans la boîte" \
    "astreinte@ de Mailpit. Lucas a « fait un peu de ménage » dans Alertmanager cette semaine." \
    "Je ne prends pas l'astreinte ce soir sans la preuve que les critiques arrivent." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 21 36"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 21 E36 4 "$@"; }
fi
