# shellcheck shell=bash
# M00-E03 — Inventaire de l'existant sur pve01.
# Contrôle de FORME uniquement (exercice de rédaction) : présence du document,
# des sections attendues et absence de champs non remplis.
# Le document est lu dans la copie locale du dépôt (variable ROOT de lab/bin/check).

title "M00-E03 — Inventaire de l'existant sur pve01 (contrôle de forme)"

INV="${ROOT}/lab/inventaire-local.md"

check_cmd "lab/inventaire-local.md existe et n'est pas vide" test -s "$INV"

for section in "Proxmox VE" "Matériel" "Disques et stockages" "Réseau" \
               "VMs et conteneurs existants" "Ressources libres" "Valeurs du lab"; do
  check_cmd "section « $section » présente" grep -Eq "^## [0-9]+\. ${section}" "$INV"
done

check_cmd "plus aucun champ « À COMPLÉTER »" bash -c "! grep -q 'À COMPLÉTER' \"\$1\"" _ "$INV"
check_cmd "la sortie de pveversion est consignée (pve-manager/x.y)" \
  grep -Eq 'pve-manager/[0-9]+\.[0-9]+' "$INV"
check_cmd "les VMID occupés sont documentés" grep -Eqi 'VMID' "$INV"
check_cmd "chaque disque a une conclusion (préserver / réaffectable)" \
  grep -Eqi 'préserver|preserver|réaffectable|reaffectable' "$INV"
