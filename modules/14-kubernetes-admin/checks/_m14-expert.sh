# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et commandes distantes ou bash -c entre apostrophes
# _m14-expert.sh — fonctions partagées par les vérifications du palier 4 et du mini-projet du module 14
# (check-E35 à check-E46). Sourcé par ces scripts, jamais lancé seul. Lecture seule : kubectl en
# lecture avec le compte de service des checks (fonction « kube » de check-lib.sh), commandes de
# consultation sur les nœuds (systemctl is-active, grep, openssl, etcdctl endpoint/member/alarm list).
# Préfixe _m14x_ : évite les collisions quand check-E43 et check-E46 chargent plusieurs checks.

_m14x_ns=wb-pannes
_m14x_vip=10.10.40.200
_m14x_api=k8s-api.par1.medisphere.internal
_m14x_depot="${WB_DEPOT:-$HOME/medisphere}"
read -r -a _m14x_cp <<<"${WB_K8S_CP:-k8s-cp01 k8s-cp02 k8s-cp03}"
read -r -a _m14x_w <<<"${WB_K8S_WORKERS:-k8s-w01 k8s-w02 k8s-w03}"
# shellcheck disable=SC2034  # utilisées par les checks qui sourcent ce fichier
declare -A _m14x_ip=([k8s-cp01]=10.10.40.51 [k8s-cp02]=10.10.40.52 [k8s-cp03]=10.10.40.53
  [k8s-w01]=10.10.40.61 [k8s-w02]=10.10.40.62 [k8s-w03]=10.10.40.63)

# _m14x_kq 'filtre jq' ARGS… — 0 si « kube get ARGS -o json » satisfait le filtre.
_m14x_kq() {
  local f="$1"
  shift
  kube get "$@" -o json 2>/dev/null | jq -e "$f" >/dev/null 2>&1
}

# _m14x_api_repond — l'API répond au compte des checks (garde-fou commun).
_m14x_api_repond() { kube get --raw /livez >/dev/null 2>&1; }

# _m14x_noeud HÔTE 'commande' — commande de lecture en root (sudo -n) sur un nœud ; code de retour.
_m14x_noeud() { remote "$1" "sudo -n bash -c $(printf '%q' "$2")" </dev/null >/dev/null 2>&1; }
# _m14x_noeud_sortie HÔTE 'commande' — idem, sortie standard.
_m14x_noeud_sortie() { remote "$1" "sudo -n bash -c $(printf '%q' "$2")" </dev/null 2>/dev/null; }

# _M14X_ETCD — préambule distant : etcdctl du nœud (M14-E24) ou du conteneur etcd, certificats
# healthcheck-client, en lecture (endpoint, member list, alarm list, get --keys-only).
# shellcheck disable=SC2016
_M14X_ETCD='crictl_() { crictl --runtime-endpoint unix:///run/containerd/containerd.sock "$@"; }
e_() { p=/etc/kubernetes/pki/etcd
  if command -v etcdctl >/dev/null 2>&1; then
    ETCDCTL_API=3 etcdctl --cacert $p/ca.crt --cert $p/healthcheck-client.crt --key $p/healthcheck-client.key --dial-timeout=5s --command-timeout=20s "$@" </dev/null
  else
    i="$(crictl_ ps -q --name "^etcd\$" --state Running 2>/dev/null </dev/null | head -n 1)"; [ -n "$i" ] || return 1
    crictl_ exec "$i" etcdctl --cacert $p/ca.crt --cert $p/healthcheck-client.crt --key $p/healthcheck-client.key --dial-timeout=5s --command-timeout=20s "$@" </dev/null
  fi; }
EP=https://10.10.40.51:2379,https://10.10.40.52:2379,https://10.10.40.53:2379'

