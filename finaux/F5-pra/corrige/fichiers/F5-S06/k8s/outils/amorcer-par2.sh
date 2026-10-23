#!/usr/bin/env bash
# outils/amorcer-par2.sh — amorçage des Secrets de k8s-par2 qu'aucun contrôleur ne peut créer (F5-S06,
# RB-356 §2). Projet plateforme/k8s. Même principe que outils/amorcer-secrets.sh du F1 : valeurs lues
# dans Ansible Vault « critique » (clone du MIROIR de plateforme/ansible sur adm02), passées par l'entrée
# standard, jamais sur la ligne de commande ni sur le disque ; objets étiquetés
# medisphere.internal/amorcage=f5 (repérables, adoptables plus tard).
#   1. cert-manager/medisphere-par2-ca     : autorité de PAR2 (certificat + racine, clé) → ClusterIssuer CA
#   2. argocd/repo-creds-miroirs-par2      : clé SSH de LECTURE des miroirs de adm02 (Argo CD)
#   3. <espaces>/harbor-pull               : compte « lecture » de reg02 sous l'hôte registry.par1… (containerd
#                                            tire de reg02 par miroir) ; même nom de Secret qu'à PAR1
#   4. wb-system : kubeconfig du compte wb-checks (~/.config/workbook/k8s-par2-checks.kubeconfig)
# Lancé depuis adm02 avec le contexte k8s-par2 (admin.conf de k8s-par2, enveloppe E7), une fois après la
# couche de base, et après chaque reconstruction du cluster. Idempotent (apply).
#
# Usage : outils/amorcer-par2.sh ANSIBLE_DIR      (ex. ~/src/ansible, clone du miroir)
set -Eeuo pipefail
umask 077

ansible_dir="${1:?usage : $0 ANSIBLE_DIR}"
ctx="${CONTEXTE:-k8s-par2}"
k() { kubectl --context "$ctx" "$@"; }
etiquette=(--overwrite medisphere.internal/amorcage=f5)
vault() { (cd "$ansible_dir" && uv run ansible-vault view --vault-id critique@outils/vault-pass-client.sh "$1"); }
champ() { vault "$1" | yq -r ".$2"; }

[[ "$(k config current-context 2>/dev/null || true)" == "$ctx" || -n "$(k get --raw /version 2>/dev/null)" ]] \
  || { echo "contexte $ctx injoignable" >&2; exit 1; }

# 1. Autorité de PAR2 : tls.crt = intermédiaire + racine (chaîne servie), tls.key = clé, ca.crt = racine.
crt="$(cat "$ansible_dir/pki/medisphere-par2-intermediate-ca.crt" "$ansible_dir/pki/medisphere-root-ca.crt")"
k -n cert-manager create secret generic medisphere-par2-ca --type=kubernetes.io/tls \
  --from-file=tls.crt=<(printf '%s\n' "$crt") \
  --from-file=tls.key=<(champ secrets/pki-par2.yml pki_par2_cle) \
  --from-file=ca.crt="$ansible_dir/pki/medisphere-root-ca.crt" \
  --dry-run=client -o yaml | k apply -f -
k -n cert-manager label secret medisphere-par2-ca "${etiquette[@]}"

# 2. Identifiants de dépôts d'Argo CD : modèle « repo-creds » (préfixe d'URL), clé de lecture des miroirs.
k -n argocd create secret generic repo-creds-miroirs-par2 \
  --from-literal=type=git \
  --from-literal=url=ssh://miroir@adm02.par2.medisphere.internal/srv/miroirs/ \
  --from-file=sshPrivateKey=<(champ secrets/miroirs-par2.yml argocd_cle_privee) \
  --dry-run=client -o yaml | k apply -f -
k -n argocd label secret repo-creds-miroirs-par2 "${etiquette[@]}" argocd.argoproj.io/secret-type=repo-creds

# 3. Tirage depuis reg02, sous le nom d'hôte des manifestes.
auth="$(printf 'lecture:%s' "$(champ secrets/reg02.yml mdp_lecture)" | base64 -w0)"
for ns in mediagenda-prod medidoc-recette legacy-rdv-prod medinotif-prod; do
  k get namespace "$ns" >/dev/null 2>&1 || continue
  jq -n --arg a "$auth" '{auths: {"registry.par1.medisphere.internal": {auth: $a}}}' \
    | k -n "$ns" create secret generic harbor-pull --type=kubernetes.io/dockerconfigjson \
        --from-file=.dockerconfigjson=/dev/stdin --dry-run=client -o yaml | k apply -f -
  k -n "$ns" label secret harbor-pull "${etiquette[@]}"
done

# 4. Kubeconfig des vérifications (jeton lié de 90 jours, compte wb-checks).
jeton="$(k -n wb-system create token wb-checks --duration=2160h)"
serveur="$(k config view --minify -o jsonpath='{.clusters[0].cluster.server}')"
ca="$(k config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')"
install -d -m 700 "$HOME/.config/workbook"
cat >"$HOME/.config/workbook/k8s-par2-checks.kubeconfig" <<KCFG
apiVersion: v1
kind: Config
clusters:
  - name: k8s-par2
    cluster: {server: "$serveur", certificate-authority-data: "$ca"}
users:
  - name: wb-checks
    user: {token: "$jeton"}
contexts:
  - name: wb-checks@k8s-par2
    context: {cluster: k8s-par2, user: wb-checks}
current-context: wb-checks@k8s-par2
KCFG
chmod 600 "$HOME/.config/workbook/k8s-par2-checks.kubeconfig"
echo "amorçage de k8s-par2 terminé (étiquette medisphere.internal/amorcage=f5)."
