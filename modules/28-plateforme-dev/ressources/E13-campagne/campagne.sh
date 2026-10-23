#!/usr/bin/env bash
# campagne.sh — M28-E13 : publie N demandes de notification FACTICES dans l'échange « notifications »
# du vhost de RECETTE de MédiNotif, par l'API HTTP de gestion de RabbitMQ (POST /api/exchanges/…/publish).
#
# Usage : campagne.sh N [--parallele P]        ex. campagne.sh 2000
#
# Compte utilisé : « campagne-recette » (déclaré par la topologie en M28-E13 : étiquette management,
# écriture sur l'échange notifications du seul vhost medinotif-recette). Son mot de passe est lu dans
# OpenBao (kv/medinotif/recette/campagne, clé mot_de_passe) avec TA session (bao login -method=oidc) ;
# il ne passe jamais en argument d'une commande (fichier de configuration curl lu sur un descripteur).
# Les destinataires sont fictifs (+33600000000 à +33600009999, @exemple.invalid) : rien ne part, et
# MédiNotif ne journalise jamais un destinataire en clair.
# Garde-fou : refuse tout autre vhost que medinotif-recette.
set -euo pipefail

VHOST=medinotif-recette
ECHANGE=notifications
API="${WB_RABBITMQ_URL:-https://rabbitmq.apps.par1.medisphere.internal}/api"
CHEMIN_SECRET="${CAMPAGNE_SECRET:-medinotif/recette/campagne}"
UTILISATEUR="${CAMPAGNE_UTILISATEUR:-campagne-recette}"

usage() { echo "Usage : $0 N [--parallele P]   (N entre 1 et 50000)" >&2; exit 2; }
[[ $# -ge 1 && "$1" =~ ^[0-9]+$ ]] || usage
n="$1"; shift
p=8
while (($#)); do
  case "$1" in
    --parallele) p="${2:?}"; shift 2 ;;
    *) usage ;;
  esac
done
((n >= 1 && n <= 50000)) || usage
[[ "${CAMPAGNE_VHOST:-$VHOST}" == "$VHOST" ]] || { echo "Refusé : ce script ne publie que dans $VHOST." >&2; exit 2; }
for c in curl jq bao xargs; do command -v "$c" >/dev/null || { echo "outil manquant : $c" >&2; exit 2; }; done

mdp="$(bao kv get -mount=kv -field=mot_de_passe "$CHEMIN_SECRET")" || {
  echo "Lecture de kv/$CHEMIN_SECRET impossible : bao login -method=oidc, puis relance." >&2; exit 1; }
conf="$(mktemp)"; chmod 600 "$conf"
trap 'rm -f "$conf"' EXIT
printf 'user = "%s:%s"\n' "$UTILISATEUR" "$mdp" >"$conf"
unset mdp

# Clé de routage : celle de la liaison échange → file « notifications » (échange direct, M27).
cle="$(curl -sf -K "$conf" "$API/exchanges/$VHOST/$ECHANGE/bindings/source" |
  jq -r '[.[] | select(.destination == "notifications" and .destination_type == "queue")][0].routing_key // empty')" || cle=""
if [[ -z "$cle" ]]; then
  echo "Liaison $ECHANGE → notifications introuvable dans $VHOST (droits du compte, topologie ?)." >&2
  exit 1
fi

export API VHOST ECHANGE cle conf
publier() {
  local i="$1" corps
  corps="$(jq -nc --arg rk "$cle" --argjson i "$i" '{
    properties: {delivery_mode: 2, content_type: "application/json"},
    routing_key: $rk, payload_encoding: "string",
    payload: ({type: "sms", destinataire: ("+3360000" + ("0000" + ($i % 10000 | tostring))[-4:]),
               modele: "rappel-campagne-essai", rendez_vous_id: (900000000 + $i)} | tojson)}')"
  curl -sf -K "$conf" -H 'Content-Type: application/json' --data "$corps" \
    "$API/exchanges/$VHOST/$ECHANGE/publish" | jq -e '.routed == true' >/dev/null || echo "KO $i"
}
export -f publier

debut=$(date +%s)
ko="$(seq 1 "$n" | xargs -P "$p" -I{} bash -c 'publier {}' | grep -c '^KO' || true)"
echo "Publié : $((n - ko)) / $n message(s) dans $VHOST/$ECHANGE en $(($(date +%s) - debut)) s (non routés : $ko)."
echo "Suivi : kubectl -n medinotif-recette get hpa,pods -w   et   file : interface RabbitMQ, vhost $VHOST."
