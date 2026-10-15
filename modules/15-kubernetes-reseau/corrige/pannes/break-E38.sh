# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E38.sh — M15-E38 « Panne : l'adresse du LoadBalancer est injoignable »
#
# Variantes :
#   1. pool LB IPAM lb-par1 désactivé (spec.disabled) ; les adresses déjà attribuées restent, mais
#      le nouveau Service témoin wb-pannes/temoin-lb reste en <pending> ;
#   2. CiliumBGPAdvertisement : « LoadBalancerIP » remplacé par « ExternalIP » (doc ancienne) :
#      les IP de service ne sont plus annoncées, la bordure retire les routes ;
#   3. CiliumBGPClusterConfig bgp-par1 : valeur de l'étiquette du nodeSelector mise en majuscules
#      (ou suffixée) : plus aucun nœud ne parle BGP ;
#   4. CiliumBGPClusterConfig bgp-par1 : localASN 65040 → 64040 (faute de frappe) : la bordure
#      refuse l'OPEN (Bad Peer AS) ;
#   5. bordure : sur la passerelle de SECOURS seulement (celle qui ne porte pas la VIP), la liste
#      PL-DEPUIS-K8S perd « le 32 » dans la configuration courante de FRR (rien sur disque) : elle
#      n'accepte plus les /32 des services. Panne latente (visible à la prochaine bascule).
# Les variantes 2 à 4 coupent toute l'entrée du cluster depuis le réseau d'administration.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m15-commun.sh
source "$WB_ROOT/modules/15-kubernetes-reseau/corrige/pannes/_m15-commun.sh"

_E38_SVC=temoin-lb

_e38_entree_coupee() { ! m15_tcp "$_M15_GW_IP" 443; }
_e38_temoin_pending() {
  [[ -z "$(m15_k -n "$_M15_NS_TEMOINS" get svc "$_E38_SVC" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)" ]]
}
_e38_secours_sans_route() {
  local g
  g="$(m15_lire E38 passerelle)"
  [[ -n "$g" ]] || return 1
  remote "$g" "! ip -4 route show proto bgp | grep -q '^10\.10\.41\.'" >/dev/null 2>&1
}

_m15E38_une() {
  local n="$1" ad g asn
  case "$n" in
    1)
      m15_k get ciliumloadbalancerippool "$_M15_POOL" >/dev/null 2>&1 || return 1
      m15_patch_json ciliumloadbalancerippool "$_M15_POOL" "" '.spec.disabled = true' || return 10
      m15_sauver svc "$_E38_SVC" "$_M15_NS_TEMOINS"
      m15_k apply -f - >/dev/null 2>&1 <<EOF || return 1
apiVersion: v1
kind: Service
metadata:
  name: $_E38_SVC
  namespace: $_M15_NS_TEMOINS
spec:
  type: LoadBalancer
  selector: {app.kubernetes.io/name: sonde}
  ports:
    - {name: sonde, port: 8080, targetPort: 8080}
