#!/usr/bin/env bash
# alim.sh — pilotage d'alimentation des serveurs du module 11 (M11-E08).
#
#   outils/alim.sh <cible> <action>
#     cibles bm01 … bm99 : VMs Proxmox, par l'API (jeton wb-maas@pve!maas, pve-maas.env)
#        actions : etat | allumer | eteindre | arreter-propre | cycle
#     cible hp01 : iLO 4 en Redfish (outils/redfish.sh, compte wb-redfish)
#        actions : etat | types        — toute action d'alimentation est REFUSÉE
#
# Codes de sortie : 0 fait (ou déjà dans l'état voulu), 1 échec ou délai dépassé,
#                   2 usage ou configuration, 3 action refusée par l'outil.
# Secrets : lus dans les fichiers (jamais exécutés), passés à curl par son entrée standard (-K -).
# TLS : vérifié (ancre de pve01, M02-E08 ; certificat épinglé de l'iLO, M11-E07). Jamais de -k.
set -euo pipefail

ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pve_env="${PVE_MAAS_ENV_FILE:-$HOME/.config/workbook/pve-maas.env}"
delai_arret="${ALIM_DELAI_ARRET:-120}"

usage() { sed -n '3,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2; }
erreur() { printf 'alim.sh : %s\n' "$1" >&2; exit "${2:-2}"; }

[[ $# -eq 2 ]] || usage
cible="$1"; action="$2"

# --- hp01 : lecture seule, par Redfish ---------------------------------------------------------------
if [[ "$cible" == hp01 ]]; then
  case "$action" in
    etat)
      "$ici/redfish.sh" /redfish/v1/Systems/1/ | jq -r '"hp01 : \(.PowerState) (\(.Model), série \(.SerialNumber))"' ;;
    types)
      "$ici/redfish.sh" /redfish/v1/Systems/1/ \
        | jq -r '.Actions["#ComputerSystem.Reset"]["ResetType@Redfish.AllowableValues"][]?' ;;
    allumer|eteindre|arreter-propre|cycle)
      erreur "hp01 porte PBS et le QDevice : action « $action » refusée. Un redémarrage de hp01 suit la procédure annoncée (fiche de changement, fenêtre hors sauvegardes)." 3 ;;
    *) usage ;;
  esac
  exit 0
fi

# --- VMs bmNN : API Proxmox ---------------------------------------------------------------------------
[[ "$cible" =~ ^bm[0-9]{2}$ ]] || erreur "cible inconnue : $cible (bmNN ou hp01)"
[[ -r "$pve_env" ]] || erreur "fichier d'accès illisible : $pve_env"
[[ "$(stat -c %a "$pve_env")" == 600 ]] || erreur "$pve_env doit être en mode 600"

lire() { # lire CLÉ — sans exécuter le fichier ; $HOME développé (forme de pve-api.env)
  local v
  v="$(sed -nE "s/^[[:space:]]*(export[[:space:]]+)?$1=\"?([^\"]*)\"?[[:space:]]*(#.*)?\$/\\2/p" "$pve_env" | tail -n 1)"
  printf '%s' "${v//\$HOME/$HOME}"
}
url="$(lire PVE_API_URL)"; jeton="$(lire PVE_TOKEN_ID)"; secret="$(lire PVE_TOKEN_SECRET)"; ca="$(lire PVE_CACERT)"
[[ -n "$url" && -n "$jeton" && -n "$secret" && -r "$ca" ]] || erreur "PVE_API_URL, PVE_TOKEN_ID, PVE_TOKEN_SECRET ou PVE_CACERT manquant ou illisible ($pve_env)"

# api MÉTHODE CHEMIN — appel de l'API ; l'en-tête d'authentification passe par l'entrée standard.
api() {
  printf 'header = "Authorization: PVEAPIToken=%s=%s"\n' "$jeton" "$secret" \
    | curl --silent --show-error --fail --max-time 20 --proto '=https' --cacert "$ca" \
           -X "$1" -K - "$url$2"
}

# La VM est cherchée par son NOM dans ce que le jeton voit (comme le pilote proxmox de MAAS).
vm="$(api GET '/cluster/resources?type=vm' | jq -c --arg n "$cible" '[.data[] | select(.name == $n)]')"
[[ "$(jq length <<<"$vm")" == 1 ]] || erreur "$cible : introuvable (ou en double) parmi les VMs visibles par $jeton" 1
noeud="$(jq -r '.[0].node' <<<"$vm")"; vmid="$(jq -r '.[0].vmid' <<<"$vm")"
base="/nodes/$noeud/qemu/$vmid/status"

etat() { api GET "$base/current" | jq -r '.data.status'; }

# attendre ÉTAT — interroge jusqu'à l'état voulu, au plus $delai_arret secondes.
attendre() {
  local fin=$((SECONDS + delai_arret))
  until [[ "$(etat)" == "$1" ]]; do
    (( SECONDS < fin )) || erreur "$cible ($vmid) : toujours pas « $1 » après ${delai_arret} s" 1
    sleep 2
  done
}

case "$action" in
  etat)
    echo "$cible ($vmid) : $(etat)" ;;
  allumer)
    if [[ "$(etat)" == running ]]; then echo "$cible ($vmid) : déjà allumée"; exit 0; fi
    api POST "$base/start" >/dev/null; attendre running; echo "$cible ($vmid) : allumée" ;;
  eteindre)      # « débrancher la prise » : immédiat, comme un arrêt électrique
    if [[ "$(etat)" == stopped ]]; then echo "$cible ($vmid) : déjà éteinte"; exit 0; fi
    api POST "$base/stop" >/dev/null; attendre stopped; echo "$cible ($vmid) : éteinte" ;;
  arreter-propre) # arrêt ACPI demandé au système (exige un système qui répond)
    if [[ "$(etat)" == stopped ]]; then echo "$cible ($vmid) : déjà éteinte"; exit 0; fi
    api POST "$base/shutdown" >/dev/null; attendre stopped; echo "$cible ($vmid) : arrêtée proprement" ;;
  cycle)         # éteindre, ATTENDRE l'arrêt réel, rallumer
    if [[ "$(etat)" != stopped ]]; then api POST "$base/stop" >/dev/null; attendre stopped; fi
    api POST "$base/start" >/dev/null; attendre running; echo "$cible ($vmid) : redémarrée (arrêt puis allumage)" ;;
  *) usage ;;
esac
