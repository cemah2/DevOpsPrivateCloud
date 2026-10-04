# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E42.sh — M02-E42 « Panne : l'environnement Python est cassé »
#
# Variantes (toutes sur adm01, compte de l'apprenant) :
#   1. environnement de l'outil installé par « uv tool » (medictl) : son lien bin/python pointe
#      vers un interpréteur géré par uv qui n'existe plus (« ménage » dans ~/.local/share/uv) ;
#   2. un vieux prototype medictl 0.1.0 installé par « pip install --user
#      --break-system-packages » : ~/.local/bin/medictl est remplacé par le lanceur de pip
#      (#!/usr/bin/python3) et le paquet est dans le site utilisateur ;
#   3. dans ~/src/outils/.venv, le dossier du paquet typer a disparu mais ses métadonnées
#      (dist-info) sont restées : uv croit l'environnement à jour ;
#   4. dans ~/src/outils/.venv, un fichier 00-compat-infoger.pth ajoute en tête de sys.path un
#      vieux module « medictl » d'InfoGér (/opt/workbook/m02/e42/compat-infoger) qui masque
#      le paquet du projet.
# Sauvegardes : /var/lib/workbook/M02-E42.* sur adm01 (fichiers via sauver, dossier typer
# déplacé, liste des dossiers créés). Annulation : tout est remis à l'identique.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"

_E42_FICHIERS="$WB_ROOT/modules/02-scripting/corrige/pannes/fichiers/M02-E42"
_E42_PROJET="${WB_SRC:-$HOME/src}/outils"

# _e42_lanceur — chemin du lanceur medictl installé par uv tool (~/.local/bin/medictl par défaut).
_e42_lanceur() {
  local b
  b="$(uv tool dir --bin 2>/dev/null)" || b="$HOME/.local/bin"
  printf '%s/medictl\n' "${b:-$HOME/.local/bin}"
}

# _e42_site_venv — dossier site-packages de l'environnement du projet.
_e42_site_venv() {
  local d
  for d in "$_E42_PROJET"/.venv/lib/python3*/site-packages; do
    [[ -d "$d" ]] && { printf '%s\n' "$d"; return 0; }
  done
  return 1
}

_e42_precondition_outil() {
  command -v uv >/dev/null || { wb_avert "uv absent du PATH"; return 1; }
  "$(_e42_lanceur)" --version >/dev/null 2>&1 \
    || { wb_avert "medictl (uv tool) ne fonctionne déjà pas : lab/bin/check 02 42"; return 1; }
}

_e42_precondition_projet() {
  command -v uv >/dev/null || { wb_avert "uv absent du PATH"; return 1; }
  _e42_site_venv >/dev/null || { wb_avert "$_E42_PROJET/.venv absent : lance « uv sync » dans le projet"; return 1; }
  (cd "$_E42_PROJET" && uv run --no-sync python -c 'import medictl, typer' >/dev/null 2>&1) \
    || { wb_avert "l'environnement du projet est déjà cassé : lab/bin/check 02 42"; return 1; }
}

panne_E42_v1() {
  _e42_precondition_outil || return 1
  local outil
  outil="$(uv tool dir)/medictl"
  [[ -L "$outil/bin/python" ]] || { wb_avert "$outil/bin/python n'est pas un lien"; return 1; }
  wb_exec localhost P="$outil/bin/python" U="$(id -un)" \
    CIBLE="$HOME/.local/share/uv/python/cpython-3.13.5-linux-x86_64-gnu/bin/python3.13" >/dev/null <<'EOF'
[ ! -e "$CIBLE" ] || { echo "$CIBLE existe : variante inapplicable" >&2; exit 1; }
sauver "$P"
ln -sfn "$CIBLE" "$P"
chown -h "$U:" "$P"
journal "lien $P → $CIBLE (interpréteur inexistant)"
EOF
}

panne_E42_v2() {
  _e42_precondition_outil || return 1
  local usite lanceur
  usite="$(python3 -c 'import site; print(site.getusersitepackages())')" || return 1
  lanceur="$(_e42_lanceur)"
  [[ ! -e "$usite/medictl" ]] || { wb_avert "un paquet medictl existe déjà dans $usite"; return 1; }
  wb_exec localhost US="$usite" L="$lanceur" U="$(id -un)" SRC="$_E42_FICHIERS" >/dev/null <<'EOF'
# Dossiers créés par la panne (supprimés à l'annulation, et eux seuls)
d="$US"; manquants=""
while [ ! -d "$d" ]; do manquants="$d $manquants"; d="$(dirname "$d")"; done
mkdir -p "$US"
for m in $manquants; do printf '%s\n' "$m" >>"$WB_DIR/M02-E42.dossiers"; done
cp -a "$SRC/user-site/medictl" "$SRC/user-site/medictl-0.1.0.dist-info" "$US/"
printf '%s\n%s\n' "$US/medictl" "$US/medictl-0.1.0.dist-info" >>"$WB_DIR/M02-E42.dossiers"
chown -R "$U:" "$US/medictl" "$US/medictl-0.1.0.dist-info"
for m in $manquants; do chown "$U:" "$m"; done
sauver "$L"
rm -f -- "$L"
install -m 755 -o "$U" -g "$(id -gn "$U")" "$SRC/lanceur-pip-medictl" "$L"
touch -d '2026-04-02 10:14' "$L" "$US/medictl" "$US/medictl-0.1.0.dist-info"
journal "prototype medictl 0.1.0 installé dans $US, lanceur $L remplacé"
EOF
}

