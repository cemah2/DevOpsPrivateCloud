# vms-lab.jq — VMs QEMU du pool « lab » (hors templates), une ligne TSV par VM. (M02-E05)
# Entrée  : réponse de GET /cluster/resources?type=vm (objet avec .data).
# Sortie  : vmid, nom, état, mémoire max. (Mio), étiquettes — triées par VMID.
# Usage   : jq -r -f lib/jq/vms-lab.jq reponse.json
.data
| map(select(.type == "qemu" and .pool == "lab" and (.template // 0) != 1 and .template != true))
| sort_by(.vmid)
| .[]
| [.vmid, .name, .status, (.maxmem / 1048576 | floor), (.tags // "")]
| @tsv
