#!/bin/bash
# ajouter-enregistrement.sh — ajoute un A dans par2 par l'API (pour la CI) — Lucas
# usage : ./ajouter-enregistrement.sh nom ip
NOM=$1
IP=$2
CLE="Lucas-PAR2-cle-api-2026-maquette"
API=http://10.20.20.10:8081/api/v1/servers/localhost/zones/par2.medisphere.internal.

curl -s -k -X PATCH $API -H "X-API-Key: $CLE" -d '{"rrsets": [{"name": "'$NOM'.par2.medisphere.internal.", "type": "A", "ttl": 60, "changetype": "REPLACE", "records": [{"content": "'$IP'", "disabled": false}]}]}'
echo "OK : $NOM -> $IP"
