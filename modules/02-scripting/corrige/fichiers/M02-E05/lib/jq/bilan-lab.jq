# bilan-lab.jq — bilan chiffré des VMs QEMU du pool « lab » (hors templates). (M02-E05)
# Entrée : réponse de GET /cluster/resources?type=vm.
# Sortie : un objet JSON (voir l'énoncé pour le format).
# Usage  : jq -f lib/jq/bilan-lab.jq reponse.json
[.data[] | select(.type == "qemu" and .pool == "lab" and (.template // 0) != 1 and .template != true)]
| {
    vms: length,
    en_marche: (map(select(.status == "running")) | length),
    memoire_en_marche_mio: (map(select(.status == "running") | .maxmem) | add // 0 | . / 1048576 | floor),
    par_etiquette: (
      [.[] | (.tags // "") | split(";")[] | select(. != "")]
      | group_by(.)
      | map({key: .[0], value: length})
      | from_entries
    ),
    sans_etiquette: (map(select((.tags // "") == "") | .vmid) | sort)
  }
