#!/usr/bin/env bash
# outils/argocd-restaurer-secret.sh (plateforme/k8s) — M20-E28, PLAT-2128 (RB-201, étape 5.4).
# Restaure dans argocd-secret, à partir d'un export DÉCHIFFRÉ (argocd admin export), les seules clés
# qui ne reviennent ni de Git ni du Vault :
#   server.secretkey           signature des sessions ET des jetons d'API (ci-lecture, argocd-checks.token)
#   accounts.<nom>.password, .passwordMtime, .tokens   mots de passe et liste des jetons des comptes locaux
# Tout le reste de l'export (Applications, AppProjects, ConfigMaps, autres Secrets) revient par
# l'application racine, Helmfile et secrets-k8s.sh : on ne le réapplique PAS (il recréerait les
# Applications avant la racine, et des Secrets peut-être plus anciens que le Vault).
#
# Usage : outils/argocd-restaurer-secret.sh EXPORT.yaml            (essai : affiche les clés retenues)
#         outils/argocd-restaurer-secret.sh EXPORT.yaml --appliquer
# Prérequis : yq 4 (mikefarah), jq, kubectl (contexte k8s-par1), release argocd installée.
# Aucune valeur n'est affichée. L'export déchiffré doit vivre en mémoire (/dev/shm), en 600.
set -Eeuo pipefail
umask 077

contexte="${KUBE_CONTEXTE:-k8s-par1}"
export_fichier="${1:-}"
mode="${2:-essai}"
[[ -r "$export_fichier" ]] || { echo "usage : $0 EXPORT.yaml [--appliquer]" >&2; exit 2; }
for c in yq jq kubectl; do command -v "$c" >/dev/null || { echo "$c introuvable" >&2; exit 2; }; done

# Le Secret argocd-secret de l'export, en JSON, réduit aux clés à restaurer.
donnees="$(yq -o=json 'select(.kind == "Secret" and .metadata.name == "argocd-secret") | .data' "$export_fichier" \
  | jq -c 'with_entries(select(.key == "server.secretkey" or (.key | test("^accounts\\.[^.]+\\.(password|passwordMtime|tokens)$"))))')"
[[ -n "$donnees" && "$donnees" != "null" && "$donnees" != "{}" ]] || {
  echo "argocd-secret introuvable ou vide dans $export_fichier" >&2; exit 1; }
jq -e 'has("server.secretkey")' <<<"$donnees" >/dev/null || { echo "server.secretkey absent de l'export" >&2; exit 1; }

echo "Clés retenues (valeurs non affichées) :"
jq -r 'keys[] | "  " + .' <<<"$donnees"

if [[ "$mode" != "--appliquer" ]]; then
  echo "Essai seulement. Relance avec --appliquer pour écrire dans argocd/argocd-secret."
  exit 0
fi

# Server-side apply d'un Secret PARTIEL : seules ces clés changent de gestionnaire ; les clés posées
# par le chart (webhook.gitlab.secret) restent à Helm. --force-conflicts : server.secretkey vient
# d'être générée par le nouveau serveur (gestionnaire argocd-server) et doit être remplacée.
jq -n --argjson d "$donnees" '{
    apiVersion: "v1", kind: "Secret", type: "Opaque",
    metadata: {name: "argocd-secret", namespace: "argocd"},
    data: $d
  }' | kubectl --context "$contexte" apply --server-side --force-conflicts \
        --field-manager=restauration-argocd -f - >/dev/null
echo "[OK] argocd-secret : clés restaurées."
# Le serveur relit argocd-secret par son informer ; on le redémarre pour ne pas dépendre de ce détail.
kubectl --context "$contexte" -n argocd rollout restart deployment/argocd-server >/dev/null
kubectl --context "$contexte" -n argocd rollout status deployment/argocd-server --timeout=5m
