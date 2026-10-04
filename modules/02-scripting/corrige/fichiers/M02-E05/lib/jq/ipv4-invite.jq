# ipv4-invite.jq — adresses IPv4 utiles d'un invité, vues par l'agent QEMU. (M02-E05)
# Entrée : réponse de GET /nodes/{node}/qemu/{vmid}/agent/network-get-interfaces.
# Sortie : une adresse par ligne, hors boucle locale (127.0.0.0/8, interface lo)
#          et hors lien local (169.254.0.0/16), dans l'ordre de l'agent.
# Usage  : jq -r -f lib/jq/ipv4-invite.jq reponse.json
.data.result[]
| select(.name != "lo")
| .["ip-addresses"][]?
| select(.["ip-address-type"] == "ipv4")
| .["ip-address"]
| select(startswith("127.") or startswith("169.254.") | not)
