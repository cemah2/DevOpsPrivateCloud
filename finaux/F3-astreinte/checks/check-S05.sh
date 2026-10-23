# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S05.sh — F3-S05 « Mardi : les certificats ne se renouvellent plus » : émetteur ACME prêt et
# pointé vers le répertoire de ca01, tous les certificats du cluster prêts (répétition du joker comprise),
# aucun défi ACME bloqué, la zone apps accepte les mises à jour de cert-manager, santé, trace INC-5905.
# Lecture seule.

# shellcheck source=_f3-debut.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f3-debut.sh"

title "F3-S05 — Les certificats sont de nouveau délivrés"
require_cmd kubectl jq curl ssh

_f3d_s05_url="${WB_F3_ACME_URL:-https://ca01.par1.medisphere.internal/acme/acme/directory}"
check_cmd "ClusterIssuer step-ca-acme prêt" _f3d_kq '.status.conditions[]? | select(.type == "Ready" and .status == "True")' clusterissuer step-ca-acme
check_cmd "step-ca-acme interroge le répertoire ACME de ca01 ($_f3d_s05_url)" \
  _f3d_kq ".spec.acme.server == \"$_f3d_s05_url\"" clusterissuer step-ca-acme

_f3d_s05_certs="$(kube get certificates.cert-manager.io -A -o json 2>/dev/null | jq -r '[.items[]
  | select(any(.status.conditions[]?; .type == "Ready" and .status == "True") | not)
  | "\(.metadata.namespace)/\(.metadata.name)"] | join(" ")' 2>/dev/null)" || _f3d_s05_certs="?"
if [[ -z "$_f3d_s05_certs" ]]; then
  _ok "tous les certificats du cluster sont prêts"
else
  _ko "certificats non prêts : $_f3d_s05_certs"
fi
if kube -n wb-pannes get certificate repetition-joker >/dev/null 2>&1; then
  check_cmd "répétition du renouvellement du joker (wb-pannes/repetition-joker) délivrée" \
    _f3d_kq '.status.conditions[]? | select(.type == "Ready" and .status == "True")' -n wb-pannes certificate repetition-joker
fi

if _f3d_s05_ch="$(kube get challenges.acme.cert-manager.io -A -o json 2>/dev/null)"; then
  _f3d_s05_vieux="$(jq -r '[.items[] | select(((.metadata.creationTimestamp | fromdateiso8601) < (now - 900)))
    | "\(.metadata.namespace)/\(.metadata.name) (\(.status.state // "?"))"] | join(" ")' <<<"$_f3d_s05_ch" 2>/dev/null)" || _f3d_s05_vieux="?"
  if [[ -z "$_f3d_s05_vieux" ]]; then _ok "aucun défi ACME bloqué depuis plus de 15 min"; else _ko "défis ACME bloqués : $_f3d_s05_vieux"; fi
else
  skip "défis ACME" "objets challenges illisibles par le compte des checks"
fi

_f3d_s05_meta() {
  remote "${WB_F3_DNS_PRIMAIRE:-dns01}" "sudo -n -u pdns pdnsutil metadata get apps.par1.medisphere.internal TSIG-ALLOW-DNSUPDATE" 2>/dev/null </dev/null |
    grep -q 'certmanager-k8s'
}
check_cmd "la zone apps.par1.medisphere.internal accepte les mises à jour signées de cert-manager" _f3d_s05_meta

check_cmd "RB-332 publié (docs/exploitation/runbooks/)" _f3d_rb_present RB-332
_f3s_sante
_f3s_trace INC-5905 1
