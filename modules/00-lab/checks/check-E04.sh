# shellcheck shell=bash
# M00-E04 — Sauvegarde vérifiée des photos de hp01.
# Lecture seule. Les contrôles s'exécutent sur pve01 (WB_PVE_HOST).
#   WB_PHOTOS_DIR        dossier de sauvegarde (défaut : /mnt/hdd-bulk/sauvegarde-photos-hp01)
#   WB_PHOTOS_FULLCHECK  1 = recalcul de TOUTES les sommes (peut durer des heures)

title "M00-E04 — Sauvegarde vérifiée des photos de hp01"

PHOTOS_DIR="${WB_PHOTOS_DIR:-/mnt/hdd-bulk/sauvegarde-photos-hp01}"
# Chemin protégé pour être inséré dans une commande distante
D="$(printf '%q' "$PHOTOS_DIR")"

check_ssh "le dossier $PHOTOS_DIR/donnees existe sur pve01" "$WB_PVE_HOST" \
  "test -d $D/donnees"
check_ssh "la sauvegarde n'est pas sur le système de fichiers racine de pve01" "$WB_PVE_HOST" \
  "test -d $D && test \"\$(stat -c %d $D)\" != \"\$(stat -c %d /)\""
check_ssh "MANIFEST.sha256 présent et non vide" "$WB_PVE_HOST" \
  "test -s $D/MANIFEST.sha256"
check_ssh "toutes les lignes du manifeste sont au format sha256sum" "$WB_PVE_HOST" \
  "test -s $D/MANIFEST.sha256 && ! grep -Evq '^[\]?[0-9a-f]{64} [ *].' $D/MANIFEST.sha256"
check_ssh "autant de fichiers dans donnees/ que de lignes dans le manifeste" "$WB_PVE_HOST" \
  "test \"\$(find $D/donnees -type f -printf . | wc -c)\" -eq \"\$(wc -l < $D/MANIFEST.sha256)\""
check_ssh "échantillon de 200 fichiers : sommes conformes au manifeste" "$WB_PVE_HOST" \
  "cd $D/donnees && shuf -n 200 ../MANIFEST.sha256 | LC_ALL=C sha256sum -c --quiet --strict"

if [[ "${WB_PHOTOS_FULLCHECK:-0}" == "1" ]]; then
  check_ssh "vérification intégrale : toutes les sommes sont conformes" "$WB_PVE_HOST" \
    "cd $D/donnees && LC_ALL=C sha256sum -c --quiet --strict ../MANIFEST.sha256"
else
  skip "vérification intégrale de toutes les sommes" "WB_PHOTOS_FULLCHECK=1 pour l'activer"
fi

check_ssh "un rapport VERIFICATION-*.txt est archivé" "$WB_PVE_HOST" \
  "ls $D/VERIFICATION-*.txt >/dev/null 2>&1"
check_ssh "le dernier rapport couvre tous les fichiers, sans aucun échec" "$WB_PVE_HOST" \
  "f=\$(ls -1t $D/VERIFICATION-*.txt 2>/dev/null | head -n1) && test -n \"\$f\" \
   && ! grep -q 'FAILED' \"\$f\" \
   && test \"\$(grep -c ': OK\$' \"\$f\")\" -eq \"\$(wc -l < $D/MANIFEST.sha256)\""
check_ssh "LISEZMOI.txt présent (provenance et autres copies)" "$WB_PVE_HOST" \
  "test -s $D/LISEZMOI.txt"
