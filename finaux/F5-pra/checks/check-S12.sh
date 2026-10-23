# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et scripts distants entre apostrophes
# check-S12.sh — F5-S12 « Le retour à PAR1 » (LIBRE, depuis adm01, après la levée de l'isolement) :
# isolement levé, noms globaux revenus à PAR1 (DNS et réponses « par1 »), dns03 redevenu secondaire au même
# numéro de série, mediagenda-db de PAR1 reconstruit après T0 et primaire, mediagenda-db-par2 de nouveau
# réplique de PAR1 et à jour, témoins écrits pendant le PRA et documents MédiDoc déposés à PAR2 retrouvés
# à PAR1, coupure du retour mesurée et courte, réplications PAR1 → PAR2 reprises, RB-351 et CHG-3512
# publiés, INC-6109 clos. Lecture seule.

# shellcheck source=_f5-exercice.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f5-exercice.sh"

title "F5-S12 — Le retour à PAR1"
require_cmd kubectl jq curl dig ssh

_f5_s12_t0="$(_f5e_t0 2>/dev/null || true)"
_f5_s12_levee="$(_f5e_levee 2>/dev/null || true)"
check_cmd "T0 (adm02 ou gw01) et heure de levée de l'isolement (gw01) lisibles dans /var/lib/workbook/" \
  test -n "$_f5_s12_t0" -a -n "$_f5_s12_levee"

# 1. Isolement levé, DNS revenu.
# Table absente ET garde de la panne S09 retiré (sinon la table reviendrait dans les 10 s).
_f5_s12_sans_table() {
  local t
  t="$(_f5p_sur "$1" 'sudo -n nft list tables && echo FIN-NFT; systemctl is-active f5-sinistre-garde.timer 2>/dev/null || true' 2>/dev/null)" || return 1
  grep -q '^FIN-NFT$' <<<"$t" && ! grep -q 'f5_sinistre' <<<"$t" && ! grep -qx 'active' <<<"$t"
}
check_cmd "gw01 : plus de table f5_sinistre ni de garde" _f5_s12_sans_table gw01
check_cmd "gw02 : plus de table f5_sinistre ni de garde" _f5_s12_sans_table gw02
_f5_s12_cname() { dig +short +time="$WB_TIMEOUT" +tries=1 "@$2" "$1" CNAME 2>/dev/null | grep -Eq '\.apps\.par1\.medisphere\.internal\.?$'; }
_f5_s12_cname2() { _f5_s12_cname "$1" "$_f5p_dns01" && _f5_s12_cname "$1" "$_f5p_dns03"; }
for _f5_n in "${_F5E_NOMS[@]}"; do
  check_cmd "dns01 et dns03 : $_f5_n → *.apps.par1.medisphere.internal" _f5_s12_cname2 "$_f5_n"
  _f5_s12_site="$(_f5e_site "$_f5_n" 2>/dev/null || true)"
  check_cmd "$_f5_n répond (2xx) avec X-MediSphere-Site: par1 (reçu : ${_f5_s12_site:-aucune réponse})" test "$_f5_s12_site" = par1
done
_f5_s12_serie() { dig +short +time="$WB_TIMEOUT" +tries=1 "@$1" medisphere.internal SOA 2>/dev/null | awk '{print $3}'; }
_f5_s12_s1="$(_f5_s12_serie "$_f5p_dns01" || true)"
_f5_s12_s3="$(_f5_s12_serie "$_f5p_dns03" || true)"
check_cmd "medisphere.internal : même numéro de série sur dns01 et dns03 (${_f5_s12_s1:-?} / ${_f5_s12_s3:-?})" \
  test -n "$_f5_s12_s1" -a "$_f5_s12_s1" = "$_f5_s12_s3"
