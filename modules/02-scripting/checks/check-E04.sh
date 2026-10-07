# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes reçoivent leurs valeurs en paramètres ($1)
#
# check-E04.sh — M02-E04 : ShellCheck et shfmt : lire, corriger, configurer
# À lancer depuis adm01. Lecture seule (shellcheck et « shfmt -d » n'écrivent rien).

title "M02-E04 — ShellCheck et shfmt : lire, corriger, configurer"
require_cmd shellcheck shfmt git

_m02_repo="${WB_SRC:-$HOME/src}/outils"
_m02_e04="$HOME/m02/e04"

# --- Outils du poste ------------------------------------------------------------
check_output "ShellCheck 0.11 sur adm01" '^version: 0\.(1[1-9]|[2-9][0-9])\.' shellcheck --version
check_output "shfmt 3.14 ou plus récent sur adm01" '^v?3\.(1[4-9]|[2-9][0-9])\.' shfmt --version

# --- Scripts InfoGér corrigés ------------------------------------------------------
for _m02_f in purge_logs.sh check_disk.sh sauvegarde_config.sh; do
  check_cmd "$_m02_f corrigé présent dans ~/m02/e04/" test -s "$_m02_e04/$_m02_f"
  # --norc : la configuration du dépôt ne doit pas masquer un défaut ; tous niveaux de sévérité.
  check_cmd "$_m02_f : ShellCheck ne signale plus rien (y compris le style)" \
    shellcheck --norc -S style "$_m02_e04/$_m02_f"
  check_cmd "$_m02_f : au plus une directive « shellcheck disable », jamais « all »" \
    bash -c '[[ $(grep -c "shellcheck disable" "$1") -le 1 ]] && ! grep -Eq "disable=all" "$1"' _ "$_m02_e04/$_m02_f"
  check_cmd "$_m02_f : syntaxe Bash valide" bash -n "$_m02_e04/$_m02_f"
done
# Seuil de 1 % (valeur valide pour toute interface raisonnable) : la racine le dépasse
# forcément ; un code non nul ne peut donc pas venir d'un refus du seuil lui-même.
check_cmd "check_disk.sh avec un seuil de 1 % : les alertes donnent un code retour non nul" \
  bash -c '! "$1" 1 >/dev/null 2>&1' _ "$_m02_e04/check_disk.sh"
check_output "check_disk.sh avec un seuil de 1 % : la partition racine est signalée sur la sortie standard" \
  '(^|[[:space:]])/([[:space:]:]|$)' bash -c '"$1" 1 2>/dev/null || true' _ "$_m02_e04/check_disk.sh"

# --- Configuration du dépôt plateforme/outils ---------------------------------------
check_cmd ".shellcheckrc versionné à la racine du dépôt" \
  git -C "$_m02_repo" ls-files --error-unmatch .shellcheckrc
check_cmd ".shellcheckrc : les fichiers chargés par « source » sont suivis" \
  grep -Eq '^[[:space:]]*external-sources[[:space:]]*=[[:space:]]*true' "$_m02_repo/.shellcheckrc"
check_cmd ".shellcheckrc : au moins une vérification optionnelle activée" \
  grep -Eq '^[[:space:]]*enable[[:space:]]*=' "$_m02_repo/.shellcheckrc"
check_cmd ".editorconfig versionné à la racine du dépôt" \
  git -C "$_m02_repo" ls-files --error-unmatch .editorconfig
check_cmd ".editorconfig : dialecte shell déclaré pour shfmt (shell_variant)" \
  grep -Eq '^[[:space:]]*shell_variant[[:space:]]*=' "$_m02_repo/.editorconfig"
check_cmd ".pre-commit-config.yaml : hook ShellCheck" \
  grep -q 'shellcheck-py/shellcheck-py' "$_m02_repo/.pre-commit-config.yaml"
check_cmd ".pre-commit-config.yaml : hook shfmt" \
  grep -q 'scop/pre-commit-shfmt' "$_m02_repo/.pre-commit-config.yaml"

# --- Les scripts du dépôt respectent ces règles -------------------------------------
check_cmd "bin/ contient au moins un script" \
  bash -c 'compgen -G "$1/bin/*" >/dev/null' _ "$_m02_repo"
check_cmd "scripts de bin/ : ShellCheck ne signale rien (avec la configuration du dépôt)" \
  bash -c 'cd "$1" && shellcheck bin/*' _ "$_m02_repo"
check_cmd "scripts de bin/ : déjà formatés selon .editorconfig (shfmt -d vide)" \
  bash -c 'cd "$1" && shfmt -d bin/' _ "$_m02_repo"
check_cmd "scripts de bin/ : indentation par espaces (la configuration de shfmt est bien lue)" \
  bash -c '! grep -lP "^\t" "$1"/bin/* 2>/dev/null | grep -q .' _ "$_m02_repo"
