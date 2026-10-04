# taches-echec.jq — tâches Proxmox terminées en échec depuis une date. (M02-E05)
# Entrée     : réponse de GET /nodes/{node}/tasks.
# Paramètre  : $depuis (époque Unix, en secondes), via --argjson depuis N.
# Sortie     : TSV début (ISO 8601 UTC), type, objet, auteur, statut — plus récente d'abord.
#              « Échec » = terminée (statut présent) avec un statut ni OK ni WARNINGS.
# Usage      : jq -r --argjson depuis "$(date -d '-24 hours' +%s)" -f lib/jq/taches-echec.jq reponse.json
.data
| map(select(.starttime >= $depuis
             and has("status")
             and .status != "OK"
             and (.status | startswith("WARNINGS") | not)))
| sort_by(.starttime) | reverse
| .[]
| [(.starttime | todate), .type, .id, .user, .status]
| @tsv
