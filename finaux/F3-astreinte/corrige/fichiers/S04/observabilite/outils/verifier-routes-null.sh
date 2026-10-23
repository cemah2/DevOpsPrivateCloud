#!/bin/sh
# outils/verifier-routes-null.sh — plateforme/observabilite (F3-S04, INC-5904, PLAT-3304)
# Garde-fou de CI : aucune route de l'Alertmanager ne doit envoyer vers le récepteur « null » des
# alertes choisies par ÉQUIPE ou par ENVIRONNEMENT. Seules sont permises vers « null » les routes qui
# portent sur alertname (Watchdog, InfoInhibitor) ou sur la gravité « info ». Pour couper le bruit
# pendant une opération : un silence daté et commenté (RB-331), jamais une route.
# Usage : sh outils/verifier-routes-null.sh am/alertmanager.yaml   (yq de mikefarah)
set -eu
fichier="${1:?usage : $0 alertmanager.yaml}"
interdites="$(yq '[.route | .. | select(tag == "!!map") | select(.receiver == "null") | (.matchers // [])[]
  | select(test("^ *(equipe|environnement|namespace) *(=|!=|=~)"))] | length' "$fichier")"
if [ "$interdites" != 0 ]; then
  echo "ÉCHEC : $interdites critère(s) de route vers \"null\" portant sur l'équipe, l'environnement ou l'espace." >&2
  yq '[.route | .. | select(tag == "!!map") | select(.receiver == "null") | .matchers]' "$fichier" >&2
  exit 1
fi
echo "OK : aucune route vers \"null\" par équipe, environnement ou espace"
