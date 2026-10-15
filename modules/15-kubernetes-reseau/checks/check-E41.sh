# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # scripts « bash -c » : arguments passés en $1, $2…
# check-E41.sh — M15-E41 « Panne : le nom n'est plus publié » : ExternalDNS configuré comme au
# M15-E15 (rfc2136, filtre de domaine, propriétaire k8s-par1, source gateway-httproute), droits de
# lecture des routes, noms publiés et nettoyés, secondaire à jour. Lecture seule.

# shellcheck source=_m15-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m15-expert.sh"

title "M15-E41 — Les noms des routes sont publiés"
require_cmd kubectl jq dig

_m15_e41_kc="${WB_K8S_KUBECONFIG:-$HOME/.config/workbook/k8s-checks.kubeconfig}"
_m15_e41_args="$(kube -n external-dns get deploy -o json 2>/dev/null | jq -r '
  [.items[] | select([.spec.template.spec.containers[].args[]?] | any(test("^--provider(=| )rfc2136")))][0]
  | .spec.template.spec.containers[0].args[]?')" || true
check_cmd "un Deployment ExternalDNS (fournisseur rfc2136) existe dans external-dns" test -n "$_m15_e41_args"
check_output "ExternalDNS : filtre de domaine $_m15x_zone" "^--domain-filter=$_m15x_zone\$" printf '%s\n' "$_m15_e41_args"
check_output "ExternalDNS : propriétaire k8s-par1" '^--txt-owner-id=k8s-par1$' printf '%s\n' "$_m15_e41_args"
check_output "ExternalDNS : source gateway-httproute" '^--source=gateway-httproute$' printf '%s\n' "$_m15_e41_args"
check_cmd "ExternalDNS : Deployment disponible" \
  _m15x_jq '[.items[] | select((.status.availableReplicas // 0) >= 1)] | length > 0' -n external-dns deploy
check_cmd "le ClusterRole d'ExternalDNS permet list et watch sur les HTTPRoute" bash -c '
  for r in $(kubectl --kubeconfig "$1" get clusterrolebindings -o json | jq -r ".items[] | select(.roleRef.kind == \"ClusterRole\") | select([.subjects[]? | select(.kind == \"ServiceAccount\" and .namespace == \"external-dns\")] | length > 0) | .roleRef.name" | sort -u); do
    kubectl --kubeconfig "$1" get clusterrole "$r" -o json | jq -e "[.rules[]? | select(((.apiGroups // []) | index(\"gateway.networking.k8s.io\") != null or index(\"*\") != null) and ((.resources // []) | index(\"httproutes\") != null or index(\"*\") != null)) | .verbs[]] | (index(\"list\") != null or index(\"*\") != null) and (index(\"watch\") != null or index(\"*\") != null)" >/dev/null && exit 0
  done
  exit 1' _ "$_m15_e41_kc"
check_output "$_m15x_hote publié sur dns01 vers $_m15x_gw_ip" "^${_m15x_gw_ip//./\\.}\$" _m15x_dig "$_m15x_hote"
check_output "$_m15x_hote présent sur le secondaire dns02" "^${_m15x_gw_ip//./\\.}\$" _m15x_dig "$_m15x_hote" A 10.10.20.16
check_output "enregistrement TXT de propriété : external-dns/owner=k8s-par1" 'external-dns/owner=k8s-par1' \
  bash -c 'for n in "$1" "a-$1" "cname-$1"; do dig +short +norec +time=3 +tries=1 -p 5300 @10.10.20.10 "$n" TXT; done' _ "$_m15x_hote"
if kube -n "$_m15x_ns_app" get httproute temoin-dns >/dev/null 2>&1; then
  check_output "route témoin temoin-dns publiée" "^${_m15x_gw_ip//./\\.}\$" _m15x_dig "temoin-dns.$_m15x_zone"
else
  check_cmd "aucun nom orphelin : temoin-dns.$_m15x_zone n'est plus publié (route absente)" \
    test -n "$(_m15x_dig "$_m15x_hote")" -a -z "$(_m15x_dig "temoin-dns.$_m15x_zone")"
fi
check_cmd "panne M15-E41 close (lab/bin/break 15 41 --annuler après réparation)" _m15x_aucune_panne_active E41
