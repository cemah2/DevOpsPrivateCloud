# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E38.sh — M02-E38 « Panne : rouge en CI, vert en local »
#
# Agit sur GitLab (projet plateforme/outils) par l'API, avec le jeton d'administration de
# l'apprenant (WB_GITLAB_ADMIN_TOKEN_FILE). Variantes 1 à 3 : Lucas (jeton d'emprunt
# d'identité, révoqué à l'annulation) pousse une branche et ouvre une MR dont le pipeline
# échoue sur runner01 alors que tout passe sur adm01 :
#   1. dépendance ajoutée dans pyproject.toml (tabulate) SANS mettre à jour uv.lock : en local,
#      « uv run » reverrouille en silence ; en CI, « uv sync --locked » refuse ;
#   2. test pytest qui appelle le vrai « medictl vm list » : en local il lit
#      ~/.config/workbook/pve-api.env et interroge Proxmox ; en CI, pas de configuration ;
#   3. test pytest qui dépend de yq, présent sur adm01 (M02-E06), absent de runner01.
# Variante 4 : variable CI de GROUPE « SHELLCHECK_OPTS=--enable=all --severity=style » sur
#   plateforme (ShellCheck la lit) : tous les pipelines du groupe rougissent sur le lint
#   ShellCheck, main compris ; en local, rien. Un pipeline est relancé sur main.
# Vérification : le pipeline concerné se termine en échec (attente jusqu'à 20 min).
# État local : ~/.local/state/workbook/M02-E38.etat (600) — identifiants à défaire à l'annulation.
# Jamais de suppression de projet ; seules la branche et la MR créées par la panne sont retirées.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"

_E38_PROJ="plateforme%2Foutils"
_E38_GROUPE="plateforme"
_E38_ETAT="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/M02-E38.etat"
_E38_URL="${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}/api/v4"
_E38_JETON_LUCAS=""

# _e38_api [--lucas] MÉTHODE CHEMIN [options curl…] — appel de l'API ; le jeton ne passe
# jamais en argument (en-tête lu depuis un descripteur).
_e38_api() {
  local jeton
  if [[ "$1" == --lucas ]]; then
    shift
    jeton="$_E38_JETON_LUCAS"
  else
    jeton="$(<"${WB_GITLAB_ADMIN_TOKEN_FILE:-$HOME/.config/workbook/gitlab-admin.token}")" || return 1
  fi
  local m="$1" p="$2"
  shift 2
  curl -sS --fail --max-time 30 -X "$m" -H @<(printf 'PRIVATE-TOKEN: %s\n' "$jeton") "$_E38_URL/$p" "$@"
}

