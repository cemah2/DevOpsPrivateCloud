#!/usr/bin/env bash
# fabriquer-depot.sh — M01-E45 : fabrique « legacy-rdv », copie de l'historique Git livré par
# InfoGér pour l'ancienne application de prise de rendez-vous (PHP).
#
# Usage : fabriquer-depot.sh [--force] [--commits N] [DOSSIER]
#   DOSSIER      défaut : ${WB_SRC:-$HOME/src}/legacy-rdv
#   --commits N  nombre de commits (défaut 4000 ; 50000 et plus pour mesurer le commit-graph)
#   --force      remplace un dépôt existant
#
# Le dépôt est généré en quelques dizaines de secondes avec « git fast-import ». Il contient,
# quelque part dans son historique, des fichiers volumineux (binaires peu compressibles et
# export de base de démonstration). Environ 200 Mo d'espace disque nécessaires.
# Les binaires sont aléatoires : deux fabrications ne donnent pas les mêmes empreintes.
set -euo pipefail

force=0 n=4000
while (($#)); do
  case "$1" in
    --force) force=1; shift ;;
    --commits) n="${2:?--commits attend un nombre}"; shift 2 ;;
    -*) echo "Option inconnue : $1" >&2; exit 2 ;;
    *) break ;;
  esac
done
if ! [[ "$n" =~ ^[0-9]+$ ]] || ((n < 1000)); then echo "--commits : 1000 au minimum" >&2; exit 2; fi
dest="${1:-${WB_SRC:-$HOME/src}/legacy-rdv}"
if [[ -e "$dest" ]]; then
  if ((force)); then rm -rf "$dest"; else echo "Refus : $dest existe déjà (--force pour remplacer)." >&2; exit 1; fi
fi

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/dev/null
git -c init.defaultBranch=main init -q "$dest"
cd "$dest"

# Jalons (en proportion du nombre de commits)
j_sdk=$((n / 8))          # ajout de vendor/sdk-legacy-1.2.tar.gz (9 Mo)
j_video1=$((n * 3 / 8))   # ajout de assets/video/presentation.mp4 (18 Mo)
j_video2=$((n * 5 / 8))   # nouvelle version de la vidéo (18 Mo)
j_video_rm=$((n * 6 / 8)) # suppression de la vidéo (elle reste dans l'historique)
pas_dump=$((n / 12))      # régénération de db/dump-demo.sql (≈ 2 Mo de texte)

t0=1420070400   # 2015-01-01
auteurs=("Marc Dubois <m.dubois@infoger.example>" "Sonia Lefèvre <s.lefevre@infoger.example>"
         "Paul Garnier <p.garnier@infoger.example>" "Julien Petit <julien.petit@medisphere.internal>")
portees=(agenda rdv patient notif admin api)
types=(fix fix fix feat feat refactor chore docs)

# data_fichier CHEMIN — bloc « data » de fast-import à partir d'un fichier
data_fichier() { printf 'data %d\n' "$(stat -c %s "$1")"; cat "$1"; printf '\n'; }
# data_texte TEXTE — bloc « data » à partir d'une chaîne
data_texte() { printf 'data %d\n%s\n' "$(printf '%s' "$1" | wc -c)" "$1"; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

php_source() {   # php_source NUMÉRO_FICHIER RÉVISION
  local f="$1" r="$2" i
  printf '<?php\n// Legacy-RDV — module %d (révision %d)\nnamespace LegacyRdv\\Module%d;\n\n' "$f" "$r" "$f"
  for ((i = 0; i < 30; i++)); do
    # shellcheck disable=SC2016  # code PHP produit tel quel
    printf 'function traitement_%d_%d($rdv) { return $rdv[%d] ?? null; }\n' "$f" "$i" $(((i * r) % 17))
  done
}

dump_demo() {   # dump_demo VERSION — export SQL de démonstration (aucune donnée réelle)
  awk -v v="$1" 'BEGIN {
    print "-- Export de démonstration Legacy-RDV, version " v " (données fictives)"
    for (i = 1; i <= 26000; i++)
      printf "INSERT INTO rdv (id, praticien, creneau, statut) VALUES (%d, %d, \x272024-%02d-%02d %02d:00\x27, \x27%s\x27);\n",
             i, (i * 7 + v) % 120, (i % 12) + 1, (i % 28) + 1, 8 + (i % 10), ((i + v) % 5 ? "confirme" : "annule")
  }'
}

{
  for ((c = 1; c <= n; c++)); do
    t=$((t0 + c * 3600 * 7))
    a="${auteurs[c % ${#auteurs[@]}]}"
    p="${portees[c % ${#portees[@]}]}"
    ty="${types[c % ${#types[@]}]}"
    printf 'commit refs/heads/main\nmark :%d\nauthor %s %d +0100\ncommitter %s %d +0100\n' "$c" "$a" "$t" "$a" "$t"
    data_texte "$ty($p): ticket RDV-$((1000 + c))"
    ((c > 1)) && printf 'from :%d\n' $((c - 1))
    if ((c == 1)); then
      printf 'M 100644 inline README.md\n'
      data_texte "# Legacy-RDV
Application historique de prise de rendez-vous (PHP 7), maintenue par InfoGér jusqu'en 2026."
    fi
    printf 'M 100644 inline src/Module%d.php\n' $((c % 60))
    php_source $((c % 60)) "$c" > "$tmp/php"
    data_fichier "$tmp/php"
    if ((c == 1 || c % pas_dump == 0)); then
      dump_demo "$c" > "$tmp/dump"
      printf 'M 100644 inline db/dump-demo.sql\n'
      data_fichier "$tmp/dump"
    fi
    if ((c == j_sdk)); then
      head -c 9437184 /dev/urandom > "$tmp/bin"
      printf 'M 100644 inline vendor/sdk-legacy-1.2.tar.gz\n'
      data_fichier "$tmp/bin"
    fi
    if ((c == j_video1 || c == j_video2)); then
      head -c 18874368 /dev/urandom > "$tmp/bin"
      printf 'M 100644 inline assets/video/presentation.mp4\n'
      data_fichier "$tmp/bin"
    fi
    if ((c == j_video_rm)); then
      printf 'D assets/video/presentation.mp4\n'
    fi
    printf '\n'
  done
} | git fast-import --quiet

git reset -q --hard main
echo "Dépôt fabriqué : $dest ($n commits)."
git count-objects -vH | sed -n 's/^size-pack: /Taille des paquets : /p'
