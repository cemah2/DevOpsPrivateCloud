#!/usr/bin/env bash
# plateforme/k8s — outils/empreinte-mediagenda.sh (M16-E24)
# Empreinte des données de MédiAgenda dans un espace : nombre de rendez-vous, somme de contrôle de
# toute la table (lignes triées par id), nombre de clés de Valkey. Lecture seule. Ne montre aucune
# donnée : seulement des nombres et une empreinte.
# Usage : outils/empreinte-mediagenda.sh ESPACE [BASE]      (BASE : défaut celle de la recette)
set -euo pipefail

ns="${1:?usage : $0 ESPACE [BASE]}"
base="${2:-$(kubectl get cluster mediagenda-db -n mediagenda-recette -o jsonpath='{.spec.bootstrap.initdb.database}')}"
base="${base:-app}"

primaire="$(kubectl get cluster mediagenda-db -n "$ns" -o jsonpath='{.status.currentPrimary}')"
[[ -n "$primaire" ]] || { echo "pas de primaire pour mediagenda-db dans $ns" >&2; exit 1; }

kubectl exec -n "$ns" "$primaire" -c postgres -- psql -X -At -d "$base" -c \
  "SELECT 'rendez_vous=' || count(*) || ' empreinte=' || coalesce(md5(string_agg(t::text, '|' ORDER BY t.id)), 'vide')
     FROM rendez_vous t"

# Valkey : DBSIZE sur le pod 0 du StatefulSet. Si Valkey exige un mot de passe (E08), il est lu
# dans le conteneur par la variable d'environnement de valkey-cli (REDISCLI_AUTH : à vérifier sur
# ta version), jamais passé en argument.
printf 'valkey_cles=%s\n' "$(kubectl exec -n "$ns" valkey-0 -- valkey-cli --no-auth-warning DBSIZE)"
