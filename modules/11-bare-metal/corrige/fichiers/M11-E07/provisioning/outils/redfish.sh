#!/usr/bin/env bash
# redfish.sh — lecture Redfish d'un contrôleur de gestion (iLO 4 de hp01), M11-E07.
#
#   outils/redfish.sh [--env FICHIER] /redfish/v1/CHEMIN      → JSON sur la sortie standard
#   ex. outils/redfish.sh /redfish/v1/Systems/1/ | jq '{Model, SerialNumber, PowerState}'
#
# LECTURE SEULE : uniquement des GET (les actions passent par outils/alim.sh, qui les refuse pour hp01).
# Identifiants lus dans le fichier d'environnement SANS l'exécuter, transmis à curl par son entrée
# standard (-K -) : jamais sur la ligne de commande ni dans ps.
# TLS : certificat de l'iLO ÉPINGLÉ (vérifié par un second chemin, M11-E07), nom du certificat
# résolu vers l'adresse de l'iLO (--resolve) : la vérification de nom reste active. Jamais de -k.
set -euo pipefail

env_fichier="${ILO_ENV_FILE:-$HOME/.config/workbook/ilo-hp01.env}"
ca="${ILO_CA_FILE:-$HOME/.config/workbook/ilo-hp01.pem}"
if [[ "${1:-}" == "--env" ]]; then
  env_fichier="$2"
  shift 2
fi
chemin="${1:-}"

erreur() { printf 'redfish.sh : %s\n' "$*" >&2; exit 2; }

[[ "$chemin" == /redfish/v1* ]] || erreur "usage : redfish.sh [--env FICHIER] /redfish/v1/…"
[[ -r "$env_fichier" ]] || erreur "fichier d'accès illisible : $env_fichier"
[[ -r "$ca" ]] || erreur "certificat épinglé illisible : $ca"
[[ "$(stat -c %a "$env_fichier")" == 600 ]] || erreur "$env_fichier doit être en mode 600"

# lire CLÉ — valeur de CLÉ=… dans le fichier (guillemets facultatifs), sans l'exécuter.
lire() {
  sed -nE "s/^[[:space:]]*(export[[:space:]]+)?$1=\"?([^\"]*)\"?[[:space:]]*\$/\\2/p" "$env_fichier" | tail -n 1
}
hote="$(lire ILO_HOST)"; nom="$(lire ILO_NOM_TLS)"; utilisateur="$(lire ILO_USER)"; mdp="$(lire ILO_PASSWORD)"
for v in hote nom utilisateur mdp; do
  [[ -n "${!v}" ]] || erreur "variable manquante dans $env_fichier ($v)"
done

# Configuration curl sur l'entrée standard : « user » entre guillemets, \ et " échappés.
mdp="${mdp//\\/\\\\}"; mdp="${mdp//\"/\\\"}"
printf 'user = "%s:%s"\n' "$utilisateur" "$mdp" \
  | curl --silent --show-error --fail --max-time 20 --proto '=https' \
         --cacert "$ca" --resolve "$nom:443:$hote" \
         -H 'Accept: application/json' -H 'OData-Version: 4.0' \
         -K - "https://$nom$chemin"