_f5_s12_secondaire() {
  _f5p_sur "$_f5e_dns03" 'sudo -n pdnsutil zone list-all secondary 2>/dev/null || sudo -n pdnsutil list-all-zones secondary' 2>/dev/null \
    | grep -qx 'medisphere.internal\.\{0,1\}'
}
check_cmd "dns03 : la zone medisphere.internal est redevenue secondaire" _f5_s12_secondaire

# 2. Bases.
check_cmd "k8s-par1 : $_F5E_CNPG_PAR1 primaire, sain, non clôturé" \
  _f5e_kq1 "($_F5E_JQ_PRIMAIRE) and $_F5E_JQ_SAIN and $_F5E_JQ_NON_CLOTURE" cluster "$_F5E_CNPG_PAR1" -n "$_F5E_NS_PROD"
check_cmd "k8s-par1 : $_F5E_CNPG_PAR1 reconstruit après T0 (l'ancien primaire divergent n'est pas réutilisé)" \
  _f5e_kq1 "(.metadata.creationTimestamp | fromdateiso8601) > ${_f5_s12_t0:-9999999999}" cluster "$_F5E_CNPG_PAR1" -n "$_F5E_NS_PROD"
check_cmd "k8s-par1 : $_F5E_CNPG_PAR1 archive ses WAL (ContinuousArchiving)" _f5e_kq1 \
  'any(.status.conditions[]?; .type == "ContinuousArchiving" and .status == "True")' cluster "$_F5E_CNPG_PAR1" -n "$_F5E_NS_PROD"
check_cmd "k8s-par2 : $_F5E_CNPG_PAR2 de nouveau réplique de $_F5E_CNPG_PAR1, saine" \
  _f5e_kq2 "(.spec.replica.primary == \"$_F5E_CNPG_PAR1\") and ($_F5E_JQ_PRIMAIRE | not) and $_F5E_JQ_SAIN" cluster "$_F5E_CNPG_PAR2" -n "$_F5E_NS_PROD"
check_cmd "temoin-rpo actif à PAR1 (succès il y a moins de 10 min)" _f5e_kq1 \
  '((.spec.suspend // false) | not) and ((now - ((.status.lastSuccessfulTime // "1970-01-01T00:00:00Z") | fromdateiso8601)) < 600)' \
  cronjob temoin-rpo -n "$_F5E_NS_PROD"
check_cmd "temoin-rpo de nouveau suspendu à PAR2" _f5e_kq2 '.spec.suspend == true' cronjob temoin-rpo -n "$_F5E_NS_PROD"
_f5_s12_retard() {
  local j
  j="$(curl -sf --max-time "$WB_TIMEOUT" --data-urlencode "query=max(cnpg_pg_replication_lag{namespace=\"$_F5E_NS_PROD\"})" \
    "$_f5e_prom2/api/v1/query" 2>/dev/null)" || return 2
  jq -e '(.data.result | length) > 0' >/dev/null 2>&1 <<<"$j" || return 2
  jq -e '(.data.result[0].value[1] | tonumber) < 600' >/dev/null 2>&1 <<<"$j"
}
_f5_s12_rc=0
_f5_s12_retard || _f5_s12_rc=$?
if ((_f5_s12_rc == 2)); then
  skip "retard de la réplique de PAR2" "cnpg_pg_replication_lag non lisible dans le Prometheus de PAR2"
else
  check_cmd "réplique de PAR2 à moins de 10 min de PAR1 (cnpg_pg_replication_lag)" test "$_f5_s12_rc" -eq 0
fi
check_cmd "s3-02 : réplication filer.sync depuis s3-01 reprise" _f5p_filersync_ok

# 3. Rien de ce qui a été écrit pendant le PRA n'est perdu.
_f5_s12_mesures="docs/pra/mesures/$_f5e_exercice"
# CHAQUE témoin du fichier (pas un échantillon) : une seule invocation de curl (connexion réutilisée), une
# URL par identifiant ; les réponses 2xx sont filtrées par jq, les identifiants manquants comptés.
_F5_S12_MANQUANTS=""
_F5_S12_API="https://mediagenda.medisphere.internal/api/v1/rendez-vous"
_f5_s12_temoins() {
  local c ids trouves
  c="$(_f5p_fichier "$_f5p_projet_doc" "$_f5_s12_mesures/temoins-par2.csv" 2>/dev/null)" || return 1
  ids="$(sed -n 's/^\([0-9][0-9]*\),.*/\1/p' <<<"$c" | LC_ALL=C sort -u)"
  (($(grep -c . <<<"$ids") >= 10)) || return 1
  trouves="$(awk -v b="$_F5_S12_API" '{ printf "url = \"%s/%s\"\n", b, $0 }' <<<"$ids" \
    | curl -s -f --max-time "$WB_TIMEOUT" -K - 2>/dev/null \
    | jq -r 'select(.praticien? == "PRA-TEMOIN") | .id' 2>/dev/null | LC_ALL=C sort -u)" || true
  _F5_S12_MANQUANTS="$(LC_ALL=C comm -23 <(printf '%s\n' "$ids") <(printf '%s\n' "$trouves") | grep -c . || true)"
  ((_F5_S12_MANQUANTS == 0))
}
_f5_s12_temoins_ok=0
_f5_s12_temoins && _f5_s12_temoins_ok=1
check_cmd "chaque témoin écrit à PAR2 pendant le PRA ($_f5_s12_mesures/temoins-par2.csv, au moins 10) servi par PAR1 (manquants : ${_F5_S12_MANQUANTS:-?})" \
  test "$_f5_s12_temoins_ok" -eq 1
