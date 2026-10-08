# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant ou par bash -c
#
# check-E25.sh — M10-E25 « Sauvegarder et restaurer OpenStack »
# Lecture seule. Les secrets PBS de osctl01 sont lus SUR osctl01 par lui-même (sudo -n), jamais
# rapatriés. Noms imposés par l'énoncé : wb-openstack-mariabackup.* (adm01), wb-backup-socle.*
# et /etc/wb-backup/pbs-osctl01.{env,key} (osctl01), espace de noms par1/openstack.

# shellcheck source=_m10-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m10-production.sh"

title "M10-E25 — Sauvegarder et restaurer OpenStack"
require_cmd openstack jq ssh

title "Mariabackup (Kolla)"
check_cmd "plateforme/openstack (clone ~/src/openstack) : enable_mariabackup dans etc/kolla/globals.d/" \
  bash -c 'grep -rqsE "^enable_mariabackup:[[:space:]]*\"?(yes|true)\"?" "$1"/etc/kolla/globals.d/' _ "$_M10P_SRC/openstack"
_m10_derniere='r=$(sudo -n docker volume inspect -f "{{.Mountpoint}}" mariadb_backup) || exit 1
  f=$(sudo -n cat "$r/last_full_file") || exit 1; f="$r/${f#/backup/}"'
check_ssh "osctl01 : sauvegarde complète de moins de 26 h dans le volume mariadb_backup" osctl01 \
  "$_m10_derniere"'
  sudo -n test -s "$f" && [ $(( $(date +%s) - $(sudo -n stat -c %Y "$f") )) -le 93600 ]'
check_ssh "osctl01 : aucune sauvegarde locale de plus de 8 jours (purge)" osctl01 \
  'r=$(sudo -n docker volume inspect -f "{{.Mountpoint}}" mariadb_backup) || exit 1
   ! sudo -n find "$r" -mindepth 1 -maxdepth 1 -type d \( -name "full-*" -o -name "incr-*" \) -mtime +8 | grep -q .'

title "Planification sur adm01"
check_cmd "wb-openstack-mariabackup : timer actif, dernier passage réussi" _m10p_unite_ok local wb-openstack-mariabackup
check_output "le service déclenche ms-alerte@… en cas d'échec" '^OnFailure=.*ms-alerte@' \
  systemctl show -p OnFailure wb-openstack-mariabackup.service
check_cmd "aucun secret dans l'unité (mot de passe, secret)" bash -c \
  '! systemctl cat wb-openstack-mariabackup.service 2>/dev/null | grep -Eiq "(password|secret|passphrase)[[:space:]]*=" \
   && systemctl cat wb-openstack-mariabackup.service >/dev/null 2>&1'

title "Envoi vers PBS (osctl01)"
check_cmd "osctl01 : wb-backup-socle (timer actif, dernier passage réussi)" _m10p_unite_ok osctl01 wb-backup-socle
check_ssh "osctl01 : secrets PBS et clé de chiffrement en root:root 600" osctl01 \
  'for f in /etc/wb-backup/pbs-osctl01.env /etc/wb-backup/pbs-osctl01.key; do [ "$(sudo -n stat -c %U:%G:%a $f 2>/dev/null)" = root:root:600 ] || exit 1; done'
check_ssh "osctl01 : instantané host/osctl01 de moins de 48 h dans par1/openstack, chiffré" osctl01 \
  'sudo -n bash -c "set -a; . /etc/wb-backup/pbs-osctl01.env; set +a; proxmox-backup-client snapshot list host/osctl01 --ns par1/openstack --output-format json" | python3 -c '"'"'
import json, sys, time
s = sorted(json.load(sys.stdin), key=lambda x: x["backup-time"], reverse=True)
if not s or s[0]["backup-time"] < time.time() - 172800: sys.exit(1)
f = [x for x in s[0]["files"] if x["filename"].endswith(".pxar.didx")]
sys.exit(0 if f and all(x.get("crypt-mode") == "encrypt" for x in f) else 2)'"'"
check_ssh "pbs01 : jeton wb-backup@pbs!osctl01 limité à par1/openstack" "$WB_PBS_HOST" \
  "proxmox-backup-manager acl list --output-format json | python3 -c '
import json, sys
a = [x for x in json.load(sys.stdin) if x.get(\"ugid\") == \"wb-backup@pbs!osctl01\"]
sys.exit(0 if a and all(x[\"path\"].startswith(\"/datastore/ds-lab/par1/openstack\") for x in a) else 1)'"
check_cmd "osctl01 joint pbs01 sur 8007" _m10p_port_ouvert osctl01 10.20.10.10 8007

title "Restauration réalisée"
check_cmd "le projet essai-restauration n'existe pas (domaine medisphere)" _m10p_projet_absent essai-restauration medisphere
_m10_orphelins() {
  local cinder rbd
  cinder="$(_m10p_os volume list --all-projects)" || return 1
  rbd="$(remote ceph01 'sudo -n cephadm shell -- rbd ls volumes' 2>/dev/null)" || return 1
  # Images RBD « volume-<id> » sans volume Cinder (les autres noms ne sont pas des volumes Cinder).
  ! comm -13 <(jq -r '.[].ID' <<<"$cinder" | sed 's/^/volume-/' | sort) \
             <(grep -E '^volume-[0-9a-f-]{36}$' <<<"$rbd" | sort) | grep -q .
}
check_cmd "pool volumes : aucune image RBD de volume sans volume Cinder (orphelin)" _m10_orphelins

title "Documentation"
check_cmd "plateforme/medisphere : docs/cloud/sauvegarde-restauration.md (Mariabackup, orphelins)" \
  _m10p_fichier_contient plateforme/medisphere docs/cloud/sauvegarde-restauration.md 'mariabackup' 'orphelin'
check_cmd "plateforme/medisphere : docs/cloud/tests/restauration.md (RTO et RPO)" \
  _m10p_fichier_contient plateforme/medisphere docs/cloud/tests/restauration.md 'RTO' 'RPO'
check_cmd "plateforme/medisphere : matrice des flux à jour (osctl01 → PBS 8007)" \
  _m10p_fichier_contient plateforme/medisphere docs/socle/matrice-flux.md '(osctl01|10\.10\.50\.51).*8007|8007.*(osctl01|10\.10\.50\.51)'
