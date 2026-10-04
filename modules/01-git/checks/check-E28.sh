# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E28.sh — M01-E28 « Sauvegarder et restaurer GitLab »
# Lancé depuis adm01. Lecture seule (git01, runner01, pbs01, pve01 en SSH, API GitLab).
# Les secrets PBS sont lus sur git01 par git01 lui-même, jamais rapatriés.

title "M01-E28 — Sauvegarder et restaurer GitLab"
require_cmd ssh jq curl

_m01_get() { gitlab_api "$1" 2>/dev/null || true; }
_m01_SCRIPT=/usr/local/sbin/wb-backup-gitlab.sh
_m01_ENV=/etc/wb-backup/pbs-git01.env
_m01_CLE=/etc/wb-backup/pbs-git01.key

# --- 1. git01 : script, secrets, minuterie -------------------------------------------------
check_ssh "git01 : $_m01_SCRIPT présent et exécutable" git01 "sudo -n test -x $_m01_SCRIPT"
check_ssh "git01 : $_m01_ENV et $_m01_CLE en root:root 600" git01 \
  "for f in $_m01_ENV $_m01_CLE; do [ \"\$(sudo -n stat -c %U:%G:%a \$f 2>/dev/null)\" = root:root:600 ] || exit 1; done"
check_ssh "git01 : le script ne contient pas le secret du jeton PBS" git01 \
  "s=\$(sudo -n sed -nE 's/^PBS_PASSWORD=[\"'\"'\"']?([^\"'\"'\"']+).*/\\1/p' $_m01_ENV); [ -n \"\$s\" ] && ! sudo -n grep -qF -- \"\$s\" $_m01_SCRIPT"
check_ssh "git01 : le script sauvegarde aussi la configuration (gitlab-ctl backup-etc)" git01 \
  "sudo -n grep -q 'backup-etc' $_m01_SCRIPT"
check_ssh "git01 : rétention locale des sauvegardes réglée (backup_keep_time)" git01 \
  'sudo -n grep -Eq "^[[:space:]]*gitlab_rails\[.backup_keep_time.\][[:space:]]*=[[:space:]]*[1-9]" /etc/gitlab/gitlab.rb'
check_ssh "git01 : minuterie wb-backup-gitlab.timer activée et active" git01 \
  'systemctl is-enabled --quiet wb-backup-gitlab.timer && systemctl is-active --quiet wb-backup-gitlab.timer'
check_ssh_output "git01 : dernier passage de wb-backup-gitlab.service réussi" git01 '^Result=success$' \
  'systemctl show -p Result wb-backup-gitlab.service'
check_ssh "git01 : le service a déjà tourné" git01 \
  'systemctl show -p ExecMainExitTimestampMonotonic wb-backup-gitlab.service | grep -qv "=0$"'

# --- 2. PBS : instantané récent et chiffré, vu par git01 -------------------------------------
_m01_SNAP='sudo -n bash -c '"'"'set -a; . '"$_m01_ENV"'; set +a; proxmox-backup-client snapshot list host/git01 --ns par1/git01 --output-format json'"'"' | python3 -c '"'"'
import json, sys, time
s = sorted(json.load(sys.stdin), key=lambda x: x["backup-time"], reverse=True)
if not s or s[0]["backup-time"] < time.time() - 172800: sys.exit(1)
f = [x for x in s[0]["files"] if x["filename"].endswith(".pxar.didx")]
sys.exit(0 if f and all(x.get("crypt-mode") == "encrypt" for x in f) else 2)'"'"
check_ssh "PBS : instantané host/git01 de moins de 48 h dans par1/git01, chiffré côté client" git01 "$_m01_SNAP"
check_ssh "pbs01 : jeton wb-backup@pbs!git01 limité à /datastore/ds-lab/par1/git01 (DatastoreBackup)" "$WB_PBS_HOST" \
  'proxmox-backup-manager acl list --output-format json | python3 -c '"'"'
import json, sys
a = [x for x in json.load(sys.stdin) if x.get("ugid") == "wb-backup@pbs!git01"]
ok = a and all(x["path"].startswith("/datastore/ds-lab/par1/git01") for x in a) and any(x["roleid"] == "DatastoreBackup" for x in a)
sys.exit(0 if ok else 1)'"'"
check_ssh "pbs01 : la clé de chiffrement de git01 n'est pas sur PAR2" "$WB_PBS_HOST" \
  '! find /etc /root /mnt -xdev -name "pbs-git01.key" 2>/dev/null | grep -q .'

# --- 3. Flux réseau au plus juste ----------------------------------------------------------------
check_ssh "flux : git01 joint pbs01 sur 8007" git01 'timeout 5 bash -c "exec 3<>/dev/tcp/10.20.10.10/8007"'
check_ssh "flux : runner01 ne joint PAS pbs01 sur 8007 (règle limitée à git01)" runner01 \
  '! timeout 5 bash -c "exec 3<>/dev/tcp/10.20.10.10/8007" 2>/dev/null'

# --- 4. Test de restauration et documentation -----------------------------------------------------
check_ssh "pve01 : une VM 2010 a été créée pour le test de restauration" "$WB_PVE_HOST" \
  'pvesh get /nodes/$(hostname)/tasks --vmid 2010 --source all --limit 1000 --output-format json | grep -Eq "\"type\" *: *\"(qmclone|qmcreate|qmrestore)\""'
check_ssh "pve01 : la VM de test 2010 a été détruite" "$WB_PVE_HOST" '! qm status 2010 >/dev/null 2>&1'
check_cmd "plateforme/medisphere : runbook RB-010 dans docs/socle/runbooks/" \
  jq -e 'any(.[]?; .name | startswith("RB-010"))' \
  <<<"$(_m01_get "projects/plateforme%2Fmedisphere/repository/tree?ref=main&path=docs%2Fsocle%2Frunbooks&per_page=100")"
check_output "plateforme/medisphere : test de restauration de GitLab consigné (tests/restauration.md)" '[Gg]it[Ll]ab|git01' \
  gitlab_api "projects/plateforme%2Fmedisphere/repository/files/docs%2Fsocle%2Ftests%2Frestauration.md/raw?ref=main"
check_output "plateforme/medisphere : matrice des flux à jour (git01 vers pbs01, 8007)" 'git01.*8007|8007.*git01' \
  gitlab_api "projects/plateforme%2Fmedisphere/repository/files/docs%2Fsocle%2Fmatrice-flux.md/raw?ref=main"
