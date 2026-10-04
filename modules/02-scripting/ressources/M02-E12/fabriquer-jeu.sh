#!/usr/bin/env bash
# =============================================================================
# fabriquer-jeu.sh — jeu de données de M02-E12 : les exports laissés par InfoGér
#
# Usage : fabriquer-jeu.sh DOSSIER
#   Crée DOSSIER/exports-infoger/ (DOSSIER doit exister ; le sous-dossier ne doit pas
#   exister) : 35 fichiers ordinaires, dans une vingtaine de dossiers, aux noms piégeux (espaces, tiret
#   initial, caractères de motif, retour à la ligne, tabulation, guillemets,
#   antislash, accents), des dates de modification anciennes ou récentes, un
#   fichier caché, un lien symbolique et un fichier vide.
#   Le jeu est identique à chaque exécution (mêmes noms, mêmes contenus, mêmes dates).
#
# Données fictives et jetables : aucune donnée réelle, rien hors de DOSSIER.
# Résumé attendu (avec l'âge par défaut de ms-ranger, 90 jours) : voir la fin du script.
# =============================================================================
set -euo pipefail
umask 022

[[ $# -eq 1 && -d "$1" ]] || {
  echo "Usage : $0 DOSSIER_EXISTANT" >&2
  exit 2
}
racine="$1/exports-infoger"
[[ ! -e "$racine" ]] || {
  echo "$racine existe déjà : supprime-le ou choisis un autre dossier" >&2
  exit 1
}

# fichier CHEMIN_RELATIF DATE — crée un fichier au contenu déterministe, daté.
fichier() {
  local chemin="$racine/$1"
  mkdir -p -- "$(dirname -- "$chemin")"
  printf 'Export InfoGér — %s\nJeu de données de M02-E12.\n' "$1" >"$chemin"
  touch -d "$2" -- "$chemin"
}

ANCIEN_1="2025-01-15 09:30:00"
ANCIEN_2="2025-02-03 18:05:00"
ANCIEN_3="2025-03-28 07:45:00"
ANCIEN_4="2025-06-30 23:59:00"
RECENT="$(date -d '-3 days' '+%Y-%m-%d 12:00:00')"

# --- Noms ordinaires -----------------------------------------------------------
for m in 01 02 03 04 05 06; do
  fichier "rapports/rapport-2025-$m.csv" "2025-$m-28 08:00:00"
done
fichier "rapports/rapport-courant.csv" "$RECENT"
fichier "configs/dns01/dnsmasq.conf" "$ANCIEN_1"
fichier "configs/gw01/nftables.conf" "$ANCIEN_2"
fichier "configs/gw01/nftables.conf.bak" "$ANCIEN_2"

# --- Espaces, tabulation, espace final ---------------------------------------------
fichier "rapports mensuels/rapport mensuel janvier 2025.pdf" "$ANCIEN_1"
fichier "rapports mensuels/rapport mensuel  février 2025.pdf" "$ANCIEN_2"
fichier "rapports mensuels/synthèse T1.ods" "$ANCIEN_3"
fichier "rapports mensuels/fin d'année .txt" "$ANCIEN_4"
fichier $'rapports mensuels/colonne\tséparée.tsv' "$ANCIEN_3"
fichier "rapports mensuels/en cours.odt" "$RECENT"

# --- Tiret initial (pris pour une option si on oublie « -- » ou « ./ ») -------------
fichier "-divers/-rf" "$ANCIEN_1"
fichier "-divers/--help.txt" "$ANCIEN_2"
fichier "-divers/-n" "$RECENT"

# --- Caractères de motif et de shell ---------------------------------------------------
fichier "factures/facture [2025] *finale*.txt" "$ANCIEN_1"
fichier "factures/facture ?.txt" "$ANCIEN_2"
fichier "factures/devis \$HOME.txt" "$ANCIEN_3"
fichier "factures/devis \$(reboot).txt" "$ANCIEN_3"
fichier "factures/a;b|c&d.txt" "$ANCIEN_4"
fichier "factures/l'export \"complet\".tar" "$ANCIEN_4"
fichier 'factures/C:\Windows\chemin.txt' "$ANCIEN_2"

# --- Retour à la ligne dans le nom (rare, mais légal) ----------------------------------
fichier $'journaux/ligne un\nligne deux.log' "$ANCIEN_1"
fichier $'journaux/\nau début.log' "$ANCIEN_2"
fichier "journaux/normal.log" "$ANCIEN_2"

# --- Accents et caractères non latins ------------------------------------------------
fichier "accentués/résumé été.txt" "$ANCIEN_3"
fichier "accentués/Ærøskøbing – São Paulo – Łódź.txt" "$ANCIEN_4"
fichier "accentués/日本語.txt" "$ANCIEN_4"

# --- Profondeur et cas particuliers --------------------------------------------------
fichier "archives/2025/01/15/a/b/c/très profond.txt" "$ANCIEN_1"
fichier "archives/.verrou-infoger" "$ANCIEN_1"
: >"$racine/archives/vide.dat"
touch -d "$ANCIEN_2" -- "$racine/archives/vide.dat"
ln -s ../rapports/rapport-2025-01.csv "$racine/archives/lien-vers-rapport"
touch -h -d "$ANCIEN_1" -- "$racine/archives/lien-vers-rapport"
mkdir -p -- "$racine/dossier vide"

# Compter des NUL, pas des lignes : un nom peut contenir un retour à la ligne.
n_fichiers=$(find "$racine" -type f -print0 | tr -cd '\0' | wc -c)
n_anciens=$(find "$racine" -type f -mtime +90 -print0 | tr -cd '\0' | wc -c)
n_liens=$(find "$racine" -type l -print0 | tr -cd '\0' | wc -c)
printf 'Jeu créé dans %s : %d fichiers ordinaires (%d de plus de 90 jours), %d lien(s) symbolique(s).\n' \
  "$racine" "$n_fichiers" "$n_anciens" "$n_liens"
