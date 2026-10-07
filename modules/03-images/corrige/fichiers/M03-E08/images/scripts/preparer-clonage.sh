#!/usr/bin/env bash
# preparer-clonage.sh — prépare une VM pour devenir un template clonable (M03-E07).
# DERNIER provisioner de chaque build (base et doré, Debian et Rocky), lancé en root.
#
# Retire tout ce qui est propre à CETTE VM ou au build, pour que chaque clone naisse
# avec sa propre identité :
#   - compte de construction et ses droits sudo, configuration réseau du build ;
#   - identité machine (machine-id), clés d'hôte SSH, graine aléatoire, baux DHCP ;
#   - état de cloud-init (le clone repartira comme une première instance) ;
#   - journaux, historiques, caches de paquets, fichiers temporaires, traces d'installeur
#     (dont les fichiers kickstart qui contiennent le mot de passe de build).
# Puis vérifie le résultat : le build échoue (code 1) si quelque chose est resté.
#
# Variable : COMPTE_BUILD (défaut : packer).
set -euo pipefail

compte="${COMPTE_BUILD:-packer}"
log() { printf '[preparer-clonage] %s\n' "$*"; }

[[ $EUID -eq 0 ]] || { log "à lancer en root (execute_command avec sudo)"; exit 1; }
# shellcheck source=/dev/null
. /etc/os-release
case " ${ID:-} ${ID_LIKE:-} " in
  *" debian "*) famille=debian ;;
  *" rhel "* | *" fedora "*) famille=rhel ;;
  *) log "distribution non prise en charge : ${ID:-inconnue}"; exit 1 ;;
esac
log "famille $famille ($PRETTY_NAME)"

# --- 1. Paquets : caches (des centaines de Mo, et des métadonnées vite périmées) -------
if [[ $famille == debian ]]; then
  apt-get -y autoremove --purge
  apt-get clean
  rm -rf /var/lib/apt/lists/*
else
  dnf -y autoremove
  dnf clean all
  rm -rf /var/cache/dnf/*
fi

# --- 2. Compte de construction et droits du build -------------------------------------
rm -f /etc/sudoers.d/90-build-packer
# Créé par cloud-init lors des builds par clonage (ciuser du build) :
rm -f /etc/sudoers.d/90-cloud-init-users
if id "$compte" >/dev/null 2>&1; then
  # --force : la session SSH de Packer appartient encore à ce compte.
  userdel --force --remove "$compte" 2>/dev/null || userdel --force "$compte"
  log "compte $compte supprimé"
fi

# --- 3. Réseau propre au build ---------------------------------------------------------
rm -f /etc/netplan/90-build.yaml # Debian (late-command.sh, M03-E05)
# Profils NetworkManager écrits par l'installeur (Rocky) ou par cloud-init lors du build
rm -f /etc/NetworkManager/system-connections/*.nmconnection
rm -f /var/lib/NetworkManager/*.lease /var/lib/dhcp/*.leases

# --- 4. cloud-init : état, graines, journaux, configurations générées -----------------
# --seed : données NoCloud mises en cache ; --configs all : réseau et sshd générés pour
# CETTE instance ; --machine-id : /etc/machine-id remis à « uninitialized » (systemd en
# génère un nouveau au premier démarrage du clone).
cloud-init clean --logs --seed --machine-id --configs all

# --- 5. Identité de la machine -------------------------------------------------------
# /var/lib/dbus/machine-id : lien vers /etc/machine-id en général ; s'il s'agit d'une copie,
# elle conserverait l'ancien identifiant.
if [[ -f /var/lib/dbus/machine-id && ! -L /var/lib/dbus/machine-id ]]; then
  rm -f /var/lib/dbus/machine-id
fi
# Clés d'hôte SSH : régénérées au premier démarrage du clone (module « ssh » de cloud-init).
rm -f /etc/ssh/ssh_host_*
rm -f /var/lib/systemd/random-seed
rm -f /var/lib/systemd/credential.secret

# --- 6. Traces : journaux, historiques, installeur, temporaires ------------------------
journalctl --rotate >/dev/null 2>&1 || true
journalctl --vacuum-time=1s >/dev/null 2>&1 || true
find /var/log -type f \( -name '*.gz' -o -name '*.[0-9]' -o -name '*.old' \) -delete
find /var/log -type f -exec truncate -s 0 {} +
rm -rf /var/log/installer /var/log/anaconda
rm -f /root/anaconda-ks.cfg /root/original-ks.cfg /root/ks-post.log
rm -f /root/.bash_history /home/*/.bash_history /root/.lesshst /root/.viminfo
rm -rf /root/.ssh /root/.cache
rm -rf /var/tmp/*
# /tmp : tout sauf ce script (Packer l'exécute depuis /tmp).
find /tmp -mindepth 1 -maxdepth 1 ! -path "$(readlink -f "$0")" -exec rm -rf {} +

# --- 7. Vérifications : on préfère un build en échec à un template « presque propre » -
erreurs=0
verifier() { if ! "$@"; then log "ÉCHEC : $*"; erreurs=$((erreurs + 1)); fi; }
verifier grep -qx 'uninitialized' /etc/machine-id
verifier bash -c '! compgen -G "/etc/ssh/ssh_host_*" >/dev/null'
verifier bash -c "! id '$compte' >/dev/null 2>&1"
verifier test ! -e /etc/sudoers.d/90-build-packer
verifier test ! -e /var/lib/cloud/instance
verifier test ! -e /root/original-ks.cfg
verifier test ! -e /etc/netplan/90-build.yaml
if ((erreurs > 0)); then
  log "$erreurs contrôle(s) en échec : template refusé"
  exit 1
fi

# --- 8. Rendre les blocs libérés au stockage (disque en discard=on sur LVM-thin) --------
fstrim -av || true
sync
log "VM prête à être convertie en template"
