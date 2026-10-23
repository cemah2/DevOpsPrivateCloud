#!/usr/bin/env bash
# convertir-vm-infoger.sh — import et conversion d'une VM de l'export VMware d'InfoGér (F4-S10, CHG-3410).
# Solution de référence ; RB-345 en décrit chaque étape. À lancer en root sur pve01, une VM à la fois.
#
#   convertir-vm-infoger.sh --vm NOM --cle /root/cle-admin.pub [--sommes FICHIER] [--stockage-export ID]
#                           [--sans-demarrer]
#     --vm NOM        legacy-rdv01 | ftp-part01 | stats01 (VMID et adresse tirés du plan, PLAN §4.14)
#     --cle F         clé publique SSH d'adm01 (copiée depuis ~/.ssh/id_ed25519.pub) pour le compte admin
#     --sommes F      sommes SHA-256 reçues « par un autre canal » (sortie de fabriquer-export-vmware.sh)
#     --stockage-export ID   stockage qui porte import/infoger-export (défaut : hdd-bulk)
#     --sans-demarrer importer et convertir sans démarrer (pour inspecter avant)
#
# Étapes : 1. intégrité (manifeste + sommes du courriel) ; 2. qm importovf (simulation puis import) ;
# 3. matériel MédiSphère (VirtIO SCSI, carte virtio sur vinfra, CPU, console série, agent, EFI sans
# Secure Boot comme à l'origine) ; 4. adaptation HORS LIGNE de l'invité (virt-customize sur le disque
# de la VM arrêtée) : réseau ens18 + adresse du plan, résolveurs, outils VMware retirés, agent QEMU,
# compte admin, accès d'InfoGér fermé, configurations re-adressées, initramfs contrôlé ;
# 5. démarrage et contrôle par l'agent ; 6. (legacy-rdv01) compte de base « stats » re-adressé.
# L'export n'est JAMAIS modifié. Le script refuse un VMID déjà pris.
set -euo pipefail

STOCKAGE=local-nvme
VNET=vinfra
PASSERELLE=10.10.20.1
DOMAINE=par1.medisphere.internal

dire() { printf '>> %s\n' "$*"; }
mourir() { printf 'ERREUR : %s\n' "$*" >&2; exit 1; }
usage() { sed -n '4,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2; }

nom="" cle="" sommes="" stockage_export=hdd-bulk demarrer=1
while (($#)); do
  case "$1" in
    --vm) nom="${2:-}"; shift 2 ;;
    --cle) cle="${2:-}"; shift 2 ;;
    --sommes) sommes="${2:-}"; shift 2 ;;
    --stockage-export) stockage_export="${2:-}"; shift 2 ;;
    --sans-demarrer) demarrer=0; shift ;;
    *) usage ;;
  esac
done
case "$nom" in
  legacy-rdv01) vmid=3401; ip=10.10.20.44; role="role-legacy"; mac=bc:24:11:20:34:01 ;;
  ftp-part01)   vmid=3402; ip=10.10.20.45; role="role-ftp";   mac=bc:24:11:20:34:02 ;;
  stats01)      vmid=3403; ip=10.10.20.46; role="role-stats"; mac=bc:24:11:20:34:03 ;;
  *) usage ;;
esac
[[ -r "$cle" ]] || mourir "clé publique d'adm01 illisible : $cle"
((EUID == 0)) || mourir "à lancer en root sur pve01"
for o in qm pvesm pveum pvesh virt-customize sha256sum perl; do
  command -v "$o" >/dev/null || mourir "outil manquant : $o"
done
if qm status "$vmid" >/dev/null 2>&1; then mourir "le VMID $vmid existe déjà : rien n'est fait"; fi

racine="$(pvesh get "/storage/$stockage_export" --output-format json | perl -MJSON::PP -0777 -ne 'print decode_json($_)->{path} // ""')"
dossier="$racine/import/infoger-export/$nom"
ovf="$dossier/$nom.ovf"
[[ -f "$ovf" ]] || mourir "export introuvable : $ovf"

