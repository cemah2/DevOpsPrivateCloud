# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et scripts entre apostrophes
# check-S09.sh — F5-S09 « Le sinistre : perte de PAR1 » (CHRONO), lancé DEPUIS adm02 pendant le PRA :
# isolement en cours (T0 noté, PAR1 injoignable), dns03 publie les trois noms globaux vers PAR2, PAR2 les
# sert (2xx, X-MediSphere-Site: par2), RTO mesuré par ms-sonde-pra sous les objectifs, mediagenda-db-par2
# primaire sain, témoin écrit à PAR2, RPO consigné dans la main courante INC-6109. Lecture seule.

# shellcheck source=_f5-exercice.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f5-exercice.sh"

title "F5-S09 — Le sinistre : perte de PAR1"
require_cmd kubectl jq curl dig git

_f5_s09_t0="$(_f5e_t0 2>/dev/null || true)"
if [[ -z "$_f5_s09_t0" ]]; then
  check_cmd "sinistre en cours : T0 lisible sur adm02 (/var/lib/workbook/f5-t0)" false
else
  check_cmd "sinistre en cours : T0 = $(date -d "@$_f5_s09_t0" '+%F %H:%M:%S')" true
fi
_f5_s09_par1_coupe() { ! _f5e_par1_joignable; }
check_cmd "PAR1 reste injoignable depuis PAR2 (dns01:53 et git01:443 par adresse ; isolement non levé)" _f5_s09_par1_coupe

_f5_s09_cname() { dig +short +time="$WB_TIMEOUT" +tries=1 "@$_f5p_dns03" "$1" CNAME 2>/dev/null | grep -Eq '\.apps\.par2\.medisphere\.internal\.?$'; }
# TTL lu sur l'autoritaire de dns03 (port 5300) ; à défaut, sur son récurseur (le TTL d'une réponse en
# cache ne dépasse jamais celui de la zone : un TTL de zone long finit par s'y voir).
_f5_s09_ttl() {
  local t
  t="$(dig +noall +answer +time="$WB_TIMEOUT" +tries=1 "@$_f5p_dns03" -p 5300 "$1" CNAME 2>/dev/null | awk '{print $2; exit}')" || t=""
  [[ -n "$t" ]] || t="$(dig +noall +answer +time="$WB_TIMEOUT" +tries=1 "@$_f5p_dns03" "$1" CNAME 2>/dev/null | awk '{print $2; exit}')" || t=""
  [[ -n "$t" ]] || return 2
  ((t <= 300))
}
for _f5_n in "${_F5E_NOMS[@]}"; do
  check_cmd "dns03 : $_f5_n → *.apps.par2.medisphere.internal" _f5_s09_cname "$_f5_n"
  _f5_s09_site="$(_f5e_site "$_f5_n" 2>/dev/null || true)"
  check_cmd "$_f5_n répond (2xx) avec X-MediSphere-Site: par2 (reçu : ${_f5_s09_site:-aucune réponse})" test "$_f5_s09_site" = par2
done
_f5_s09_rc=0
_f5_s09_ttl mediagenda.medisphere.internal || _f5_s09_rc=$?
if ((_f5_s09_rc == 2)); then
  check_cmd "TTL de mediagenda.medisphere.internal lisible sur dns03 (autoritaire ou récurseur)" false
else
  check_cmd "TTL des noms globaux court (≤ 300 s) sur dns03" test "$_f5_s09_rc" -eq 0
fi

# RTO mesurés par la sonde.
if [[ -n "$_f5_s09_t0" ]] && _f5e_csv >/dev/null 2>&1; then
  for _f5_couple in "mediagenda:$_f5e_rto_mediagenda" "medidoc:$_f5e_rto_medidoc" "rdv:$_f5e_rto_rdv"; do
    _f5_app="${_f5_couple%%:*}"
    _f5_obj="${_f5_couple#*:}"
    _f5_rto="$(_f5e_rto "$_f5_app.medisphere.internal" "$_f5_s09_t0" || true)"
    check_cmd "RTO mesuré par ms-sonde-pra pour $_f5_app : ${_f5_rto:-pas encore de réponse de PAR2} min (objectif $_f5_obj min)" \
      test "${_f5_rto:-99999}" -le "$_f5_obj"
  done
else
  check_cmd "mesures de ms-sonde-pra lisibles sur adm02 ($_f5e_csv_chemin)" false
fi

# Base et témoin à PAR2.
check_cmd "k8s-par2 : $_F5E_CNPG_PAR2 est PRIMAIRE et sain" \
  _f5e_kq2 "($_F5E_JQ_PRIMAIRE) and $_F5E_JQ_SAIN" cluster "$_F5E_CNPG_PAR2" -n "$_F5E_NS_PROD"
_f5_s09_temoin() {
  local j
  j="$(_f5p_kube get cronjob temoin-rpo -n "$_F5E_NS_PROD" -o json 2>/dev/null)" || return 1
  jq -e --argjson t0 "${_f5_s09_t0:-0}" '((.spec.suspend // false) | not)
    and ((.status.lastSuccessfulTime // "1970-01-01T00:00:00Z") | fromdateiso8601) > $t0
    and ((now - ((.status.lastSuccessfulTime // "1970-01-01T00:00:00Z") | fromdateiso8601)) < 600)' >/dev/null 2>&1 <<<"$j"
}
check_cmd "k8s-par2 : temoin-rpo réactivé, dernier succès après T0 et il y a moins de 10 min" _f5_s09_temoin

# Main courante INC-6109 (clone de travail de adm02, commits de la branche courante).
_f5_s09_journal="$(_f5e_journal_pra pra 2>/dev/null || true)"
check_cmd "main courante INC-6109 commitée : ouverture et décision de déclenchement" \
  bash -c 'grep -Eq "\[ouverture\]" <<<"$1" && grep -Eiq "\[d(é|e)cision\].*(d(é|e)clench|bascul|PRA)" <<<"$1"' _ "$_f5_s09_journal"
check_cmd "main courante : au moins 8 entrées horodatées pour INC-6109" \
  test "$(grep -c . <<<"$_f5_s09_journal" || true)" -ge 8
check_cmd "main courante : RPO mesuré consigné (valeur chiffrée)" \
  grep -Eiq 'RPO[^0-9]{0,40}[0-9]+([.,][0-9]+)? ?(s|min|minutes?|secondes?)\b' <<<"$_f5_s09_journal"
check_cmd "main courante : RTO consigné pour MédiAgenda" \
  grep -Eiq 'RTO.*m(é|e)diagenda|m(é|e)diagenda.*RTO' <<<"$_f5_s09_journal"
