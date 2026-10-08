#!/usr/bin/env bash
# creer-tpl-nested.sh — template Debian 13 des invités imbriqués du cluster hv-par1 (M09-E06).
#
# Usage (root sur un nœud du cluster ; depuis adm01) :
#   ssh hv01 'bash -s' -- [--stockage local-lvm] [--remplacer] [--commentaire admin@adm01] \
#     < outils/hv/creer-tpl-nested.sh
#
# Produit le template 199 « tpl-nested-debian13 » sur le nœud où il est lancé :
#   - image Debian 13 genericcloud téléchargée par l'API du nœud dans local:import/, somme
#     SHA-512 vérifiée par Proxmox lui-même (liste SHA512SUMS lue en HTTPS) ;
#   - disque importé (import-from), agrandi à 8 Gio, contrôleur virtio-scsi-single ;
#   - cloud-init : compte admin, clé publique de adm01 (lue dans /root/.ssh/authorized_keys, ligne
#     « admin@adm01 »), DHCP, fragment vendor commun (agent QEMU, rôle pve_noeud) ;
#   - réseau : vmbr1, VLAN 99 ; CPU x86-64-v2-AES (pas « host » : migrable partout) ; console série.
# Prérequis (M09-E06) : stockage « local » avec les contenus import et snippets ; fragment
# /var/lib/vz/snippets/medisphere-agent.yaml présent (rôle pve_noeud).
# Refuse d'écraser un VMID 199 existant sans --remplacer.
set -euo pipefail

vmid=199
nom="tpl-nested-debian13"
stockage="local-lvm"
remplacer=0
commentaire="admin@adm01"   # commentaire de la clé publique de adm01 (fin de ligne d'authorized_keys)
base="https://cloud.debian.org/images/cloud/trixie/latest"
image="debian-13-genericcloud-amd64.qcow2"
noeud="$(hostname -s)"

while (($#)); do
  case "$1" in
    --stockage) stockage="${2:?}"; shift 2 ;;
    --remplacer) remplacer=1; shift ;;
    --commentaire) commentaire="${2:?}"; shift 2 ;;
    *) echo "option inconnue : $1" >&2; exit 2 ;;
  esac
done

[[ $EUID -eq 0 ]] || { echo "à lancer en root sur un nœud" >&2; exit 1; }
command -v pvesh >/dev/null || { echo "pas un nœud Proxmox VE" >&2; exit 1; }

contenu="$(pvesh get /storage/local --output-format json | jq -r .content)"
for c in import snippets; do
  grep -qw "$c" <<<"${contenu//,/ }" \
    || { echo "le stockage « local » n'a pas le contenu « $c » (pvesm set local --content …)" >&2; exit 1; }
done
[[ -s /var/lib/vz/snippets/medisphere-agent.yaml ]] \
  || { echo "fragment medisphere-agent.yaml absent : appliquer le rôle pve_noeud" >&2; exit 1; }

cle="$(grep -m1 -F " $commentaire" /root/.ssh/authorized_keys | grep -E "^(ssh-ed25519|ecdsa-sha2-nistp256) " || true)"
[[ -n "$cle" ]] || { echo "clé « $commentaire » introuvable dans /root/.ssh/authorized_keys (--commentaire)" >&2; exit 1; }

if qm status "$vmid" >/dev/null 2>&1; then
  if ((remplacer)); then
    echo "== Destruction de l'ancien $vmid (--remplacer)"
    qm destroy "$vmid" --purge 1
  else
    echo "le VMID $vmid existe déjà ; --remplacer pour le reconstruire" >&2
    exit 1
  fi
fi

echo "== Image $image"
somme="$(curl -fsSL "$base/SHA512SUMS" | awk -v f="$image" '$2 == f { print $1 }')"
[[ "$somme" =~ ^[0-9a-f]{128}$ ]] || { echo "somme SHA-512 de $image introuvable" >&2; exit 1; }
if pvesm list local --content import | grep -q "local:import/$image"; then
  # Déjà là : on revérifie la somme (une image de la semaine passée a pu être remplacée en amont).
  chemin="$(pvesm path "local:import/$image")"
  if [[ "$(sha512sum "$chemin" | cut -d' ' -f1)" != "$somme" ]]; then
    echo "image locale différente de la dernière publiée : suppression et nouveau téléchargement"
    pvesm free "local:import/$image"
  fi
fi
if ! pvesm list local --content import | grep -q "local:import/$image"; then
  # Le nœud télécharge et vérifie lui-même la somme ; la tâche échoue si elle ne correspond pas.
  pvesh create "/nodes/$noeud/storage/local/download-url" --content import --filename "$image" \
    --url "$base/$image" --checksum "$somme" --checksum-algorithm sha512
fi

echo "== Template $vmid $nom sur $noeud ($stockage)"
fichier_cle="$(mktemp)"
trap 'rm -f "$fichier_cle"' EXIT
printf '%s\n' "$cle" >"$fichier_cle"

qm create "$vmid" --name "$nom" --ostype l26 --memory 1024 --cores 1 --cpu x86-64-v2-AES \
  --scsihw virtio-scsi-single \
  --scsi0 "$stockage:0,import-from=local:import/$image,discard=on,ssd=1,iothread=1" \
  --ide2 "$stockage:cloudinit" --boot order=scsi0 \
  --net0 virtio,bridge=vmbr1,tag=99 \
  --serial0 socket --vga serial0 --agent enabled=1 \
  --ciuser admin --sshkeys "$fichier_cle" --ipconfig0 ip=dhcp \
  --cicustom "vendor=local:snippets/medisphere-agent.yaml" \
  --tags "nested;debian13" \
  --description "Template des invités imbriqués du cluster hv-par1 (M09-E06), image $image."
qm disk resize "$vmid" scsi0 8G
qm template "$vmid"
qm config "$vmid"
