#!/usr/bin/env bash
# plateforme/k8s — outils/secret-mediagenda.sh (M14-E19)
# Crée, s'il n'existe pas, le Secret « mediagenda-db » d'un espace MédiAgenda : clé « mot-de-passe »,
# mot de passe du rôle PostgreSQL « mediagenda », aléatoire, jamais affiché. Même forme que le Secret
# créé à la main dans wb-essais en M14-E08 : les manifestes de l'équipe construisent l'URL de la base
# par interpolation ($(MEDIAGENDA_DB_MDP)).
# PostgreSQL est JETABLE au M14 (emptyDir) : le mot de passe n'a pas besoin d'être conservé ailleurs.
# Au M16 (CloudNativePG), c'est l'opérateur qui produira ce Secret ; au M25, Vault.
#
# Usage : outils/secret-mediagenda.sh ESPACE        ex. outils/secret-mediagenda.sh mediagenda-dev
set -euo pipefail

espace="${1:?usage : secret-mediagenda.sh ESPACE}"
if kubectl get secret mediagenda-db -n "$espace" >/dev/null 2>&1; then
  echo "Secret mediagenda-db déjà présent dans $espace : inchangé."
  exit 0
fi
# La valeur passe par l'entrée standard (format env), jamais par la ligne de commande ;
# printf est une commande interne du shell (absente de « ps »).
printf 'mot-de-passe=%s\n' "$(openssl rand -hex 24)" \
  | kubectl create secret generic mediagenda-db -n "$espace" --from-env-file=/dev/stdin \
      --dry-run=client -o yaml \
  | kubectl label --local -f - -o yaml app.kubernetes.io/part-of=mediagenda \
      app.kubernetes.io/managed-by=secret-mediagenda.sh \
  | kubectl apply -f -
