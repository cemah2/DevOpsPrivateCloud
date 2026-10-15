#!/usr/bin/env bash
# outils/kubeconfig-checks.sh — kubeconfig des vérifications du workbook (M14-E06, PLAN §4.10).
#
# Lit le jeton et la CA du Secret wb-system/wb-checks-jeton (rbac/wb-checks.yaml) avec TON identité
# (contexte k8s-par1), écrit ~/.config/workbook/k8s-checks.kubeconfig (600), puis vérifie que
# l'identité obtenue lit le cluster et ne lit PAS les Secrets.
#
#   outils/kubeconfig-checks.sh                 # crée ou remplace le fichier
#   outils/kubeconfig-checks.sh --verifier      # contrôle le fichier existant seulement
#
# Révocation : supprimer le Secret wb-checks-jeton (le jeton est aussitôt refusé), le réappliquer
# (task appliquer), relancer ce script.
set -euo pipefail

CONTEXTE="k8s-par1"
ESPACE="wb-system"
SECRET="wb-checks-jeton"
SERVEUR="https://k8s-api.par1.medisphere.internal:8443"
CIBLE="${WB_K8S_KUBECONFIG:-$HOME/.config/workbook/k8s-checks.kubeconfig}"

verifier() {
  local f="$1" qui
  qui="$(kubectl --kubeconfig "$f" auth whoami -o jsonpath='{.status.userInfo.username}')"
  [[ "$qui" == "system:serviceaccount:$ESPACE:wb-checks" ]] \
    || { echo "Identité inattendue : ${qui:-aucune}" >&2; return 1; }
  kubectl --kubeconfig "$f" get nodes >/dev/null \
    || { echo "wb-checks ne lit pas les nœuds" >&2; return 1; }
  # « auth can-i » répond « no » avec le code 1 : c'est le résultat attendu ici.
  if kubectl --kubeconfig "$f" auth can-i list secrets --all-namespaces >/dev/null 2>&1; then
    echo "DANGER : wb-checks peut lister les Secrets" >&2; return 1
  fi
  if kubectl --kubeconfig "$f" auth can-i delete pods --all-namespaces >/dev/null 2>&1; then
    echo "DANGER : wb-checks peut supprimer des pods" >&2; return 1
  fi
  echo "OK : $qui lit le cluster, sans les Secrets, sans écrire."
}

if [[ "${1:-}" == --verifier ]]; then
  [[ -r "$CIBLE" ]] || { echo "Fichier absent : $CIBLE" >&2; exit 1; }
  [[ "$(stat -c %a "$CIBLE")" == 600 ]] || { echo "Droits de $CIBLE différents de 600" >&2; exit 1; }
  verifier "$CIBLE"
  exit 0
fi
[[ $# -eq 0 ]] || { echo "Usage : $0 [--verifier]" >&2; exit 2; }

# Le contrôleur de jetons remplit le Secret quelques instants après sa création.
jeton=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  jeton="$(kubectl --context "$CONTEXTE" -n "$ESPACE" get secret "$SECRET" -o jsonpath='{.data.token}' 2>/dev/null || true)"
  [[ -n "$jeton" ]] && break
  sleep 2
done
[[ -n "$jeton" ]] || { echo "Secret $ESPACE/$SECRET vide ou absent : rbac/wb-checks.yaml est-il appliqué ?" >&2; exit 1; }
ca="$(kubectl --context "$CONTEXTE" -n "$ESPACE" get secret "$SECRET" -o jsonpath='{.data.ca\.crt}')"

umask 077
mkdir -p "$(dirname "$CIBLE")"
temporaire="$(mktemp "$(dirname "$CIBLE")/.k8s-checks.XXXXXX")"
trap 'rm -f -- "$temporaire"' EXIT
# Écrit par printf (commande interne du shell) : le jeton n'apparaît dans aucun argument de
# processus visible (ps), contrairement à « kubectl config set-credentials --token=… ».
printf '%s\n' \
  "apiVersion: v1" \
  "kind: Config" \
  "clusters:" \
  "  - name: $CONTEXTE" \
  "    cluster:" \
  "      server: $SERVEUR" \
  "      certificate-authority-data: $ca" \
  "users:" \
  "  - name: wb-checks" \
  "    user:" \
  "      token: $(printf '%s' "$jeton" | base64 -d)" \
  "contexts:" \
  "  - name: wb-checks@$CONTEXTE" \
  "    context:" \
  "      cluster: $CONTEXTE" \
  "      user: wb-checks" \
  "current-context: wb-checks@$CONTEXTE" > "$temporaire"

verifier "$temporaire"
mv -f -- "$temporaire" "$CIBLE"
trap - EXIT
chmod 600 "$CIBLE"
echo "Écrit : $CIBLE"