_e38_etat() { # _e38_etat CLÉ [VALEUR] — lit ou écrit une valeur de l'état local
  if (($# == 2)); then
    mkdir -p "$(dirname "$_E38_ETAT")"
    (umask 077 && printf '%s=%s\n' "$1" "$2" >>"$_E38_ETAT")
  else
    [[ -f "$_E38_ETAT" ]] && sed -n "s/^$1=//p" "$_E38_ETAT" | tail -n 1
  fi
}

_e38_precondition() {
  local st
  command -v jq >/dev/null || { wb_avert "jq absent"; return 1; }
  st="$(_e38_api GET "projects/$_E38_PROJ/pipelines?ref=main&per_page=1" | jq -r '.[0].status // "aucun"')" \
    || { wb_avert "API GitLab inaccessible avec le jeton d'administration"; return 1; }
  [[ "$st" == success ]] || { wb_avert "le dernier pipeline de main n'est pas vert ($st) : lab/bin/check 02 38"; return 1; }
}

# _e38_lucas — crée un jeton d'emprunt d'identité pour lucas.martin (expire demain).
_e38_lucas() {
  local uid rep
  uid="$(_e38_api GET 'users?username=lucas.martin' | jq -r '.[0].id // empty')"
  [[ -n "$uid" ]] || { wb_avert "compte lucas.martin introuvable (M01-E05)"; return 1; }
  rep="$(_e38_api POST "users/$uid/impersonation_tokens" \
    --data-urlencode "name=workbook-M02-E38" --data-urlencode "scopes[]=api" \
    --data-urlencode "expires_at=$(date -d tomorrow +%F)")" || return 1
  _E38_JETON_LUCAS="$(jq -r '.token' <<<"$rep")"
  _e38_etat uid "$uid"
  _e38_etat jeton_id "$(jq -r '.id' <<<"$rep")"
}

# _e38_mr BRANCHE TITRE DESCRIPTION ACTIONS_JSON — branche + commit + MR au nom de Lucas.
_e38_mr() {
  local br="$1" titre="$2" desc="$3" actions="$4" corps sha iid
  _e38_lucas || return 1
  _e38_api --lucas POST "projects/$_E38_PROJ/repository/branches" \
    --data-urlencode "branch=$br" --data-urlencode "ref=main" >/dev/null || return 1
  _e38_etat branche "$br"
  corps="$(jq -n --arg b "$br" --arg m "$titre" --argjson a "$actions" \
    '{branch: $b, commit_message: $m, actions: $a}')"
  sha="$(_e38_api --lucas POST "projects/$_E38_PROJ/repository/commits" \
    -H 'Content-Type: application/json' --data "$corps" | jq -r '.id')" || return 1
  _e38_etat sha "$sha"
  iid="$(_e38_api --lucas POST "projects/$_E38_PROJ/merge_requests" \
    --data-urlencode "source_branch=$br" --data-urlencode "target_branch=main" \
    --data-urlencode "title=$titre" --data-urlencode "description=$desc" \
    --data-urlencode "remove_source_branch=true" | jq -r '.iid')" || return 1
  _e38_etat mr "$iid"
}

# _e38_action create|update CHEMIN FICHIER_LOCAL — objet JSON d'une action de commit.
_e38_action() {
  jq -n --arg a "$1" --arg p "$2" --rawfile c "$3" '{action: $a, file_path: $p, content: $c}'
}

panne_E38_v1() {
  _e38_precondition || return 1
  local t actions
  t="$(mktemp -d)"
  if ! _e38_api GET "projects/$_E38_PROJ/repository/files/pyproject.toml/raw?ref=main" >"$t/pyproject.toml"; then
    rm -rf -- "$t"
    return 1
  fi
  python3 - "$t/pyproject.toml" <<'PY' || { wb_avert "pyproject.toml : section dependencies introuvable"; rm -rf -- "$t"; return 1; }
import re, sys, tomllib
chemin = sys.argv[1]
texte = open(chemin, encoding="utf-8").read()
m = re.search(r'^dependencies\s*=\s*\[', texte, re.M)
if not m or "tabulate" in texte:
    sys.exit(1)
fin = texte.index("]", m.end())
interieur = texte[m.end():fin]
if "\n" in interieur:
    avant = texte[:fin].rstrip()
    if not avant.endswith((",", "[")):
        avant += ","
    nouveau = avant + '\n    "tabulate>=0.9",\n' + texte[fin:]
else:
    sep = ", " if interieur.strip() else ""
    nouveau = texte[:fin] + sep + '"tabulate>=0.9"' + texte[fin:]
tomllib.loads(nouveau)
open(chemin, "w", encoding="utf-8").write(nouveau)
PY
  cat >"$t/rapport.py" <<'PY'
"""Rendu tabulaire des rapports de medictl (PLAT-380)."""

from tabulate import tabulate


def tableau(lignes: list[dict[str, object]]) -> str:
    """Rend une liste de dictionnaires en tableau Markdown (colonnes = clés)."""
    if not lignes:
        return ""
    return tabulate(lignes, headers="keys", tablefmt="github")
PY
  cat >"$t/test_rapport.py" <<'PY'
"""Tests du rendu tabulaire (PLAT-380)."""

from medictl.rapport import tableau


def test_tableau_vide() -> None:
    assert tableau([]) == ""


def test_tableau_entetes() -> None:
    sortie = tableau([{"vmid": 1002, "nom": "dns01"}])
    assert "vmid" in sortie.splitlines()[0]
PY
  actions="$(jq -s '.' <(_e38_action update pyproject.toml "$t/pyproject.toml") \
    <(_e38_action create src/medictl/rapport.py "$t/rapport.py") \
    <(_e38_action create tests/python/test_rapport.py "$t/test_rapport.py"))"
  local rc=0
  _e38_mr lucas/rendu-tableau "feat(medictl): rendu tabulaire des rapports" \
    "Ajoute medictl.rapport.tableau() (tabulate) pour les sorties Markdown. Testé en local : task test OK." \
    "$actions" || rc=$?
  rm -rf -- "$t"
  return "$rc"
}

panne_E38_v2() {
  _e38_precondition || return 1
  local t actions
  t="$(mktemp -d)"
  cat >"$t/test_cli_vm_list.py" <<'PY'
"""Test de bout en bout de « medictl vm list » (PLAT-380)."""

import json
import shutil
import subprocess


def test_vm_list_json_valide() -> None:
    medictl = shutil.which("medictl")
    assert medictl is not None
    resultat = subprocess.run(
        [medictl, "vm", "list", "--pool", "lab", "--format", "json"],
        capture_output=True,
        text=True,
        check=False,
        timeout=60,
    )
    assert resultat.returncode == 0, resultat.stderr
    assert json.loads(resultat.stdout) is not None
PY
  actions="$(jq -s '.' <(_e38_action create tests/python/test_cli_vm_list.py "$t/test_cli_vm_list.py"))"
  local rc=0
  _e38_mr lucas/test-vm-list "test(medictl): test de bout en bout de vm list" \
    "Vérifie que la sortie JSON de « vm list » est valide. Testé en local : task test OK." \
    "$actions" || rc=$?
  rm -rf -- "$t"
  return "$rc"
}

panne_E38_v3() {
  _e38_precondition || return 1
  local t actions
  t="$(mktemp -d)"
  cat >"$t/test_taskfile.py" <<'PY'
"""Le Taskfile expose les tâches standard de l'équipe (PLAT-380)."""

import subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parents[2]


def test_taches_standard_presentes() -> None:
    requete = '.tasks | has("lint") and has("test") and has("build")'
    resultat = subprocess.run(
        ["yq", "-e", requete, str(RACINE / "Taskfile.yml")],
        capture_output=True,
        text=True,
        check=False,
    )
    assert resultat.returncode == 0, resultat.stderr
PY
  actions="$(jq -s '.' <(_e38_action create tests/python/test_taskfile.py "$t/test_taskfile.py"))"
  local rc=0
  _e38_mr lucas/test-taskfile "test: vérifier les tâches standard du Taskfile" \
    "Garde-fou : lint, test et build doivent exister dans le Taskfile. Testé en local : task test OK." \
    "$actions" || rc=$?
  rm -rf -- "$t"
  return "$rc"
}

panne_E38_v4() {
  _e38_precondition || return 1
  if _e38_api GET "groups/$_E38_GROUPE/variables/SHELLCHECK_OPTS" >/dev/null 2>&1; then
    wb_avert "une variable SHELLCHECK_OPTS existe déjà sur le groupe $_E38_GROUPE"
    return 1
  fi
  _e38_api POST "groups/$_E38_GROUPE/variables" \
    --data-urlencode "key=SHELLCHECK_OPTS" --data-urlencode "value=--enable=all --severity=style" \
    --data-urlencode "description=SEC-382 : ShellCheck au niveau d'exigence maximal pour tout le groupe" \
    >/dev/null || return 1
  _e38_etat variable SHELLCHECK_OPTS
  _e38_etat pipeline "$(_e38_api POST "projects/$_E38_PROJ/pipeline?ref=main" | jq -r '.id')"
}

# verifier_E38 — le pipeline visé échoue (attente bornée à 20 minutes).
verifier_E38() {
  local sha pid st fin=$((SECONDS + 1200))
  sha="$(_e38_etat sha)"
  pid="$(_e38_etat pipeline)"
  echo "Attente du pipeline sur runner01 (jusqu'à 20 min)…" >&2
  while ((SECONDS < fin)); do
    if [[ -n "$pid" ]]; then
      st="$(_e38_api GET "projects/$_E38_PROJ/pipelines/$pid" | jq -r '.status')"
    elif [[ -n "$sha" ]]; then
      st="$(_e38_api GET "projects/$_E38_PROJ/pipelines?sha=$sha" | jq -r '[.[].status] | if index("failed") then "failed" elif length > 0 and all(. == "success" or . == "skipped" or . == "canceled") then "success" else "en cours" end')"
    else
      return 1
    fi
    case "$st" in
      failed) return 0 ;;
      success | skipped | canceled) return 1 ;;
    esac
    sleep 20
  done
  return 1
}