# --- 1. Intégrité ---------------------------------------------------------------------------------
dire "$nom : vérification du manifeste"
(cd "$dossier" && sed -nE 's/^SHA256\(([^)]+)\)= ([0-9a-f]{64})$/\2  \1/p' "$nom.mf" | sha256sum -c -)
if [[ -n "$sommes" ]]; then
  dire "$nom : comparaison avec les sommes reçues par un autre canal"
  (cd "$racine/import/infoger-export" && grep -E "  $nom/" "$sommes" | sha256sum -c -)
else
  dire "$nom : pas de --sommes : seul le manifeste a été vérifié (il voyage AVEC les fichiers)"
fi
micrologiciel="$(perl -ne 'print $1 if /vmw:key="firmware" vmw:value="([^"]+)"/' "$ovf")"

# --- 2. Import ------------------------------------------------------------------------------------
dire "$nom : simulation de l'import"
qm importovf "$vmid" "$ovf" "$STOCKAGE" --dryrun 1
dire "$nom : import (conversion du VMDK vers $STOCKAGE)"
qm importovf "$vmid" "$ovf" "$STOCKAGE"
volid="$(qm config "$vmid" | sed -nE 's/^scsi0: ([^,]+).*/\1/p')"
[[ -n "$volid" ]] || mourir "disque scsi0 introuvable après l'import (qm config $vmid)"

# --- 3. Matériel MédiSphère -----------------------------------------------------------------------
dire "$nom : matériel (VirtIO, agent, console série, carte sur $VNET)"
qm set "$vmid" \
  --scsihw virtio-scsi-single \
  --scsi0 "$volid,discard=on,iothread=1,ssd=1" \
  --net0 "virtio=$mac,bridge=$VNET" \
  --cpu x86-64-v2-AES \
  --ostype l26 \
  --serial0 socket --vga serial0 \
  --agent enabled=1 \
  --onboot 1 \
  --tags "env-f4;$role" \
  --description "VM migrée de l'export VMware d'InfoGér (CHG-3410). Gérée par OpenTofu (envs/f4-infoger)." >/dev/null
if [[ "$micrologiciel" == efi ]]; then
  # Origine : EFI sans Secure Boot (bootOptions.efiSecureBootEnabled=false) : pas de clés préchargées.
  qm set "$vmid" --bios ovmf --efidisk0 "$STOCKAGE:1,efitype=4m,pre-enrolled-keys=0" >/dev/null
fi
pveum pool modify lab --vms "$vmid"

# --- 4. Adaptation hors ligne de l'invité ---------------------------------------------------------
disque="$(pvesm path "$volid")"
t="$(mktemp -d)"
trap 'rm -rf "$t"' EXIT
cat > "$t/interfaces" <<EOF
# /etc/network/interfaces — $nom, migrée chez MédiSphère (CHG-3410). Carte virtio : ens18.
source /etc/network/interfaces.d/*

auto lo
iface lo inet loopback

auto ens18
iface ens18 inet static
    address $ip/24
    gateway $PASSERELLE
EOF
cat > "$t/resolv.conf" <<EOF
search $DOMAINE
nameserver 10.10.20.10
nameserver 10.10.20.16
EOF
printf '127.0.0.1\tlocalhost\n%s\t%s.%s %s\n' "$ip" "$nom" "$DOMAINE" "$nom" > "$t/hosts"
cat > "$t/10-medisphere.conf" <<'EOF'
# /etc/ssh/sshd_config.d/10-medisphere.conf (CHG-3410) — remplace 10-infoger.conf.
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
AllowUsers admin
EOF
printf 'admin ALL=(ALL) NOPASSWD:ALL\n' > "$t/90-medisphere"
printf '\n  %s — MédiSphère (VM migrée de chez InfoGér, CHG-3410). Gérée par le code.\n\n' "$nom" > "$t/motd"

specifique=()
case "$nom" in
  ftp-part01)
    specifique=(--run-command "sed -i 's/^pasv_address=.*/pasv_address=$ip/' /etc/vsftpd.conf") ;;
  stats01)
    specifique=(
      --run-command "sed -i '/infoger\\.local/d' /etc/hosts"
      --run-command "sed -i 's/^host *=.*/host     = legacy-rdv01.$DOMAINE/' /etc/stats/stats.cnf"
    ) ;;
esac

dire "$nom : adaptation hors ligne du disque (VM arrêtée) — quelques minutes"
virt-customize --quiet -a "$disque" \
  --upload "$t/interfaces:/etc/network/interfaces" \
  --delete /etc/resolv.conf \
  --upload "$t/resolv.conf:/etc/resolv.conf" \
  --upload "$t/hosts:/etc/hosts" \
  --upload "$t/motd:/etc/motd" \
  --run-command "DEBIAN_FRONTEND=noninteractive apt-get -y -q purge open-vm-tools" \
  --install qemu-guest-agent \
  --run-command "id admin >/dev/null 2>&1 || useradd --create-home --shell /bin/bash --groups sudo admin" \
  --upload "$t/90-medisphere:/etc/sudoers.d/90-medisphere" \
  --chmod "0440:/etc/sudoers.d/90-medisphere" \
  --ssh-inject "admin:file:$cle" \
  --delete /etc/ssh/sshd_config.d/10-infoger.conf \
  --upload "$t/10-medisphere.conf:/etc/ssh/sshd_config.d/10-medisphere.conf" \
  --delete /etc/sudoers.d/90-infoger \
  --run-command "usermod --lock --expiredate 1 --shell /usr/sbin/nologin infoger" \
  --delete /home/infoger/.ssh \
  "${specifique[@]}" \
  --run-command "update-initramfs -u -k all" \
  --run-command "for i in /boot/initrd.img-*; do lsinitramfs \"\$i\" | grep -q 'virtio_scsi' || { echo \"virtio_scsi absent de \$i\" >&2; exit 1; }; done" \
  --run-command "apt-get clean"

if ((demarrer == 0)); then
  dire "$nom : converti, NON démarré (--sans-demarrer). Démarrage : qm start $vmid"
  exit 0
fi

# --- 5. Démarrage et contrôle ---------------------------------------------------------------------
dire "$nom : démarrage"
qm start "$vmid"
for _ in $(seq 1 36); do
  qm guest cmd "$vmid" ping >/dev/null 2>&1 && break
  sleep 5
done
qm guest cmd "$vmid" ping >/dev/null 2>&1 || mourir "l'agent QEMU ne répond pas après 3 min : regarde la console (qm terminal $vmid)"
dire "$nom : l'agent répond ; adresses vues par l'invité :"
qm guest cmd "$vmid" network-get-interfaces | perl -MJSON::PP -0777 -ne '
  for my $i (@{decode_json($_)}) { for my $a (@{$i->{"ip-addresses"} // []}) {
    printf "   %-8s %s/%s\n", $i->{name}, $a->{"ip-address"}, $a->{prefix} if $a->{"ip-address-type"} eq "ipv4" } }'

# --- 6. Compte de base de stats01 (legacy-rdv01 seulement) ----------------------------------------
if [[ "$nom" == legacy-rdv01 ]]; then
  dire "$nom : compte MariaDB « stats » re-adressé vers 10.10.20.46"
  qm guest exec "$vmid" --timeout 30 -- mariadb -e \
    "RENAME USER 'stats'@'192.168.50.40' TO 'stats'@'10.10.20.46'" >/dev/null \
    || echo "avertissement : RENAME USER a échoué (déjà fait ?) : vérifie SELECT user,host FROM mysql.user" >&2
fi
dire "$nom : terminé. Suite : DNS/NetBox/import dans envs/f4-infoger, Ansible, sauvegarde (RB-345)."
