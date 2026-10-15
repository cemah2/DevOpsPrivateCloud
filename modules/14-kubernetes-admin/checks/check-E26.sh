# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E26.sh — M14-E26 « Les certificats du cluster »
# À lancer depuis adm01. Lecture seule : dates des certificats sur le disque des nœuds de contrôle
# (openssl, sudo -n), certificats SERVIS par les ports 6443, 2379 et 10250 (openssl s_client depuis
# adm01, vérifiés avec la CA du cluster), ConfigMap kubelet-config, demandes de certificat, metrics-server,
# minuterie d'adm01, dépôts GitLab (en-tête des fichiers chiffrés seulement).

# shellcheck source=_m14-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m14-production.sh"

title "M14-E26 — Les certificats du cluster"
require_cmd kubectl jq ssh openssl
check_cmd "l'API du cluster répond (readyz)" _m14p_joignable

title "Certificats gérés par kubeadm (nœuds de contrôle)"
# Sur le nœud : pour chaque certificat, « NOM JOURS_RESTANTS ». CA : ca, etcd/ca, front-proxy-ca.
_M14_E26_JOURS='for f in $(find /etc/kubernetes/pki -name "*.crt" | sort); do
  fin=$(date -d "$(openssl x509 -in "$f" -noout -enddate | cut -d= -f2)" +%s)
  echo "${f#/etc/kubernetes/pki/} $(( (fin - $(date +%s)) / 86400 ))"
done'
for _m14_e26_n in "${_M14P_CP[@]}"; do
  _m14_e26_l="$(remote "$_m14_e26_n" "sudo -n bash -c '$_M14_E26_JOURS'" 2>/dev/null || true)"
  check_output "$_m14_e26_n : certificats lus (au moins 10)" '^ok$' \
    bash -c '(( $(grep -c . <<<"$1") >= 10 )) && echo ok' _ "$_m14_e26_l"
  check_output "$_m14_e26_n : chaque certificat feuille a plus de 180 jours devant lui" '^ok$' \
    bash -c 'awk '\''$1 !~ /(^|\/)ca\.crt$|front-proxy-ca\.crt$/ && $2 <= 180 { ko=1 } END { exit ko }'\'' <<<"$1" \
      && grep -q . <<<"$1" && echo ok' _ "$_m14_e26_l"
  check_output "$_m14_e26_n : les trois autorités ont plus de 9 ans devant elles" '^ok$' \
    bash -c '(( $(awk '\''$1 ~ /(^|\/)ca\.crt$|front-proxy-ca\.crt$/ && $2 > 3285 { n++ } END { print n+0 }'\'' <<<"$1") == 3 )) && echo ok' \
    _ "$_m14_e26_l"
  # Ce que les processus servent = ce qui est sur le disque (renouvellement suivi d'un redémarrage).
  for _m14_e26_p in "6443 apiserver.crt" "2379 etcd/server.crt"; do
    read -r _m14_e26_port _m14_e26_f <<<"$_m14_e26_p"
    _m14_e26_servi="$(_m14p_fin_servie "${_M14P_IP[$_m14_e26_n]}" "$_m14_e26_port" || true)"
    _m14_e26_disque="$(_m14p_sudo "$_m14_e26_n" "openssl x509 -in /etc/kubernetes/pki/$_m14_e26_f -noout -enddate" | cut -d= -f2 || true)"
    _m14_e26_disque="$(date -d "$_m14_e26_disque" +%s 2>/dev/null || true)"
    check_output "$_m14_e26_n : le port $_m14_e26_port sert le certificat $_m14_e26_f du disque (composant redémarré)" '^ok$' \
      bash -c '[[ -n "$1" && "$1" == "$2" ]] && echo ok' _ "$_m14_e26_servi" "$_m14_e26_disque"
  done
done

title "Certificats de service des kubelets"
check_output "ConfigMap kubelet-config : serverTLSBootstrap: true" 'serverTLSBootstrap: *true' \
  kube -n kube-system get configmap kubelet-config -o 'jsonpath={.data.kubelet}'
_m14_e26_ca="$(mktemp)"
if _m14p_ca_cluster "$_m14_e26_ca"; then
  for _m14_e26_n in "${_M14P_TOUS[@]}"; do
    check_cmd "$_m14_e26_n:10250 : certificat signé par la CA du cluster, valide pour le nom du nœud" bash -c \
      'timeout "$4" openssl s_client -connect "$1:10250" -servername "$2" -CAfile "$3" -verify_hostname "$2" -verify_return_error \
         </dev/null >/dev/null 2>&1' _ "${_M14P_IP[$_m14_e26_n]}" "$_m14_e26_n" "$_m14_e26_ca" "$WB_TIMEOUT"
  done
else
  check_cmd "CA du cluster lue dans le kubeconfig des checks" false
fi
rm -f "$_m14_e26_ca"
_m14_e26_csr="$(_m14p_json get csr)"
if [[ "$_m14_e26_csr" != null ]]; then
  check_cmd "aucune demande kubelet-serving en attente depuis plus d'une heure" _m14p_jq "$_m14_e26_csr" \
    '[.items[] | select(.spec.signerName == "kubernetes.io/kubelet-serving")
      | select((.status.conditions // []) | length == 0)
      | select((now - (.metadata.creationTimestamp | fromdateiso8601)) > 3600)] | length == 0'
else
  skip "demandes de certificat en attente" "lecture des CSR non permise au compte wb-checks"
fi

title "metrics-server"
_m14_e26_ms="$(_m14p_json -n kube-system get deployment metrics-server)"
check_cmd "metrics-server existe et ne désactive plus la vérification TLS des kubelets" _m14p_jq "$_m14_e26_ms" \
  '[.spec.template.spec.containers[] | (.args // []) + (.command // []) | .[]] | any(. == "--kubelet-insecure-tls") | not'
check_cmd "l'API de métriques est disponible (APIService v1beta1.metrics.k8s.io)" bash -c \
  'jq -e "any(.status.conditions[]?; .type == \"Available\" and .status == \"True\")" >/dev/null <<<"$1"' \
  _ "$(_m14p_json get apiservice v1beta1.metrics.k8s.io)"

title "Surveillance et coffre"
check_cmd "adm01 : k8s-certificats.timer activé et actif" bash -c \
  'systemctl is-enabled --quiet k8s-certificats.timer && systemctl is-active --quiet k8s-certificats.timer'
check_output "adm01 : le service d'échéances alerte en cas d'échec" '^OnFailure=.*ms-alerte@' \
  systemctl show -p OnFailure k8s-certificats.service
_m14_e26_secrets="$(_m14p_arbre plateforme/k8s secrets || true)"
for _m14_e26_k in admin super-admin; do
  _m14_e26_f="$(grep -E "(^|/)$_m14_e26_k\.conf" <<<"$_m14_e26_secrets" | head -1 || true)"
  _m14_e26_entete=""
  if [[ -n "$_m14_e26_f" ]]; then
    _m14_e26_entete="$(_m14p_fichier_main plateforme/k8s "$_m14_e26_f" 2>/dev/null | head -1 || true)"
  fi
  check_output "plateforme/k8s : $_m14_e26_k.conf chiffré (Vault « critique ») sur main" '^\$ANSIBLE_VAULT;1\.2;AES256;critique' \
    echo "$_m14_e26_entete"
done
check_cmd "RB-143 sur main (renouvellement, kubelet-serving, rotation de la CA)" \
  _m14p_doc_prefixe docs/kubernetes/runbooks RB-143 'certs renew' 'kubelet-serving' 'CA'