annuler_E38() {
  local br mr uid jid var
  br="$(_e38_etat branche)"
  mr="$(_e38_etat mr)"
  uid="$(_e38_etat uid)"
  jid="$(_e38_etat jeton_id)"
  var="$(_e38_etat variable)"
  if [[ -n "$mr" ]]; then
    _e38_api PUT "projects/$_E38_PROJ/merge_requests/$mr" --data-urlencode "state_event=close" >/dev/null 2>&1 || true
  fi
  if [[ -n "$br" ]]; then
    _e38_api DELETE "projects/$_E38_PROJ/repository/branches/${br//\//%2F}" >/dev/null 2>&1 || true
  fi
  if [[ -n "$uid" && -n "$jid" ]]; then
    _e38_api DELETE "users/$uid/impersonation_tokens/$jid" >/dev/null 2>&1 \
      || wb_avert "jeton d'emprunt d'identité $jid non révoqué : retire-le dans Admin > Users > lucas.martin"
  fi
  if [[ -n "$var" ]]; then
    _e38_api DELETE "groups/$_E38_GROUPE/variables/$var" >/dev/null 2>&1 || true
  fi
  rm -f -- "$_E38_ETAT"
}

resume_E38() {
  # shellcheck disable=SC2031
  if [[ "${WB_VAR:-}" == 4 ]]; then
    echo "Tous les pipelines de plateforme/outils sont rouges sur le lint, même main, alors que tout est vert en local."
  else
    echo "La MR de Lucas sur plateforme/outils est rouge en CI, alors que « task test » est vert sur adm01."
  fi
}

symptome_E38() {
  # shellcheck disable=SC2031
  if [[ "${WB_VAR:-}" == 4 ]]; then
    wb_symptome "Ticket PLAT-380 — De : Karim Benali" \
      "Depuis ce matin, tous les pipelines de plateforme/outils sont rouges, main compris," \
      "alors que personne n'a poussé sur main et que « task lint » est vert sur adm01. Je" \
      "ne peux plus rien fusionner. Trouve ce qui diffère entre la CI et nos postes." \
      "" \
      "Temps cible : 30 min. Contrôle : lab/bin/check 02 38"
  else
    wb_symptome "Ticket PLAT-380 — De : Lucas Martin" \
      "Ma MR sur plateforme/outils (branche $(_e38_etat branche)) est rouge en CI, mais chez" \
      "moi tout passe : « task test » est vert sur adm01, je l'ai lancé trois fois. C'est" \
      "runner01 qui doit avoir un problème ? Tu peux regarder ? J'aimerais la fusionner aujourd'hui." \
      "" \
      "Temps cible : 30 min. Contrôle : lab/bin/check 02 38"
  fi
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 02 E38 4 "$@"; }
fi