EOF
      ;;
    2)
      local vu=0
      while read -r ad; do
        [[ -n "$ad" ]] || continue
        if m15_patch_json ciliumbgpadvertisement "$ad" "" \
          '.spec.advertisements |= map(if .advertisementType == "Service" then .service.addresses |= map(if . == "LoadBalancerIP" then "ExternalIP" else . end) else . end)'; then
          printf '%s\n' "$ad" >>"$(m15_etat E38)/annonces"
          vu=1
        fi
      done < <(m15_k get ciliumbgpadvertisements -o json 2>/dev/null \
        | jq -r '.items[] | select([.spec.advertisements[]? | select(.advertisementType == "Service") | .service.addresses[]?] | index("LoadBalancerIP")) | .metadata.name')
      ((vu)) || return 10
      ;;
    3)
      m15_k get ciliumbgpclusterconfig "$_M15_BGP" -o json 2>/dev/null \
        | jq -e '.spec.nodeSelector.matchLabels | length > 0' >/dev/null || return 10
      m15_patch_json ciliumbgpclusterconfig "$_M15_BGP" "" \
        '.spec.nodeSelector.matchLabels |= (to_entries | .[0].value = (if .[0].value == "" then "true" elif (.[0].value | ascii_upcase) != .[0].value then (.[0].value | ascii_upcase) else .[0].value + "-1" end) | from_entries)' || return 1
      m15_ecrire E38 bgp_pose "$(m15_k get ciliumbgpclusterconfig "$_M15_BGP" -o json | jq -cS '.spec')"
      ;;
    4)
      asn="$(m15_k get ciliumbgpclusterconfig "$_M15_BGP" -o jsonpath='{.spec.bgpInstances[0].localASN}' 2>/dev/null)"
      [[ "$asn" == 65040 ]] || return 10
      m15_patch_json ciliumbgpclusterconfig "$_M15_BGP" "" '.spec.bgpInstances |= map(if .localASN == 65040 then .localASN = 64040 else . end)' || return 1
      m15_ecrire E38 bgp_pose "$(m15_k get ciliumbgpclusterconfig "$_M15_BGP" -o json | jq -cS '.spec')"
      ;;
    5)
      g="$(m15_passerelle_secours)"
      [[ -n "$g" ]] || return 10
      m15_ecrire E38 passerelle "$g"
      wb_exec "$g" <<'EOF' || return 10
command -v vtysh >/dev/null 2>&1 || exit 1
avant="$(vtysh -c 'show ip prefix-list PL-DEPUIS-K8S' 2>/dev/null)"
printf '%s\n' "$avant" | grep 'seq 10 permit 10\.10\.41\.0/24' | grep -q 'le 32' || exit 1
ip -4 route show proto bgp | grep -q '^10\.10\.41\.' || exit 1
printf '%s\n' "$avant" > "$WB_DIR/$WB_EX.prefix-list.orig"
vtysh -c 'configure terminal' -c 'no ip prefix-list PL-DEPUIS-K8S seq 10' \
  -c 'ip prefix-list PL-DEPUIS-K8S seq 10 permit 10.10.41.0/24' -c 'end' >/dev/null || exit 1
vtysh -c 'clear bgp ipv4 unicast * soft in' >/dev/null 2>&1 || true
journal "PL-DEPUIS-K8S seq 10 : « le 32 » retiré (configuration courante seulement)"
EOF
      ;;
  esac
  m15_journal E38 "variante $n posée"
}

panne_E38_v1() { m15_preparer && m15_essayer E38 5 1; }
panne_E38_v2() { m15_preparer && m15_essayer E38 5 2; }
panne_E38_v3() { m15_preparer && m15_essayer E38 5 3; }
panne_E38_v4() { m15_preparer && m15_essayer E38 5 4; }
panne_E38_v5() { m15_preparer && m15_essayer E38 5 5; }

verifier_E38() {
  case "$WB_VAR" in
    1) sleep 20; _e38_temoin_pending ;;
    # Avec le redémarrage gracieux (M15-E25), la bordure garde les routes « périmées » jusqu'à
    # restartTimeSeconds avant de les retirer.
    2 | 3 | 4) m15_attendre 300 _e38_entree_coupee ;;
    5) m15_attendre 60 _e38_secours_sans_route ;;
    *) return 1 ;;
  esac
}

