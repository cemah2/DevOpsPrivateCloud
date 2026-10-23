# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S10.sh — F5-S10 « Panne : les surprises de la crise » (BF, pendant le PRA, DEPUIS adm02) : état
# sain de PAR2 quelle que soit la variante (horloge de s3-02 synchronisée sur une source de PAR2, dns03
# résout les noms internes par ses propres autoritaires, sshd de adm02 laisse entrer « miroir », Argo CD de
# k8s-par2 lit ses dépôts), conséquences réparées (MédiDoc prêt, archivage de la base de PAR2), incident
# INC-6110 tracé dans la main courante. Lecture seule.

# shellcheck source=_f5-exercice.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f5-exercice.sh"

title "F5-S10 — Panne : les surprises de la crise"
require_cmd kubectl jq curl dig git

_f5_s10_horloge() {
  local t
  t="$(_f5e_sur "$_f5e_s302" 'chronyc -n tracking 2>/dev/null; chronyc -n sources 2>/dev/null')" || return 1
  grep -Eq 'Leap status *: Normal' <<<"$t" || return 1
  # Source retenue (« ^* ») ailleurs qu'à PAR1.
  grep -E '^\^\*' <<<"$t" | grep -vq ' 10\.10\.' || return 1
  # Écart absolu avec adm02 inférieur à 5 s.
  local d
  d="$(_f5e_sur "$_f5e_s302" 'date +%s')" || return 1
  (( (d - $(date +%s)) ** 2 < 25 ))
}
check_cmd "s3-02 : horloge synchronisée sur une source joignable de PAR2, écart < 5 s" _f5_s10_horloge

_f5_s10_resout() { dig +short +time="$WB_TIMEOUT" +tries=1 "@$_F5E_DNS03" "$1" A 2>/dev/null | grep -Eq '^[0-9]'; }
check_cmd "dns03 (récurseur) résout s3-02.par2.medisphere.internal" _f5_s10_resout s3-02.par2.medisphere.internal
check_cmd "dns03 (récurseur) résout mediagenda.medisphere.internal" _f5_s10_resout mediagenda.medisphere.internal
_f5_s10_relais() {
  local c
  c="$(_f5e_sur "$_f5e_dns03" 'sudo -n cat /etc/powerdns/recursor.yml' 2>/dev/null)" || return 1
  grep -q 'forward_zones' <<<"$c" || return 1
  ! grep -Eq '10\.10\.20\.(10|16)' <<<"$c"
}
check_cmd "dns03 : le récurseur ne renvoie aucune zone vers les autoritaires de PAR1" _f5_s10_relais

_f5_s10_miroir() {
  local t
  t="$(_f5e_sur "$_f5e_adm02" 'sudo -n sshd -T -C user=miroir,host=k8s-par2-n01,addr=10.20.20.50' 2>/dev/null)" || return 1
  if grep -qi '^allowusers' <<<"$t"; then grep -i '^allowusers' <<<"$t" | grep -qw miroir || return 1; fi
  if grep -qi '^denyusers' <<<"$t"; then grep -i '^denyusers' <<<"$t" | grep -qw miroir && return 1; fi
  return 0
}
check_cmd "adm02 : sshd accepte le compte miroir (lecture des miroirs par Argo CD de PAR2)" _f5_s10_miroir
check_cmd "Argo CD de k8s-par2 : aucune Application en erreur de comparaison ou de synchronisation" _f5e_kq2 \
  '[.items[] | select(any(.status.conditions[]?; .type | test("ComparisonError|SyncError|InvalidSpecError")))] | length == 0' \
  -n argocd applications.argoproj.io

_f5_s10_pret() { [[ "$(curl -s -o /dev/null -w '%{http_code}' --max-time "$WB_TIMEOUT" "https://medidoc.medisphere.internal/readyz" 2>/dev/null)" == 200 ]]; }
check_cmd "MédiDoc (servi par PAR2) prêt : son compartiment répond (/readyz)" _f5_s10_pret
check_cmd "k8s-par2 : $_F5E_CNPG_PAR2 archive ses WAL (condition ContinuousArchiving)" _f5e_kq2 \
  'any(.status.conditions[]?; .type == "ContinuousArchiving" and .status == "True")' cluster "$_F5E_CNPG_PAR2" -n "$_F5E_NS_PROD"

_f5_s10_inc() {
  local f l=""
  while IFS= read -r f; do
    [[ "$f" == docs/pra/journal/*.md ]] || continue
    l+="$(_f5e_pra_contenu "$f" | grep -E '^- [0-2][0-9]:[0-5][0-9] INC-6110 \[' || true)"$'\n'
  done < <(_f5e_pra_fichiers docs/pra/journal)
  grep -q '\[ouverture\]' <<<"$l" && grep -Eq '\[cl(ô|o)ture\]' <<<"$l" && grep -Eiq 'cause' <<<"$l"
}
check_cmd "main courante : INC-6110 ouvert, cause écrite, clos" _f5_s10_inc
