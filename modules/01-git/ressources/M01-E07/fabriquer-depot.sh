#!/usr/bin/env bash
# shellcheck disable=SC2016  # les motifs sed contiennent des $ littéraux (code Bash à écrire)
# fabriquer-depot.sh — fabrique le dépôt d'exercice « git-labo » (M01-E07).
#
# Usage : fabriquer-depot.sh [DOSSIER]        (défaut : $WB_SRC/git-labo, soit ~/src/git-labo)
#
# Construit en local, sans rien publier, l'historique du petit outil « inventaire » hérité
# d'InfoGér : branches fusionnées en avance rapide ou par commit de fusion, une branche
# abandonnée, une fusion avec conflit résolu, une annulation (revert), des étiquettes légères
# et annotées. Les auteurs, dates et contenus sont FIXÉS : l'historique, donc chaque empreinte
# de commit, est identique chez tous les apprenants.
#
# Le script refuse d'écraser un dossier existant. Il ne touche ni à GitLab ni à ta
# configuration Git : il neutralise seulement, pour lui-même, la configuration globale
# (signature, hooks, fins de ligne) afin que l'historique produit soit reproductible.
# La publication vers formation/git-labo est faite par toi (énoncé de l'E07).
set -euo pipefail

dest="${1:-${WB_SRC:-$HOME/src}/git-labo}"

if [[ -e "$dest" ]]; then
  echo "Refus : $dest existe déjà. Renomme-le ou supprime-le (après avoir vérifié qu'il ne" >&2
  echo "contient rien d'utile), puis relance." >&2
  exit 1
fi
command -v git >/dev/null || { echo "git est introuvable." >&2; exit 1; }

# Environnement neutre : ni configuration globale ni système (identité, signature, hooks,
# autocrlf…). Seules les variables ci-dessous comptent.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export TZ=Europe/Paris LC_ALL=C

IG=("InfoGér Support" "support@infoger.example")
KB=("Karim Benali" "karim.benali@medisphere.internal")
LM=("Lucas Martin" "lucas.martin@medisphere.internal")
CM=("Claire Morel" "claire.morel@medisphere.internal")

# qui NOM EMAIL DATE — fixe auteur et validateur (committer) des opérations suivantes
qui() {
  export GIT_AUTHOR_NAME="$1" GIT_AUTHOR_EMAIL="$2" GIT_AUTHOR_DATE="$3"
  export GIT_COMMITTER_NAME="$1" GIT_COMMITTER_EMAIL="$2" GIT_COMMITTER_DATE="$3"
}

