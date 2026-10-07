# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E03.sh — M06-E03 : Faire confiance à la nouvelle PKI
# À lancer depuis adm01. Lecture seule : magasins de certificats des hôtes du socle (SSH),
# certificats présentés par git01 et s3-01, fichiers des clones de travail.

# shellcheck source=_m06-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m06-decouverte.sh"

title "M06-E03 — Faire confiance à la nouvelle PKI"
require_cmd openssl curl sha256sum

_m06d_e03_racine="$(_m06d_racine)"
_m06d_e03_somme="$(sha256sum "$_m06d_e03_racine" 2>/dev/null | cut -d' ' -f1)" || true

# --- 1. Magasins de confiance : la racine partout, la CA provisoire nulle part -----------------
# adm01 (local) + les hôtes du socle joints en SSH ; nbx01 n'existe qu'après M06-E04.
for _m06d_e03_h in adm01 gw01 dns01 ca01 git01 s3-01 runner01; do
  check_ssh "$_m06d_e03_h : racine MédiSphère installée (identique à celle du dépôt)" "$_m06d_e03_h" \
    "[ \"\$(sha256sum /usr/local/share/ca-certificates/medisphere-root-ca.crt 2>/dev/null | cut -d' ' -f1)\" = '$_m06d_e03_somme' ] && test -e /etc/ssl/certs/medisphere-root-ca.pem"
  check_ssh "$_m06d_e03_h : la CA provisoire n'est plus de confiance" "$_m06d_e03_h" \
    '! test -e /usr/local/share/ca-certificates/medisphere-provisoire.crt && ! test -e /etc/ssl/certs/medisphere-provisoire.pem'
done

# --- 2. Les services présentent un certificat de la nouvelle PKI -----------------------------------
for _m06d_e03_s in "git01.par1.medisphere.internal:443" "s3-01.par1.medisphere.internal:8333"; do
  _m06d_e03_hote="${_m06d_e03_s%%:*}"
  _m06d_e03_port="${_m06d_e03_s##*:}"
  _m06d_e03_cert="$(_m06d_cert "$_m06d_e03_hote" "$_m06d_e03_port")"
  check_output "$_m06d_e03_hote:$_m06d_e03_port : certificat émis par « MédiSphère Intermediate CA »" \
    '^issuer=.*CN ?= ?MédiSphère Intermediate CA' printf '%s\n' "$_m06d_e03_cert"
  check_cmd "$_m06d_e03_hote:$_m06d_e03_port : chaîne complète, vérifiée par la seule racine, nom valide" \
    _m06d_chaine_ok "$_m06d_e03_hote" "$_m06d_e03_port"
  check_cmd "$_m06d_e03_hote:$_m06d_e03_port : encore valable au moins 7 jours" \
    test "$(_m06d_jours_restants "$_m06d_e03_cert")" -ge 7
done

# --- 3. Les clients qui ont leur propre magasin -------------------------------------------------------
check_ssh "git01 : la racine est dans le magasin propre de GitLab (/etc/gitlab/trusted-certs)" git01 \
  "for f in /etc/gitlab/trusted-certs/*; do [ \"\$(sudo -n sha256sum \"\$f\" | cut -d' ' -f1)\" = '$_m06d_e03_somme' ] && exit 0; done; exit 1"
check_ssh "runner01 : HTTPS vers git01 vérifié par le magasin système" runner01 \
  'curl -sf -o /dev/null --max-time 5 https://git01.par1.medisphere.internal/users/sign_in'
check_ssh "runner01 : HTTPS vers s3-01 vérifié par le magasin système" runner01 \
  'curl -s -o /dev/null --max-time 5 https://s3-01.par1.medisphere.internal:8333/'
check_cmd "adm01 : HTTPS vers s3-01 (état OpenTofu) vérifié par le magasin système" \
  curl -s -o /dev/null --max-time "$WB_TIMEOUT" https://s3-01.par1.medisphere.internal:8333/

# --- 4. Le code et les images ------------------------------------------------------------------------
_m06d_e03_coll="$_M06D_ANSIBLE/collections/ansible_collections/medisphere/socle"
check_cmd "Collection medisphere.socle en version 1.1.x ou plus" \
  grep -Eq '^version: (1\.([1-9]|[1-9][0-9])\.[0-9]+|[2-9]\.[0-9]+\.[0-9]+)$' "$_m06d_e03_coll/galaxy.yml"
check_cmd "Rôle ca_lab : sait retirer une autorité (ca_lab_retirer)" \
  grep -q 'ca_lab_retirer' "$_m06d_e03_coll/roles/ca_lab/tasks/main.yml"
check_cmd "Images : la racine MédiSphère remplace la CA provisoire dans plateforme/images" \
  bash -c 'd="$1/images/fichiers/ca"; [[ "$(sha256sum "$d/medisphere-root-ca.crt" 2>/dev/null | cut -d" " -f1)" == "$2" ]] && [[ ! -e "$d/medisphere-provisoire.crt" ]]' \
  _ "${WB_SRC:-$HOME/src}" "$_m06d_e03_somme"

# --- 5. La CA provisoire est mise hors service --------------------------------------------------------
check_cmd "adm01 : plus de clé privée de CA provisoire en clair dans pki-provisoire" \
  bash -c '! compgen -G "$1/*.key" >/dev/null' _ "$HOME/pki-provisoire"