_f5_s12_documents() {
  local c ids n=0 ok=0 id
  c="$(_f5p_fichier "$_f5p_projet_doc" "$_f5_s12_mesures/medidoc-par2.csv" 2>/dev/null)" || return 1
  ids="$(grep -Eo '^[0-9a-f]{32}' <<<"$c")"
  [[ -n "$ids" ]] || return 1
  while IFS= read -r id; do
    n=$((n + 1))
    [[ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "https://medidoc.medisphere.internal/documents/$id" 2>/dev/null)" == 200 ]] && ok=$((ok + 1))
  done <<<"$ids"
  ((n > 0 && ok == n))
}
check_cmd "chaque document MédiDoc déposé à PAR2 ($_f5_s12_mesures/medidoc-par2.csv) servi par PAR1" _f5_s12_documents

# 4. Coupure du retour, documents.
if [[ -n "$_f5_s12_levee" ]] && _f5e_csv >/dev/null 2>&1; then
  _f5_s12_coupure="$(_f5e_coupure_max mediagenda.medisphere.internal "$_f5_s12_levee" || true)"
  check_cmd "coupure de MédiAgenda pendant le retour (ms-sonde-pra) : ${_f5_s12_coupure:-?} min (au plus $_f5e_coupure_max)" \
    test "${_f5_s12_coupure:-99999}" -le "$_f5e_coupure_max"
else
  check_cmd "mesures de ms-sonde-pra lisibles sur adm02 depuis adm01" false
fi
check_cmd "RB-351 publié (neutralisation, jetons CNPG, données MédiDoc, DNS)" \
  _f5p_doc_motif runbooks '^RB-351' 'neutralis' 'demotionToken' 'promotionToken' 'rclone|s3-02' 'dns03|DNS'
check_cmd "fiche CHG-3512 publiée (fenêtre, coupure mesurée, retour arrière)" \
  _f5p_doc_motif "exercices/$_f5e_exercice" '^CHG-3512' 'coupure' 'retour arri(è|e)re'
_f5_s12_clos() { _f5e_journal_pra gitlab 2>/dev/null | grep -Eq '\[cl(ô|o)ture\]'; }
check_cmd "main courante INC-6109 sur main de $_f5p_projet_doc, incident clos" _f5_s12_clos
