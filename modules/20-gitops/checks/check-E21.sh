# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-E21.sh — M20-E21 « Revue : les Applications du stagiaire ». Contrôle la version CORRIGÉE déposée
# dans ~/m20/e21/corrige/ (fichiers YAML lus localement, rien n'est appliqué). La revue elle-même
# (~/m20/e21/revue.md) est auto-évaluée avec le corrigé ; on vérifie seulement qu'elle est complète.

# shellcheck source=_m20-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m20-operationnel.sh"

title "M20-E21 — Revue : les Applications du stagiaire"
require_cmd jq yq

_e21_d="$_m20o_brouillons/e21"
_e21_lignes() {
  local n
  n="$(grep -Ec '^\|[[:space:]]*[0-9]+' "$_e21_d/revue.md" 2>/dev/null)" || n=0
  (( n >= 10 ))
}
check_cmd "revue.md : au moins 10 défauts numérotés dans le tableau" _e21_lignes
check_cmd "revue.md : le mot de passe exposé est à CHANGER (pas seulement à retirer de Git)" \
  _m20o_fichier_contient "$_e21_d/revue.md" '(chang|rotation|renouvel)[a-z]* (le |du )?mot de passe|mot de passe[^|]*(chang|rotation|renouvel)'

shopt -s nullglob
_e21_f=("$_e21_d"/corrige/*.yaml "$_e21_d"/corrige/*.yml)
shopt -u nullglob
check_cmd "version corrigée : fichiers YAML présents dans $_e21_d/corrige/" test "${#_e21_f[@]}" -gt 0
if (( ${#_e21_f[@]} == 0 )); then
  skip "contrôles de la version corrigée" "aucun fichier dans $_e21_d/corrige/"
else
  _e21_j="$(_m20o_yaml_json "${_e21_f[@]}")"
  # Les Applications et les gabarits d'ApplicationSet, ramenés à une liste de « spec » d'Application.
  _e21_specs='[.[] | if .kind == "Application" then {nom: .metadata.name, fin: (.metadata.finalizers // []), spec: .spec}
    elif .kind == "ApplicationSet" then {nom: .metadata.name, fin: (.spec.template.metadata.finalizers // []), spec: .spec.template.spec, appset: .spec}
    else empty end]'
  check_cmd "version corrigée : au moins un ApplicationSet et une Application" \
    _m20o_jq "$_e21_j" '([.[] | select(.kind == "ApplicationSet")] | length >= 1) and ([.[] | select(.kind == "Application")] | length >= 1)'
  check_cmd "aucun Secret" _m20o_jq "$_e21_j" '[.[] | select(.kind == "Secret")] | length == 0'
  check_cmd "aucun projet « default »" _m20o_jq "$_e21_j" "$_e21_specs"' | all(.spec.project != "default" and .spec.project != null)'
  check_cmd "aucune révision flottante (HEAD, *, latest)" \
    _m20o_jq "$_e21_j" '[.. | objects | (.targetRevision?, .revision?) | strings] | all(test("^(HEAD|\\*|latest)$") | not)'
  check_cmd "aucune source hors de git01 et du registre MédiSphère" \
    _m20o_jq "$_e21_j" '[.. | objects | .repoURL? | strings] | all(test("^(https://git01\\.par1\\.medisphere\\.internal/|registry\\.par1\\.medisphere\\.internal/)"))'
  # Options de synchronisation : celles de l'Application, ou celles du gabarit ET du templatePatch
  # (texte) d'un ApplicationSet.
  _e21_opts='[.[] | if .kind == "Application" then ((.spec.syncPolicy.syncOptions // []) | join(" "))
    elif .kind == "ApplicationSet" then (((.spec.template.spec.syncPolicy.syncOptions // []) | join(" ")) + " " + (.spec.templatePatch // ""))
    else empty end]'
  check_cmd "ServerSideApply=true partout, CreateNamespace jamais à true, ni Replace=true" \
    _m20o_jq "$_e21_j" "$_e21_opts"' | length > 0 and all(test("ServerSideApply=true") and (test("CreateNamespace=true") | not) and (test("Replace=true") | not))'
  check_cmd "aucune ignoreDifferences sur /spec entier ni sans nom d'objet" \
    _m20o_jq "$_e21_j" '[.. | objects | .ignoreDifferences? | arrays | .[]] | all((.name // "") != "" and ((.jsonPointers // []) | index("/spec") == null))'
  check_cmd "aucun allowEmpty, aucune réessai infini (retry.limit < 0)" \
    _m20o_jq "$_e21_j" '[.. | objects | select(has("allowEmpty")) | .allowEmpty] | all(. != true)
      and ([.. | objects | .retry? | objects | .limit // 0] | all(. >= 0))'
  check_cmd "goTemplate : pas de syntaxe {{path…}} sans point" \
    _m20o_jq "$_e21_j" '[.[] | select(.kind == "ApplicationSet" and .spec.goTemplate == true) | tostring | test("\\{\\{ *path")] | all(. == false)'
  check_cmd "prod : aucune synchronisation automatique" \
    _m20o_jq "$_e21_j" '[.[] | select(.kind == "Application" and (.metadata.name | test("prod"))) | .spec.syncPolicy.automated // null] | all(. == null)
      and ([.[] | select(.kind == "ApplicationSet") | .spec.generators[]?.list.elements[]? | select((.env // "") == "prod") | (.auto // false)] | all(. == false))'
  check_cmd "ApplicationSet : create-update et preserveResourcesOnDeletion" \
    _m20o_jq "$_e21_j" '[.[] | select(.kind == "ApplicationSet") | .spec.syncPolicy] | all(.applicationsSync == "create-update" and .preserveResourcesOnDeletion == true)'
  check_cmd "une seule définition de chaque Application (aucune Application déjà générée par un ApplicationSet)" \
    _m20o_jq "$_e21_j" '[.[] | select(.kind == "ApplicationSet") | .metadata.name + "-"] as $p
      | [.[] | select(.kind == "Application") | .metadata.name | select(. as $n | $p | any(. as $q | $n | startswith($q)))] | length == 0'
  check_cmd "multi-sources : chaque \$ref utilisée est déclarée par une source « ref »" \
    _m20o_jq "$_e21_j" '[.[] | select(.kind == "Application") | .spec.sources? | arrays
      | ([.[] | .ref? | strings]) as $r | [.[] | .helm?.valueFiles? | arrays | .[] | select(startswith("$")) | ltrimstr("$") | split("/")[0]]
      | all(. as $x | $r | index($x))] | all'
fi