panne_E42_v3() {
  _e42_precondition_projet || return 1
  local site
  site="$(_e42_site_venv)"
  [[ -d "$site/typer" ]] || { wb_avert "$site/typer absent"; return 1; }
  wb_exec localhost T="$site/typer" >/dev/null <<'EOF'
[ ! -e "$WB_DIR/M02-E42.typer" ] || { echo "sauvegarde de typer déjà présente" >&2; exit 1; }
printf '%s\n' "$T" >"$WB_DIR/M02-E42.typer.chemin"
mv -- "$T" "$WB_DIR/M02-E42.typer"
journal "dossier $T retiré (métadonnées dist-info conservées)"
EOF
}

panne_E42_v4() {
  _e42_precondition_projet || return 1
  local site
  site="$(_e42_site_venv)"
  wb_exec localhost SITE="$site" U="$(id -un)" SRC="$_E42_FICHIERS" >/dev/null <<'EOF'
c=/opt/workbook/m02/e42/compat-infoger
[ ! -e /opt/workbook/m02/e42 ] || { echo "/opt/workbook/m02/e42 existe déjà" >&2; exit 1; }
mkdir -p /opt/workbook/m02 && chown "$U:" /opt/workbook/m02
mkdir -p "$c"
printf '%s\n' /opt/workbook/m02/e42 >>"$WB_DIR/M02-E42.dossiers"
cp -a "$SRC/compat-infoger/medictl" "$c/"
chown -R "$U:" /opt/workbook/m02/e42
sauver "$SITE/00-compat-infoger.pth"
install -m 644 -o "$U" -g "$(id -gn "$U")" "$SRC/00-compat-infoger.pth" "$SITE/00-compat-infoger.pth"
touch -d 'yesterday 17:52' "$SITE/00-compat-infoger.pth"
journal "chemin $c ajouté en tête de sys.path par $SITE/00-compat-infoger.pth"
EOF
}

verifier_E42() {
  # shellcheck disable=SC2031  # WB_VAR est fixé par wb_main (ou par l'astreinte) avant l'appel
  case "${WB_VAR:-}" in
    1) ! "$(_e42_lanceur)" --version >/dev/null 2>&1 ;;
    2) "$(_e42_lanceur)" --version 2>&1 | grep -q '0\.1\.0' ;;
    3) ! (cd "$_E42_PROJET" && uv run --no-sync python -c 'import typer' >/dev/null 2>&1) ;;
    4) (cd "$_E42_PROJET" && uv run --no-sync python -c 'import medictl; print(medictl.__file__)' 2>/dev/null) \
         | grep -q compat-infoger ;;
    *) return 1 ;;
  esac
}

annuler_E42() {
  wb_exec localhost >/dev/null <<'EOF' || wb_avert "annulation incomplète sur adm01"
restaurer_fichiers
if [ -d "$WB_DIR/M02-E42.typer" ] && [ -f "$WB_DIR/M02-E42.typer.chemin" ]; then
  t="$(cat "$WB_DIR/M02-E42.typer.chemin")"
  if [ ! -e "$t" ]; then
    mv -- "$WB_DIR/M02-E42.typer" "$t"
  fi
  rm -rf -- "$WB_DIR/M02-E42.typer"
  rm -f -- "$WB_DIR/M02-E42.typer.chemin"
fi
# Dossiers créés par la panne, du plus profond au moins profond
if [ -f "$WB_DIR/M02-E42.dossiers" ]; then
  sort -r "$WB_DIR/M02-E42.dossiers" | while read -r d; do
    case "$d" in
      */medictl | */medictl-0.1.0.dist-info | /opt/workbook/m02/e42) rm -rf -- "$d" ;;
      *) rmdir -- "$d" 2>/dev/null || true ;;
    esac
  done
  rm -f -- "$WB_DIR/M02-E42.dossiers"
fi
journal "annulation : environnements Python rétablis"
exit 0
EOF
}

resume_E42() {
  echo "medictl (ou les tests du projet outils) plante sur adm01 avec des erreurs Python incompréhensibles."
}

symptome_E42() {
  local detail
  # shellcheck disable=SC2031
  case "${WB_VAR:-}" in
    1 | 2) detail="« medictl » ne marche plus sur adm01 (essaie « medictl --version » puis « medictl vm list »)." ;;
    *) detail="dans ~/src/outils, « task test » et « uv run medictl --version » plantent." ;;
  esac
  wb_symptome "Ticket INC-2846 — De : Karim Benali" \
    "Depuis le « ménage » fait hier par Lucas sur adm01, l'outillage Python est en vrac :" \
    "$detail" \
    "Personne n'a touché au code ni à la release. Ne réinstalle pas tout à l'aveugle :" \
    "je veux savoir ce qui a été cassé, pour que ça ne se reproduise pas sur les autres postes." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 02 42"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 02 E42 4 "$@"; }
fi
