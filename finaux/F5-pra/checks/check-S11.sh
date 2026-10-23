# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S11.sh — F5-S11 « Tenir en mode dégradé » (LIBRE, pendant le PRA, DEPUIS adm02) : sauvegardes DE
# PAR2 (base de PAR2 archivée et sauvegardée après T0, VMs du pool par2 sauvegardées sur PBS après T0),
# supervision minimale (Prometheus et Alertmanager de PAR2, Mailpit de secours qui reçoit), MédiNotif
# repris, demandes des métiers et journal tenus. Lecture seule.

# shellcheck source=_f5-exercice.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f5-exercice.sh"

title "F5-S11 — Tenir en mode dégradé"
require_cmd kubectl jq curl git ssh

_f5_s11_t0="$(_f5e_t0 2>/dev/null || true)"
check_cmd "sinistre en cours (T0 lisible sur adm02)" test -n "$_f5_s11_t0"
_f5_s11_t0="${_f5_s11_t0:-0}"

# 1. Sauvegardes de PAR2.
check_cmd "k8s-par2 : $_F5E_CNPG_PAR2 archive ses WAL (ContinuousArchiving)" _f5e_kq2 \
  'any(.status.conditions[]?; .type == "ContinuousArchiving" and .status == "True")' cluster "$_F5E_CNPG_PAR2" -n "$_F5E_NS_PROD"
check_cmd "k8s-par2 : une sauvegarde de base de $_F5E_CNPG_PAR2 terminée après T0" _f5e_kq2 \
  "[.items[] | select(.spec.cluster.name == \"$_F5E_CNPG_PAR2\" and .status.phase == \"completed\"
     and ((.status.stoppedAt // \"1970-01-01T00:00:00Z\") | sub(\"\\\\.[0-9]+\"; \"\") | fromdateiso8601) > $_f5_s11_t0)] | length > 0" \
  backups.postgresql.cnpg.io -n "$_F5E_NS_PROD"
check_cmd "k8s-par2 : sauvegarde de base planifiée (ScheduledBackup) pour $_F5E_CNPG_PAR2" _f5e_kq2 \
  "[.items[] | select(.spec.cluster.name == \"$_F5E_CNPG_PAR2\" and ((.spec.suspend // false) | not))] | length > 0" \
  scheduledbackups.postgresql.cnpg.io -n "$_F5E_NS_PROD"
_f5_s11_vzdump() {
  local j
  j="$(_f5e_sur "$_f5e_hp01" "pvesh get /nodes/\$(hostname -s)/tasks --typefilter vzdump --since $_f5_s11_t0 --limit 50 --output-format json" 2>/dev/null)" || return 1
  jq -e '[.[] | select(.status == "OK")] | length > 0' >/dev/null 2>&1 <<<"$j"
}
check_cmd "hp01 : au moins une sauvegarde vzdump réussie depuis T0 (VMs de PAR2)" _f5_s11_vzdump

# 2. Supervision minimale de PAR2.
_f5_s11_prom() {
  local j
  j="$(curl -sf --max-time "$WB_TIMEOUT" "$_f5e_prom2/api/v1/targets?state=active" 2>/dev/null)" || return 1
  jq -e '[.data.activeTargets[] | select(.health == "up")] | length >= 4' >/dev/null 2>&1 <<<"$j"
}
check_cmd "Prometheus de PAR2 ($_f5e_prom2) : au moins 4 cibles actives « up »" _f5_s11_prom
_f5_s11_regles() {
  local j
  j="$(curl -sf --max-time "$WB_TIMEOUT" "$_f5e_prom2/api/v1/rules?type=alert" 2>/dev/null)" || return 1
  jq -e '[.data.groups[].rules[] | .query] | (map(test("cnpg|pg_")) | any) and (map(test("probe_success|up")) | any)' >/dev/null 2>&1 <<<"$j"
}
check_cmd "Prometheus de PAR2 : alertes sur la base (cnpg_/pg_) et sur la disponibilité (probe_success/up)" _f5_s11_regles
check_cmd "Alertmanager de PAR2 ($_f5e_am2) répond" bash -c 'curl -sf --max-time "$1" "$2/api/v2/status" >/dev/null' _ "$WB_TIMEOUT" "$_f5e_am2"
_f5_s11_mailpit() {
  local j c
  j="$(curl -sf --max-time "$WB_TIMEOUT" "$_f5e_mailpit2/api/v1/messages?limit=200" 2>/dev/null)" || return 1
  while IFS= read -r c; do
    [[ -n "$c" ]] || continue
    (($(date -d "$c" +%s 2>/dev/null || echo 0) > _f5_s11_t0)) && return 0
  done < <(jq -r '.messages[]?.Created // empty' <<<"$j" 2>/dev/null)
  return 1
}
check_cmd "Mailpit de secours ($_f5e_mailpit2) : au moins un message reçu depuis T0 (alerte ou message d'état)" _f5_s11_mailpit

# 3. MédiNotif.
check_cmd "k8s-par2 : le worker MédiNotif tourne (medinotif-prod, au moins une réplique prête)" _f5e_kq2 \
  '[.items[] | select((.status.readyReplicas // 0) >= 1)] | length > 0' deployments -n medinotif-prod

# 4. Journal et demandes des métiers.
check_cmd "mode dégradé décrit (périmètre ouvert/fermé, demandes des métiers, décisions)" \
  _f5e_doc_pra "docs/pra/exercices/$_f5e_exercice" '^mode-degrade' 'd(é|e)grad' 'demande' 'd(é|e)cision' 'sauvegarde'
_f5_s11_heures() {
  _f5e_journal_pra pra 2>/dev/null | sed -n 's/^- \([0-2][0-9]\):.*/\1/p' | sort -u | wc -l
}
check_cmd "main courante INC-6109 tenue sur au moins trois heures différentes" test "$(_f5_s11_heures || echo 0)" -ge 3
