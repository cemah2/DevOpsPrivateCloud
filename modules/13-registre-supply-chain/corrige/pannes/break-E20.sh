# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E20.sh — M13-E20 « Panne : la publication de l'image échoue »
#
# Variantes :
#   1. quota de stockage du projet wb-sonde ramené à son occupation actuelle → toute poussée qui ajoute
#      un blob dépasse le quota ;
#   2. règle d'immuabilité trop large sur wb-sonde (dépôts « ** », étiquettes « ** ») → l'étiquette
#      roulante « courant » ne peut plus être réécrite ;
#   3. robot$wb-sonde-ci privé de son droit de poussée (lecture seule) ;
#   4. chrony arrêté sur runner02 et horloge avancée de 40 jours → le certificat de Harbor (30 jours au
#      plus) est vu expiré par le client (seulement si aucun job ne tourne sur runner02) ; les
#      certificats SSH (16 h) aussi : runner02 ne se joint plus qu'en secours (agent QEMU, compte
#      secours), comme en M06-E37 ; la vérification et l'annulation passent par l'agent QEMU.
# Valeurs d'origine dans ~/.local/state/workbook/M13-E20/ (adm01) et /var/lib/workbook/ (runner02).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m13-commun.sh
source "$WB_ROOT/modules/13-registre-supply-chain/corrige/pannes/_m13-commun.sh"

# VMID de runner02 (PLAN §4.5) pour l'agent QEMU de la variante 4.
_E20_VMID_RUNNER="${WB_M13_RUNNER_VMID:-$WB_VMID_RUNNER02}"

_e20_quota() {
  local pid
  pid="$(m13_projet_id wb-sonde)"
  [[ -n "$pid" ]] || return 1
  m13_api GET "quotas?reference=project&reference_id=$pid" | jq -c '.[0] // empty'
}

_e20_regle_large() {
  # Identifiant de la règle « ** / ** » posée par la panne (vide si absente).
  m13_api GET "projects/wb-sonde/immutabletagrules" | jq -r '[.[]? | select(
      any(.scope_selectors.repository[]?; .pattern == "**") and any(.tag_selectors[]?; .pattern == "**"))][0].id // empty'
}

_e20_poser() {
  local q qid used r id
  case "$1" in
    1)
      q="$(_e20_quota)"
      [[ -n "$q" ]] || return 1
      m13_ecrire E20 quota "$(jq -c '{id, hard}' <<<"$q")"
      qid="$(jq -r '.id' <<<"$q")"
      used="$(jq -r '.used.storage // 0' <<<"$q")"
      ((used > 0)) || return 10
      m13_api PUT "quotas/$qid" "{\"hard\":{\"storage\":$used}}" >/dev/null || return 1
      m13_ecrire E20 quota_pose "$used"
      ;;
    2)
      [[ -z "$(_e20_regle_large)" ]] || return 10
      m13_api POST projects/wb-sonde/immutabletagrules \
        '{"disabled":false,"action":"immutable","template":"immutable_template","priority":0,
          "scope_selectors":{"repository":[{"kind":"doublestar","decoration":"repoMatches","pattern":"**"}]},
          "tag_selectors":[{"kind":"doublestar","decoration":"matches","pattern":"**"}]}' >/dev/null || return 1
      [[ -n "$(_e20_regle_large)" ]] || return 1
      ;;
    3)
      r="$(m13_robot wb-sonde-ci)"
      [[ -n "$r" ]] || return 1
      m13_ecrire E20 robot "$r"
      id="$(jq -r '.id' <<<"$r")"
      m13_api PUT "robots/$id" "$(jq -c '.permissions |= map(.access |= map(select(.action != "push")))' <<<"$r")" >/dev/null || return 1
      ;;
    4)
      m13_runner_libre || { wb_avert "un job tourne sur $_M13_RUNNER : variante 4 impossible maintenant"; return 10; }
      wb_exec "$_M13_RUNNER" <<'EOF' || return 1
set -e
systemctl is-active -q chrony
date +%s > "$WB_DIR/$WB_EX.date-avant"
systemctl stop chrony
date -s "@$(( $(date +%s) + 40 * 86400 ))" >/dev/null
journal "chrony arrêté, horloge avancée de 40 jours"
EOF
      ;;
  esac
  m13_journal E20 "variante $1 posée"
}

