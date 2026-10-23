#!/usr/bin/env bash
# plateforme/tofu-modules — outils/nettoyer-terratest.sh (M29-E21, INC-5621 ; RB-293)
# Retrouve et (sur demande) détruit les VMs laissées par Terratest sur Proxmox.
# Une VM n'est retenue que si TOUTES les conditions sont vraies :
#   - VMID dans la plage Terratest 2290-2299 (PLAN §4.13) ;
#   - sous-pool « lab/terratest » (M29-E08) ;
#   - nom qui commence par « tt- » ;
#   - étiquette « terratest » OU « env-m29 » (une VM de test sans « terratest » est signalée à part) ;
#   - créée il y a plus de AGE_MIN minutes (meta.ctime), pour ne jamais tuer un test en cours.
# Mode SIMULATION par défaut : affiche ce qui serait fait. --appliquer : arrête puis détruit.
# Accès : API de Proxmox avec le jeton du test, wb-terratest@pve!terratest (M29-E08 : VM.Audit,
# VM.PowerMgmt, VM.Config.Options, VM.Allocate sur /pool/lab/terratest SEULEMENT : même une erreur de
# sélection ne peut rien détruire ailleurs), dans les variables protégées du projet (même format que le
# fournisseur bpg/proxmox) :
#   PROXMOX_VE_ENDPOINT   ex. https://pve01.par1.medisphere.internal:8006/
#   PROXMOX_VE_API_TOKEN  utilisateur@royaume!jeton=secret   (jamais affiché)
# Sortie : un journal sur la sortie standard ; code 0 si rien d'orphelin ou tout nettoyé, 3 si des
# orphelins restent (simulation), 1 en cas d'erreur.
set -euo pipefail

AGE_MIN="${AGE_MIN:-120}"
PLAGE_MIN=2290
PLAGE_MAX=2299
appliquer=0
case "${1:-}" in
  --appliquer) appliquer=1 ;;
  ""|--simulation) ;;
  *) echo "usage : $0 [--simulation|--appliquer]" >&2; exit 2 ;;
esac
: "${PROXMOX_VE_ENDPOINT:?PROXMOX_VE_ENDPOINT manquant}"
: "${PROXMOX_VE_API_TOKEN:?PROXMOX_VE_API_TOKEN manquant}"
base="${PROXMOX_VE_ENDPOINT%/}/api2/json"

# api MÉTHODE CHEMIN [options curl] — le jeton passe par un fichier de configuration curl (jamais en argument).
api() {
  local m="$1" p="$2"
  shift 2
  curl -sf --max-time 30 ${CA_PROXMOX:+--cacert "$CA_PROXMOX"} -X "$m" \
    -K <(printf 'header = "Authorization: PVEAPIToken=%s"\n' "$PROXMOX_VE_API_TOKEN") "$base$p" "$@"
}

maintenant="$(date +%s)"
orphelins=0
echo "$(date -Is) nettoyage Terratest (mode : $([ "$appliquer" = 1 ] && echo APPLIQUER || echo simulation), âge minimal ${AGE_MIN} min)"

# Champs vides remplacés par « - » : « read » avec IFS=tabulation fusionne les tabulations consécutives.
while IFS=$'\t' read -r vmid noeud nom pool etiquettes etat; do
  [[ "$pool" == lab/terratest && "$nom" == tt-* ]] || { echo "  $vmid ($nom) : hors critères (pool $pool) — ignorée, à examiner à la main"; continue; }
  case ";$etiquettes;" in
    *";terratest;"*) ;;
    *";env-m29;"*) echo "  $vmid ($nom) : étiquette « terratest » ABSENTE (seulement env-m29) — le test doit la poser" ;;
    *) echo "  $vmid ($nom) : ni terratest ni env-m29 — ignorée, à examiner à la main"; continue ;;
  esac
  ctime="$(api GET "/nodes/$noeud/qemu/$vmid/config" | jq -r '.data.meta // "" | capture("ctime=(?<t>[0-9]+)").t // empty')"
  if [[ -z "$ctime" ]]; then
    echo "  $vmid ($nom) : date de création inconnue — ignorée"
    continue
  fi
  age=$(((maintenant - ctime) / 60))
  if ((age < AGE_MIN)); then
    echo "  $vmid ($nom) : créée il y a $age min (< ${AGE_MIN}) — test peut-être en cours, ignorée"
    continue
  fi
  orphelins=$((orphelins + 1))
  if ((appliquer == 0)); then
    echo "  $vmid ($nom, $etat, $age min) : ORPHELINE — serait arrêtée puis détruite"
    continue
  fi
  echo "  $vmid ($nom, $etat, $age min) : ORPHELINE — arrêt et destruction"
  api PUT "/nodes/$noeud/qemu/$vmid/config" --data-urlencode "protection=0" >/dev/null
  if [[ "$etat" == running ]]; then
    api POST "/nodes/$noeud/qemu/$vmid/status/stop" >/dev/null
    for _ in $(seq 1 30); do
      [[ "$(api GET "/nodes/$noeud/qemu/$vmid/status/current" | jq -r .data.status)" == stopped ]] && break
      sleep 2
    done
  fi
  api DELETE "/nodes/$noeud/qemu/$vmid?purge=1&destroy-unreferenced-disks=1" >/dev/null
  orphelins=$((orphelins - 1))
done < <(api GET "/cluster/resources?type=vm" |
  jq -r --argjson a "$PLAGE_MIN" --argjson b "$PLAGE_MAX" \
    '.data[] | select(.vmid >= $a and .vmid <= $b) | [.vmid, .node, (.name // "-"), (.pool // "-"), ((.tags // "") | if . == "" then "-" else . end), .status] | @tsv')

echo "$(date -Is) fin : $orphelins orpheline(s) restante(s)"
# NetBox (adresses et VMs « terratest » restées après une destruction hors OpenTofu) : non traité ici,
# voir RB-293 §3 ; le check de M29-E08 le signale.
((orphelins == 0)) || exit 3
