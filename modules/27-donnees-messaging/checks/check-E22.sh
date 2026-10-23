# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq, PromQL et LogQL entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E22.sh — M27-E22 « Panne : le cache ne sert plus » : Valkey de recette joignable, aucune erreur de
# cache récente (métriques et journaux), des succès de cache, /pret à 200 ; RB-279 ; panne close. Lecture seule.

# shellcheck source=_m27-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m27-expert.sh"

title "M27-E22 — Le cache sert à nouveau"
require_cmd kubectl jq curl

check_cmd "exportateur Valkey de recette : redis_up = 1" \
  _m27p_prom_positif "min(redis_up{namespace=\"$_m27p_recette\"})"
check_cmd "aucune erreur de lecture du cache dans l'API de recette (10 min)" \
  _m27p_prom_nul_ou_absent "sum(increase(mediagenda_cache_total{namespace=\"$_m27p_recette\", resultat=\"erreur\"}[10m]))"
check_cmd "des succès de cache récents en recette (15 min)" \
  _m27p_prom_positif "sum(increase(mediagenda_cache_total{namespace=\"$_m27p_recette\", resultat=\"hit\"}[15m]))"
check_cmd "/pret de MédiAgenda recette répond 200" _m27x_pret_recette
_m27_e22_journaux() {
  local r
  r="$(loki_requete "{namespace=\"$_m27p_recette\"} |~ \"cache indisponible|criture en cache impossible\"" "${WB_M27_LOKI_LOCATAIRE:-mediagenda}" 10m 2>/dev/null)" || return 2
  jq -e '.status == "success"' >/dev/null 2>&1 <<<"$r" || return 2
  jq -e '[.data.result[]?.values[]?] | length == 0' >/dev/null 2>&1 <<<"$r"
}
_m27_e22_rc=0
_m27_e22_journaux || _m27_e22_rc=$?
if ((_m27_e22_rc == 2)); then
  skip "aucun message d'erreur de cache dans les journaux de l'API (10 min)" "Loki non interrogeable (WB_M27_LOKI_LOCATAIRE ?)"
else
  check_cmd "aucun message d'erreur de cache dans les journaux de l'API (10 min)" _m27_e22_journaux
fi
check_cmd "runbook RB-279 « Le cache ne sert plus » (ACL, mémoire, TLS, réglages à chaud)" \
  _m27p_doc "$_m27p_runbooks" RB-279 'ACL' 'maxmemory|noeviction' 'TLS|certificat' 'CONFIG|à chaud'
check_cmd "journal de diagnostic INC-5422" _m27x_journal_inc 5422 'hypoth' 'cause'
check_cmd "panne M27-E22 close (lab/bin/break 27 22 --annuler après réparation)" _m27p_aucune_panne_active E22
