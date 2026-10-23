#!/usr/bin/env bash
# inspecter-export.sh — audit HORS LIGNE et EN LECTURE SEULE de l'export VMware d'InfoGér (F4-S09).
# Solution de référence. Root sur pve01 (libguestfs-tools installé pour la fabrication).
#
#   inspecter-export.sh [--stockage-export ID] [--sommes FICHIER] > ~/audit-infoger.txt
#
# Ne démarre aucune VM, n'écrit rien dans l'export : libguestfs ouvre chaque VMDK en lecture seule
# (--ro / -a … --format=vmdk). La sortie ne contient AUCUN secret : les fichiers qui en portent sont
# signalés (chemin, propriétaire, droits), jamais affichés. Les nombres de Legacy-RDV sont tirés du
# vidage nocturne d'InfoGér (lecture d'un flux gzip, aucune copie sur disque).
set -euo pipefail

stockage=hdd-bulk
sommes=""
while (($#)); do
  case "$1" in
    --stockage-export) stockage="${2:-}"; shift 2 ;;
    --sommes) sommes="${2:-}"; shift 2 ;;
    *) echo "usage : $0 [--stockage-export ID] [--sommes FICHIER]" >&2; exit 2 ;;
  esac
done
racine="$(pvesh get "/storage/$stockage" --output-format json | perl -MJSON::PP -0777 -ne 'print decode_json($_)->{path} // ""')"
EXPORT="$racine/import/infoger-export"
titre() { printf '\n==== %s ====\n' "$*"; }

for nom in legacy-rdv01 ftp-part01 stats01; do
  d="$EXPORT/$nom"
  v="$d/$nom-disk1.vmdk"
  titre "$nom : intégrité"
  (cd "$d" && sed -nE 's/^SHA256\(([^)]+)\)= ([0-9a-f]{64})$/\2  \1/p' "$nom.mf" | sha256sum -c -)
  if [[ -n "$sommes" ]]; then (cd "$EXPORT" && grep -E "  $nom/" "$sommes" | sha256sum -c -); fi
  qemu-img info "$v" | grep -E 'file format|virtual size|disk size|create type'

  titre "$nom : matériel déclaré (OVF)"
  perl -0777 -ne '
    my %t = (3 => "processeurs", 4 => "mémoire (Mo)", 6 => "contrôleur SCSI", 10 => "carte réseau", 17 => "disque");
    print "  matériel virtuel : $1\n" if /<vssd:VirtualSystemType>([^<]+)/;
    print "  système : $1\n" if /vmw:osType="([^"]+)"/;
    print "  micrologiciel : $1\n" if /vmw:key="firmware" vmw:value="([^"]+)"/;
    print "  Secure Boot : $1\n" if /efiSecureBootEnabled" vmw:value="([^"]+)"/;
    while (/<Item>(.*?)<\/Item>/sg) {
      my $i = $1; my ($rt) = $i =~ /<rasd:ResourceType>(\d+)/; next unless $t{$rt};
      my ($q) = $i =~ /<rasd:VirtualQuantity>([^<]+)/; my ($s) = $i =~ /<rasd:ResourceSubType>([^<]+)/;
      my ($a) = $i =~ /<rasd:Address>([^<]+)/; my ($c) = $i =~ /<rasd:Connection>([^<]+)/;
      printf "  %-16s %s\n", $t{$rt}, join(" ", grep { defined } $q, $s, ($rt == 10 ? ($a, "réseau $c") : ()));
    }' "$d/$nom.ovf"

  titre "$nom : système (virt-inspector)"
  virt-inspector --no-applications --format=vmdk -a "$v" 2>/dev/null \
    | grep -E '<(name|distro|major_version|minor_version|hostname|product_name|root)>' | sed 's/^ */  /'

  titre "$nom : fichiers de configuration significatifs"
  for f in /etc/network/interfaces /etc/resolv.conf /etc/hosts /etc/ssh/sshd_config.d/10-infoger.conf \
           /etc/initramfs-tools/conf.d/infoger.conf /etc/mysql/mariadb.conf.d/60-infoger.cnf /etc/vsftpd.conf; do
    if virt-cat --format=vmdk -a "$v" "$f" >/dev/null 2>&1; then
      echo "--- $f"
      virt-cat --format=vmdk -a "$v" "$f" | grep -vE '^\s*(#|$)' | grep -viE 'password|passwd|secret' | sed 's/^/  /'
    fi
  done

  titre "$nom : tâches planifiées, comptes, services, fichiers sensibles"
  guestfish --ro --format=vmdk -a "$v" -i <<'GF' 2>/dev/null | sed 's/^/  /'
echo "[cron.d]"
ls /etc/cron.d
echo "[comptes avec shell de connexion]"
-egrep ".*" /etc/passwd
echo "[sudoers.d]"
ls /etc/sudoers.d
echo "[unités activées (multi-user)]"
ls /etc/systemd/system/multi-user.target.wants
echo "[clés SSH autorisées]"
-glob ls /home/*/.ssh/authorized_keys
echo "[fichiers de secrets connus]"
-ls /etc/stats
-ls /var/backups/infoger
GF
done 2>&1 | sed -E 's#(/bin/(ba)?sh)$#\1  <- shell#'

titre "legacy-rdv01 : données (vidage nocturne d'InfoGér, lu en flux)"
v="$EXPORT/legacy-rdv01/legacy-rdv01-disk1.vmdk"
dernier="$(virt-ls --format=vmdk -a "$v" /var/backups/infoger | sort | tail -n 1)"
echo "  vidage le plus récent : /var/backups/infoger/$dernier"
virt-cat --format=vmdk -a "$v" "/var/backups/infoger/$dernier" | gunzip | perl -ne '
  $n += () = /\),\(|\)\s*;\s*$/g if /^INSERT INTO `rendez_vous`/;
  $pj += () = /,\x27[0-9]{8}_[0-9a-z]+\.(pdf|jpg|png)\x27,/g if /^INSERT INTO `rendez_vous`/;
  END { print "  rendez-vous : $n\n  références de pièces jointes : $pj\n" }'
printf '  pièces jointes présentes sur le disque : %s\n' \
  "$(virt-ls --format=vmdk -a "$v" /var/www/legacy-rdv/uploads | grep -cE '\.(pdf|jpg|png)$')"
echo "  comptes MariaDB : non lisibles hors ligne sans démarrer un serveur (mysql.global_priv est un"
echo "  fichier Aria) ; le compte « stats » et son hôte se déduisent de /etc/stats/stats.cnf (stats01)"
echo "  et de la configuration réseau de stats01 ; à confirmer au premier démarrage (F4-S10)."
