#!/usr/bin/env bash
# fabriquer-depot.sh — M01-E44 : fabrique le dépôt « flux-check » (≈ 130 commits, avec fusions)
# qui sert à l'exercice git bisect.
#
# Usage : fabriquer-depot.sh [--force] [DOSSIER]
#   DOSSIER  défaut : ${WB_SRC:-$HOME/src}/labo-e44
#   --force  remplace un dépôt existant (sinon refus)
#
# flux-check est un petit outil Bash qui transforme une matrice de flux CSV en règles lisibles.
# La version v1.0.0 passe ses tests ; la tête de main ne les passe plus. Sans accès réseau.
# Identités et dates fixes : deux fabrications donnent exactement les mêmes empreintes.
# ⚠️ Ne lis pas ce script avant d'avoir fait l'exercice : il contient la réponse.
set -euo pipefail

force=0
if [[ "${1:-}" == --force ]]; then force=1; shift; fi
dest="${1:-${WB_SRC:-$HOME/src}/labo-e44}"
if [[ -e "$dest" ]]; then
  if ((force)); then rm -rf "$dest"; else echo "Refus : $dest existe déjà (--force pour remplacer)." >&2; exit 1; fi
fi
mkdir -p "$dest"
cd "$dest"

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/dev/null
t=1767600000   # 2026-01-05
g() { git -c init.defaultBranch=main -c core.hooksPath=/dev/null -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }
qui() {
  case "$1" in
    karim) export GIT_AUTHOR_NAME="Karim Benali" GIT_AUTHOR_EMAIL="karim.benali@medisphere.internal" ;;
    lucas) export GIT_AUTHOR_NAME="Lucas Martin" GIT_AUTHOR_EMAIL="lucas.martin@medisphere.internal" ;;
    julien) export GIT_AUTHOR_NAME="Julien Petit" GIT_AUTHOR_EMAIL="julien.petit@medisphere.internal" ;;
  esac
  export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME" GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
}
dater() { t=$((t + 7200)); export GIT_AUTHOR_DATE="@$t +0100" GIT_COMMITTER_DATE="@$t +0100"; }
valider() { dater; g add -A; g commit -q --no-verify -m "$1"; }
fusionner() { dater; g merge -q --no-ff --no-edit -m "Merge branch '$1'" "$1"; g branch -q -d "$1"; }

# --------------------------------------------------------------------------------------------
# Contenus de référence
# --------------------------------------------------------------------------------------------
ecrire_ports_sain() {
  cat > lib/ports.sh <<'EOF'
# ports.sh — validation et normalisation des ports et plages de ports.

# verifier_port PORT — échoue si PORT n'est pas un entier entre 1 et 65535.
verifier_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 )) || { echo "port invalide : $1" >&2; return 1; }
}

# normaliser_ports "22, 80,8000-8010" → « { 22, 80, 8000-8010 } » (ou « 443 » s'il est seul).
normaliser_ports() {
  local IFS=',' p debut fin
  local -a liste=()
  for p in $1; do
    p="${p// /}"
    if [[ "$p" == *-* ]]; then
      debut="${p%-*}"
      fin="${p#*-}"
      verifier_port "$debut" && verifier_port "$fin" || return 1
      (( debut < fin )) || { echo "plage invalide : $p" >&2; return 1; }
      liste+=("$debut-$fin")
    else
      verifier_port "$p" || return 1
      liste+=("$p")
    fi
  done
  if (( ${#liste[@]} == 1 )); then
    printf '%s' "${liste[0]}"
  else
    local IFS='|'
    printf '{ %s }' "$(sed 's/|/, /g' <<<"${liste[*]}")"
  fi
}
EOF
}

ecrire_ports_refactor1() {
  cat > lib/ports.sh <<'EOF'
# ports.sh — validation et normalisation des ports et plages de ports.

# verifier_port PORT — échoue si PORT n'est pas un entier entre 1 et 65535.
verifier_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 )) || { echo "port invalide : $1" >&2; return 1; }
}

# normaliser_element "8000-8010" | "443" — un élément de la liste, validé.
normaliser_element() {
  local p="${1// /}" debut fin
  if [[ "$p" == *-* ]]; then
    debut="${p%-*}"
    fin="${p#*-}"
    verifier_port "$debut" && verifier_port "$fin" || return 1
    (( debut < fin )) || { echo "plage invalide : $p" >&2; return 1; }
    printf '%s-%s' "$debut" "$fin"
  else
    verifier_port "$p" || return 1
    printf '%s' "$p"
  fi
}