# _m14x_etcd 'commande' — sur le premier nœud de contrôle où etcdctl répond ; sortie standard.
_M14X_ETCD_RELAIS="${_M14X_ETCD_RELAIS:-}"
_m14x_etcd() {
  local h
  if [[ -z "$_M14X_ETCD_RELAIS" ]]; then
    for h in "${_m14x_cp[@]}"; do
      if _m14x_noeud "$h" "$_M14X_ETCD
e_ endpoint health >/dev/null 2>&1"; then
        _M14X_ETCD_RELAIS="$h"
        break
      fi
    done
  fi
  [[ -n "$_M14X_ETCD_RELAIS" ]] || return 1
  _m14x_noeud_sortie "$_M14X_ETCD_RELAIS" "$_M14X_ETCD
$1"
}

# _m14x_aucune_panne_active [EXX…] — aucune des pannes listées (ou M14-* si aucune) n'est marquée.
_m14x_aucune_panne_active() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives" e
  if (($# == 0)); then
    [[ -z "$(find "$d" -maxdepth 1 -name 'M14-E*' 2>/dev/null)" ]]
    return
  fi
  for e in "$@"; do
    [[ ! -e "$d/M14-$e" ]] || return 1
  done
}

# _m14x_temoins — les témoins du palier 4 existent (créés à la première injection).
_m14x_temoins() { kube -n "$_m14x_ns" get deploy agenda >/dev/null 2>&1; }

# _m14x_deploy_pret ESPACE NOM — déploiement entièrement à jour et disponible.
_m14x_deploy_pret() {
  _m14x_kq '(.spec.replicas // 1) as $n | (.status.updatedReplicas // 0) == $n and (.status.availableReplicas // 0) == $n
            and (.status.replicas // 0) == $n and (.status.observedGeneration // 0) >= .metadata.generation' \
    -n "$1" deploy "$2"
}

# _m14x_pods_sans 'filtre jq sur un conteneur en attente' ESPACE… — aucun pod de ces espaces n'a un
# conteneur dont l'état satisfait le filtre (ex. raison ImagePullBackOff).
_m14x_pods_sans() {
  local f="$1" ns
  shift
  for ns in "$@"; do
    kube -n "$ns" get pods -o json 2>/dev/null |
      jq -e "[.items[].status.containerStatuses[]? | select($f)] | length == 0" >/dev/null 2>&1 || return 1
  done
}

# _m14x_espaces_workbook — espaces du workbook qui existent (wb-*, mediagenda-*).
_m14x_espaces_workbook() {
  kube get namespaces -o json 2>/dev/null | jq -r '.items[].metadata.name | select(test("^(wb-|mediagenda-)"))'
}

# _m14x_doc_commite CHEMIN_RELATIF_OU_MOTIF — un fichier du dépôt de documentation correspond au
# motif, il est suivi par git et sans modification en attente.
_m14x_doc_commite() {
  (
    cd "$_m14x_depot" 2>/dev/null || exit 1
    shopt -s nullglob
    # shellcheck disable=SC2206  # motif de chemin voulu
    local -a f=($1)
    ((${#f[@]} > 0)) || exit 1
    git ls-files --error-unmatch "${f[0]}" >/dev/null 2>&1 && [[ -z "$(git status --porcelain -- "${f[0]}")" ]]
  )
}

# _m14x_doc_contient MOTIF 'regex' — le premier fichier correspondant au motif contient la regex.
_m14x_doc_contient() {
  (
    cd "$_m14x_depot" 2>/dev/null || exit 1
    shopt -s nullglob
    # shellcheck disable=SC2206
    local -a f=($1)
    ((${#f[@]} > 0)) || exit 1
    grep -Eqi -- "$2" "${f[0]}"
  )
}

# _m14x_memoire_mio QUANTITÉ — quantité Kubernetes (Ki, Mi, Gi, M, G, octets) en Mio, entier.
_m14x_memoire_mio() {
  local q="$1"
  case "$q" in
    *Ki) echo $((${q%Ki} / 1024)) ;;
    *Mi) echo "${q%Mi}" ;;
    *Gi) echo $((${q%Gi} * 1024)) ;;
    *k) echo $((${q%k} * 1000 / 1048576)) ;;
    *M) echo $((${q%M} * 1000000 / 1048576)) ;;
    *G) echo $((${q%G} * 1000000000 / 1048576)) ;;
    '' | *[!0-9]*) echo 0 ;;
    *) echo $((q / 1048576)) ;;
  esac
}
