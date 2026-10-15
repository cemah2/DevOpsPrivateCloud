# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E36.sh — M15-E36 « Panne : la résolution DNS échoue dans les pods »
#
# Variantes :
#   1. Corefile de CoreDNS : dans le bloc « medisphere.internal », le transfert vise 10.10.20.1
#      (la passerelle, qui ne sert pas de DNS) au lieu de dns01/dns02 : les noms du cluster et
#      d'Internet résolvent, ceux de medisphere.internal expirent ;
#   2. CiliumNetworkPolicy « interdire-kube-system » (egressDeny vers tout kube-system, port 53
#      compris) dans mediagenda-recette, puis redémarrage du Deployment : les nouveaux pods ne
#      résolvent plus rien, le déploiement reste bloqué (les anciens pods servent encore) ;
#   3. dnsPolicy: Default sur le Deployment de MédiAgenda (résolveurs du nœud, qui ne connaissent
#      pas cluster.local) : mêmes symptômes que 2, autre cause.
# Sauvegardes : ConfigMap coredns, CNP (absente), Deployment.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m15-commun.sh
source "$WB_ROOT/modules/15-kubernetes-reseau/corrige/pannes/_m15-commun.sh"

_E36_CNP=interdire-kube-system

# _e36_corefile_casse CORFILE — réécrit les « forward » du seul bloc medisphere.internal.
_e36_corefile_casse() {
  awk '
    /^[[:space:]]*medisphere\.internal(:53)?[[:space:]]*\{/ { bloc = 1 }
    bloc && /^[[:space:]]*forward[[:space:]]/ {
      sub(/forward[[:space:]]+\.[[:space:]]+[^{]*/, "forward . 10.10.20.1 ")
      vu = 1
    }
    bloc && /^[[:space:]]*\}[[:space:]]*$/ { bloc = 0 }
    { print }
    END { if (!vu) exit 3 }
  '
}

_e36_nom_externe_ko() {
  ! m15_temoin_exec "${_M15_TRAVAILLEURS[0]}" sh -c 'dig +short +time=2 +tries=1 s3-01.par1.medisphere.internal | grep -q .' >/dev/null 2>&1
}

_e36_rollout_bloque() {
  local d
  d="$(m15_lire E36 deploiement)"
  [[ -n "$d" ]] || return 1
  ! m15_k -n "$_M15_NS_APP" rollout status "deploy/$d" --timeout=5s >/dev/null 2>&1
}

_m15E36_une() {
  local n="$1" cf neuf d
  case "$n" in
    1)
      cf="$(m15_k -n kube-system get cm coredns -o json 2>/dev/null | jq -r '.data.Corefile // empty')"
      [[ -n "$cf" ]] || return 1
      neuf="$(_e36_corefile_casse <<<"$cf")" || return 10
      [[ "$neuf" != "$cf" ]] || return 10
      m15_patch_json cm coredns kube-system ".data.Corefile = $(jq -Rs . <<<"$neuf")" || return 1
      m15_ecrire E36 corefile_pose "$(m15_k -n kube-system get cm coredns -o json | jq -j '.data.Corefile' | sha256sum | cut -d' ' -f1)"
      ;;
    2 | 3)
      d="$(m15_deploiement_app)"
      [[ -n "$d" ]] || return 10
      m15_ecrire E36 deploiement "$d"
      m15_sauver deploy "$d" "$_M15_NS_APP"
      if ((n == 2)); then
        m15_sauver cnp "$_E36_CNP" "$_M15_NS_APP"
        m15_k apply -f - >/dev/null 2>&1 <<EOF || return 1
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: $_E36_CNP
  namespace: $_M15_NS_APP
  annotations:
    medisphere.internal/demande: "SEC-1612 : aucune application ne parle aux composants de kube-system"
