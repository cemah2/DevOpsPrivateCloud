#!/usr/bin/env bash
# m07-vnets.sh — VNets de la maquette réseau du module 07 (vfab1 à vfab8, VLAN 901 à 908).
#
# À lancer EN ROOT SUR pve01 (le jeton d'OpenTofu n'a pas le droit d'administrer le SDN) :
#   root@pve01:~# ./m07-vnets.sh etat|creer|supprimer
#
# creer     : crée les VNets manquants dans la zone « lab », montre les changements EN ATTENTE,
#             demande confirmation, applique (pvesh set /cluster/sdn), puis donne PVESDNUser sur
#             chaque VNet au jeton wb-tofu@pve!tofu ET à son utilisateur (privilèges séparés :
#             le droit effectif est l'intersection des deux).
# supprimer : retire les droits, puis les VNets, avec la même confirmation.
# etat      : ce qui existe, ce qui est en attente, les droits.
#
# ⚠️ Appliquer le SDN régénère /etc/network/interfaces.d/sdn et recharge TOUTE la configuration
# réseau de pve01 (ifreload -a). Le script sauvegarde les deux fichiers avant d'appliquer et
# refuse d'appliquer si des changements en attente ne viennent pas de lui.
set -euo pipefail

ZONE="lab"
UTILISATEUR="wb-tofu@pve"
JETON="wb-tofu@pve!tofu"
ROLE="PVESDNUser"
SAUVEGARDES="/root/sauvegardes-reseau"

# vnet:vlan:alias
VNETS=(
  "vfab1:901:M07 spine01-leaf01"
  "vfab2:902:M07 spine01-leaf02"
  "vfab3:903:M07 spine02-leaf01"
  "vfab4:904:M07 spine02-leaf02"
  "vfab5:905:M07 leaf01-srv01"
  "vfab6:906:M07 leaf02-srv02"
  "vfab7:907:M07 leaf01-leaf02"
  "vfab8:908:M07 LAN LYO1"
)

die() { echo "m07-vnets : $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "à lancer en root sur pve01"
command -v pvesh >/dev/null || die "pvesh introuvable : ce script tourne sur pve01"
command -v jq >/dev/null || die "jq requis"

vnets_json() { pvesh get /cluster/sdn/vnets --output-format json; }
en_attente() { pvesh get /cluster/sdn/vnets --pending 1 --output-format json | jq -r '.[] | select(.state != null) | "\(.vnet) \(.state)"'; }
existe() { vnets_json | jq -e --arg v "$1" 'map(select(.vnet == $v)) | length == 1' >/dev/null; }

confirmer() {
  local rep
  read -r -p "$1 [oui/NON] " rep
  [[ "$rep" == "oui" ]]
}

sauvegarder() {
  local d
  d="$SAUVEGARDES/$(date +%Y%m%d-%H%M%S)"
  install -d -m 700 "$d"
  cp -a /etc/network/interfaces "$d/"
  [[ -f /etc/network/interfaces.d/sdn ]] && cp -a /etc/network/interfaces.d/sdn "$d/"
  echo "Sauvegarde : $d"
  echo "  Retour arrière : supprimer les VNets créés (« $0 supprimer »), puis comparer"
  echo "  /etc/network/interfaces.d/sdn à $d/sdn."
}

# Applique le SDN seulement si TOUT ce qui est en attente concerne nos VNets.
appliquer() {
  local attente noms autres
  attente="$(en_attente)"
  if [[ -z "$attente" ]]; then
    echo "Rien en attente."
    return 0
  fi
  echo "Changements SDN en attente :"
  awk '{print "  " $0}' <<<"$attente"
  noms="$(printf '%s\n' "${VNETS[@]}" | cut -d: -f1)"
  autres="$(awk '{print $1}' <<<"$attente" | grep -vxF -f <(echo "$noms") || true)"
  [[ -z "$autres" ]] || die "changements en attente qui ne viennent pas de ce script ($autres) : applique-les ou annule-les d'abord, à la main"
  confirmer "Appliquer le SDN (recharge le réseau de pve01) ?" || die "abandon : rien n'a été appliqué (les changements restent en attente)"
  sauvegarder
  pvesh set /cluster/sdn
  echo "Appliqué. Vérifie : pve01 répond-il toujours sur le LAN ? (ping depuis ton poste)"
}

droits() {
  local action="$1" v
  for v in "${VNETS[@]%%:*}"; do
    if [[ "$action" == ajouter ]]; then
      pveum acl modify "/sdn/zones/$ZONE/$v" --roles "$ROLE" --users "$UTILISATEUR"
      pveum acl modify "/sdn/zones/$ZONE/$v" --roles "$ROLE" --tokens "$JETON"
    else
      pveum acl delete "/sdn/zones/$ZONE/$v" --roles "$ROLE" --tokens "$JETON" 2>/dev/null || true
      pveum acl delete "/sdn/zones/$ZONE/$v" --roles "$ROLE" --users "$UTILISATEUR" 2>/dev/null || true
    fi
  done
}

etat() {
  local e v vlan
  echo "VNets de la maquette (zone $ZONE) :"
  for e in "${VNETS[@]}"; do
    v="${e%%:*}"; vlan="$(cut -d: -f2 <<<"$e")"
    if existe "$v"; then
      printf '  %-6s VLAN %s  présent (tag %s)\n' "$v" "$vlan" \
        "$(vnets_json | jq -r --arg v "$v" '.[] | select(.vnet == $v) | .tag')"
    else
      printf '  %-6s VLAN %s  absent\n' "$v" "$vlan"
    fi
  done
  echo "En attente :"
  en_attente | sed 's/^/  /'
  echo "Droits ($ROLE) :"
  pveum acl list --output-format json \
    | jq -r --arg z "/sdn/zones/$ZONE/vfab" '.[] | select(.path | startswith($z)) | "  \(.path) \(.type) \(.ugid) \(.roleid)"'
}

creer() {
  local e v vlan alias
  for e in "${VNETS[@]}"; do
    IFS=: read -r v vlan alias <<<"$e"
    if existe "$v"; then
      echo "= $v existe"
    else
      pvesh create /cluster/sdn/vnets --vnet "$v" --zone "$ZONE" --tag "$vlan" --alias "$alias"
      echo "+ $v (VLAN $vlan)"
    fi
  done
  appliquer
  droits ajouter
  echo "Droits $ROLE posés sur /sdn/zones/$ZONE/vfab1..8 pour $UTILISATEUR et $JETON."
}

supprimer() {
  local v
  confirmer "Supprimer les VNets vfab1 à vfab8 (les VMs 2070-2079 doivent être détruites) ?" || die "abandon"
  droits retirer
  for v in "${VNETS[@]%%:*}"; do
    if existe "$v"; then
      pvesh delete "/cluster/sdn/vnets/$v"
      echo "- $v"
    fi
  done
  appliquer
}

case "${1:-}" in
  etat) etat ;;
  creer) creer ;;
  supprimer) supprimer ;;
  *) echo "Usage : $0 etat|creer|supprimer" >&2; exit 2 ;;
esac
