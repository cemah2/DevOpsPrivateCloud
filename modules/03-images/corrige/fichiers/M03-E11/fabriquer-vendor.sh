#!/usr/bin/env bash
# fabriquer-vendor.sh — assemble et vérifie le vendor-data multi-part de M03-E11.
# À lancer sur adm01 (cloud-init y est installé : c'est un clone de l'image genericcloud),
# dans ~/m03/e11/. Produit m03-e11-vendor.mime, à copier ensuite sur pve01 :
#   scp m03-e11-vendor.mime m03-e11-network.yaml pve01:/mnt/hdd-bulk/snippets/
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

# Contrôles avant assemblage : schéma réseau, syntaxe du script.
cloud-init schema -t network-config -c m03-e11-network.yaml
sh -n m03-e11-inscription.sh
# La partie Jinja ne se valide qu'une fois rendue : on la rend avec les données d'instance
# de adm01 (sudo : instance-data-sensitive.json n'est lisible que par root), puis schéma.
rendu="$(sudo cloud-init devel render m03-e11-config.yaml)"
printf '%s\n' "$rendu" > m03-e11-config.rendu.yaml
cloud-init schema -c m03-e11-config.rendu.yaml
rm -f m03-e11-config.rendu.yaml

cloud-init devel make-mime \
  -a m03-e11-config.yaml:jinja2 \
  -a m03-e11-inscription.sh:x-shellscript > m03-e11-vendor.mime
# Nombre de parties (l'en-tête « multipart/mixed » de l'enveloppe n'est pas compté)
grep -c '^Content-Type: text/' m03-e11-vendor.mime
echo "m03-e11-vendor.mime prêt"
