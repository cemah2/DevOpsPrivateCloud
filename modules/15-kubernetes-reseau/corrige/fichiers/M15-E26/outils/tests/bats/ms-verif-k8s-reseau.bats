#!/usr/bin/env bats
# Tests de bin/ms-verif-k8s-reseau (M15-E26). Aucun accès réseau ni cluster : kubectl, curl, dig et ssh
# sont remplacés par des fonctions (prioritaires sur les commandes du PATH) qui répondent selon des
# variables d'état préparées par chaque test. Chaque contrôle a au moins un test « rouge ».
# Prérequis : le script charge lib/ms-commun.sh (M02-E20) : les tests tournent dans plateforme/outils.
# shellcheck disable=SC2329,SC2317,SC2034
# shellcheck source-path=SCRIPTDIR

setup() {
  # shellcheck source=../../bin/ms-verif-k8s-reseau
  source "$BATS_TEST_DIRNAME/../../bin/ms-verif-k8s-reseau"
  D="$BATS_TEST_TMPDIR"
  : >"$D/kubeconfig"
  export MS_CONF="$D/ms-verif-k8s-reseau.conf"
  cat >"$MS_CONF" <<FIN
MS_K8S_KUBECONFIG=$D/kubeconfig
MS_K8S_DAEMONSETS=(kube-system/cilium)
MS_K8S_DEPLOIEMENTS=(kube-system/cilium-operator)
MS_K8S_NB_NOEUDS=2
MS_K8S_NOEUDS=(10.0.0.1 10.0.0.2)
MS_K8S_PORT_AGENT=9962
MS_K8S_BGP_SESSIONS_MIN=2
MS_K8S_RESEAU_NOEUDS=10.10.40.
MS_K8S_BGP_SESSIONS_MAITRE_MIN=1
MS_K8S_ADRESSES_SERVICE=(10.10.41.10)
MS_K8S_SAUTS_MIN=2
MS_SSH_CLE=/dev/null
MS_SSH_COMPTE=supervision
MS_PASSERELLES=(gw01 gw02)
MS_DNS=127.0.0.1
MS_RACINE=/dev/null
MS_K8S_NOMS=(app.apps.test=10.10.41.10)
FIN

  # État simulé (modifié par les tests).
  API=ok
  DS_PREVUS=2; DS_PRETS=2
  DEP_PRETS=2
  CLES="k1 k2"
  BGP_ETATS="established established"
  CERT_PRET=True
  CERT_FIN="2099-01-01T00:00:00Z"
  INJOIGNABLES=0
  METRIQUES_OK=1
  MAITRE=gw01
  SAUTS='["10.10.40.61","10.10.40.62"]'
  DNS_IP=10.10.41.10
  HTTPS_CODE=200

  kubectl() {
    local a="$*"
    case "$a" in
      *"get --raw /readyz"*) [[ "$API" == ok ]] && echo ok || return 1 ;;
      *daemonset*) printf '{"status":{"desiredNumberScheduled":%d,"numberReady":%d,"updatedNumberScheduled":%d}}\n' "$DS_PREVUS" "$DS_PRETS" "$DS_PREVUS" ;;
      *deployment*) printf '{"spec":{"replicas":2},"status":{"readyReplicas":%d}}\n' "$DEP_PRETS" ;;
      *ciliumnodes*)
        local k items="" i=0
        for k in $CLES; do
          i=$((i + 1))
          [[ "$k" == - ]] && k=""
          items+="${items:+,}{\"metadata\":{\"name\":\"n$i\",\"annotations\":{\"network.cilium.io/wg-pub-key\":\"$k\"}}}"
        done
        echo "{\"items\":[$items]}" ;;
      *ciliumbgpnodeconfigs*)
        local e pairs=""
        for e in $BGP_ETATS; do pairs+="${pairs:+,}{\"peerAddress\":\"10.10.40.2\",\"peeringState\":\"$e\"}"; done
        echo "{\"items\":[{\"metadata\":{\"name\":\"k8s-w01\"},\"status\":{\"bgpInstances\":[{\"peers\":[$pairs]}]}}]}" ;;
      *certificates*)
        echo "{\"items\":[{\"metadata\":{\"namespace\":\"passerelles\",\"name\":\"apps-joker\"},\"status\":{\"notAfter\":\"$CERT_FIN\",\"conditions\":[{\"type\":\"Ready\",\"status\":\"$CERT_PRET\"}]}}]}" ;;
      *) return 1 ;;
    esac
  }
  curl() {
    local a="$*"
    if [[ "$a" == *":9962/metrics"* ]]; then
      ((METRIQUES_OK)) || return 22
      printf 'cilium_version 1\ncilium_unreachable_nodes %d\n' "$INJOIGNABLES"
    else
      printf '%s' "$HTTPS_CODE"
    fi
  }
  dig() { echo "$DNS_IP"; }
  ssh() {
    local h etat=BACKUP
    for h in "$@"; do :; done
    h="${*: -2:1}"
    [[ "$h" == *"$MAITRE" ]] && etat=MASTER
    printf '{"etat_bordure":"%s","adresses":[],"bgp":[{"voisin":"10.10.40.61","etat":"Established"}],"routes_service":[{"dst":"10.10.41.10","type":"unicast","sauts":%s}]}\n' "$etat" "$SAUTS"
  }
}

