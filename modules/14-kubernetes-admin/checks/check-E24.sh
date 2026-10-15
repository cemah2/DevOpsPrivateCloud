# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E24.sh — M14-E24 « Sauvegarder et restaurer etcd »
# À lancer depuis adm01. Lecture seule : unités systemd et état des nœuds de contrôle (SSH, sudo -n
# pour lire), etcd (endpoint status), objets S3 du compartiment etcd-k8s-par1 (identité etcd-k8s :
# liste et lecture des 21 premiers octets d'un objet), ConfigMap témoin, GitLab, datastore PBS.

# shellcheck source=_m14-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m14-production.sh"

title "M14-E24 — Sauvegarder et restaurer etcd"
require_cmd kubectl jq aws ssh
check_cmd "l'API du cluster répond (readyz)" _m14p_joignable

_m14_e24_version="$(_m14p_version_etcd_cluster || true)"
check_output "version de l'etcd du cluster lue sur le pod etcd de ${_M14P_CP[0]}" '^[0-9]+\.[0-9]+\.[0-9]+$' \
  echo "$_m14_e24_version"

title "Minuterie et instantanés sur les nœuds de contrôle"
for _m14_e24_n in "${_M14P_CP[@]}"; do
  check_ssh "$_m14_e24_n : etcd-instantane.timer activé et actif" "$_m14_e24_n" \
    'systemctl is-enabled --quiet etcd-instantane.timer && systemctl is-active --quiet etcd-instantane.timer'
  check_ssh_output "$_m14_e24_n : le service se relance à chaque heure (OnCalendar)" "$_m14_e24_n" \
    'OnCalendar=\*-\*-\* \*:[0-5][0-9]' 'systemctl show -p TimersCalendar etcd-instantane.timer'
  check_ssh_output "$_m14_e24_n : le service alerte en cas d'échec (OnFailure=ms-alerte@)" "$_m14_e24_n" \
    '^OnFailure=.*ms-alerte@' 'systemctl show -p OnFailure etcd-instantane.service'
  check_ssh_output "$_m14_e24_n : dernier passage du service réussi" "$_m14_e24_n" '^Result=success$' \
    'systemctl show -p Result etcd-instantane.service'
  _m14_e24_age="$(_m14p_age_succes "$_m14_e24_n" || true)"
  check_output "$_m14_e24_n : dernier instantané envoyé il y a moins de 2 h" '^ok$' \
    bash -c '[[ "$1" =~ ^[0-9]+$ ]] && (( $1 < 7200 )) && echo ok' _ "$_m14_e24_age"
  check_ssh_output "$_m14_e24_n : secrets S3 en root:root 600" "$_m14_e24_n" '^root:root 600$' \
    'sudo -n stat -c "%U:%G %a" /etc/etcd-instantane/s3.env'
  if [[ -n "$_m14_e24_version" ]]; then
    check_ssh_output "$_m14_e24_n : etcdctl et etcdutl en $_m14_e24_version (version de l'etcd du cluster)" "$_m14_e24_n" \
      "^ok$" "/usr/local/bin/etcdctl version | grep -qx 'etcdctl version: $_m14_e24_version' \
        && /usr/local/bin/etcdutl version | grep -qx 'etcdutl version: $_m14_e24_version' && echo ok"
  else
    check_cmd "$_m14_e24_n : outils etcd à la version du cluster (version du cluster illisible)" false
  fi
done

title "Stockage objet (s3-01, compartiment $_M14P_COMPARTIMENT)"
check_cmd "identité etcd-k8s présente sur adm01 ($_M14P_S3_ENV, mode 600)" \
  bash -c '[[ -r "$1" && "$(stat -c %a "$1")" == 600 ]]' _ "$_M14P_S3_ENV"
check_output "le compartiment est versionné" '"Status": *"Enabled"' \
  _m14p_s3 s3api get-bucket-versioning --bucket "$_M14P_COMPARTIMENT"