annuler_E38() {
  local ad g f pose
  if [[ "$(m15_k get ciliumloadbalancerippool "$_M15_POOL" -o jsonpath='{.spec.disabled}' 2>/dev/null || true)" == true ]]; then
    m15_remettre ciliumloadbalancerippool "$_M15_POOL" ""
  fi
  m15_k -n "$_M15_NS_TEMOINS" delete svc "$_E38_SVC" --ignore-not-found >/dev/null 2>&1 || true
  f="$(m15_etat E38)/annonces"
  if [[ -f "$f" ]]; then
    while read -r ad; do
      if m15_k get ciliumbgpadvertisement "$ad" -o json 2>/dev/null \
        | jq -e '[.spec.advertisements[]? | select(.advertisementType == "Service") | .service.addresses[]?] | (index("LoadBalancerIP") | not)' >/dev/null 2>&1; then
        m15_remettre ciliumbgpadvertisement "$ad" ""
      fi
    done <"$f"
  fi
  pose="$(m15_lire E38 bgp_pose)"
  if [[ -n "$pose" && "$(m15_k get ciliumbgpclusterconfig "$_M15_BGP" -o json 2>/dev/null | jq -cS '.spec' 2>/dev/null || true)" == "$pose" ]]; then
    m15_remettre ciliumbgpclusterconfig "$_M15_BGP" ""
  fi
  g="$(m15_lire E38 passerelle)"
  if [[ -n "$g" ]]; then
    wb_exec "$g" <<'EOF' || wb_avert "annulation : PL-DEPUIS-K8S non rétablie sur la passerelle de secours"
l="$(vtysh -c 'show ip prefix-list PL-DEPUIS-K8S' 2>/dev/null | grep 'seq 10 permit 10\.10\.41\.0/24' | head -n 1)"
if [ -n "$l" ] && ! printf '%s' "$l" | grep -q ' le '; then
  vtysh -c 'configure terminal' -c 'no ip prefix-list PL-DEPUIS-K8S seq 10' \
    -c 'ip prefix-list PL-DEPUIS-K8S seq 10 permit 10.10.41.0/24 le 32' -c 'end' >/dev/null
  vtysh -c 'clear bgp ipv4 unicast * soft in' >/dev/null 2>&1 || true
  journal "annulation : PL-DEPUIS-K8S seq 10 rétablie"
fi
rm -f "$WB_DIR/$WB_EX.prefix-list.orig"
EOF
  fi
  m15_oublier E38
}

resume_E38() {
  case "${WB_VAR:-}" in
    1) echo "Un nouveau Service LoadBalancer reste sans adresse (EXTERNAL-IP <pending>)." ;;
    5) echo "La sonde de la bordure signale qu'une passerelle n'a plus de route vers les services Kubernetes." ;;
    *) echo "Plus aucune adresse de 10.10.41.0/24 (Gateway comprise) ne répond depuis le réseau d'administration." ;;
  esac
}

symptome_E38() {
  case "$WB_VAR" in
    1)
      wb_symptome "Ticket INC-4244 — De : Julien Petit" \
        "Je viens de créer un Service LoadBalancer de test ($_M15_NS_TEMOINS/$_E38_SVC) : il reste en" \
        "EXTERNAL-IP <pending> depuis un quart d'heure. Les applications déjà publiées marchent." \
        "C'est bloquant : MédiDoc doit avoir son adresse demain." \
        "" \
        "Temps cible : 45 min. Contrôle : lab/bin/check 15 38"
      ;;
    5)
      wb_symptome "Ticket INC-4244 — De : Nadia Roussel" \
        "La sonde réseau de la bordure (M07) signale depuis cette nuit : « $(m15_lire E38 passerelle) : aucune" \
        "route vers 10.10.41.0/24 ». Tout fonctionne pour les utilisateurs. Karim doit arrêter" \
        "l'autre passerelle jeudi pour maintenance : je veux savoir si on sera en panne ce jour-là," \
        "et que ce soit corrigé avant. Ne bascule PAS la VIP pour tester." \
        "" \
        "Temps cible : 45 min. Contrôle : lab/bin/check 15 38"
      ;;
    *)
      wb_symptome "Ticket INC-4244 — De : Nadia Roussel — priorité P2" \
        "Depuis 10 minutes, plus aucun service du cluster n'est joignable depuis adm01 ni depuis les" \
        "postes : https://$_M15_HOTE/ expire, comme l'interface Hubble, et rien ne répond sur" \
        "$_M15_GW_IP:443. Les pods tournent, et depuis les nœuds Kubernetes eux-mêmes ça répond." \
        "Lucas a « appliqué les derniers changements de la configuration réseau du cluster » ce matin." \
        "" \
        "Temps cible : 45 min. Contrôle : lab/bin/check 15 38"
      ;;
  esac
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 15 E38 5 "$@"; }
fi
