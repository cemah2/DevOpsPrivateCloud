# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E39.sh — M02-E39 « Panne : set -e ne fait pas ce qu'on croit »
#
# Dépose dans la zone de test /opt/workbook/m02/e39/ de adm01 un spool de journaux FICTIFS
# (ressources/M02-E39/fabriquer-spool.sh, dont un journal de dns01 arrivé en mode 000), une
# sauvegarde du spool faite par root, et le script d'archivage de Lucas (« mode strict
# activé »), puis le lance comme la tâche de cette nuit. tar échoue sur le fichier illisible,
# le script continue, annonce « Terminé », rend 0 et vide le spool de dns01.
# Variantes (corrige/pannes/fichiers/M02-E39/ms-archiver-journaux.vN) — l'erreur de tar est
# masquée par :
#   1. un pipeline « tar -cf - | gzip » sans pipefail ;
#   2. une fonction appelée comme condition d'un « if » (errexit ignoré dans tout son corps) ;
#   3. « local var=$(commande) » (le code retour est celui de local) ;
#   4. une substitution de commande « x=$(fonction) » (bash y désactive errexit, faute
#      d'inherit_errexit).
# Réinjection : une zone existante est déplacée (e39.precedent-<date>). Annulation : la zone
# est déplacée (e39.annule-<date>) ; rien n'est supprimé.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"

_E39_ZONE=/opt/workbook/m02/e39
_E39_MOD="$WB_ROOT/modules/02-scripting"
_E39_RC=""

_e39_injecter() {
  local v="$1" z="$_E39_ZONE" j
  wb_exec localhost U="$(id -un)" Z="$z" >/dev/null <<'EOF' || return 1
mkdir -p /opt/workbook/m02
chown "$U:" /opt/workbook/m02
if [ -e "$Z" ]; then
  mv -- "$Z" "$Z.precedent-$(date +%Y%m%d-%H%M%S)"
fi
journal "préparation de la zone $Z"
EOF
  bash "$_E39_MOD/ressources/M02-E39/fabriquer-spool.sh" "$z" >/dev/null || return 1
  mkdir -p "$z/bin" "$z/journal" "$z/sauvegardes" || return 1
  install -m 755 "$_E39_MOD/corrige/pannes/fichiers/M02-E39/ms-archiver-journaux.v$v" "$z/bin/ms-archiver-journaux" || return 1
  touch -d 'yesterday 15:47' "$z/bin/ms-archiver-journaux"
  # Sauvegarde du spool faite par root (elle seule lit le fichier en mode 000), avant l'archivage.
  wb_exec localhost U="$(id -un)" Z="$z" >/dev/null <<'EOF' || return 1
s="$Z/sauvegardes/spool-$(date +%F)-0100.tar.gz"
tar -C "$Z" -czf "$s" spool && chown "$U:" "$s"
journal "sauvegarde du spool : $s"
EOF
  # 02:00 : l'archivage « de la nuit ».
  j="$z/journal/archivage-$(date +%F)-0200.log"
  _E39_RC=0
  (cd "$z" && bin/ms-archiver-journaux) >"$j" 2>&1 || _E39_RC=$?
  printf 'code retour : %s\n' "$_E39_RC" >>"$j"
}

panne_E39_v1() { _e39_injecter 1; }
panne_E39_v2() { _e39_injecter 2; }
panne_E39_v3() { _e39_injecter 3; }
panne_E39_v4() { _e39_injecter 4; }

# verifier_E39 — le script a rendu 0, le spool de dns01 est vide et son archive est incomplète.
verifier_E39() {
  local z="$_E39_ZONE" a
  [[ "$_E39_RC" == 0 ]] || return 1
  [[ -z "$(find "$z/spool/dns01" -type f 2>/dev/null)" ]] || return 1
  a="$(find "$z/archives" -name 'dns01-*.tar.gz' | head -n 1)"
  [[ -n "$a" ]] || return 1
  ! tar -tzf "$a" 2>/dev/null | grep -q 'dnsmasq\.log\.1$'
}

annuler_E39() {
  local z="$_E39_ZONE"
  if [[ -e "$z" ]]; then
    mv -- "$z" "$z.annule-$(date +%Y%m%d-%H%M%S)" || wb_avert "zone $z non déplacée"
  fi
}

resume_E39() {
  echo "L'archivage des journaux de cette nuit dit « Terminé » (code 0) mais des journaux de dns01 ont disparu (/opt/workbook/m02/e39)."
}

symptome_E39() {
  wb_symptome "Ticket INC-2844 — De : Sophie Laurent (RSSI)" \
    "La tâche d'archivage des journaux de cette nuit (/opt/workbook/m02/e39, journal dans" \
    "journal/) s'est terminée en succès, code retour 0. Pourtant l'archive de dns01 ne contient" \
    "pas tous les journaux collectés, et le spool de dns01 est vide : des journaux ont disparu." \
    "Pour un hébergeur HDS, perdre une trace est un incident de sécurité. Lucas m'assure que son" \
    "script est en « mode strict » et s'arrête à la moindre erreur. Je veux comprendre comment" \
    "c'est possible, récupérer les journaux, et un script dont l'échec ne passe plus inaperçu." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 02 39"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 02 E39 4 "$@"; }
fi
