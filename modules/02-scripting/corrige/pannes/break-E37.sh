# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E37.sh — M02-E37 « Panne : le nettoyage a supprimé trop de choses »
#
# Dépose dans la zone de test /opt/workbook/m02/e37/ de adm01 un jeu de rapports FICTIFS
# (ressources/M02-E37/fabriquer-donnees.sh), sa « sauvegarde de la nuit », et le script de
# purge de Lucas (version 0.1, défectueuse), puis le lance comme Lucas l'a fait hier soir.
# Aucune donnée réelle n'est touchée : le script ne travaille que sur une racine marquée
# .zone-de-test. Variantes (fichiers corrige/fichiers/M02-E37/panne/ms-purge-rapports.vN) :
#   1. variable mal orthographiée dans la règle « applications retirées » (rm -rf "$RACINE/$appli"
#      avec $appli jamais définie) : toute la racine disparaît ;
#   2. précédence de find (-o sans parenthèses) : tous les PDF partent, y compris récents et
#      sous conservation légale, et les vieux JSON restent ;
#   3. « cd » non vérifié dans la boucle des tmp/ : medi-notif n'a pas de tmp/, le rm -rf ./*
#      s'exécute à la racine ;
#   4. signe inversé (-mtime -30) : les rapports RÉCENTS sont supprimés, les vieux restent.
# Réinjection : une zone existante est déplacée (e37.precedent-<date>), jamais supprimée.
# Annulation : la zone encore cassée est déplacée (e37.annule-<date>) ; rien n'est supprimé ;
# une zone réparée reste en place.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"

_E37_ZONE=/opt/workbook/m02/e37
_E37_MOD="$WB_ROOT/modules/02-scripting"

# _e37_preparer_zone — /opt/workbook/m02 appartenant à l'apprenant ; zone précédente mise de côté.
_e37_preparer_zone() {
  wb_exec localhost U="$(id -un)" Z="$_E37_ZONE" >/dev/null <<'EOF'
mkdir -p /opt/workbook/m02
chown "$U:" /opt/workbook/m02
if [ -e "$Z" ]; then
  mv -- "$Z" "$Z.precedent-$(date +%Y%m%d-%H%M%S)"
  journal "zone précédente mise de côté"
fi
journal "préparation de la zone $Z"
EOF
}

_e37_injecter() {
  local v="$1" z="$_E37_ZONE" j
  _e37_preparer_zone || return 1
  bash "$_E37_MOD/ressources/M02-E37/fabriquer-donnees.sh" "$z" >/dev/null || return 1
  mkdir -p "$z/bin" "$z/etc" "$z/sauvegardes" "$z/journal" || return 1
  printf '%s\n' '# Configuration de ms-purge-rapports (PLAT-384)' \
    "RACINE=$z/rapports" 'RETENTION_JOURS=30' 'APPLIS_RETIREES="legacy-rdv"' >"$z/etc/purge.conf"
  install -m 755 "$_E37_MOD/corrige/fichiers/M02-E37/panne/ms-purge-rapports.v$v" "$z/bin/ms-purge-rapports" || return 1
  touch -d 'yesterday 16:12' "$z/bin/ms-purge-rapports" "$z/etc/purge.conf"
  # Sauvegarde « de la nuit » (avant la purge) : les dates de modification sont conservées.
  tar -C "$z" -czf "$z/sauvegardes/rapports-$(date -d yesterday +%F)-0215.tar.gz" rapports || return 1
  # Hier soir, 18 h 30 : Lucas lance son script « pour de vrai ».
  j="$z/journal/purge-$(date -d yesterday +%F)-1830.log"
  # Le code retour du script de Lucas n'a pas d'importance ici : verifier_E37 constate l'effet.
  (cd "$z" && bin/ms-purge-rapports) >"$j" 2>&1 || true
}

panne_E37_v1() { _e37_injecter 1; }
panne_E37_v2() { _e37_injecter 2; }
panne_E37_v3() { _e37_injecter 3; }
panne_E37_v4() { _e37_injecter 4; }

# verifier_E37 — au moins un fichier qui devait rester a disparu.
verifier_E37() {
  local z="$_E37_ZONE" s p _
  [[ -f "$z/attendu.tsv" ]] || return 1
  while IFS=$'\t' read -r s p _; do
    [[ "$s" == CONSERVER && ! -f "$z/$p" ]] && return 0
  done <"$z/attendu.tsv"
  return 1
}

# annuler_E37 — zone encore cassée (un rapport à conserver manque) : mise de côté, rien n'est
# supprimé. Zone réparée par l'apprenant : laissée en place (c'est elle que vérifie le contrôle).
annuler_E37() {
  local z="$_E37_ZONE"
  [[ -e "$z" ]] || return 0
  if [[ ! -f "$z/attendu.tsv" ]] || verifier_E37; then
    mv -- "$z" "$z.annule-$(date +%Y%m%d-%H%M%S)" || wb_avert "zone $z non déplacée"
  else
    echo "Zone $z réparée : laissée en place." >&2
  fi
}

resume_E37() {
  echo "La purge des rapports lancée hier soir par Lucas a supprimé des rapports qui devaient rester (/opt/workbook/m02/e37)."
}

symptome_E37() {
  wb_symptome "Ticket INC-2843 — De : Julien Petit" \
    "Il manque des rapports ce matin dans /opt/workbook/m02/e37/rapports (zone de recette)." \
    "Lucas y a lancé hier soir, pour la première fois « en vrai », son script de purge" \
    "(bin/ms-purge-rapports, politique PLAT-384) : il dit qu'il n'a supprimé que les vieux" \
    "rapports. Or des rapports récents ou sous conservation légale ont disparu. Rends-nous" \
    "ce qui n'aurait jamais dû partir, et que ça ne se reproduise pas : ce script doit" \
    "tourner chaque nuit sur la vraie racine. Sauvegardes de la nuit : sauvegardes/." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 02 37"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 02 E37 4 "$@"; }
fi
