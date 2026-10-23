#!/usr/bin/env bash
# outils/par2/restaurer-kms01-par2.sh — restaure kms01 depuis PBS dans le BAC À SABLE de PAR2 (F5-S05,
# RB-355 §2) : VMID 3501, carte réseau COUPÉE, adresse changée en 10.20.20.24, puis carte rebranchée sur
# vmbr2 (où la table inet par2 l'isole : jamais routé hors de PAR2 INFRA). Projet plateforme/infra.
# À lancer EN ROOT SUR hp01. Ne touche JAMAIS au kms01 de PAR1 (il est sur pve01 ; ce script ne parle
# qu'à l'hyperviseur local et au stockage PBS « pbs-local », espace de noms par1/secrets, RB-353 §4).
#
# Usage : restaurer-kms01-par2.sh [INSTANTANÉ]     (défaut : le plus récent de vm/1024)
#         restaurer-kms01-par2.sh --detruire          (fin de répétition : arrêt et destruction de 3501)
set -Eeuo pipefail

vmid=3501
stockage_pbs="${STOCKAGE_PBS:-pbs-local}"
stockage_vm="${STOCKAGE_VM:-par2-vms}"
ip=10.20.20.24

erreur() { echo "restaurer-kms01-par2 : $*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || erreur "à lancer en root sur hp01"
[[ "$(hostname -s)" == "pbs01" ]] || erreur "ce script ne tourne que sur hp01 (nœud pbs01)"

if [[ "${1:-}" == "--detruire" ]]; then
  qm status "$vmid" >/dev/null 2>&1 || { echo "3501 absente : rien à faire"; exit 0; }
  # Garde-fou : on ne détruit que la COPIE posée par ce script (étiquette pra-kms01).
  qm config "$vmid" | grep -Eq '^tags:.*pra-kms01' || erreur "la VM $vmid n'a pas l'étiquette pra-kms01 : ce n'est pas une copie de kms01, rien n'est détruit"
  qm stop "$vmid" --skiplock 1 || true
  qm destroy "$vmid" --purge 1 --destroy-unreferenced-disks 1
  echo "3501 détruite."
  exit 0
fi

qm status "$vmid" >/dev/null 2>&1 && erreur "la VM $vmid existe déjà : termine ou détruis la répétition précédente (--detruire)"
nft list set inet par2 isoles 2>/dev/null | grep -q "$ip" || erreur "10.20.20.24 n'est pas dans le set « isoles » de inet par2 : bac à sable non garanti"

instantane="${1:-}"
if [[ -z "$instantane" ]]; then
  instantane="$(pvesm list "$stockage_pbs" --vmid 1024 --content backup --output-format json \
    | jq -r 'sort_by(.ctime) | last | .volid // empty')"
  [[ -n "$instantane" ]] || erreur "aucune sauvegarde de 1024 visible sur $stockage_pbs (espace de noms par1/secrets ?)"
fi
echo "instantané : $instantane"

# 1. Restauration : nouvelles adresses MAC (--unique), disques sur par2-vms, PAS de démarrage.
qmrestore "$instantane" "$vmid" --storage "$stockage_vm" --unique 1

# 2. Carte coupée et déplacée sur vmbr2 AVANT tout démarrage ; nouvelle adresse par cloud-init.
mac="$(qm config "$vmid" | sed -n 's/^net0: virtio=\([0-9A-Fa-f:]*\).*/\1/p')"
[[ -n "$mac" ]] || erreur "net0 introuvable dans la configuration restaurée"
qm set "$vmid" --name kms01-par2 --net0 "virtio=$mac,bridge=vmbr2,link_down=1" \
  --ipconfig0 "ip=$ip/24,gw=10.20.20.1" --nameserver 10.20.20.11 --searchdomain par2.medisphere.internal \
  --onboot 0 --tags 'pra-kms01;site-par2' --description "COPIE de kms01 restaurée à PAR2 (F5-S05, RB-355). ISOLÉE. Détruire après usage."
pveum pool modify par2 --vms "$vmid"

# 3. Premier démarrage, carte coupée : cloud-init applique la nouvelle adresse (la configuration a
#    changé), on le vérifie par l'agent QEMU avant de rebrancher.
qm start "$vmid"
for _ in $(seq 1 60); do
  qm guest ping "$vmid" >/dev/null 2>&1 && break
  sleep 5
done
qm guest exec "$vmid" -- ip -4 -o addr show | grep -q "inet $ip/24" \
  || erreur "l'adresse $ip n'est pas en place dans la VM (carte toujours coupée) : diagnostique par la console avant de rebrancher"
echo "adresse $ip vérifiée, carte coupée."
echo "Suite (RB-355 §2) : désactiver dans la copie les minuteries qui sortent (instantanés, ACME, journaux),"
echo "puis : qm set $vmid --net0 virtio=$mac,bridge=vmbr2   (carte rebranchée, isolée par inet par2)"
