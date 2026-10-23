#!/usr/bin/env bash
# tests/ms-verif-equipe/lancer.sh — tests de ms-verif-equipe sans aucun service réel (F2-S13).
# Faux ldapsearch et kubectl (dossier faux/), sources sans identité ignorées : on vérifie la logique
# (statuts, code retour, JSON), pas les services. Lancé par la CI de plateforme/outils (job
# test:ms-verif-equipe) et à la main : tests/ms-verif-equipe/lancer.sh
set -euo pipefail

ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTIL="$ICI/../../bin/ms-verif-equipe"
export PATH="$ICI/faux:$PATH" MS_VERIF_ENV=/nonexistent KUBECONFIG=/dev/null
echecs=0

attendu() { # attendu "description" CODE_ATTENDU commande…
  local d="$1" c="$2" r=0
  shift 2
  "$@" >/dev/null 2>&1 || r=$?
  if [[ "$r" == "$c" ]]; then echo "ok    $d"; else echo "ÉCHEC $d (code $r, attendu $c)"; echecs=$((echecs + 1)); fi
}
json() { "$OUTIL" --json "$@" 2>/dev/null || true; }

attendu "usage : sans argument → 2" 2 "$OUTIL"
attendu "usage : nom d'équipe invalide → 2" 2 "$OUTIL" "Data;rm"
attendu "sources sans identité non ignorées → 1" 1 "$OUTIL" data

IGN=keycloak,gitlab,openbao,grafana,alertes,catalogue,annuaire
attendu "équipe data conforme sur les sources simulées → 0" 0 "$OUTIL" --ignorer "$IGN" data

r="$(IPA_URL=ldaps://faux IPA_BIND_DN=faux IPA_BIND_PASSWORD=faux json --ignorer "${IGN%,annuaire}" data)"
if jq -e '.conforme == false and (.controles[] | select(.controle == "annuaire") | .statut == "KO")' <<<"$r" >/dev/null; then
  echo "ok    membre désactivé encore dans le groupe → annuaire KO"
else
  echo "ÉCHEC membre désactivé non détecté"; echecs=$((echecs + 1))
fi
r="$(json --ignorer "$IGN" medivisio)"
if jq -e '.controles[] | select(.controle == "locataire") | .statut == "KO"' <<<"$r" >/dev/null; then
  echo "ok    locataire absent → KO"
else
  echo "ÉCHEC locataire absent non détecté"; echecs=$((echecs + 1))
fi
r="$(json --ignorer "$IGN" ext-essai)"
if jq -e '.externe == true and (.controles[] | select(.controle == "argocd") | .statut == "OK")' <<<"$r" >/dev/null; then
  echo "ok    équipe externe : pas d'AppProject attendu"
else
  echo "ÉCHEC équipe externe mal reconnue"; echecs=$((echecs + 1))
fi

((echecs == 0)) || { echo "$echecs test(s) en échec"; exit 1; }
echo "tous les tests passent"
