# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S13.sh — F6-S13 « Notifications, communication et post-mortem » (RED publié) : présence et
# contenu minimal des livrables de INC-6211 (décision de notification justifiée, registre des violations
# art. 33.5, message d'état, post-mortem sans recherche de coupable). Lecture seule (GitLab).

# shellcheck source=_f6-incident.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f6-incident.sh"

title "F6-S13 — Notifications, communication et post-mortem (INC-6211)"
require_cmd curl jq

check_cmd "decision-notification.md sur main : décision CNIL tranchée et justifiée sur preuves" \
  _f6i_inc_doc 'decision-notif|notification' 'CNIL' '72\s?h|72 heures|improbable|risque' 'preuve|(é|e)tabli|port(é|e)e'
check_cmd "decision-notification.md : clients HDS et signalement (CERT Santé) traités" \
  _f6i_inc_doc 'decision-notif|notification' 'client|HDS' 'CERT Sant(é|e)|L\.?1111-8-2|signalement'
check_cmd "registre des violations (art. 33.5) renseigné même sans notification" \
  _f6i_inc_doc 'registre|violation' '33\.?5|33 ?\.?5|registre' 'nature|cat(é|e)gor|cons(é|e)quence'
check_cmd "message-etat.md sur main (message d'état interne, factuel)" \
  _f6i_inc_doc '^message-etat|message' 'INC-6211'
check_cmd "post-mortem.md sur main : cause racine (mécanisme), actions datées, sans coupable" \
  _f6i_inc_doc 'post-mortem' 'cause' 'action' 'm(é|e)canisme|sans recherche de coupable|sans coupable'
