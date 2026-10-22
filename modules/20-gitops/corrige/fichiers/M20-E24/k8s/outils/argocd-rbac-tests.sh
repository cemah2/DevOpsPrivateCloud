#!/usr/bin/env bash
# outils/argocd-rbac-tests.sh (plateforme/k8s) — M20-E24, SEC-2124.
# Joue les cas de releases/argocd/rbac-tests.txt contre la politique releases/argocd/policy.csv, HORS
# LIGNE, avec « argocd admin settings rbac can » (CLI de la version d'Argo CD déployée).
#
# Usage : outils/argocd-rbac-tests.sh [POLITIQUE] [TESTS]
#   défauts : releases/argocd/policy.csv  releases/argocd/rbac-tests.txt (depuis la racine du dépôt)
#   Variable : ARGOCD_POLICY_DEFAULT (défaut : vide, comme composants/argocd/values-rbac.yaml).
# Code de sortie : 0 si tous les cas donnent le résultat attendu ; 1 s'il y a au moins un écart ou une
# ligne invalide (tous sont affichés, la boucle va au bout) ; 2 si un outil ou un fichier manque.
#
# Pièges de la commande, constatés avec argocd 3.5.5 :
#   - elle construit un client Kubernetes même avec --policy-file : sans configuration, elle échoue
#     (« invalid configuration ») ; un kubeconfig FACTICE suffit, aucune connexion n'est faite ;
#     ce kubeconfig doit porter un jeton (sinon client-go demande un nom d'utilisateur au terminal) ;
#   - elle sort en 1 pour « No » ET pour une erreur (action ou ressource inconnue) : on lit la SORTIE ;
#   - elle écrit des avertissements de chargement sur la sortie d'erreur : on ne les mélange pas.
set -Eeuo pipefail

politique="${1:-releases/argocd/policy.csv}"
tests="${2:-releases/argocd/rbac-tests.txt}"

command -v argocd >/dev/null 2>&1 || { echo "argocd (CLI) introuvable" >&2; exit 2; }
for f in "$politique" "$tests"; do
  [[ -r "$f" ]] || { echo "fichier illisible : $f" >&2; exit 2; }
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# ConfigMap équivalente à argocd-rbac-cm (la commande accepte ce format avec --policy-file).
{
  printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: argocd-rbac-cm\ndata:\n'
  printf '  policy.default: "%s"\n' "${ARGOCD_POLICY_DEFAULT:-}"
  printf '  policy.matchMode: glob\n'
  printf '  policy.csv: |\n'
  sed 's/^/    /' "$politique"
} >"$tmp/argocd-rbac-cm.yaml"

cat >"$tmp/factice.kubeconfig" <<'EOF'
apiVersion: v1
kind: Config
clusters:
  - name: aucun
    cluster:
      server: https://127.0.0.1:9
contexts:
  - name: aucun
    context: {cluster: aucun, user: aucun, namespace: argocd}
current-context: aucun
users:
  - name: aucun
    user: {token: factice}
EOF
export KUBECONFIG="$tmp/factice.kubeconfig"

if ! argocd admin settings rbac validate --policy-file "$tmp/argocd-rbac-cm.yaml" </dev/null >"$tmp/validation" 2>&1; then
  echo "Politique INVALIDE :" >&2
  cat "$tmp/validation" >&2
  exit 1
fi

total=0 ecarts=0 n=0
while IFS= read -r ligne || [[ -n "$ligne" ]]; do
  n=$((n + 1))
  ligne="${ligne%%#*}"
  [[ -z "${ligne//[[:space:]]/}" ]] && continue
  read -r attendu sujet action ressource objet reste <<<"$ligne"
  if [[ "$attendu" != oui && "$attendu" != non ]] || [[ -z "${objet:-}" || -n "${reste:-}" ]]; then
    echo "ligne $n invalide (attendu : oui|non SUJET ACTION RESSOURCE OBJET) : $ligne" >&2
    ecarts=$((ecarts + 1))
    continue
  fi
  total=$((total + 1))
  # Réponse sur la sortie standard ; avertissements et erreurs sur la sortie d'erreur, gardés à part
  # (argocd 3.5 avertit « user defined roles not found in policies » pour un rôle qui n'a que des
  # héritages, comme role:plateforme-admin → role:admin intégré : sans conséquence).
  sortie="$(argocd admin settings rbac can "$sujet" "$action" "$ressource" "$objet" \
    --policy-file "$tmp/argocd-rbac-cm.yaml" </dev/null 2>"$tmp/erreur")" || true
  case "$sortie" in
    Yes) obtenu=oui ;;
    No) obtenu=non ;;
    *)
      echo "ligne $n : erreur de la commande pour « $sujet $action $ressource $objet » : $(cat "$tmp/erreur")" >&2
      ecarts=$((ecarts + 1))
      continue
      ;;
  esac
  if [[ "$obtenu" == "$attendu" ]]; then
    printf 'ok    %-3s %s %s %s %s\n' "$attendu" "$sujet" "$action" "$ressource" "$objet"
  else
    printf 'ÉCART attendu %s, obtenu %s : %s %s %s %s (ligne %d)\n' \
      "$attendu" "$obtenu" "$sujet" "$action" "$ressource" "$objet" "$n" >&2
    ecarts=$((ecarts + 1))
  fi
done <"$tests"

echo "Cas joués : $total ; écarts ou erreurs : $ecarts"
(( total > 0 )) || { echo "aucun cas dans $tests" >&2; exit 1; }
(( ecarts == 0 ))
