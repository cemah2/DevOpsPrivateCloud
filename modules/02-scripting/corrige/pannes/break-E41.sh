# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E41.sh — M02-E41 « Panne : le contrôle planifié ne tourne plus »
#
# Cible : ms-verif-sauvegardes.timer / .service de adm01 (M02-E26). Variantes :
#   1. timer arrêté à chaud (« systemctl stop ») : il reste « enabled », mais ne se
#      déclenchera plus avant le prochain démarrage de adm01 ;
#   2. drop-in du timer 10-horaire.conf : OnCalendar remis à zéro puis remplacé par une
#      expression invalide recopiée d'une crontab (« *-*-* 30:07:00 ») : le timer n'a plus
#      aucun déclencheur, systemd refuse de le charger (bad-setting) ;
#   3. drop-in du service 90-gel.conf : ConditionPathExists= vers un fichier absent (« gel de
#      l'outillage » jamais levé) : le timer se déclenche, le service est sauté en silence,
#      sans échec ni notification ;
#   4. drop-in du timer 20-audit.conf : OnCalendar remplacé par « Mon *-*-* 07:30:00 » (crontab
#      InfoGér « 30 7 * * 1 » recopiée pendant l'audit) : le timer est sain, actif, mais ne se
#      déclenche plus que le lundi.
# Sauvegardes : /var/lib/workbook/M02-E41.* sur adm01 (drop-ins créés notés ABSENT).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"

_E41_TIMER=ms-verif-sauvegardes.timer
_E41_SVC=ms-verif-sauvegardes.service

_e41_injecter() {
  WB_VAR="$1" wb_exec localhost T="$_E41_TIMER" S="$_E41_SVC" N="$1" >/dev/null <<'EOF'
systemctl cat "$T" "$S" >/dev/null 2>&1 || { echo "unités $T / $S absentes (M02-E26 non fait ?)" >&2; exit 1; }
systemctl is-active -q "$T" || { echo "le timer $T n'est déjà pas actif : lab/bin/check 02 26" >&2; exit 1; }
case "$N" in
  1)
    systemctl stop "$T"
    journal "timer $T arrêté (reste enabled)"
    ;;
  2)
    d="/etc/systemd/system/$T.d"; f="$d/10-horaire.conf"
    mkdir -p "$d"; sauver "$f"
    cat >"$f" <<'UNIT'
# CHG-382 : harmonisation des horaires des contrôles sur la crontab InfoGér (« 30 7 * * * »)
[Timer]
OnCalendar=
OnCalendar=*-*-* 30:07:00
UNIT
    systemctl daemon-reload
    systemctl restart "$T" 2>/dev/null || true
    journal "drop-in $f : OnCalendar invalide"
    ;;
  3)
    c=/etc/ms-outils/controle-actif
    [ ! -e "$c" ] || { echo "$c existe déjà : variante inapplicable" >&2; exit 1; }
    d="/etc/systemd/system/$S.d"; f="$d/90-gel.conf"
    mkdir -p "$d"; sauver "$f"
    cat >"$f" <<'UNIT'
# CHG-383 : gel de l'outillage pendant la migration du datastore de pbs01.
# Le contrôle ne tourne que si /etc/ms-outils/controle-actif existe (levée du gel par Karim).
[Unit]
ConditionPathExists=/etc/ms-outils/controle-actif
UNIT
    systemctl daemon-reload
    # Le passage de 07:30 : sauté.
    systemctl start "$S" 2>/dev/null || true
    journal "drop-in $f : condition jamais remplie"
    ;;
  4)
    d="/etc/systemd/system/$T.d"; f="$d/20-audit.conf"
    mkdir -p "$d"; sauver "$f"
    cat >"$f" <<'UNIT'
# CHG-384 : pendant l'audit HDS, contrôle aligné sur l'ancienne planification InfoGér
# (crontab « 30 7 * * 1 ») pour réduire le bruit. À retirer après l'audit.
[Timer]
OnCalendar=
OnCalendar=Mon *-*-* 07:30:00
UNIT
    systemctl daemon-reload
    systemctl restart "$T"
    journal "drop-in $f : déclenchement hebdomadaire"
    ;;
esac
EOF
}

panne_E41_v1() { _e41_injecter 1; }
panne_E41_v2() { _e41_injecter 2; }
panne_E41_v3() { _e41_injecter 3; }
panne_E41_v4() { _e41_injecter 4; }

verifier_E41() {
  # shellcheck disable=SC2031  # WB_VAR est fixé par wb_main (ou par l'astreinte) avant l'appel
  case "${WB_VAR:-}" in
    1) ! systemctl is-active -q "$_E41_TIMER" ;;
    2) [[ "$(systemctl show "$_E41_TIMER" -p LoadState --value)" == bad-setting ]] \
         || ! systemctl is-active -q "$_E41_TIMER" ;;
    3) [[ "$(systemctl show "$_E41_SVC" -p ConditionResult --value)" == no ]] ;;
    4) systemctl is-active -q "$_E41_TIMER" \
         && ! systemctl show "$_E41_TIMER" -p TimersCalendar --value | grep -q 'OnCalendar=\*-\*-\* 07:30:00' ;;
    *) return 1 ;;
  esac
}

annuler_E41() {
  wb_exec localhost T="$_E41_TIMER" S="$_E41_SVC" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur adm01"
restaurer_fichiers
rmdir "/etc/systemd/system/$T.d" "/etc/systemd/system/$S.d" 2>/dev/null || true
systemctl daemon-reload
systemctl reset-failed "$T" 2>/dev/null || true
systemctl restart "$T" || echo "le timer $T ne redémarre pas" >&2
# Un passage réel du contrôle efface un éventuel « sauté par condition » (variante 3).
timeout 300 systemctl start "$S" || echo "le contrôle $S échoue après annulation" >&2
journal "annulation : timer et service rétablis"
exit 0
EOF
}

resume_E41() {
  echo "Plus aucun compte rendu du contrôle des sauvegardes depuis plusieurs jours, et aucune alerte non plus."
}

symptome_E41() {
  wb_symptome "Ticket INC-2845 — De : Nadia Roussel" \
    "Je viens de m'en rendre compte : je n'ai plus aucune trace du contrôle quotidien des" \
    "sauvegardes (07:30 sur adm01) depuis plusieurs jours. Pas d'échec, pas de notification," \
    "rien : il ne tourne plus, tout simplement. Un contrôle silencieux, c'est pire que pas de" \
    "contrôle. Remets-le en route, et dis-moi comment on aurait pu s'en apercevoir plus tôt." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 02 41"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 02 E41 4 "$@"; }
fi
