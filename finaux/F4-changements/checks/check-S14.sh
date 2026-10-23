# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-S14.sh — F4-S14 « Revue des changements et décommissionnement » (RED publié) : présence et
# contenu minimal des livrables, VM 3401 retirée (ou arrêtée avec décision écrite), DNS, NetBox, code,
# sauvegarde finale protégée, étiquette changements-v1. Lecture seule.

# shellcheck source=_f4-migrations.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f4-migrations.sh"

title "F4-S14 — Revue des changements et décommissionnement"
require_cmd jq curl ssh dig

check_cmd "revue-trimestre.md sur main : changements, mesures, leçons, actions" \
  _f4g_doc "$_f4g_doc_dir" '^revue-trimestre' 'CHG-3410' 'CHG-3413' 'mesur' 'le[cç]on|ce qui a' 'action'
check_cmd "RB-347 sur main (décommissionnement : sauvegarde finale, effacement, preuves)" \
  _f4g_doc "$_f4g_doc_dir/runbooks" '^RB-347' 'sauvegarde finale|finale' 'effac' 'preuve' 'prot[eé]g'
check_cmd "fiche CHG-3414 sur main (conservation, effacement)" \
  _f4g_doc "$_f4g_doc_dir/fiches" '^CHG-3414' 'conserv' 'effac'
check_cmd "ADR-0340 sur main (options, décision)" \
  _f4g_doc "$_f4g_doc_dir/adr" '^ADR-0340' 'option' 'd[ée]cision' 'cons[ée]quence'

# VM 3401 : absente, ou arrêtée avec la décision écrite dans CHG-3414.
_f4_s14_vm_ok() {
  ! _f4g_vm_existe 3401 && return 0
  _f4g_vm_filtre 3401 '.status == "stopped"' && _f4g_doc "$_f4g_doc_dir/fiches" '^CHG-3414' 'arr[eê]t[ée]e'
}
check_cmd "VM 3401 (legacy-rdv01) supprimée de pve01 (ou arrêtée par décision écrite dans CHG-3414)" _f4_s14_vm_ok
# Réponse du serveur exigée (NXDOMAIN, ou NOERROR sans réponse) : un DNS injoignable n'est pas un succès.
_f4_s14_pas_de_nom() {
  local r
  r="$(dig +time="$WB_TIMEOUT" +tries=1 @10.10.20.10 legacy-rdv01.par1.medisphere.internal A 2>/dev/null)" || return 1
  grep -q 'status: NXDOMAIN' <<<"$r" || { grep -q 'status: NOERROR' <<<"$r" && grep -q 'ANSWER: 0' <<<"$r"; }
}
check_cmd "legacy-rdv01.par1.medisphere.internal ne résout plus" _f4_s14_pas_de_nom
_f4_s14_netbox_inactive() {
  local j
  j="$(netbox_api "virtualization/virtual-machines/?name=legacy-rdv01" 2>/dev/null)" || return 1
  jq -e '(.results | length) == 0 or (.results[0].status.value != "active")' >/dev/null 2>&1 <<<"$j"
}
check_cmd "NetBox : legacy-rdv01 n'est plus une VM active" _f4_s14_netbox_inactive
_f4_s14_code() {
  local f c n=0
  while IFS= read -r f; do
    [[ "$f" == *.tf ]] || continue
    c="$(_f4g_fichier plateforme/infra "$f" 2>/dev/null)" || return 1
    n=$((n + 1))
    if grep -Eq '"legacy-rdv01"|vmid *= *3401' <<<"$c"; then return 1; fi
  done < <(_f4g_arbre plateforme/infra envs/f4-infoger)
  ((n > 0))
}
check_cmd "plateforme/infra (main) : envs/f4-infoger ne décrit plus legacy-rdv01" _f4_s14_code
_f4_s14_sauvegarde_protegee() {
  _f4g_pve "pvesh get /nodes/\$(hostname -s)/storage/pbs-par2/content --vmid 3401 --output-format json" 2>/dev/null \
    | jq -e 'any(.[]; (.protected // 0) == 1 or .protected == true)' >/dev/null 2>&1
}
check_cmd "sauvegarde finale de 3401 sur pbs-par2, protégée" _f4_s14_sauvegarde_protegee
check_cmd "étiquette changements-v1 posée sur plateforme/medisphere" _f4g_etiquette changements-v1
