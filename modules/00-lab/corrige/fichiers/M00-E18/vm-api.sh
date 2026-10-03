#!/usr/bin/env bash
# =============================================================================
# vm-api.sh — cycle de vie d'une VM sandbox par l'API Proxmox (M00-E18)
#
# Uniquement curl et jq, depuis adm01, avec le jeton wb-automation@pve!lab.
#
# Usage : vm-api.sh create | ip | destroy | cycle
#   create   clone le template, configure cloud-init, démarre, attend l'agent
#   ip       affiche l'adresse IPv4 de la VM (via l'agent QEMU)
#   destroy  arrête et détruit la VM (refuse si ce n'est pas notre sandbox)
#   cycle    create + ip + test SSH + destroy
#
# Variables (facultatives) :
#   VMID=5001 VMNAME=sbx01 IPCONFIG="ip=dhcp"   (ou "ip=10.10.99.20/24,gw=10.10.99.1")
#   NET0="virtio,bridge=vmbr1,tag=99"           (après M00-E28 : "virtio,bridge=vsandbox")
#   PVE_ENV_FILE=~/.config/workbook/pve-api.env
#
# Codes retour : 0 succès, 1 erreur (message explicite sur stderr), 2 usage.
# =============================================================================
set -euo pipefail
umask 077

readonly ENV_FILE="${PVE_ENV_FILE:-$HOME/.config/workbook/pve-api.env}"
readonly TEMPLATE_ID=9000
readonly VMID="${VMID:-5001}"
readonly VMNAME="${VMNAME:-sbx01}"
readonly POOL="lab"
readonly NET0="${NET0:-virtio,bridge=vmbr1,tag=99}"   # après M00-E28 (SDN) : virtio,bridge=vsandbox
readonly IPCONFIG="${IPCONFIG:-ip=dhcp}"
readonly SSH_PUBKEY_FILE="${SSH_PUBKEY_FILE:-$HOME/.ssh/id_ed25519.pub}"
readonly TASK_TIMEOUT=600     # s, durée max d'une tâche Proxmox
readonly AGENT_TIMEOUT=300    # s, démarrage de l'invité jusqu'à l'agent QEMU
readonly SSH_TIMEOUT=120      # s, fin de cloud-init (clé SSH posée)

log() { printf '[%s] %s\n' "$(date +%T)" "$*" >&2; }
die() { printf 'ERREUR : %s\n' "$*" >&2; exit 1; }

# --- Préparation ----------------------------------------------------------------
for c in curl jq; do
  command -v "$c" >/dev/null 2>&1 || die "outil manquant : $c"
done
[[ -r "$ENV_FILE" ]] || die "fichier d'accès à l'API illisible : $ENV_FILE"
# shellcheck source=/dev/null
source "$ENV_FILE"
: "${PVE_API_URL:?absent de $ENV_FILE}" "${PVE_NODE:?absent de $ENV_FILE}"
: "${PVE_TOKEN_ID:?absent de $ENV_FILE}" "${PVE_TOKEN_SECRET:?absent de $ENV_FILE}"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# L'en-tête d'authentification est passé par fichier (curl -H @fichier) :
# le secret n'apparaît ni dans « ps », ni dans l'historique, ni dans « set -x ».
AUTH_HEADER="$WORKDIR/auth"
printf 'Authorization: PVEAPIToken=%s=%s\n' "$PVE_TOKEN_ID" "$PVE_TOKEN_SECRET" >"$AUTH_HEADER"
unset PVE_TOKEN_SECRET

# --- Appels à l'API -------------------------------------------------------------
# _call MÉTHODE CHEMIN [clé=valeur ...]
#   Corps de la réponse dans $WORKDIR/body ; renvoie 0 si HTTP 2xx.
#   API_STATUS contient la ligne de statut HTTP : Proxmox y met le motif de
#   l'erreur (ex. « 403 Permission check failed (/vms/5001, VM.Allocate) »).
API_STATUS=""
_call() {
  local method="$1" path="$2"; shift 2
  local -a args=(--silent --show-error --max-time 60 -X "$method"
                 -H "@$AUTH_HEADER" -D "$WORKDIR/headers" -o "$WORKDIR/body"
                 -w '%{http_code}')
  if [[ -n "${PVE_CACERT:-}" ]]; then
    args+=(--cacert "$PVE_CACERT")
  fi
  if [[ "$method" == GET || "$method" == DELETE ]]; then
    args+=(-G)    # paramètres dans l'URL (query string)
  fi
  local kv
  for kv in "$@"; do
    args+=(--data-urlencode "$kv")
  done
  local code
  code="$(curl "${args[@]}" "${PVE_API_URL}${path}")" || die "échec réseau ou TLS : $method $path"
  API_STATUS="$(head -n 1 "$WORKDIR/headers" | tr -d '\r')"
  [[ "$code" == 2?? ]]
}