# normaliser_ports "22, 80,8000-8010" → « { 22, 80, 8000-8010 } » (ou « 443 » s'il est seul).
normaliser_ports() {
  local IFS=',' p
  local -a liste=()
  for p in $1; do
    liste+=("$(normaliser_element "$p")") || return 1
  done
  if (( ${#liste[@]} == 1 )); then
    printf '%s' "${liste[0]}"
  else
    local IFS='|'
    printf '{ %s }' "$(sed 's/|/, /g' <<<"${liste[*]}")"
  fi
}
EOF
}

# --------------------------------------------------------------------------------------------
# Historique
# --------------------------------------------------------------------------------------------
g init -q
mkdir -p bin lib tests donnees docs

qui karim
cat > README.md <<'EOF'
# flux-check

Transforme la matrice des flux (CSV `source;destination;proto;ports;commentaire`) en règles
lisibles, pour relire la matrice et la comparer au pare-feu de gw01.

    bin/flux-check donnees/flux-par1.csv

Tests : `tests/test.sh` (code 0 si tout passe).
EOF
cat > bin/flux-check <<'EOF'
#!/usr/bin/env bash
# flux-check — affiche la matrice des flux sous forme de règles lisibles.
set -euo pipefail
racine="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for f in "$racine"/lib/*.sh; do
  # shellcheck source=/dev/null
  source "$f"
done
principal "$@"
EOF
chmod +x bin/flux-check
cat > lib/principal.sh <<'EOF'
# principal.sh — boucle de lecture de la matrice.
principal() {
  local fichier="${1:?usage : flux-check <matrice.csv>}"
  local src dst proto ports commentaire
  while IFS=';' read -r src dst proto ports commentaire; do
    [[ -z "$src" || "$src" == \#* ]] && continue
    proto="$(valider_proto "$proto")"
    printf '%s -> %s %s dport %s  # %s\n' "$src" "$dst" "$proto" "$(normaliser_ports "$ports")" "$commentaire"
  done < "$fichier"
}
EOF
cat > lib/proto.sh <<'EOF'
# proto.sh — validation du protocole.
valider_proto() {
  local p="${1,,}"
  case "$p" in
    tcp|udp) printf '%s' "$p" ;;
    *) echo "protocole non géré : $1" >&2; return 1 ;;
  esac
}
EOF
ecrire_ports_sain
valider "feat: première version de flux-check"

cat > tests/flux-exemple.csv <<'EOF'
# source;destination;proto;ports;commentaire
10.10.10.10;10.10.20.12;tcp;22,443;adm01 vers git01 (SSH, HTTPS)
10.10.20.15;10.10.20.12;TCP;443;runner01 vers git01
10.10.20.12;10.20.10.10;tcp;8007;git01 vers pbs01 (sauvegarde)
10.10.10.0/24;10.10.20.10;udp;53;DNS
10.10.10.10;10.10.40.0/24;tcp;6443, 30000-32767;API et NodePorts Kubernetes (futur)
EOF
cat > tests/attendu.txt <<'EOF'
10.10.10.10 -> 10.10.20.12 tcp dport { 22, 443 }  # adm01 vers git01 (SSH, HTTPS)
10.10.20.15 -> 10.10.20.12 tcp dport 443  # runner01 vers git01
10.10.20.12 -> 10.20.10.10 tcp dport 8007  # git01 vers pbs01 (sauvegarde)
10.10.10.0/24 -> 10.10.20.10 udp dport 53  # DNS
10.10.10.10 -> 10.10.40.0/24 tcp dport { 6443, 30000-32767 }  # API et NodePorts Kubernetes (futur)
EOF
cat > tests/test.sh <<'EOF'
#!/usr/bin/env bash
# test.sh — compare la sortie de flux-check à la sortie attendue. Code 0 : succès.
set -u
ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if diff -u "$ici/attendu.txt" <("$ici/../bin/flux-check" "$ici/flux-exemple.csv" 2>&1); then
  echo "tests : OK"
  exit 0
fi
echo "tests : ÉCHEC"
exit 1
EOF
chmod +x tests/test.sh
valider "test: ajouter le test de bout en bout"

printf '# source;destination;proto;ports;commentaire\n' > donnees/flux-par1.csv
cat > docs/utilisation.md <<'EOF'
# Utilisation

flux-check lit un fichier CSV séparé par des points-virgules.
EOF
cat > lib/format.sh <<'EOF'
# format.sh — utilitaires d'affichage.
# révision 0
titre() { printf '== %s ==\n' "$1"; }
EOF
valider "docs: guide d'utilisation et squelette des données"

# Générateur de commits « ordinaires » (données, documentation, cosmétique).
n=0
ordinaire() {
  n=$((n + 1))
  case $((n % 5)) in
    0) qui lucas
       printf '10.10.20.%d;10.10.20.12;tcp;%d;flux applicatif n°%d\n' $((20 + n % 30)) $((9000 + n)) "$n" >> donnees/flux-par1.csv
       valider "feat(donnees): déclarer le flux applicatif n°$n" ;;
    1) qui karim
       printf -- "- Point d'utilisation n°%d.\n" "$n" >> docs/utilisation.md
       valider "docs: compléter le guide d'utilisation ($n)" ;;
    2) qui julien
       sed -i "s/^# révision .*/# révision $n/" lib/format.sh
       valider "style(format): harmoniser les commentaires ($n)" ;;
    3) qui lucas
       printf '10.10.10.10;10.10.20.%d;tcp;22;administration n°%d\n' $((10 + n % 40)) "$n" >> donnees/flux-par1.csv
       valider "feat(donnees): ouvrir l'administration SSH n°$n" ;;
    4) qui karim
       printf '\n<!-- relu le %s -->\n' "$n" >> README.md
       valider "chore: relecture périodique du README ($n)" ;;
  esac
}

