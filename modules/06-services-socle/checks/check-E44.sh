# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant ou par bash -c
# check-E44.sh — M06-E44 « Sous le capot : une résolution DNS et une émission ACME pas à pas » :
# compte rendu présent, structuré et commité ; aucune trace ni capture laissée active ; certificat
# d'essai non resté en service. Lecture seule.

# shellcheck source=_m06-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m06-expert.sh"

title "M06-E44 — Sous le capot : DNS et ACME"
require_cmd git

_m06_e44_depot="${WB_DEPOT:-$HOME/medisphere}"
_m06_e44_cr="$_m06_e44_depot/docs/socle/analyses/resolution-et-acme.md"
check_cmd "compte rendu docs/socle/analyses/resolution-et-acme.md présent" test -s "$_m06_e44_cr"
check_output "section sur la résolution DNS" '^## .*[Rr][ée]solution' cat "$_m06_e44_cr"
check_output "section sur l'émission ACME" '^## .*ACME' cat "$_m06_e44_cr"
check_output "section « Réponses aux questions »" '^## Réponses aux questions' cat "$_m06_e44_cr"
check_cmd "trace du récurseur, capture et étapes ACME citées (trace-regex, 5300, newOrder, http-01, finalize)" \
  bash -c 'for m in trace-regex 5300 newOrder http-01 finalize; do grep -qi -- "$m" "$1" || exit 1; done' _ "$_m06_e44_cr"
check_cmd "compte rendu commité, sans modification en attente" \
  bash -c 'cd "$1" && git ls-files --error-unmatch docs/socle/analyses/resolution-et-acme.md >/dev/null 2>&1 && [ -z "$(git status --porcelain -- docs/socle/analyses)" ]' _ "$_m06_e44_depot"
check_ssh "dns01 : aucune capture tcpdump en cours" dns01 '! pgrep -x tcpdump >/dev/null'
check_ssh "ca01 : aucune capture tcpdump en cours" ca01 '! pgrep -x tcpdump >/dev/null'
# Le client autonome s'appelle « step » ; step-ca (écouteur CRL de M06-E27) s'appelle « step-ca ».
check_ssh "dns02 : aucune capture tcpdump ni client ACME autonome en cours, clé d'essai supprimée" dns02 \
  '! pgrep -x tcpdump >/dev/null && ! pgrep -x step >/dev/null && ! sudo -n find /tmp /root /home -xdev -name "essai.key" 2>/dev/null | grep -q .'
check_cmd "aucune clé privée dans le compte rendu" bash -c '! grep -q "PRIVATE KEY" "$1"' _ "$_m06_e44_cr"