# valider "sujet" ["corps"] — indexe tout et commite
valider() {
  git add -A
  if [[ $# -ge 2 ]]; then git commit -q -m "$1" -m "$2"; else git commit -q -m "$1"; fi
}

mkdir -p "$(dirname "$dest")"
git init -q -b main "$dest"
cd "$dest"
git config core.autocrlf false

# --- 2024 : InfoGér ----------------------------------------------------------------------
qui "${IG[@]}" "2024-03-04T10:12:00+01:00"
mkdir -p conf
cat > README.md <<'EOF'
# inventaire

Script d'inventaire des VM, livré par InfoGér.

Usage : ./inventaire.sh <fichier-vms>
EOF
cat > inventaire.sh <<'EOF'
#!/bin/bash
# Inventaire des VM - InfoGer
. ./conf/inventaire.conf
FICHIER=$1
while read nom ram disque
do
echo "$nom $ram $disque"
done < $FICHIER
EOF
chmod +x inventaire.sh
cat > conf/inventaire.conf <<'EOF'
FORMAT=texte
EOF
valider "Version initiale du script d'inventaire"

qui "${IG[@]}" "2024-03-11T16:40:00+01:00"
cat > inventaire.sh <<'EOF'
#!/bin/bash
# Inventaire des VM - InfoGer
. ./conf/inventaire.conf
FICHIER=$1
mkdir -p $REPERTOIRE_EXPORT
while read nom ram disque
do
echo "$nom $ram $disque"
done < $FICHIER
EOF
cat > conf/inventaire.conf <<'EOF'
FORMAT=texte
REPERTOIRE_EXPORT=/var/tmp/inventaire
EOF
valider "Ajout de la configuration"

qui "${IG[@]}" "2024-04-02T09:05:00+02:00"
cat > inventaire.sh <<'EOF'
#!/bin/bash
# Inventaire des VM - InfoGer
. ./conf/inventaire.conf
FICHIER=$1
mkdir -p $REPERTOIRE_EXPORT
while read nom ram disque
do
    echo "$nom $ram $disque"
    if [ "$disque" -gt "$SEUIL_ALERTE" ]; then
        echo "ALERTE : $nom utilise $disque % de son disque"
    fi
done < $FICHIER
EOF
cat > conf/inventaire.conf <<'EOF'
FORMAT=texte
REPERTOIRE_EXPORT=/var/tmp/inventaire
SEUIL_ALERTE=85
EOF
valider "Corrections diverses"
git tag livraison-infoger

qui "${IG[@]}" "2024-05-15T14:20:00+02:00"
cat > README.md <<'EOF'
# inventaire

Script d'inventaire des VM, livré par InfoGér.

## Usage

    ./inventaire.sh <fichier-vms>

Le fichier contient une VM par ligne : nom, RAM (Go), occupation du disque (%).

## Configuration

Voir `conf/inventaire.conf`.
EOF
valider "Documentation"
git tag -a v0.1.0 -m "Version livrée par InfoGér"

# Branche abandonnée par InfoGér
git switch -q -c infoger/ancien-format
qui "${IG[@]}" "2024-06-03T11:00:00+02:00"
mkdir -p lib
cat > lib/xml.sh <<'EOF'
# Export XML (en cours)
exporter_xml() {
    echo "<vms>"
}
EOF
valider "WIP format XML"
qui "${IG[@]}" "2024-06-10T17:45:00+02:00"
cat > lib/xml.sh <<'EOF'
# Export XML (en cours)
exporter_xml() {
    echo "<vms>"
    echo "  <vm nom=\"$1\"/>"
    echo "</vms>"
}
EOF
valider "WIP XML suite"
git switch -q main

# --- 2026 : reprise par l'équipe Plateforme ------------------------------------------------
qui "${KB[@]}" "2026-01-12T09:30:00+01:00"
cat >> README.md <<'EOF'

## Responsable

Équipe Plateforme MédiSphère (reprise d'InfoGér en janvier 2026).
EOF
valider "docs: reprise du projet par l'équipe Plateforme"

# Correctif de Lucas : sera intégré par avance rapide (aucun commit de fusion)
git switch -q -c correctif/espaces-noms
qui "${LM[@]}" "2026-01-13T15:10:00+01:00"
cat > inventaire.sh <<'EOF'
#!/bin/bash
# Inventaire des VM - InfoGer
. ./conf/inventaire.conf
FICHIER=$1
mkdir -p $REPERTOIRE_EXPORT
while IFS=';' read -r nom ram disque
do
    echo "$nom $ram $disque"
    if [ "$disque" -gt "$SEUIL_ALERTE" ]; then
        echo "ALERTE : $nom utilise $disque % de son disque"
    fi
done < "$FICHIER"
EOF
valider "fix: noms de VM contenant des espaces" \
  "Le fichier d'entrée utilise désormais « ; » comme séparateur : un nom de VM peut contenir des espaces."

# Fonctionnalité de Karim, partie du même commit de base
git switch -q main
git switch -q -c fonction/export-csv
qui "${KB[@]}" "2026-01-14T10:00:00+01:00"
mkdir -p lib
cat > inventaire.sh <<'EOF'
#!/bin/bash
# Inventaire des VM - InfoGer
. ./conf/inventaire.conf
. ./lib/format.sh
FICHIER=$1
mkdir -p $REPERTOIRE_EXPORT
while read nom ram disque
do
    case "$FORMAT" in
        texte) echo "$nom $ram $disque" ;;
        csv) exporter_csv "$nom" "$ram" "$disque" ;;
    esac
    if [ "$disque" -gt "$SEUIL_ALERTE" ]; then
        echo "ALERTE : $nom utilise $disque % de son disque"
    fi
done < $FICHIER
EOF
cat > lib/format.sh <<'EOF'
# Fonctions de mise en forme de l'inventaire

exporter_csv() {
    echo "$1,$2,$3"
}
EOF
valider "feat: fonction exporter_csv"

qui "${KB[@]}" "2026-01-15T11:20:00+01:00"
cat > lib/format.sh <<'EOF'
# Fonctions de mise en forme de l'inventaire

exporter_csv() {
    printf '%s%s%s%s%s\n' "$1" "$SEPARATEUR" "$2" "$SEPARATEUR" "$3"
}
EOF
cat >> conf/inventaire.conf <<'EOF'
SEPARATEUR=','
EOF
valider "feat: séparateur configurable"

qui "${KB[@]}" "2026-01-16T16:05:00+01:00"
mkdir -p exemples
cat > exemples/vms.txt <<'EOF'
web01;4;42
db01;16;91
app 01;8;77
EOF
valider "test: jeu de données d'exemple"

# Intégration dans main : avance rapide pour le correctif, commit de fusion pour la fonctionnalité
git switch -q main
qui "${KB[@]}" "2026-01-19T10:15:00+01:00"
git merge -q --ff-only correctif/espaces-noms
git merge -q --no-ff -m "Merge branch 'fonction/export-csv'" fonction/export-csv >/dev/null
git tag -a v0.2.0 -m "Version 0.2.0 : export CSV, noms de VM avec espaces"

qui "${LM[@]}" "2026-02-02T14:30:00+01:00"
cat >> lib/format.sh <<'EOF'

purger_exports() {
    find "$REPERTOIRE_EXPORT" -type f -mtime +30 -delete
}
EOF
sed -i 's|^mkdir -p \$REPERTOIRE_EXPORT$|mkdir -p $REPERTOIRE_EXPORT\npurger_exports|' inventaire.sh
valider "feat: purge des anciens exports"
purge="$(git rev-parse HEAD)"

qui "${KB[@]}" "2026-02-03T09:00:00+01:00"
git revert -n "$purge"
valider "Revert \"feat: purge des anciens exports\"" \
  "This reverts commit $purge.

La purge supprimait aussi les fichiers de référence déposés à la main dans le répertoire d'export."

# Deux évolutions concurrentes du même bloc : conflit à la fusion
git switch -q -c fonction/sortie-json
qui "${LM[@]}" "2026-02-05T10:40:00+01:00"
sed -i 's|^        csv) exporter_csv "\$nom" "\$ram" "\$disque" ;;$|&\n        json) exporter_json "$nom" "$ram" "$disque" ;;|' inventaire.sh
cat >> lib/format.sh <<'EOF'

exporter_json() {
    printf '{"nom": "%s", "ram": %s, "disque": %s}\n' "$1" "$2" "$3"
}
EOF
valider "feat: sortie JSON"

git switch -q main
qui "${KB[@]}" "2026-02-06T15:00:00+01:00"
sed -i 's|^        csv) exporter_csv "\$nom" "\$ram" "\$disque" ;;$|&\n        yaml) exporter_yaml "$nom" "$ram" "$disque" ;;|' inventaire.sh
cat >> lib/format.sh <<'EOF'

exporter_yaml() {
    printf -- '- nom: "%s"\n  ram: %s\n  disque: %s\n' "$1" "$2" "$3"
}
EOF
valider "feat: sortie YAML"

qui "${KB[@]}" "2026-02-09T11:30:00+01:00"
if git merge -q --no-ff fonction/sortie-json >/dev/null 2>&1; then
  echo "Erreur interne : la fusion de fonction/sortie-json aurait dû être en conflit." >&2
  exit 1
fi
# Résolution : on garde les deux formats, YAML puis JSON
git show HEAD:inventaire.sh | sed 's|^        yaml) exporter_yaml "\$nom" "\$ram" "\$disque" ;;$|&\n        json) exporter_json "$nom" "$ram" "$disque" ;;|' > inventaire.sh
{ git show HEAD:lib/format.sh; printf '\n'; git show fonction/sortie-json:lib/format.sh | sed -n '/^exporter_json()/,/^}/p'; } > lib/format.sh
git add inventaire.sh lib/format.sh
git commit -q -m "Merge branch 'fonction/sortie-json'"

qui "${CM[@]}" "2026-02-10T08:50:00+01:00"
cat >> README.md <<'EOF'

## Astreinte

En cas de problème : équipe Plateforme, canal « astreinte-plateforme ».
EOF
valider "docs: ajout du contact d'astreinte"

# Travail en cours de Lucas, pas encore fusionné
git switch -q -c fonction/tri
qui "${LM[@]}" "2026-02-12T16:20:00+01:00"
sed -i 's|^done < "\$FICHIER"$|done < <(sort "$FICHIER")|' inventaire.sh
valider "feat: tri des VM par nom"
git switch -q main

# Contrôles de cohérence de la fabrication
[[ -z "$(git status --porcelain)" ]] || { echo "Erreur interne : arbre de travail non propre." >&2; exit 1; }
git fsck --no-progress --strict >/dev/null

echo "Dépôt d'exercice fabriqué dans : $dest"
echo "Branches  : $(git for-each-ref --format='%(refname:short)' refs/heads | paste -sd' ')"
echo "Étiquettes : $(git tag | paste -sd' ')"
echo "Commit de main : $(git rev-parse --short HEAD)"
echo
echo "Suite : crée le projet vide formation/git-labo dans GitLab, puis publie toutes les"
echo "branches et toutes les étiquettes (énoncé de l'E07, étape 2)."