# api MÉTHODE CHEMIN [clé=valeur ...] — comme _call, mais toute erreur est fatale.
api() {
  _call "$@" || die "$1 $2 → $API_STATUS"
  cat "$WORKDIR/body"
}

uri() { jq -rn --arg v "$1" '$v | @uri'; }

# wait_task UPID — attend la fin d'une tâche asynchrone et vérifie son résultat.
# Toujours affecter l'UPID à une variable AVANT d'appeler wait_task :
# « wait_task "$(api ...)" » masquerait un échec de api (set -e ne s'applique pas
# à une substitution utilisée comme argument).
wait_task() {
  local upid="$1" deadline=$((SECONDS + TASK_TIMEOUT)) st exitstatus
  [[ -n "$upid" && "$upid" != null ]] || return 0   # rien d'asynchrone à attendre
  while :; do
    st="$(api GET "/nodes/${PVE_NODE}/tasks/$(uri "$upid")/status")"
    if [[ "$(jq -r '.data.status' <<<"$st")" == stopped ]]; then
      exitstatus="$(jq -r '.data.exitstatus' <<<"$st")"
      case "$exitstatus" in
        OK) return 0 ;;
        WARNINGS*) log "tâche terminée avec avertissements ($exitstatus) : $upid"; return 0 ;;
        *) die "tâche en échec ($exitstatus) : $upid" ;;
      esac
    fi
    (( SECONDS < deadline )) || die "tâche toujours en cours après ${TASK_TIMEOUT}s : $upid"
    sleep 2
  done
}

# vmid_is_free — vrai si le VMID n'est utilisé par AUCUNE VM du nœud (même hors
# de nos droits : /cluster/nextid ne dépend pas des permissions).
#   Proxmox répond 400 si le VMID est pris ; tout autre échec (jeton refusé,
#   réseau…) est fatal, pour ne pas le confondre avec « VMID pris ».
vmid_is_free() {
  if _call GET /cluster/nextid "vmid=${VMID}"; then
    return 0
  fi
  if [[ "$API_STATUS" == *" 400 "* ]]; then
    return 1
  fi
  die "GET /cluster/nextid → $API_STATUS"
}

# our_vm — vrai si la VM existe, est visible par le jeton, porte le nom attendu
# et appartient au pool lab. Garde-fou avant toute action destructrice.
our_vm() {
  local res
  res="$(api GET /cluster/resources type=vm)"
  jq -e --argjson id "$VMID" --arg n "$VMNAME" --arg p "$POOL" \
    '.data[] | select(.vmid == $id and .name == $n and .pool == $p)' <<<"$res" >/dev/null
}

