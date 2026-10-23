#!/usr/bin/env bash
# shellcheck disable=SC2016  # commandes passées à « bash -c » entre apostrophes (développées par ce bash)
# outils/par2/go-no-go-hp01.sh — contrôles AVANT l'installation de Proxmox VE sur hp01 (F5-S03,
# CHG-3503, RB-353 §1). Projet plateforme/infra. À lancer EN ROOT SUR hp01 ; ne modifie RIEN :
# lectures, et une simulation APT (apt-get -s) qui n'installe rien.
#
# Sortie : une ligne OK/KO par critère, puis « GO » (code 0) ou « NO-GO » (code 1). Un seul KO = NO-GO.
#
# Variables : MEMOIRE_LIBRE_MIN_GO (défaut 12), ESPACE_LIBRE_MIN_GO (défaut 150, sur le système de
# fichiers de ds-lab), PVE_SOURCES (défaut /etc/apt/sources.list.d/pve-install-repo.sources : le dépôt
# pve-no-subscription doit être déclaré AVANT ce contrôle, sans « apt-get update » de paquets PVE
# installés : seule la liste des paquets est rafraîchie).
set -uo pipefail

MEMOIRE_LIBRE_MIN_GO="${MEMOIRE_LIBRE_MIN_GO:-12}"
ESPACE_LIBRE_MIN_GO="${ESPACE_LIBRE_MIN_GO:-150}"
PVE_SOURCES="${PVE_SOURCES:-/etc/apt/sources.list.d/pve-install-repo.sources}"
nogo=0

critere() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    printf 'OK  %s\n' "$desc"
  else
    printf 'KO  %s\n' "$desc"
    nogo=1
  fi
}

[[ $EUID -eq 0 ]] || { echo "à lancer en root sur hp01" >&2; exit 2; }
command -v proxmox-backup-manager >/dev/null || { echo "proxmox-backup-manager absent : ce n'est pas hp01 ?" >&2; exit 2; }

ds_path="$(proxmox-backup-manager datastore show ds-lab --output-format json 2>/dev/null | jq -r '.path // empty')"

# 1. PBS en bon état.
critere "PBS : proxmox-backup-proxy et proxmox-backup actifs" systemctl is-active --quiet proxmox-backup-proxy proxmox-backup
critere "PBS : datastore ds-lab présent ($ds_path)" test -n "$ds_path" -a -d "$ds_path"
critere "PBS : aucune tâche en cours (sauvegarde, vérification, élagage, GC)" \
  bash -c '[ "$(proxmox-backup-manager task list --output-format json 2>/dev/null | jq "[.[] | select(.endtime == null)] | length")" = 0 ]'
critere "PBS : aucune tâche en échec depuis 24 h" \
  bash -c 'depuis=$(( $(date +%s) - 86400 )); proxmox-backup-manager task list --all --output-format json 2>/dev/null \
    | jq -e --argjson d "$depuis" "[.[] | select(.starttime >= \$d and (.status // \"OK\") != \"OK\")] | length == 0" >/dev/null'

# 2. Ressources.
critere "mémoire disponible ≥ ${MEMOIRE_LIBRE_MIN_GO} Gio" \
  bash -c "[ \$(awk '/MemAvailable/ { print int(\$2 / 1048576) }' /proc/meminfo) -ge $MEMOIRE_LIBRE_MIN_GO ]"
critere "espace libre ≥ ${ESPACE_LIBRE_MIN_GO} Gio sur le système de fichiers de ds-lab" \
  bash -c "[ \$(df -BG --output=avail '$ds_path' | tail -n 1 | tr -dc 0-9) -ge $ESPACE_LIBRE_MIN_GO ]"

# 3. Base logicielle commune.
critere "Debian 13 (trixie)" grep -q 'VERSION_CODENAME=trixie' /etc/os-release
critere "noyau Proxmox en service (proxmox-kernel)" bash -c 'uname -r | grep -q -- "-pve$"'
critere "nom d'hôte pbs01 résolu vers 10.20.10.10 (/etc/hosts)" \
  bash -c 'getent ahostsv4 "$(hostname)" | awk "{print \$1}" | grep -qx 10.20.10.10'
critere "port 8006 libre (aucun service ne l'occupe encore)" bash -c '! ss -Htln "sport = :8006" | grep -q .'
critere "sauvegarde de la configuration de PBS du jour présente (/root/f5/pbs-config-$(date +%Y%m%d).tar.gz)" \
  test -s "/root/f5/pbs-config-$(date +%Y%m%d).tar.gz"

# 4. Simulation : rien de PBS ne doit être retiré ni rétrogradé.
if [[ -r "$PVE_SOURCES" ]]; then
  sim="$(apt-get -s -o Debug::NoLocking=1 install proxmox-ve postfix open-iscsi chrony 2>&1)"
  printf '%s\n' "$sim" >/root/f5/simulation-apt-"$(date +%Y%m%d-%H%M)".txt
  critere "simulation APT : aucun paquet retiré" bash -c '! grep -q "^Remv " <<<"$1"' _ "$sim"
  critere "simulation APT : aucun paquet proxmox-backup* touché" bash -c '! grep -Eq "^(Inst|Remv|Conf) proxmox-backup" <<<"$1"' _ "$sim"
  critere "simulation APT : le noyau en service n'est pas remplacé par un noyau Debian" \
    bash -c '! grep -Eq "^Inst linux-image-[0-9]" <<<"$1"' _ "$sim"
else
  printf 'KO  dépôt Proxmox VE non déclaré (%s) : simulation impossible\n' "$PVE_SOURCES"
  nogo=1
fi

echo
if ((nogo)); then echo "NO-GO"; exit 1; fi
echo "GO (décision à reporter dans CHG-3503 avec cette sortie)"
