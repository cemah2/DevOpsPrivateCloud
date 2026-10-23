#!/usr/bin/env bash
# fabriquer-export-vmware.sh — fabrique, sur pve01, l'export VMware « livré par InfoGér » (F4-S09).
#
# Le workbook ne versionne aucune image disque. Ce script reconstruit les trois VMs d'InfoGér à partir de
# l'image cloud officielle Debian 12 (genericcloud, vérifiée par sa somme SHA-512), personnalisées HORS
# LIGNE par virt-customize (libguestfs), puis exportées comme le ferait un vCenter : disque VMDK
# « streamOptimized », descripteur OVF 1.0 (celui des exports vSphere) au matériel VMware (vmx-19, vmxnet3, pvscsi ou LSI Logic,
# micrologiciel EFI ou BIOS), manifeste .mf (SHA-256).
#
#   legacy-rdv01  192.168.50.21  Apache + mod_php + MariaDB 10.11, Legacy-RDV 2.3.1 AVEC ses données
#   ftp-part01    192.168.50.30  vsftpd (dépôt des partenaires)
#   stats01       192.168.50.40  statistiques nocturnes qui lisent la base de legacy-rdv01
#
# Garanties :
#   - ne crée, ne modifie, ne démarre AUCUNE VM : n'appelle jamais qm ; lit seulement la configuration
#     du stockage (pvesh get /storage/<id>) ;
#   - n'écrit que dans <chemin du stockage>/import/infoger-export/ (dossier dédié) ;
#   - idempotent : une VM dont l'export est complet et conforme à son manifeste n'est pas refabriquée
#     (--forcer pour tout refaire) ; les données sont déterministes (date de référence mémorisée) ;
#   - toute image téléchargée est vérifiée par sa somme SHA-512 (fichier SHA512SUMS de Debian, HTTPS).
#
# Usage (root sur pve01) :
#   fabriquer-export-vmware.sh [--stockage ID] [--image FICHIER.qcow2] [--date AAAA-MM-JJ]
#                              [--vm NOM]... [--forcer]
#     --stockage ID   stockage Proxmox de type répertoire qui reçoit l'export (défaut : hdd-bulk)
#     --image F       image debian-12-genericcloud-amd64.qcow2 déjà téléchargée (vérifiée quand même)
#     --date D        date de référence des données (première fabrication seulement ; défaut : aujourd'hui)
#     --vm NOM        ne fabriquer que cette VM (répétable)
#     --forcer        refabriquer même si l'export existe et est conforme
# Prérequis : paquet libguestfs-tools (virt-customize, virt-resize, virt-sparsify), qemu-img, curl,
#   perl ; accès à Internet depuis pve01 (image Debian, paquets installés dans les images) ;
#   environ 25 Gio libres sur le stockage pendant la fabrication, 3 Gio ensuite.
# Durée : 15 à 30 minutes (installation de paquets dans trois images).
set -euo pipefail

URL_BASE="https://cloud.debian.org/images/cloud/bookworm/latest"
IMAGE_NOM="debian-12-genericcloud-amd64.qcow2"
CAPACITE_GIO=8
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PERSO="$ICI/personnalisation"
APP_SRC="$(cd "$ICI/../../../../apps/legacy-rdv" 2>/dev/null && pwd || true)"

# nom;adresse;vcpu;memoire_mo;controleur OVF;micrologiciel;MAC;paquets supplémentaires;annotation
VMS=(
  "legacy-rdv01;192.168.50.21;2;2048;VirtualSCSI;efi;00:50:56:8a:21:01;apache2,libapache2-mod-php,php-mysql,php-mbstring,mariadb-server,mariadb-client,logrotate;Legacy-RDV 2.3.1 (prise de RDV des cabinets) - PROD - ne pas redemarrer en journee"
  "ftp-part01;192.168.50.30;1;1024;VirtualSCSI;efi;00:50:56:8a:30:01;vsftpd;Depot FTP des partenaires (labo, radio) - PROD"
  "stats01;192.168.50.40;1;1024;lsilogic;bios;00:50:56:8a:40:01;mariadb-client;Statistiques RDV - cree en 2018 par JMV"
)

usage() {
  sed -n '/^# Usage/,/^# Durée/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 2
}
dire() { printf '>> %s\n' "$*"; }
mourir() { printf 'ERREUR : %s\n' "$*" >&2; exit 1; }

