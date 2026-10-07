# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant
#
# check-E28.sh — M06-E28 « Sauvegarder et restaurer les services socle »
# Lancé depuis adm01. Lecture seule. Les secrets PBS de chaque hôte sont lus SUR l'hôte par
# l'hôte lui-même (sudo -n), jamais rapatriés. Noms imposés par l'énoncé (contraintes) : script
# wb-backup-socle.sh, unités wb-backup-socle.*, /etc/wb-backup/pbs-<hôte>.env et .key.

# shellcheck source=_m06-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m06-production.sh"

title "M06-E28 — Sauvegarder et restaurer les services socle"
require_cmd ssh jq curl
_m06p_charger

# Instantané le plus récent de host/<hôte> dans par1/<hôte> : moins de 48 h et chiffré.
_m06_snap='h=$(hostname -s); sudo -n bash -c "set -a; . /etc/wb-backup/pbs-$h.env; set +a; proxmox-backup-client snapshot list host/$h --ns par1/$h --output-format json" | python3 -c '"'"'
import json, sys, time
s = sorted(json.load(sys.stdin), key=lambda x: x["backup-time"], reverse=True)
if not s or s[0]["backup-time"] < time.time() - 172800: sys.exit(1)
f = [x for x in s[0]["files"] if x["filename"].endswith(".pxar.didx")]
sys.exit(0 if f and all(x.get("crypt-mode") == "encrypt" for x in f) else 2)'"'"

for _m06_h in dns01 ca01 nbx01; do
  title "$_m06_h"
  check_ssh "$_m06_h : script de sauvegarde exécutable" "$_m06_h" 'sudo -n test -x /usr/local/sbin/wb-backup-socle.sh'
  check_ssh "$_m06_h : secrets PBS et clé de chiffrement en root:root 600" "$_m06_h" \
    'h=$(hostname -s); for f in /etc/wb-backup/pbs-$h.env /etc/wb-backup/pbs-$h.key; do [ "$(sudo -n stat -c %U:%G:%a $f 2>/dev/null)" = root:root:600 ] || exit 1; done'
  check_ssh "$_m06_h : minuterie wb-backup-socle.timer activée et active" "$_m06_h" \
    'systemctl is-enabled --quiet wb-backup-socle.timer && systemctl is-active --quiet wb-backup-socle.timer'
  check_ssh "$_m06_h : le service a déjà tourné" "$_m06_h" \
    'systemctl show -p ExecMainExitTimestampMonotonic wb-backup-socle.service | grep -qv "=0$"'
  check_ssh_output "$_m06_h : dernier passage réussi" "$_m06_h" '^Result=success$' \
    'systemctl show -p Result wb-backup-socle.service'
  check_ssh "$_m06_h : instantané de moins de 48 h dans par1/$_m06_h, chiffré côté client" "$_m06_h" "$_m06_snap"
done

title "ca01 : pas de clé racine dans la sauvegarde"
check_ssh "ca01 : le catalogue du dernier instantané ne contient aucune clé racine (et contient la configuration)" ca01 \
  'sudo -n bash -c '"'"'set -a; . /etc/wb-backup/pbs-ca01.env; set +a
s=$(proxmox-backup-client snapshot list host/ca01 --ns par1/ca01 --output-format json | python3 -c "import json,sys,time; s=sorted(json.load(sys.stdin), key=lambda x: x[\"backup-time\"]); print(time.strftime(\"host/ca01/%Y-%m-%dT%H:%M:%SZ\", time.gmtime(s[-1][\"backup-time\"]))) if s else sys.exit(1)") || exit 1
c=$(proxmox-backup-client catalog dump "$s" --ns par1/ca01 --keyfile /etc/wb-backup/pbs-ca01.key 2>/dev/null) || exit 1
grep -q "ca.json" <<<"$c" && ! grep -Eiq "root[^/]*key" <<<"$c"'"'"

title "PBS (pbs01)"
for _m06_h in dns01 ca01 nbx01; do
  check_ssh "pbs01 : jeton wb-backup@pbs!$_m06_h limité à par1/$_m06_h" "$WB_PBS_HOST" \
    "proxmox-backup-manager acl list --output-format json | python3 -c '
import json, sys
a = [x for x in json.load(sys.stdin) if x.get(\"ugid\") == \"wb-backup@pbs!$_m06_h\"]
sys.exit(0 if a and all(x[\"path\"].startswith(\"/datastore/ds-lab/par1/$_m06_h\") for x in a) else 1)'"
done
check_ssh "pbs01 : aucune clé de chiffrement des hôtes socle sur PAR2" "$WB_PBS_HOST" \
  '! find /etc /root /mnt -xdev \( -name "pbs-dns01.key" -o -name "pbs-ca01.key" -o -name "pbs-nbx01.key" \) 2>/dev/null | grep -q .'

title "Flux"
for _m06_h in dns01 ca01 nbx01; do
  check_cmd "$_m06_h joint pbs01 sur 8007" _m06p_port_ouvert "$_m06_h" 10.20.10.10 8007
done
check_cmd "runner01 ne joint PAS pbs01 sur 8007" _m06p_port_ferme runner01 10.20.10.10 8007

title "Test de restauration et documentation"
check_cmd "pve01 : une VM 2068 a servi au test de restauration" _m06p_vm_a_existe 2068
check_cmd "pve01 : la VM 2068 n'existe plus" _m06p_vm_absente 2068
check_cmd "plateforme/medisphere : RB-061 dans docs/socle/runbooks/" _m06p_runbook RB-061
check_output "plateforme/medisphere : test de restauration consigné (NetBox, PowerDNS, step-ca)" \
  '[Nn]et[Bb]ox' _m06p_fichier_main plateforme/medisphere docs/socle/tests/restauration.md
check_output "plateforme/medisphere : matrice des flux à jour (sauvegardes du module 06)" \
  '(nbx01|ca01|dns01).*8007|8007.*(nbx01|ca01|dns01)' _m06p_fichier_main plateforme/medisphere docs/socle/matrice-flux.md