# --- Actions --------------------------------------------------------------------
create() {
  vmid_is_free || die "le VMID $VMID est déjà pris : rien n'a été modifié"
  [[ -r "$SSH_PUBKEY_FILE" ]] || die "clé publique SSH introuvable : $SSH_PUBKEY_FILE"

  local upid
  log "clone lié du template $TEMPLATE_ID vers $VMID ($VMNAME), pool $POOL"
  upid="$(api POST "/nodes/${PVE_NODE}/qemu/${TEMPLATE_ID}/clone" \
    "newid=${VMID}" "name=${VMNAME}" "pool=${POOL}" "full=0" | jq -r '.data')"
  wait_task "$upid"

  # sshkeys : l'API attend la valeur DÉJÀ encodée en URL (espaces en %20, pas en +),
  # puis curl l'encode une seconde fois pour le formulaire. Sans cela, la clé
  # arrive tronquée ou refusée (« invalid urlencoded string »).
  local keys
  keys="$(jq -rn --rawfile k "$SSH_PUBKEY_FILE" '$k | @uri')"
  # L'agent QEMU est déjà activé dans le template (M00-E11) : ne pas redéfinir
  # « agent », on écraserait ses options (fstrim_cloned_disks…).
  log "configuration réseau et cloud-init (net0 VLAN 99, ${IPCONFIG})"
  upid="$(api POST "/nodes/${PVE_NODE}/qemu/${VMID}/config" \
    "net0=${NET0}" "ipconfig0=${IPCONFIG}" \
    "nameserver=10.10.20.10" "searchdomain=par1.medisphere.internal" \
    "ciuser=admin" "sshkeys=${keys}" | jq -r '.data // empty')"
  wait_task "$upid"

  log "démarrage"
  upid="$(api POST "/nodes/${PVE_NODE}/qemu/${VMID}/status/start" | jq -r '.data')"
  wait_task "$upid"

  log "attente de l'agent QEMU (au plus ${AGENT_TIMEOUT}s)"
  local deadline=$((SECONDS + AGENT_TIMEOUT))
  until _call POST "/nodes/${PVE_NODE}/qemu/${VMID}/agent/ping"; do
    (( SECONDS < deadline )) || die "l'agent QEMU ne répond pas après ${AGENT_TIMEOUT}s ($API_STATUS)"
    sleep 3
  done
  log "agent QEMU opérationnel"
}

# get_ip — première adresse IPv4 hors boucle locale vue par l'agent (vide si aucune).
get_ip() {
  _call GET "/nodes/${PVE_NODE}/qemu/${VMID}/agent/network-get-interfaces" || return 0
  jq -r '[.data.result[]
          | select(.name != "lo")
          | .["ip-addresses"][]?
          | select(.["ip-address-type"] == "ipv4")
          | .["ip-address"]] | first // empty' "$WORKDIR/body"
}

show_ip() {
  local ip="" deadline=$((SECONDS + 60))
  while [[ -z "$ip" ]]; do
    ip="$(get_ip)"
    if [[ -z "$ip" ]]; then
      (( SECONDS < deadline )) || die "pas d'adresse IPv4 remontée par l'agent après 60s (DHCP ?)"
      sleep 3
    fi
  done
  printf '%s\n' "$ip"
}

destroy() {
  if vmid_is_free; then
    log "la VM $VMID n'existe pas : rien à détruire"
    return 0
  fi
  our_vm || die "la VM $VMID n'est pas $VMNAME dans le pool $POOL (ou n'est pas visible) : destruction refusée"

  local status upid
  status="$(api GET "/nodes/${PVE_NODE}/qemu/${VMID}/status/current" | jq -r '.data.status')"
  if [[ "$status" == running ]]; then
    # Sandbox jetable : arrêt immédiat. Pour une vraie VM : status/shutdown avec
    # timeout, puis stop seulement si l'invité ne s'éteint pas.
    log "arrêt de $VMID"
    upid="$(api POST "/nodes/${PVE_NODE}/qemu/${VMID}/status/stop" | jq -r '.data')"
    wait_task "$upid"
  fi
  log "destruction de $VMID (purge des références, disques orphelins compris)"
  upid="$(api DELETE "/nodes/${PVE_NODE}/qemu/${VMID}" \
    "purge=1" "destroy-unreferenced-disks=1" | jq -r '.data')"
  wait_task "$upid"
  log "VM $VMID détruite"
}

ssh_test() {
  local ip="$1" deadline=$((SECONDS + SSH_TIMEOUT))
  log "test SSH vers admin@${ip} (cloud-init peut encore poser la clé)"
  until ssh -o BatchMode=yes -o ConnectTimeout=5 \
            -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
            "admin@${ip}" 'cloud-init status --wait >/dev/null || true; hostname'; do
    (( SECONDS < deadline )) || die "SSH vers ${ip} impossible après ${SSH_TIMEOUT}s"
    sleep 5
  done
}

cycle() {
  local t0=$SECONDS ip
  create
  ip="$(show_ip)"
  log "adresse de ${VMNAME} : ${ip}"
  ssh_test "$ip"
  destroy
  log "cycle complet en $((SECONDS - t0))s"
}

case "${1:-}" in
  create)  create ;;
  ip)      show_ip ;;
  destroy) destroy ;;
  cycle)   cycle ;;
  *) echo "Usage : $0 create|ip|destroy|cycle" >&2; exit 2 ;;
esac