_e20_defaire() {
  local q id h pose r
  case "$1" in
    1)
      q="$(m13_lire E20 quota)"
      pose="$(m13_lire E20 quota_pose)"
      [[ -n "$q" && -n "$pose" ]] || return 0
      id="$(jq -r '.id' <<<"$q")"
      if m13_api GET "quotas/$id" | jq -e --argjson p "$pose" '.hard.storage == $p' >/dev/null 2>&1; then
        h="$(jq -c '{hard}' <<<"$q")"
        m13_api PUT "quotas/$id" "$h" >/dev/null || wb_avert "annulation : quota de wb-sonde non rétabli"
      fi
      ;;
    2)
      id="$(_e20_regle_large)"
      [[ -z "$id" ]] || m13_api DELETE "projects/wb-sonde/immutabletagrules/$id" >/dev/null || wb_avert "annulation : règle d'immuabilité non retirée"
      ;;
    3)
      r="$(m13_lire E20 robot)"
      [[ -n "$r" ]] || return 0
      id="$(jq -r '.id' <<<"$r")"
      if ! m13_api GET "robots/$id" | jq -e 'any(.permissions[]?.access[]?; .action == "push")' >/dev/null 2>&1; then
        m13_api PUT "robots/$id" "$(jq -c 'del(.secret)' <<<"$r")" >/dev/null || wb_avert "annulation : droits de wb-sonde-ci non rétablis"
      fi
      ;;
    4)
      # Par l'agent QEMU : horloge en avance, les certificats SSH (16 h) sont refusés par runner02
      # (même méthode que M06-E37). L'horloge est d'abord ramenée, puis chrony affine.
      wb_exec_invite "$_E20_VMID_RUNNER" <<'EOF' || wb_avert "annulation : horloge de runner02 non rétablie (agent QEMU) : vérifie-la par la console"
f="$WB_DIR/$WB_EX.date-avant"
if [ -f "$f" ]; then
  ecart=$(( $(date +%s) - $(cat "$f") ))
  if [ "$ecart" -gt 864000 ]; then
    date -s "@$(( $(date +%s) - 40 * 86400 ))" >/dev/null
    journal "annulation : horloge reculée de 40 jours"
  else
    journal "annulation : horloge déjà corrigée (réparation)"
  fi
  systemctl is-active -q chrony || systemctl start chrony
  sleep 5
  chronyc -a makestep >/dev/null 2>&1 || true
  rm -f "$f"
  journal "chrony relancé, horloge resynchronisée"
fi
EOF
      ;;
  esac
}

_e20_injecter() { m13_preparer || return 1; _e20_poser "$1"; }
panne_E20_v1() { _e20_injecter 1; }
panne_E20_v2() { _e20_injecter 2; }
panne_E20_v3() { _e20_injecter 3; }
panne_E20_v4() { _e20_injecter 4; }

# Variante 4 : SSH vers runner02 est refusé (horloge en avance) ; la sonde est lancée par l'agent
# QEMU, et la panne n'est constatée que si la sonde y échoue vraiment (pas un simple échec SSH).
_e20_sonde_echoue_agent() {
  wb_exec_invite "$_E20_VMID_RUNNER" <<'EOF'
if /usr/local/sbin/wb-sonde-registre --etape publication >/dev/null 2>&1; then exit 1; fi
exit 0
EOF
}
verifier_E20() {
  case "$WB_VAR" in
    4) m13_attendre 90 _e20_sonde_echoue_agent ;;
    *) m13_attendre 60 m13_sonde_echoue publication ;;
  esac
}

annuler_E20() {
  case "${WB_VAR:-}" in
    1 | 2 | 3 | 4) _e20_defaire "$WB_VAR" ;;
    *) _e20_defaire 4; _e20_defaire 3; _e20_defaire 2; _e20_defaire 1 ;;
  esac
  m13_journal E20 "annulation"
  rm -rf -- "$(m13_etat E20)"
}

resume_E20() { echo "La publication des images depuis runner02 échoue au moment de la poussée."; }

symptome_E20() {
  wb_symptome "Ticket INC-4020 — De : Julien Petit" \
    "Le job de publication échoue au « push », après une construction réussie. Je l'ai relancé" \
    "deux fois, même résultat. La sonde le reproduit : « sudo wb-sonde-registre » sur runner02," \
    "étape « publication ». Mise en production cet après-midi : ne touche ni aux politiques de" \
    "medisphere, ni à l'immuabilité des versions." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 13 20"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 13 E20 4 "$@"; }
fi