for _ in {1..8}; do ordinaire; done
qui karim
dater
g tag -a v1.0.0 -m "flux-check 1.0.0"

for _ in {1..14}; do ordinaire; done

# Branche de fonctionnalité fusionnée (sans effet sur les tests).
g switch -q -c feat/titres
qui julien
cat > lib/titres.sh <<'EOF'
# titres.sh — titres de second niveau des rapports.
sous_titre() { printf -- '-- %s --\n' "$1"; }
EOF
valider "feat(format): ajouter les sous-titres"
printf '# Titres\n\nLes titres et sous-titres sont réservés aux rapports.\n' > docs/titres.md
valider "docs(format): documenter les titres"
g switch -q main
ordinaire
ordinaire
fusionner feat/titres

for _ in {1..10}; do ordinaire; done

# Une erreur de syntaxe sans rapport avec la régression casse tout pendant un temps.
qui julien
cat > lib/export.sh <<'EOF'
# export.sh — export de la matrice (préparation de l'export JSON).
exporter_lignes() {
  local l
  while read -r l; do
    if [[ -n "$l" ]]; then
      printf '"%s",\n' "$l"
  done
}
EOF
valider "feat(export): préparer l'export JSON"
for _ in {1..22}; do ordinaire; done
qui julien
cat > lib/export.sh <<'EOF'
# export.sh — export de la matrice (préparation de l'export JSON).
exporter_lignes() {
  local l
  while read -r l; do
    if [[ -n "$l" ]]; then
      printf '"%s",\n' "$l"
    fi
  done
}
EOF
valider "fix(export): corriger la structure conditionnelle"

for _ in {1..6}; do ordinaire; done

# Branche de refactorisation : c'est ici que la régression entre.
g switch -q -c refactor/ports
qui karim
ecrire_ports_refactor1
valider "refactor(ports): extraire la normalisation d'un élément"
# Régression : copier-coller (fin calculée comme le début) et contrôle assoupli.
# shellcheck disable=SC2016  # remplacement littéral dans le code fabriqué
sed -i 's/^    fin="\${p#\*-}"$/    fin="${p%-*}"/; s/^    (( debut < fin ))/    (( debut <= fin ))/' lib/ports.sh
valider "refactor(ports): simplifier le découpage des plages"
cat > docs/ports.md <<'EOF'
# Ports

Une ligne peut contenir plusieurs ports séparés par des virgules, et des plages `début-fin`.
EOF
valider "docs(ports): documenter le format des plages"
g switch -q main
ordinaire
ordinaire
fusionner refactor/ports

for _ in {1..18}; do ordinaire; done

g switch -q -c docs/exemples
qui lucas
cat > docs/exemples.md <<'EOF'
# Exemples

    bin/flux-check tests/flux-exemple.csv
EOF
valider "docs: ajouter des exemples"
g switch -q main
ordinaire
fusionner docs/exemples

for _ in {1..16}; do ordinaire; done

g gc -q --prune=now
echo "Dépôt fabriqué : $dest ($(g rev-list --count HEAD) commits sur main, étiquette v1.0.0)"
