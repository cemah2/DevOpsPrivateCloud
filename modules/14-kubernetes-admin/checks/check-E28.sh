# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres et commandes distantes entre apostrophes
#
# check-E28.sh — M14-E28 « Chiffrer les Secrets dans etcd »
# À lancer depuis adm01. Lecture seule : options des serveurs d'API, ConfigMap kubeadm-config, mode et
# PREMIER fournisseur du fichier de configuration (lu par sudo -n, seul le nom du type sort du nœud),
# préfixes des valeurs stockées dans etcd (40 premiers octets, jamais la valeur), dépôts GitLab.

# shellcheck source=_m14-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m14-production.sh"

title "M14-E28 — Chiffrer les Secrets dans etcd"
require_cmd kubectl jq ssh
check_cmd "l'API du cluster répond (readyz)" _m14p_joignable

_M14_E28_CONF=/etc/kubernetes/chiffrement/configuration.yaml

title "Serveurs d'API et configuration"
for _m14_e28_n in "${_M14P_CP[@]}"; do
  check_cmd "$_m14_e28_n : --encryption-provider-config=$_M14_E28_CONF" \
    _m14p_arg_api "$_m14_e28_n" encryption-provider-config "$_M14_E28_CONF"
  check_cmd "$_m14_e28_n : rechargement automatique de la configuration" \
    _m14p_arg_api "$_m14_e28_n" encryption-provider-config-automatic-reload 'true'
  check_ssh_output "$_m14_e28_n : configuration en root, 600" "$_m14_e28_n" '^root 600$' \
    "sudo -n stat -c '%U %a' $_M14_E28_CONF"
  # Premier fournisseur de la ressource « secrets » : seul son TYPE est imprimé.
  check_ssh_output "$_m14_e28_n : premier fournisseur pour les Secrets = secretbox (seul fournisseur local non déconseillé)" "$_m14_e28_n" \
    '^secretbox$' "sudo -n awk '
      /^[[:space:]]*-[[:space:]]*resources:/ { dans=0 }
      /^[[:space:]]*-[[:space:]]*secrets[[:space:]]*\$/ { dans=1 }
      dans && /^[[:space:]]*providers:/ { prov=1; next }
      prov && match(\$0, /^[[:space:]]*-[[:space:]]*(identity|aescbc|aesgcm|secretbox|kms)/) {
        t=\$0; sub(/^[[:space:]]*-[[:space:]]*/, \"\", t); sub(/[^a-z].*\$/, \"\", t); print t; exit }' $_M14_E28_CONF"
done
_m14_e28_cc="$(_m14p_cc || true)"
check_output "kubeadm-config contient l'option de chiffrement" 'encryption-provider-config' echo "$_m14_e28_cc"
check_cmd "plateforme/k8s : option de chiffrement dans cluster/kubeadm-config.yaml sur main" \
  _m14p_fichier_contient plateforme/k8s cluster/kubeadm-config.yaml 'encryption-provider-config'

title "Dans etcd"
_m14_e28_cp="${_M14P_CP[0]}"
check_output "wb-essais/temoin-chiffrement stocké chiffré par secretbox" '^k8s:enc:secretbox:v1:' \
  _m14p_prefixe_secret "$_m14_e28_cp" wb-essais temoin-chiffrement
# Décompte sur le nœud : « TOTAL CLAIR » sur toutes les clés /registry/secrets/ (aucune valeur ne sort).
_M14_E28_DECOMPTE='
export ETCDCTL_ENDPOINTS=https://127.0.0.1:2379 ETCDCTL_CACERT=/etc/kubernetes/pki/etcd/ca.crt
export ETCDCTL_CERT=/etc/kubernetes/pki/etcd/healthcheck-client.crt ETCDCTL_KEY=/etc/kubernetes/pki/etcd/healthcheck-client.key
total=0; clair=0
for k in $(/usr/local/bin/etcdctl get /registry/secrets/ --prefix --keys-only); do
  total=$((total + 1))
  p=$(/usr/local/bin/etcdctl get "$k" --print-value-only | head -c 8)
  [ "$p" = "k8s:enc:" ] || clair=$((clair + 1))
done
echo "$total $clair"'
read -r _m14_e28_total _m14_e28_clair <<<"$(remote "$_m14_e28_cp" "sudo -n bash -c '$_M14_E28_DECOMPTE'" 2>/dev/null || echo "x x")"
check_output "Secrets lus dans etcd ($_m14_e28_total)" '^ok$' \
  bash -c '[[ "$1" =~ ^[0-9]+$ ]] && (( $1 > 0 )) && echo ok' _ "$_m14_e28_total"
check_output "aucun Secret stocké en clair dans etcd (en clair : $_m14_e28_clair)" '^0$' echo "$_m14_e28_clair"

title "Documentation"
check_cmd "analyse sur main (menaces, KMS, restauration)" \
  _m14p_fichier_contient plateforme/medisphere docs/kubernetes/securite/chiffrement-secrets.md 'KMS' 'secretbox' 'restaur'
check_cmd "RB-141 cite la clé de chiffrement des Secrets parmi les préalables" \
  _m14p_doc_prefixe docs/kubernetes/runbooks RB-141 'chiffrement des Secrets|EncryptionConfiguration|clé de chiffrement'
