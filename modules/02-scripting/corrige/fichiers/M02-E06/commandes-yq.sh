#!/usr/bin/env bash
# shellcheck disable=SC2016  # les expressions yq sont entre apostrophes : pas d'expansion shell voulue
# commandes-yq.sh — solution rejouable de M02-E06 (yq de mikefarah, v4.54).
#
# Recopie les fichiers fournis dans ~/m02/e06/ puis applique toutes les
# transformations avec yq, sans édition à la main. Rejouable à volonté.
# Usage : commandes-yq.sh [DOSSIER_RESSOURCES]
#   DOSSIER_RESSOURCES : défaut ~/DevOpsPrivateCloud/modules/02-scripting/ressources/M02-E06
set -euo pipefail

res="${1:-$HOME/DevOpsPrivateCloud/modules/02-scripting/ressources/M02-E06}"
travail="$HOME/m02/e06"
cle_pub="$HOME/.ssh/id_ed25519.pub"

yq --version | grep -q mikefarah || {
  echo "ce yq n'est pas celui de mikefarah" >&2
  exit 1
}
mkdir -p -- "$travail"
cp -- "$res"/*.yml "$res"/*.yaml "$travail/"
cd -- "$travail"

# 1. Hôtes et serveur NTP effectif, selon la spécification YAML de la clé de fusion
#    (une clé explicite l'emporte sur « << », où qu'elle soit placée).
yq --yaml-fix-merge-anchor-to-spec=true -r '
  explode(.) | .all.children[].hosts | to_entries | .[]
  | [.key, .value.ansible_host, .value.ntp_serveur] | @tsv
' inventaire-infoger.yml >hotes.tsv

# 2. Inventaire sans ambiguïté de type ni d'ordre, commentaires et ancres conservés.
cp inventaire-infoger.yml inventaire-corrige.yml
yq -i '
  (.. | select(tag == "!!map" and has("sauvegarde")) | .sauvegarde) |= (. == "yes" or . == true)
  | .all.vars.defaut.version_python |= to_string
  | .all.vars.defaut.mode_cles |= to_string
  | .all.children.socle.hosts.gw01 |= sort_keys(.)
' inventaire-corrige.yml 2>/dev/null # avertissement de la clé de fusion : traité ci-dessus

# 3. user-data : modification en place.
CLE="$(head -n 1 -- "$cle_pub")" yq -i '
  .ntp.servers = ["10.10.99.1"]
  | (.users[] | select(.name == "admin") | .ssh_authorized_keys) += [strenv(CLE)]
  | .package_upgrade = true
' user-data-sandbox.yaml
head -n 1 user-data-sandbox.yaml | grep -qx '#cloud-config' || {
  echo "user-data : la ligne #cloud-config a disparu" >&2
  exit 1
}
if command -v cloud-init >/dev/null; then
  cloud-init schema -c user-data-sandbox.yaml
fi

# 4. Paramètres effectifs de PAR2 : fusion profonde, les listes de PAR2 REMPLACENT celles par défaut.
yq ea '. as $f ireduce ({}; . * $f)' parametres-defaut.yml parametres-par2.yml \
  >parametres-effectifs-par2.yml

# 5. JSON → YAML : VMs QEMU du pool lab (fixture de M02-E05).
yq -p json -o yaml '
  [.data[]
   | select(.type == "qemu" and .pool == "lab" and .template == 0)
   | {"vmid": .vmid, "nom": .name,
      "etiquettes": ((.tags // "") | split(";") | map(select(. != "")))}]
  | sort_by(.vmid)
' "$res/../M02-E05/cluster-resources.json" >vms-lab.yml

ls -l -- "$travail"