@test "cluster sain : code 0" {
  run main --quiet
  [ "$status" -eq 0 ]
  [[ "$output" == *"Bilan"* ]]
}

@test "option inconnue : code 2" {
  run main --nimporte-quoi
  [ "$status" -eq 2 ]
}

@test "seuil invalide : code 2" {
  run main -s 0
  [ "$status" -eq 2 ]
}

@test "configuration absente : code 1" {
  MS_CONF="$D/absente.conf" run main
  [ "$status" -eq 1 ]
}

@test "API injoignable : code 1" {
  API=ko
  run main --quiet
  [ "$status" -eq 1 ]
  [[ "$output" == *"API du cluster injoignable"* ]]
}

@test "DaemonSet incomplet : code 1" {
  DS_PRETS=1
  run main --quiet
  [ "$status" -eq 1 ]
  [[ "$output" == *"kube-system/cilium : 1/2"* ]]
}

@test "opérateur non prêt : code 1" {
  DEP_PRETS=0
  run main --quiet
  [ "$status" -eq 1 ]
  [[ "$output" == *"cilium-operator : 0/2"* ]]
}

@test "nœud sans clé WireGuard : code 1" {
  CLES="k1 -"
  run main --quiet
  [ "$status" -eq 1 ]
  [[ "$output" == *"sans clé WireGuard"* ]]
}

@test "session BGP non établie : code 1, nœud et pair dans le message" {
  BGP_ETATS="established active"
  run main --quiet
  [ "$status" -eq 1 ]
  [[ "$output" == *"k8s-w01→10.10.40.2:active"* ]]
}

@test "certificat non prêt : code 1" {
  CERT_PRET=False
  run main --quiet
  [ "$status" -eq 1 ]
  [[ "$output" == *"apps-joker non prêt"* ]]
}

@test "certificat proche de l'expiration : code 1" {
  CERT_FIN="$(date -u -d '+3 days' +%Y-%m-%dT%H:%M:%SZ)"
  run main --quiet
  [ "$status" -eq 1 ]
  [[ "$output" == *"expire dans moins de 10 jours"* ]]
}

@test "métriques d'un agent injoignables : code 1" {
  METRIQUES_OK=0
  run main --quiet
  [ "$status" -eq 1 ]
  [[ "$output" == *"métriques de l'agent injoignables"* ]]
}

@test "agent qui voit un nœud injoignable : code 1" {
  INJOIGNABLES=1
  run main --quiet
  [ "$status" -eq 1 ]
  [[ "$output" == *"ne joint pas 1 nœud"* ]]
}

@test "aucune passerelle maître : code 1" {
  MAITRE=personne
  run main --quiet
  [ "$status" -eq 1 ]
  [[ "$output" == *"aucune passerelle maître"* ]]
}

@test "adresse de service installée vers un seul nœud : code 1" {
  SAUTS='["10.10.40.61"]'
  run main --quiet
  [ "$status" -eq 1 ]
  [[ "$output" == *"10.10.41.10 installée vers 1 nœud"* ]]
}

@test "nom publié qui résout mal : code 1" {
  DNS_IP=10.10.41.99
  run main --quiet
  [ "$status" -eq 1 ]
  [[ "$output" == *"résout vers « 10.10.41.99 »"* ]]
}

@test "nom publié dont le HTTPS échoue : code 1" {
  HTTPS_CODE=000
  run main --quiet
  [ "$status" -eq 1 ]
  [[ "$output" == *"HTTPS 000"* ]]
}