spec:
  endpointSelector: {}
  enableDefaultDeny:
    egress: false
    ingress: false
  egressDeny:
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: kube-system
EOF
        m15_k -n "$_M15_NS_APP" rollout restart "deploy/$d" >/dev/null 2>&1 || return 1
      else
        [[ "$(m15_k -n "$_M15_NS_APP" get deploy "$d" -o jsonpath='{.spec.template.spec.dnsPolicy}')" != Default ]] || return 10
        m15_k -n "$_M15_NS_APP" patch deploy "$d" --type merge \
          -p '{"spec":{"template":{"spec":{"dnsPolicy":"Default"}}}}' >/dev/null 2>&1 || return 1
      fi
      ;;
  esac
  m15_journal E36 "variante $n posée"
}

panne_E36_v1() { m15_preparer && m15_essayer E36 3 1; }
panne_E36_v2() { m15_preparer && m15_essayer E36 3 2; }
panne_E36_v3() { m15_preparer && m15_essayer E36 3 3; }

verifier_E36() {
  case "$WB_VAR" in
    # Le greffon reload de CoreDNS relit le Corefile en 30 s à 2 min (propagation du ConfigMap).
    1) m15_attendre 180 _e36_nom_externe_ko ;;
    *) sleep 60; _e36_rollout_bloque ;;
  esac
}

annuler_E36() {
  local d h
  h="$(m15_lire E36 corefile_pose)"
  if [[ -n "$h" ]] && [[ "$(m15_k -n kube-system get cm coredns -o json 2>/dev/null | jq -j '.data.Corefile' | sha256sum | cut -d' ' -f1)" == "$h" ]]; then
    m15_remettre cm coredns kube-system
  fi
  m15_k -n "$_M15_NS_APP" delete cnp "$_E36_CNP" --ignore-not-found >/dev/null 2>&1 || true
  d="$(m15_lire E36 deploiement)"
  if [[ -n "$d" && "$(m15_k -n "$_M15_NS_APP" get deploy "$d" -o jsonpath='{.spec.template.spec.dnsPolicy}' 2>/dev/null || true)" == Default ]]; then
    m15_k -n "$_M15_NS_APP" patch deploy "$d" --type merge \
      -p '{"spec":{"template":{"spec":{"dnsPolicy":"ClusterFirst"}}}}' >/dev/null 2>&1 || true
  fi
  m15_oublier E36
}

resume_E36() {
  case "${WB_VAR:-}" in
    1) echo "Depuis les pods, les noms en medisphere.internal (s3-01, registry, ca01) ne résolvent plus." ;;
    *) echo "Le déploiement de MédiAgenda en recette ne se termine pas : les nouveaux pods ne sont jamais prêts." ;;
  esac
}

symptome_E36() {
  case "$WB_VAR" in
    1)
      wb_symptome "Ticket INC-4242 — De : Julien Petit" \
        "Depuis ce matin, nos pods ne trouvent plus nos serveurs internes : MédiDoc en dev échoue" \
        "sur « lookup s3-01.par1.medisphere.internal: i/o timeout » et un pod de test dit pareil pour" \
        "registry.par1.medisphere.internal. Bizarrement, les noms des Services du cluster et" \
        "les noms publics marchent. Depuis adm01, tout résout normalement." \
        "Reproduis avec un témoin : kubectl -n $_M15_NS_TEMOINS exec ds/sonde -- dig s3-01.par1.medisphere.internal" \
        "" \
        "Temps cible : 30 min. Contrôle : lab/bin/check 15 36"
      ;;
    *)
      wb_symptome "Ticket INC-4242 — De : Julien Petit" \
        "Le déploiement de MédiAgenda en recette de ce matin ne se termine pas : un nouveau pod" \
        "reste à 0/1 READY, « kubectl rollout status » attend toujours. Ses journaux parlent" \
        "d'un nom d'hôte de base de données introuvable, alors que la version précédente tourne" \
        "encore sans souci avec exactement la même configuration. Rien n'a changé dans l'image." \
        "" \
        "Temps cible : 30 min. Contrôle : lab/bin/check 15 36"
      ;;
  esac
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 15 E36 3 "$@"; }
fi
