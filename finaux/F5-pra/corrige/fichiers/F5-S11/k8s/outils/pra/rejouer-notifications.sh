#!/usr/bin/env bash
# shellcheck disable=SC2016  # filtre jq entre apostrophes
# plateforme/k8s — outils/pra/rejouer-notifications.sh (F5-S11, PLAT-3511, INC-6109)
#
# Rejoue les demandes de notification « confirmation » de MédiAgenda perdues pendant un PRA :
# rendez-vous créés dans une fenêtre [DEPUIS, JUSQUA[ (UTC), dont le patient a choisi un canal de rappel,
# hors témoins PRA-TEMOIN. Publication sur l'échange « notifications » (clé « notifications ») du vhost
# de MédiNotif par l'API HTTP de gestion de RabbitMQ, message persistant au format de MédiNotif, avec
# l'en-tête x-medisphere-rejeu (traçabilité). Livraison « au moins une fois » : un patient peut recevoir
# deux confirmations (règle validée par Julien Petit, main courante).
#
# Usage :
#   rejouer-notifications.sh DEPUIS JUSQUA            compte seulement (aucune publication)
#   rejouer-notifications.sh DEPUIS JUSQUA --publier  publie
#   DEPUIS, JUSQUA : horodatages ISO 8601 en UTC (ex. 2026-12-15T08:50:00Z)
#
# Ne journalise JAMAIS un destinataire : seulement les identifiants de rendez-vous et des compteurs.
#
# Variables : KUBECONFIG_PAR2 (~/.kube/k8s-par2.config), NS (mediagenda-prod), CLUSTER (mediagenda-db-par2),
#   RABBITMQ_API (https://rabbitmq.apps.par2.medisphere.internal), VHOST (medinotif-prod),
#   RABBITMQ_IDENTIFIANTS (~/.config/pra/rabbitmq-rejeu.env : RABBITMQ_USER=…, RABBITMQ_PASSWORD=… ;
#   compte du vhost avec le droit d'écrire sur l'échange « notifications »), CA (racine MédiSphère).
set -euo pipefail

KUBECONFIG_PAR2="${KUBECONFIG_PAR2:-$HOME/.kube/k8s-par2.config}"
NS="${NS:-mediagenda-prod}"
CLUSTER="${CLUSTER:-mediagenda-db-par2}"
RABBITMQ_API="${RABBITMQ_API:-https://rabbitmq.apps.par2.medisphere.internal}"
VHOST="${VHOST:-medinotif-prod}"
RABBITMQ_IDENTIFIANTS="${RABBITMQ_IDENTIFIANTS:-$HOME/.config/pra/rabbitmq-rejeu.env}"
CA="${CA:-/usr/local/share/ca-certificates/medisphere-root-ca.crt}"

depuis="${1:?DEPUIS (UTC ISO 8601) attendu}"
jusqua="${2:?JUSQUA (UTC ISO 8601) attendu}"
publier=0
[[ "${3:-}" == "--publier" ]] && publier=1

for h in "$depuis" "$jusqua"; do
  [[ "$h" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || { echo "horodatage UTC attendu : $h" >&2; exit 2; }
done

pod="$(kubectl --kubeconfig "$KUBECONFIG_PAR2" -n "$NS" get cluster "$CLUSTER" -o jsonpath='{.status.currentPrimary}')"
[[ -n "$pod" ]] || { echo "instance primaire de $CLUSTER introuvable" >&2; exit 1; }

# Une ligne JSON par demande, dans l'ordre des identifiants. Rien n'est affiché à l'écran.
demandes="$(kubectl --kubeconfig "$KUBECONFIG_PAR2" -n "$NS" exec "$pod" -c postgres -- \
  psql -d mediagenda -AtX -v ON_ERROR_STOP=1 -c "
    SELECT json_build_object('type', canal_rappel, 'destinataire', contact_rappel,
                             'modele', 'confirmation', 'rendez_vous_id', id)::text
      FROM rendez_vous
     WHERE cree_le >= '$depuis'::timestamptz AND cree_le < '$jusqua'::timestamptz
       AND canal_rappel <> 'aucun' AND praticien <> 'PRA-TEMOIN'
     ORDER BY id")"

n="$(grep -c . <<<"$demandes" || true)"
echo "Fenêtre $depuis → $jusqua : $n demande(s) de confirmation à rejouer."
echo "Par canal : $(jq -r '.type' <<<"$demandes" 2>/dev/null | sort | uniq -c | tr '\n' ' ')"
((publier)) || { echo "Aucune publication (ajoute --publier)."; exit 0; }
((n > 0)) || exit 0

[[ -r "$RABBITMQ_IDENTIFIANTS" ]] || { echo "identifiants illisibles : $RABBITMQ_IDENTIFIANTS" >&2; exit 1; }
RABBITMQ_USER=""
RABBITMQ_PASSWORD=""
# shellcheck disable=SC1090
source "$RABBITMQ_IDENTIFIANTS"
vhost_enc="$(jq -rn --arg v "$VHOST" '$v|@uri')"

ok=0
ko=0
while IFS= read -r d; do
  [[ -n "$d" ]] || continue
  id="$(jq -r '.rendez_vous_id' <<<"$d")"
  corps="$(jq -nc --arg p "$d" '{properties: {delivery_mode: 2, content_type: "application/json",
             headers: {"x-medisphere-rejeu": "INC-6109"}},
           routing_key: "notifications", payload: $p, payload_encoding: "string"}')"
  # Identifiants par un fichier de configuration curl (jamais sur la ligne de commande).
  if curl -sf --max-time 10 --cacert "$CA" -K <(printf 'user = "%s:%s"\n' "$RABBITMQ_USER" "$RABBITMQ_PASSWORD") \
    -H 'Content-Type: application/json' --data-binary "$corps" \
    "$RABBITMQ_API/api/exchanges/$vhost_enc/notifications/publish" | jq -e '.routed == true' >/dev/null; then
    ok=$((ok + 1))
  else
    ko=$((ko + 1))
    echo "rendez-vous $id : publication NON routée" >&2
  fi
done <<<"$demandes"
echo "Publiées et routées : $ok ; échecs : $ko."
((ko == 0))
