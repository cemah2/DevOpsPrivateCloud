# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-S04.sh — F3-S04 « Lundi : pourquoi personne n'a été prévenu ? » : la configuration CHARGÉE de
# l'Alertmanager route les alertes de MédiAgenda production vers l'astreinte et l'équipe, les règles de
# latence et d'erreurs sont évaluées avec des délais raisonnables, aucun silence large et durable ne les
# couvre, l'essai de routage est protégé par la CI, le dead man's switch tient, trace INC-5904.
# Lecture seule.

# shellcheck source=_f3-debut.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f3-debut.sh"

title "F3-S04 — La chaîne d'alerte de MédiAgenda (production) prévient de nouveau"
require_cmd jq curl

if command -v amtool >/dev/null 2>&1; then
  check_cmd "critique de MédiAgenda prod → astreinte-mail (configuration chargée)" _f3d_route_contient astreinte-mail \
    alertname=MediagendaTauxErreurEleve gravite=critique equipe=mediagenda environnement=prod
  check_cmd "critique de MédiAgenda prod → mediagenda-mail (l'équipe est prévenue aussi)" _f3d_route_contient mediagenda-mail \
    alertname=MediagendaTauxErreurEleve gravite=critique equipe=mediagenda environnement=prod
  check_cmd "avertissement de latence de MédiAgenda prod → mediagenda-mail" _f3d_route_contient mediagenda-mail \
    alertname=MediagendaLatenceElevee gravite=avertissement equipe=mediagenda environnement=prod
else
  _ko "amtool absent d'adm01 (M21) : impossible de rejouer l'arbre de routage chargé"
fi

_f3d_s04_d="$(_f3d_regle_duree MediagendaLatenceElevee prod)"
if [[ "$_f3d_s04_d" =~ ^[0-9]+$ ]] && ((_f3d_s04_d <= 1800)); then
  _ok "règle MediagendaLatenceElevee (prod) chargée, délai ${_f3d_s04_d} s"
else
  _ko "règle MediagendaLatenceElevee (prod) absente ou trop lente à se déclencher (for : ${_f3d_s04_d:-absent})"
fi
_f3d_s04_d="$(_f3d_regle_duree MediagendaTauxErreurEleve 'environnement="prod"\} > 0.05')"
if [[ "$_f3d_s04_d" =~ ^[0-9]+$ ]] && ((_f3d_s04_d <= 1800)); then
  _ok "règle critique MediagendaTauxErreurEleve (prod) chargée, délai ${_f3d_s04_d} s"
else
  _ko "règle critique MediagendaTauxErreurEleve (prod) absente ou trop lente (for : ${_f3d_s04_d:-absent})"
fi

_f3d_s04_n="$(_f3d_silences_larges '{"alertname":"MediagendaLatenceElevee","gravite":"critique","equipe":"mediagenda","environnement":"prod","namespace":"mediagenda-prod"}')"
if [[ "$_f3d_s04_n" == 0 ]]; then
  _ok "aucun silence actif de plus de 24 h ne couvre les alertes de MédiAgenda prod"
else
  _ko "$_f3d_s04_n silence(s) actif(s) de plus de 24 h couvrent les alertes de MédiAgenda prod"
fi

_f3d_s04_tests() {
  local t
  t="$(gitlab_api "projects/$(_f3s_enc "${WB_F3_PROJET_OBSERVABILITE:-plateforme/observabilite}")/repository/files/$(_f3s_enc "${WB_F3_FICHIER_ROUTES_TESTS:-alertmanager/routes-tests.txt}")/raw?ref=main" 2>/dev/null)" || return 1
  grep -v '^[[:space:]]*#' <<<"$t" | grep -E 'equipe=mediagenda' | grep -E 'environnement=prod' | grep -Eq '^[^|]*astreinte-mail'
}
check_cmd "essai de routage en CI : une critique de MédiAgenda prod doit aller à l'astreinte" _f3d_s04_tests

_f3d_s04_watchdog() { _f3s_p_temoin >/dev/null; }
check_cmd "dead man's switch de mon01 toujours fonctionnel (Watchdog vu, sondes vertes)" _f3d_s04_watchdog

check_cmd "RB-331 publié (docs/exploitation/runbooks/)" _f3d_rb_present RB-331
check_cmd "ticket PLAT-3304 ouvert (la lenteur aurait-elle dû réveiller l'astreinte ?)" _f3d_ticket_present PLAT-3304
_f3s_trace INC-5904 1
