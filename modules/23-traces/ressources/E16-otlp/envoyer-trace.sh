#!/usr/bin/env bash
# envoyer-trace.sh — envoie une trace OTLP/JSON de deux spans au point d'entrée OTLP/HTTP (M23-E16).
# Usage : ./envoyer-trace.sh [--sans-jeton] [--jeton-fichier FICHIER] [--gros]
#   jeton lu dans ~/.config/workbook/otlp-essai.token (600) ; il n'apparaît ni dans « ps » ni dans l'historique.
#   --gros : ajoute un attribut de ~6 Mo pour éprouver la taille maximale des requêtes.
# Affiche le code HTTP et l'identifiant de trace à chercher dans Grafana (Explore → Tempo).
set -euo pipefail

URL="${OTLP_URL:-https://otlp.apps.par1.medisphere.internal:4318/v1/traces}"
RACINE="${WB_RACINE_PKI:-/usr/local/share/ca-certificates/medisphere-root-ca.crt}"
JETON_FICHIER="$HOME/.config/workbook/otlp-essai.token"
SANS_JETON=0
GROS=0
while (($#)); do
  case "$1" in
    --sans-jeton) SANS_JETON=1; shift ;;
    --jeton-fichier) JETON_FICHIER="$2"; shift 2 ;;
    --gros) GROS=1; shift ;;
    *) echo "option inconnue : $1" >&2; exit 2 ;;
  esac
done

ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
hex() { od -An -N"$1" -tx1 /dev/urandom | tr -d ' \n'; }
trace="$(hex 16)"
racine="$(hex 8)"
enfant="$(hex 8)"
maintenant="$(date +%s%N)"
corps="$(mktemp)"
trap 'rm -f "$corps"' EXIT
sed -e "s/__TRACE_ID__/$trace/g" -e "s/__SPAN_RACINE__/$racine/g" -e "s/__SPAN_ENFANT__/$enfant/g" \
  -e "s/__DEBUT__/$((maintenant - 250000000))/" -e "s/__FIN__/$maintenant/" \
  -e "s/__DEBUT_ENFANT__/$((maintenant - 200000000))/" -e "s/__FIN_ENFANT__/$((maintenant - 50000000))/" \
  "$ici/trace-modele.json" >"$corps"
if ((GROS)); then
  head -c 6000000 /dev/zero | tr '\0' 'x' >"$corps.bourrage"
  jq --rawfile b "$corps.bourrage" '.resourceSpans[0].scopeSpans[0].spans[0].attributes += [{"key": "bourrage", "value": {"stringValue": $b}}]' \
    "$corps" >"$corps.gros" && mv "$corps.gros" "$corps" && rm -f "$corps.bourrage"
fi

reponse="$(mktemp)"
config_curl="$(mktemp)" # en-tête d'authentification passé par fichier (600), jamais sur la ligne de commande
chmod 600 "$config_curl"
trap 'rm -f "$corps" "$reponse" "$config_curl"' EXIT
if ((!SANS_JETON)); then
  [[ -r "$JETON_FICHIER" ]] || { echo "jeton illisible : $JETON_FICHIER" >&2; exit 1; }
  printf 'header = "Authorization: Bearer %s"\n' "$(head -n 1 "$JETON_FICHIER" | awk '{print $1}')" >"$config_curl"
fi
code="$(curl -sS -o "$reponse" -w '%{http_code}' --cacert "$RACINE" -X POST \
  -H 'Content-Type: application/json' -K "$config_curl" --data-binary "@$corps" "$URL")" || true
echo "HTTP ${code:-000} — trace $trace"
head -c 300 "$reponse"
echo