_m14_e24_tmp="$(mktemp -d)"
for _m14_e24_n in "${_M14P_CP[@]}"; do
  _m14_e24_liste="$(_m14p_s3 s3api list-objects-v2 --bucket "$_M14P_COMPARTIMENT" --prefix "horaire/$_m14_e24_n/" 2>/dev/null || echo null)"
  _m14_e24_cle="$(jq -r '[.Contents[]?] | sort_by(.LastModified) | last | .Key // empty' <<<"$_m14_e24_liste" 2>/dev/null || true)"
  _m14_e24_date="$(jq -r '[.Contents[]?] | sort_by(.LastModified) | last | .LastModified // empty' <<<"$_m14_e24_liste" 2>/dev/null || true)"
  check_output "$_m14_e24_n : objet horaire/ de moins de 2 h, nommé *.db.age" '^ok$' \
    bash -c '[[ "$1" == *.db.age && -n "$2" ]] && (( $(date +%s) - $(date -d "$2" +%s) < 7200 )) && echo ok' _ \
    "$_m14_e24_cle" "$_m14_e24_date"
  if [[ -n "$_m14_e24_cle" ]]; then
    _m14p_s3 s3api get-object --bucket "$_M14P_COMPARTIMENT" --key "$_m14_e24_cle" --range bytes=0-20 \
      "$_m14_e24_tmp/entete" >/dev/null 2>&1 || true
    check_output "$_m14_e24_n : l'objet est chiffré par age (en-tête age-encryption.org/v1)" '^age-encryption\.org/v1' \
      head -c 21 "$_m14_e24_tmp/entete"
    rm -f "$_m14_e24_tmp/entete"
  else
    check_cmd "$_m14_e24_n : l'objet est chiffré par age (aucun objet trouvé)" false
  fi
done
rm -rf "$_m14_e24_tmp"
# La suppression refusée ne se teste pas ici (un check ne modifie rien) : on lit la politique en
# vigueur si l'identité y a accès, et celle du dépôt dans tous les cas.
_m14_e24_pol="$(_m14p_s3 s3api get-bucket-policy --bucket "$_M14P_COMPARTIMENT" 2>/dev/null | jq -r '.Policy // empty' || true)"
if [[ -n "$_m14_e24_pol" ]]; then
  check_cmd "politique en vigueur : DeleteObject refusé à etcd-k8s" bash -c \
    'jq -e "any(.Statement[]; .Effect == \"Deny\" and (.Action | tostring | test(\"DeleteObject\")) and (.Principal | tostring | test(\"etcd-k8s\")))" >/dev/null <<<"$1"' \
    _ "$_m14_e24_pol"
else
  skip "politique en vigueur" "illisible avec l'identité etcd-k8s ; seule celle du dépôt est contrôlée"
fi
check_cmd "plateforme/infra : politique du compartiment sur main (DeleteObject refusé à etcd-k8s)" \
  _m14p_fichier_contient plateforme/infra outils/s3/politique-etcd-k8s-par1.json 'DeleteObject' 'etcd-k8s'

title "Restauration réelle"
_m14_e24_statut="$(_m14p_etcd_json "${_M14P_CP[0]}" 'endpoint status' || echo null)"
check_cmd "révision etcd supérieure au saut de révision (restauration avec --bump-revision faite)" \
  _m14p_jq "$_m14_e24_statut" '(.[0].Status.header.revision // 0) > 1000000000'
check_cmd "l'espace wb-essais existe" kube get namespace wb-essais
check_output "wb-essais/temoin-restauration vaut avant-instantane" '^avant-instantane$' \
  kube -n wb-essais get configmap temoin-restauration -o 'jsonpath={.data.etat}'

title "Code et documentation"
check_cmd "plateforme/k8s : outils/etcd-instantane.sh sur main" \
  _m14p_fichier_contient plateforme/k8s outils/etcd-instantane.sh 'etcd-instantane'
check_cmd "plateforme/ansible : rôle etcd_instantane sur main" \
  _m14p_fichier_contient plateforme/ansible roles/etcd_instantane/tasks/main.yml 'etcd'
check_cmd "RB-141 sur main (saut de révision, révisions compactées, retour arrière)" \
  _m14p_doc_prefixe docs/kubernetes/runbooks RB-141 'bump-revision' 'mark-compacted' 'retour arri'
check_cmd "compte rendu de restauration sur main (RPO et RTO)" \
  _m14p_fichier_contient plateforme/medisphere docs/kubernetes/tests/restauration-etcd.md 'RPO' 'RTO'

title "Sauvegardes PBS des VMs (par1/k8s)"
for _m14_e24_id in 2141 2142 2143 2144 2145 2146; do
  check_cmd "VM $_m14_e24_id : sauvegarde de moins de 48 h dans par1/k8s" _m14p_pbs_vm_recente "$_m14_e24_id" 48
done