stockage=hdd-bulk
image=""
date_ref=""
forcer=0
choix=()
while (($#)); do
  case "$1" in
    --stockage) (($# >= 2)) || usage; stockage="$2"; shift 2 ;;
    --image) (($# >= 2)) || usage; image="$2"; shift 2 ;;
    --date) (($# >= 2)) || usage; date_ref="$2"; shift 2 ;;
    --vm) (($# >= 2)) || usage; choix+=("$2"); shift 2 ;;
    --forcer) forcer=1; shift ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
done

# --- 0. Contrôles préalables ------------------------------------------------------------------------
((EUID == 0)) || mourir "à lancer en root sur pve01"
command -v pvesh >/dev/null 2>&1 || mourir "pvesh introuvable : ce script se lance sur pve01 (Proxmox VE)"
for o in virt-customize virt-resize virt-sparsify; do
  command -v "$o" >/dev/null 2>&1 || mourir "$o introuvable : installe d'abord libguestfs-tools (voir README.md)"
done
for o in qemu-img curl sha512sum sha256sum perl ssh-keygen flock stat sed awk; do
  command -v "$o" >/dev/null 2>&1 || mourir "outil manquant : $o"
done
[[ -n "$APP_SRC" && -f "$APP_SRC/index.php" ]] || mourir "code de Legacy-RDV introuvable (apps/legacy-rdv du dépôt du workbook)"
[[ -z "$date_ref" || "$date_ref" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || mourir "--date attend AAAA-MM-JJ"
for c in "${choix[@]}"; do
  printf '%s\n' "${VMS[@]}" | grep -q "^$c;" || mourir "VM inconnue : $c (legacy-rdv01, ftp-part01, stats01)"
done

racine="$(pvesh get "/storage/$stockage" --output-format json 2>/dev/null \
  | perl -MJSON::PP -0777 -ne 'my $s = decode_json($_); print $s->{path} // ""')" \
  || mourir "stockage $stockage introuvable (pvesm status)"
[[ -n "$racine" && -d "$racine" ]] || mourir "le stockage $stockage n'est pas de type répertoire (pas de chemin) : choisis-en un avec --stockage"
EXPORT="$racine/import/infoger-export"
WB="$EXPORT/.workbook"
mkdir -p "$EXPORT" "$WB"
chmod 0700 "$WB"

exec 9>"$WB/verrou"
flock -n 9 || mourir "une fabrication est déjà en cours (verrou $WB/verrou)"

TRAVAIL="$(mktemp -d "$EXPORT/.travail-XXXXXX")"
trap 'rm -rf "$TRAVAIL"' EXIT

# Date de référence : fixée à la première fabrication, réutilisée ensuite (données identiques).
if [[ -s "$WB/date-reference" ]]; then
  ancienne="$(cat "$WB/date-reference")"
  [[ -z "$date_ref" || "$date_ref" == "$ancienne" ]] \
    || mourir "date de référence déjà fixée à $ancienne (supprime $WB/date-reference et relance avec --forcer pour changer)"
  date_ref="$ancienne"
else
  date_ref="${date_ref:-$(date +%F)}"
  printf '%s\n' "$date_ref" > "$WB/date-reference"
fi

# --- 1. Que faut-il fabriquer ? -------------------------------------------------------------------
# export_conforme NOM — les trois fichiers existent et le manifeste se vérifie.
export_conforme() {
  local d="$EXPORT/$1"
  [[ -f "$d/$1.ovf" && -f "$d/$1.mf" && -f "$d/$1-disk1.vmdk" ]] || return 1
  (cd "$d" && sed -nE 's/^SHA256\(([^)]+)\)= ([0-9a-f]{64})$/\2  \1/p' "$1.mf" | sha256sum --quiet -c -) >/dev/null 2>&1
}
a_faire=()
for l in "${VMS[@]}"; do
  nom="${l%%;*}"
  if ((${#choix[@]})) && ! printf '%s\n' "${choix[@]}" | grep -qx "$nom"; then continue; fi
  if ((forcer == 0)) && export_conforme "$nom"; then
    dire "$nom : export déjà présent et conforme à son manifeste (rien à faire ; --forcer pour refaire)"
    continue
  fi
  a_faire+=("$l")
done

if ((${#a_faire[@]})); then
  # Espace exigé seulement s'il y a quelque chose à fabriquer (une relance qui ne fait qu'afficher les
  # sommes ne doit pas échouer faute de place).
  libre_gio=$(($(df --output=avail -k "$EXPORT" | tail -n 1) / 1048576))
  ((libre_gio >= 25)) || mourir "$libre_gio Gio libres sous $EXPORT : il en faut 25 pendant la fabrication"

  # --- 2. Image source, vérifiée ----------------------------------------------------------------------
  mkdir -p "$WB/cache"
  curl -fsSL --proto "=https" --proto-redir "=https" "$URL_BASE/SHA512SUMS" -o "$TRAVAIL/SHA512SUMS"
  attendue="$(awk -v n="$IMAGE_NOM" '$2 == n {print $1}' "$TRAVAIL/SHA512SUMS")"
  [[ -n "$attendue" ]] || mourir "somme de $IMAGE_NOM absente de SHA512SUMS"
  if [[ -n "$image" ]]; then
    source_img="$image"
  else
    source_img="$WB/cache/$IMAGE_NOM"
    if [[ ! -f "$source_img" ]] || [[ "$(sha512sum "$source_img" | awk '{print $1}')" != "$attendue" ]]; then
      dire "téléchargement de $IMAGE_NOM"
      curl -fSL --proto "=https" --proto-redir "=https" --progress-bar "$URL_BASE/$IMAGE_NOM" -o "$TRAVAIL/$IMAGE_NOM"
      mv -f "$TRAVAIL/$IMAGE_NOM" "$source_img"
    fi
  fi
  [[ "$(sha512sum "$source_img" | awk '{print $1}')" == "$attendue" ]] \
    || mourir "somme SHA-512 incorrecte pour $source_img (image corrompue, ou « latest » vient de changer : relance plus tard)"
  dire "image source vérifiée (SHA-512) : $source_img"

  # --- 3. Données et secrets partagés (déterministes, conservés dans .workbook) ----------------------
  perl "$PERSO/legacy-rdv01/generer-donnees.pl" "$TRAVAIL/donnees" "$date_ref"
  install -m 0600 "$TRAVAIL/donnees/temoins.csv" "$WB/temoins.csv"
  install -m 0600 "$TRAVAIL/donnees/resume.txt" "$WB/resume-donnees.txt"
  sha256sum "$TRAVAIL/donnees/pieces/"*_temoin*.pdf | awk '{n=$2; sub(".*/", "", n); print $1 "  " n}' > "$WB/temoins-pieces.sha256"
  chmod 0600 "$WB/temoins-pieces.sha256"
  # Mot de passe MariaDB du compte « stats » : le même dans legacy-rdv01 (GRANT) et stats01 (stats.cnf).
  if [[ ! -s "$WB/stats.mdp" ]]; then
    (umask 077; head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24 > "$WB/stats.mdp")
  fi
  # Clé SSH « d'InfoGér » : la partie privée n'est jamais conservée (accès d'InfoGér, pas le nôtre).
  ssh-keygen -q -t ed25519 -N "" -C "exploitation@infoger.fr" -f "$TRAVAIL/infoger_ed25519"
fi

# --- 4. Fabrication de chaque VM --------------------------------------------------------------------
fabriquer() {
  local nom="$1" adresse="$2" vcpu="$3" memoire="$4" controleur="$5" micrologiciel="$6" mac="$7"
  local paquets="$8" annotation="$9"
  local t="$TRAVAIL/$nom" disque mdp taille
  mkdir -p "$t/infoger" "$t/export"
  disque="$t/$nom.qcow2"

  dire "$nom : disque de $CAPACITE_GIO Gio (copie de l'image, partition racine agrandie)"
  qemu-img create -q -f qcow2 "$disque" "${CAPACITE_GIO}G"
  virt-resize --quiet --expand /dev/sda1 "$source_img" "$disque"

  # Fichiers déposés dans /root/infoger de l'invité (effacés à la fin de la personnalisation).
  cp "$PERSO/commun/"* "$t/infoger/"
  printf '%s\n' "$nom" > "$t/infoger/nom"
  printf '%s\n' "$adresse" > "$t/infoger/adresse"
  case "$nom" in
    legacy-rdv01)
      cp -a "$PERSO/legacy-rdv01/." "$t/infoger/"
      mkdir -p "$t/infoger/app"
      cp -a "$APP_SRC/." "$t/infoger/app/"
      cp -a "$TRAVAIL/donnees" "$t/infoger/donnees"
      install -m 0600 "$WB/stats.mdp" "$t/infoger/stats.mdp"
      ;;
    ftp-part01) cp -a "$PERSO/ftp-part01/." "$t/infoger/" ;;
    stats01)
      cp -a "$PERSO/stats01/." "$t/infoger/"
      install -m 0600 "$WB/stats.mdp" "$t/infoger/stats.mdp"
      ;;
  esac
  mdp="$t/mdp-infoger"
  (umask 077; head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 20 > "$mdp")

  local specifique=()
  case "$nom" in
    legacy-rdv01)
      specifique=(
        --run "$PERSO/legacy-rdv01/initialiser-legacy.sh"
        --run-command "install -m 0644 /root/infoger/60-infoger.cnf /etc/mysql/mariadb.conf.d/60-infoger.cnf"
        --run-command "install -m 0755 /root/infoger/infoger-sauvegarde-base /usr/local/sbin/infoger-sauvegarde-base"
        --run-command "install -m 0644 /root/infoger/infoger-sauvegarde.cron /etc/cron.d/infoger-sauvegarde"
        --run-command "install -m 0644 /root/infoger/logrotate-legacy-rdv /etc/logrotate.d/legacy-rdv"
        --run-command "systemctl enable apache2.service mariadb.service >/dev/null"
      )
      ;;
    ftp-part01)
      specifique=(
        --run-command "install -m 0755 /root/infoger/archiver-depots /usr/local/sbin/archiver-depots"
        --run-command "install -m 0644 /root/infoger/archiver-depots.cron /etc/cron.d/archiver-depots"
        --run-command "install -m 0644 /root/infoger/vsftpd.conf /etc/vsftpd.conf"
        --run-command "install -m 0644 /root/infoger/vsftpd.user_list /etc/vsftpd.user_list"
        --run "$PERSO/ftp-part01/initialiser-ftp.sh"
        --run-command "systemctl enable vsftpd.service >/dev/null"
      )
      ;;
    stats01)
      specifique=(--run "$PERSO/stats01/initialiser-stats.sh")
      ;;
  esac

  dire "$nom : personnalisation hors ligne (paquets, configuration d'InfoGér) — plusieurs minutes"
  virt-customize --quiet -a "$disque" --memsize 2048 --smp 2 \
    --hostname "$nom" \
    --timezone Europe/Paris \
    --install "linux-image-amd64,open-vm-tools,ifupdown,cron,sudo,openssh-server,$paquets" \
    --copy-in "$t/infoger:/root" \
    --run "$PERSO/commun/systeme.sh" \
    "${specifique[@]}" \
    --password "infoger:file:$mdp" \
    --ssh-inject "infoger:file:$TRAVAIL/infoger_ed25519.pub" \
    --root-password disabled \
    --run-command "apt-get clean" \
    --delete /root/infoger
  rm -f "$mdp"

  dire "$nom : récupération de l'espace libre, conversion en VMDK streamOptimized"
  virt-sparsify --quiet --in-place "$disque"
  qemu-img convert -q -f qcow2 -O vmdk -o subformat=streamOptimized,adapter_type=lsilogic \
    "$disque" "$t/export/$nom-disk1.vmdk"
  rm -f "$disque"

  taille="$(stat -c %s "$t/export/$nom-disk1.vmdk")"
  sed -e "s/@NOM@/$nom/g" -e "s/@DISQUE@/$nom-disk1.vmdk/g" -e "s/@TAILLE_FICHIER@/$taille/g" \
    -e "s/@CAPACITE_GIO@/$CAPACITE_GIO/g" -e "s/@VCPU@/$vcpu/g" -e "s/@MEMOIRE_MO@/$memoire/g" \
    -e "s/@CONTROLEUR_SOUS_TYPE@/$controleur/g" -e "s/@MICROLOGICIEL@/$micrologiciel/g" \
    -e "s/@MAC@/$mac/g" -e "s/@ANNOTATION@/$annotation/g" \
    "$ICI/modele-vmware.ovf" > "$t/export/$nom.ovf"
  if grep -q '@[A-Z_]*@' "$t/export/$nom.ovf"; then mourir "$nom : variable non remplacée dans le descripteur OVF"; fi
  (
    cd "$t/export"
    for f in "$nom.ovf" "$nom-disk1.vmdk"; do
      printf 'SHA256(%s)= %s\n' "$f" "$(sha256sum "$f" | awk '{print $1}')"
    done
  ) > "$t/export/$nom.mf"

  # Remplacement atomique de l'export de cette VM.
  rm -rf "$EXPORT/$nom.ancien"
  if [[ -d "$EXPORT/$nom" ]]; then mv "$EXPORT/$nom" "$EXPORT/$nom.ancien"; fi
  mv "$t/export" "$EXPORT/$nom"
  rm -rf "$EXPORT/$nom.ancien" "$t"
  dire "$nom : export prêt dans $EXPORT/$nom"
}

for l in "${a_faire[@]}"; do
  IFS=';' read -r n a c m ctl fw mac pq an <<<"$l"
  fabriquer "$n" "$a" "$c" "$m" "$ctl" "$fw" "$mac" "$pq" "$an"
done

# --- 5. Bilan : sommes « envoyées par un autre canal » ------------------------------------------------
(
  cd "$EXPORT"
  for l in "${VMS[@]}"; do
    n="${l%%;*}"
    if [[ -d "$n" ]]; then sha256sum "$n/$n.ovf" "$n/$n.mf" "$n/$n-disk1.vmdk"; fi
  done
) > "$WB/SHA256SUMS.attendues"
chmod 0600 "$WB/SHA256SUMS.attendues"

echo
dire "export d'InfoGér dans $EXPORT (date de référence des données : $date_ref)"
ls -l "$EXPORT"/*/ 2>/dev/null || true
echo
echo "Sommes SHA-256 des fichiers livrés (le « courriel d'InfoGér », à comparer avant tout import) :"
cat "$WB/SHA256SUMS.attendues"
