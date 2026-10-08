#!/usr/bin/env bash
# preparer-iso.sh — prépare une ISO d'installation automatique de Proxmox VE par nœud du
# cluster hv-par1 (M09-E03, M09-E08).
#
# Usage (sur adm01, depuis envs/hv/) :
#   installation/preparer-iso.sh [--iso proxmox-ve_9.2-1.iso] [--stockage hdd-bulk] hv01 [hv02 …]
#
# Pour chaque nœud :
#   1. lit ses données dans noeuds.auto.tfvars.json (même source qu'OpenTofu) ;
#   2. produit son fichier de réponse à partir de reponse.toml.modele, dans un dossier 700
#      (empreinte du mot de passe root calculée depuis ~/.config/workbook/hv-root.pass, lu
#      sur l'entrée standard d'openssl : il n'apparaît ni dans ps ni dans un fichier) ;
#   3. l'envoie sur pve01 par l'entrée standard de SSH, le valide (validate-answer), prépare
#      l'ISO <stockage>:iso/pve92-auto-<nœud>.iso (prepare-iso --fetch-from iso), puis efface
#      le fichier de réponse de pve01.
# Prérequis : ISO source déposée et vérifiée (deposer-iso.sh proxmox-ve, M09-E02) ;
# proxmox-auto-install-assistant et xorriso installés sur pve01 (M09-E02) ; alias SSH pve01 (root).
# Code 0 si toutes les ISO sont prêtes.
set -euo pipefail

ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
racine_env="$(dirname "$ici")"
modele="$ici/reponse.toml.modele"
donnees="$racine_env/noeuds.auto.tfvars.json"
pass="$HOME/.config/workbook/hv-root.pass"
cle_pub="$HOME/.ssh/id_ed25519.pub"
pve="${WB_PVE_HOST:-pve01}"
iso_source="proxmox-ve_9.2-1.iso"
stockage="hdd-bulk"
prefixe="pve92-auto"

usage() { echo "Usage : $0 [--iso NOM.iso] [--stockage STOCKAGE] hv01 [hv02 …]" >&2; exit 2; }

noeuds=()
while (($#)); do
  case "$1" in
    --iso) iso_source="${2:?}"; shift 2 ;;
    --stockage) stockage="${2:?}"; shift 2 ;;
    -h|--help) usage ;;
    hv0[1-3]) noeuds+=("$1"); shift ;;
    *) echo "Nœud ou option inconnu : $1" >&2; usage ;;
  esac
done
((${#noeuds[@]})) || usage

for c in jq openssl ssh sed; do
  command -v "$c" >/dev/null || { echo "outil manquant : $c" >&2; exit 1; }
done
[[ -r "$pass" && "$(stat -c %a "$pass")" == 600 ]] \
  || { echo "$pass absent ou pas en 600 (mot de passe root des nœuds, Vault critique)" >&2; exit 1; }
[[ -r "$cle_pub" ]] || { echo "clé publique $cle_pub introuvable" >&2; exit 1; }
cle="$(head -n 1 "$cle_pub")"
[[ "$cle" =~ ^ssh-ed25519\ AAAA[A-Za-z0-9+/=]+(\ [^\"]*)?$ ]] \
  || { echo "clé publique illisible ou contenant un guillemet : $cle_pub" >&2; exit 1; }

# Empreinte SHA-512 crypt ($6$…), sel aléatoire. Le mot de passe passe par l'entrée standard.
hash_root="$(tr -d '\n' <"$pass" | openssl passwd -6 -stdin)"
# Forme attendue : $6$<sel>$<empreinte>, alphabet crypt seulement (sûr dans sed et dans TOML).
[[ "$hash_root" =~ ^\$6\$[./A-Za-z0-9]+\$[./A-Za-z0-9]+$ ]] \
  || { echo "empreinte du mot de passe root non calculée" >&2; exit 1; }

travail="$(umask 077; mktemp -d)"
trap 'rm -rf "$travail"' EXIT

# Le chemin réel du stockage côté pve01 (dossier template/iso du stockage).
dest_iso() { ssh -o BatchMode=yes "$pve" "pvesm path $stockage:iso/$1"; }
source_iso="$(dest_iso "$iso_source")"
ssh -o BatchMode=yes "$pve" "test -s '$source_iso'" \
  || { echo "ISO source absente sur $pve : $stockage:iso/$iso_source (deposer-iso.sh proxmox-ve)" >&2; exit 1; }
ssh -o BatchMode=yes "$pve" 'command -v proxmox-auto-install-assistant >/dev/null' \
  || { echo "proxmox-auto-install-assistant absent de $pve (M09-E02)" >&2; exit 1; }

for n in "${noeuds[@]}"; do
  echo "== $n"
  ligne="$(jq -ce --arg n "$n" '.noeuds[$n]' "$donnees")" \
    || { echo "$n absent de $donnees" >&2; exit 1; }
  num="$(jq -r .numero <<<"$ligne")"
  mgmt="$(jq -r .mgmt <<<"$ligne")"
  # Mêmes MAC qu'OpenTofu (locals.tf) : 02:4d:53:09:<numéro>:<carte>
  declare -a mac=()
  for k in 0 1 2 3 4; do
    mac[k]="$(printf '02:4d:53:09:%02x:%02x' "$num" "$k")"
  done
  reponse="$travail/$n.toml"
  # « | » comme séparateur de sed : absent des valeurs (empreinte vérifiée plus haut, clé aussi).
  sed -e "s|@@FQDN@@|$n.par1.medisphere.internal|" \
      -e "s|@@NOEUD@@|$n|g" \
      -e "s|@@IP_MGMT@@|$mgmt|" \
      -e "s|@@HASH_ROOT@@|$hash_root|" \
      -e "s|@@CLE_SSH_ADM01@@|$cle|" \
      -e "s|@@MAC0_COMPACTE@@|${mac[0]//:/}|" \
      -e "s|@@MAC0@@|${mac[0]}|" -e "s|@@MAC1@@|${mac[1]}|" -e "s|@@MAC2@@|${mac[2]}|" \
      -e "s|@@MAC3@@|${mac[3]}|" -e "s|@@MAC4@@|${mac[4]}|" \
      "$modele" >"$reponse"
  if grep -q '@@' "$reponse"; then
    echo "marqueur non remplacé dans le fichier de réponse de $n" >&2
    exit 1
  fi

  sortie="$(dest_iso "$prefixe-$n.iso")"
  # Sur pve01 : dossier temporaire 700, fichier reçu sur l'entrée standard, validé, ISO
  # produite dans un fichier partiel puis renommée, fichier de réponse effacé dans tous les cas.
  ssh -o BatchMode=yes "$pve" "set -euo pipefail
    d=\$(umask 077; mktemp -d)
    trap 'rm -rf \"\$d\"' EXIT
    cat > \"\$d/$n.toml\"
    proxmox-auto-install-assistant validate-answer \"\$d/$n.toml\"
    proxmox-auto-install-assistant prepare-iso '$source_iso' --fetch-from iso \
      --answer-file \"\$d/$n.toml\" --output '${sortie%.iso}.partiel.iso'
    mv -f '${sortie%.iso}.partiel.iso' '$sortie'
    sha256sum '$sortie'" <"$reponse"
  echo "ISO prête : $stockage:iso/$prefixe-$n.iso"
done
