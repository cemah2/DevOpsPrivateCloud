# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les scripts bash -c reçoivent leurs chemins en argument ($1)
# check-E44.sh — M04-E44 « Sous le capot : AnsiballZ et un module maison » : le module
# medisphere.socle.systemd_dropin existe, se documente, déclare le mode vérification, ses tests
# unitaires passent, il est utilisé par un rôle et son effet est en place sur le socle ; l'analyse
# AnsiballZ est rédigée. Lecture seule (pytest sans fichiers .pyc : PYTHONDONTWRITEBYTECODE).

# shellcheck source=_m04-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m04-expert.sh"

title "M04-E44 — AnsiballZ et module maison"
require_cmd git ssh python3

_m04_e44_coll="$_m04x_src/collections/ansible_collections/medisphere/socle"
_m04_e44_mod="$_m04_e44_coll/plugins/modules/systemd_dropin.py"
_m04_e44_doc="$_m04x_src/docs/analyses/ansiballz.md"

_m04_e44_syntaxe() { python3 -c 'import ast, sys; ast.parse(open(sys.argv[1], encoding="utf-8").read())' "$_m04_e44_mod"; }
_m04_e44_doc_ok() { _m04x_ansible ansible-doc medisphere.socle.systemd_dropin >/dev/null 2>&1; }
_m04_e44_versionne() { git -C "$_m04x_src" ls-files --error-unmatch "$_m04_e44_mod" >/dev/null 2>&1; }
_m04_e44_pytest() {
  ls "$_m04_e44_coll"/tests/unit/plugins/modules/test_*.py >/dev/null 2>&1 || return 1
  (cd "$_m04x_src/collections" && PYTHONDONTWRITEBYTECODE=1 "$_m04x_src/.venv/bin/python" -m pytest -q \
    -p no:cacheprovider ansible_collections/medisphere/socle/tests/unit/plugins/modules) >/dev/null 2>&1
}
_m04_e44_reponses() {
  [[ -f "$_m04_e44_doc" ]] || return 1
  awk '/^## Réponses aux questions/ { r = 1; next } /^## / { r = 0 } r && /^[0-9]+\. / { n++ } END { exit !(n >= 8) }' "$_m04_e44_doc"
}

check_cmd "module plugins/modules/systemd_dropin.py présent dans la collection medisphere.socle" test -f "$_m04_e44_mod"
check_cmd "module : syntaxe Python valide" _m04_e44_syntaxe
check_cmd "module : ansible-doc medisphere.socle.systemd_dropin lit sa documentation" _m04_e44_doc_ok
check_cmd "module : déclare le mode vérification (supports_check_mode=True)" \
  grep -Eq 'supports_check_mode[[:space:]]*=[[:space:]]*True' "$_m04_e44_mod"
check_cmd "module : gère --diff (module._diff)" grep -q '_diff' "$_m04_e44_mod"
check_cmd "module : versionné dans plateforme/ansible" _m04_e44_versionne
if [[ -x "$_m04x_src/.venv/bin/python" ]] && "$_m04x_src/.venv/bin/python" -c 'import pytest' >/dev/null 2>&1; then
  check_cmd "tests unitaires du module (pytest) : présents et verts" _m04_e44_pytest
else
  skip "tests unitaires du module" "pytest absent de l'environnement du projet (dépendance de développement à ajouter)"
fi
check_cmd "un rôle du projet utilise medisphere.socle.systemd_dropin" \
  bash -c 'grep -rqs "medisphere\.socle\.systemd_dropin" "$1/roles"' _ "$_m04x_src"
for _m04_e44_h in gw01 dns01 git01 runner01; do
  check_ssh_output "$_m04_e44_h : chrony redémarre seul en cas d'échec (Restart=on-failure)" "$_m04_e44_h" \
    '^on-failure$' 'systemctl show chrony.service -p Restart --value'
done
check_output "adm01 : chrony redémarre seul en cas d'échec (Restart=on-failure)" '^on-failure$' \
  systemctl show chrony.service -p Restart --value
check_cmd "docs/analyses/ansiballz.md : section « Réponses aux questions », au moins 8 réponses" _m04_e44_reponses
