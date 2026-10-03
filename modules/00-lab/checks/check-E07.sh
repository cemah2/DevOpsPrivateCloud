# shellcheck shell=bash
# M00-E07 — Organiser les stockages sans rien casser.
# Lecture seule. Les contrôles s'exécutent sur pve01 (WB_PVE_HOST).
#   WB_STORAGE_NVME / WB_STORAGE_SSD / WB_STORAGE_BULK : noms réels si différents des noms logiques.

title "M00-E07 — Organiser les stockages sans rien casser"

NVME="${WB_STORAGE_NVME:-local-nvme}"
SSD="${WB_STORAGE_SSD:-ssd-lab}"
BULK="${WB_STORAGE_BULK:-hdd-bulk}"

# Commande distante : code 0 si le stockage $1 accepte le contenu $2
_m00_contenu() {
  printf "pvesh get /storage/%s --output-format json | perl -MJSON::PP -0777 -ne 'my \$s = decode_json(\$_); exit(!grep { \$_ eq q{%s} } split(/,/, \$s->{content} // q{}))'" "$1" "$2"
}

for st in "$NVME" "$SSD" "$BULK"; do
  check_ssh_output "stockage $st déclaré et actif" "$WB_PVE_HOST" \
    "^${st}[[:space:]]+[a-z]+[[:space:]]+active" "pvesm status"
done

check_ssh "$NVME accepte les disques de VM (images)" "$WB_PVE_HOST" "$(_m00_contenu "$NVME" images)"
check_ssh "$SSD accepte les disques de VM (images)" "$WB_PVE_HOST" "$(_m00_contenu "$SSD" images)"
for c in iso snippets backup; do
  check_ssh "$BULK accepte le contenu $c" "$WB_PVE_HOST" "$(_m00_contenu "$BULK" "$c")"
done
if remote "$WB_PVE_HOST" "pveversion | grep -q '^pve-manager/9\.'" >/dev/null 2>&1; then
  check_ssh "$BULK accepte le contenu import" "$WB_PVE_HOST" "$(_m00_contenu "$BULK" import)"
else
  skip "$BULK accepte le contenu import" "contenu disponible selon la version de Proxmox VE"
fi

if remote "$WB_PVE_HOST" "pvesh get /storage/$BULK --output-format json | perl -MJSON::PP -0777 -ne 'exit(decode_json(\$_)->{type} ne q{dir})'" >/dev/null 2>&1; then
  check_ssh "$BULK (répertoire) est déclaré comme point de montage externe" "$WB_PVE_HOST" \
    "pvesh get /storage/$BULK --output-format json | perl -MJSON::PP -0777 -ne 'my \$v = decode_json(\$_)->{is_mountpoint} // q{}; exit(!(\$v ne q{} && \$v ne q{0} && \$v ne q{no}))'"
else
  skip "$BULK déclaré comme point de montage externe" "ne concerne que le type répertoire"
fi

# Deux stockages de même type sur le même support (même chemin, même VG/thin pool, même pool ZFS)
check_ssh "aucun support n'est déclaré sous deux noms de stockage" "$WB_PVE_HOST" \
  "pvesh get /storage --output-format json | perl -MJSON::PP -0777 -ne 'my %v; for my \$s (@{decode_json(\$_)}) { my \$k = join(q{|}, \$s->{type}, map { \$s->{\$_} // q{} } qw(path vgname thinpool pool)); next if \$k =~ /^\w+\|+\$/; exit 1 if \$v{\$k}++ } exit 0'"
