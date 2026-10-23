# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq, yq et commandes distantes entre apostrophes
# _m29-expert.sh — fonctions partagées par les vérifications du palier 4 et du mini-projet du module 29
# (check-E19 à check-E25). Sourcé, jamais lancé seul. S'appuie sur _m29-production.sh (préfixe _m29p_).
# Lecture seule : « kube » (wb-checks), GitLab en GET, SSH + sudo -n de commandes de CONSULTATION sur les
# nœuds (crictl, nsenter … tc qdisc show) et les VMs, SSH root sur pve01 pour pvesh/qm en lecture,
# conftest et opa sur une copie locale temporaire des politiques. Préfixe _m29x_.

# shellcheck source=_m29-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m29-production.sh"

_m29x_politiques="${WB_M29_PROJET_POLITIQUES:-plateforme/politiques}"
_m29x_infra="${WB_M29_PROJET_INFRA:-plateforme/infra}"
_m29x_ci="${WB_M29_PROJET_CI_TEMPLATES:-plateforme/ci-templates}"
_m29x_composant="${WB_M29_COMPOSANT_VALIDATION:-templates/validation/template.yml}"
_m29x_plan="${WB_M29_E19_PLAN:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/ressources/E19-plan-dangereux/plan-dangereux.json}"
_m29x_api_sel='app.kubernetes.io/name=mediagenda,app.kubernetes.io/component=api'

# _m29x_aucune_panne_active [EXX…] — aucune des pannes listées (ou M29-* si aucune) n'est marquée.
_m29x_aucune_panne_active() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives" e
  if (($# == 0)); then
    [[ -z "$(find "$d" -maxdepth 1 -name 'M29-E*' 2>/dev/null)" ]]
    return
  fi
  for e in "$@"; do
    [[ ! -e "$d/M29-$e" ]] || return 1
  done
}

# _m29x_hote HÔTE 'commande' — commande de LECTURE en root (sudo -n) sur un nœud ou une VM ; code.
_m29x_hote() { remote "$1" "sudo -n bash -c $(printf '%q' "$2")" </dev/null >/dev/null 2>&1; }

# --- Politiques (E19, E25) ----------------------------------------------------------------------------

_m29x_tmp="${_m29x_tmp:-}"   # gardé si le fichier est sourcé plusieurs fois (mini-projet)
_m29x_tmpdir() {
  if [[ -z "$_m29x_tmp" ]]; then
    _m29x_tmp="$(mktemp -d)"
    # shellcheck disable=SC2064  # le chemin est fixé maintenant
    trap "rm -rf -- '$_m29x_tmp'" EXIT
  fi
  printf '%s\n' "$_m29x_tmp"
}

# _m29x_rapatrier_rego — copie locale de rego/ de plateforme/politiques (main) ; affiche le dossier.
_m29x_rapatrier_rego() {
  local d c
  d="$(_m29x_tmpdir)/politiques"
  if [[ ! -d "$d/rego/tofu" ]]; then
    rm -rf -- "$d"
    while IFS= read -r c; do
      [[ "$c" == rego/* ]] || continue
      mkdir -p "$d/$(dirname "$c")"
      _m29p_fichier_main "$_m29x_politiques" "$c" >"$d/$c" 2>/dev/null || return 1
    done < <(_m29p_arbre "$_m29x_politiques" rego)
  fi
  [[ -d "$d/rego/tofu" ]] && printf '%s\n' "$d"
}

# _m29x_args_conftest — arguments d'espaces de conftest de la CI de plateforme/infra (un par ligne).
# Même logique que la panne : WB_M29_CONFTEST_ARGS, sinon --all-namespaces ou --namespace X lus dans le
# .gitlab-ci.yml de plateforme/infra et le composant validation ; rien = espace « main ».
_m29x_args_conftest() {
  local texte n
  if [[ -n "${WB_M29_CONFTEST_ARGS:-}" ]]; then
    tr ' ' '\n' <<<"$WB_M29_CONFTEST_ARGS" | grep -v '^$'
    return 0
  fi
  texte="$(_m29p_fichier_main "$_m29x_infra" .gitlab-ci.yml 2>/dev/null; _m29p_fichier_main "$_m29x_ci" "$_m29x_composant" 2>/dev/null)"
  if grep -q -- '--all-namespaces' <<<"$texte"; then
    echo --all-namespaces
    return 0
  fi
  {
    grep -oE -- '--namespace[= ]+[A-Za-z0-9_.]+' <<<"$texte" | sed -E 's/--namespace[= ]+//'
    _m29p_fichier_main "$_m29x_infra" .gitlab-ci.yml 2>/dev/null |
      yq -r '[.include[]? | .inputs? // {} | to_entries[] | select(.key | test("namespace")) | .value] | flatten | .[]' 2>/dev/null |
      sed -E 's/[, ]+/\n/g'
  } | grep -E '^[A-Za-z0-9_.]+$' | sort -u | while IFS= read -r n; do
    printf -- '--namespace\n%s\n' "$n"
  done
}

# _m29x_plan_refuse — le plan de référence est refusé (au moins un FAIL) par rego/tofu de main avec
# les arguments de la CI.
_m29x_plan_refuse() {
  local d sortie rc=0
  local -a a
  [[ -r "$_m29x_plan" ]] || return 1
  d="$(_m29x_rapatrier_rego)" || return 1
  mapfile -t a < <(_m29x_args_conftest)
  sortie="$(conftest test --no-color -p "$d/rego/tofu" "${a[@]}" "$_m29x_plan" 2>&1)" || rc=$?
  ((rc != 0)) && grep -q 'FAIL' <<<"$sortie"
}

# _m29x_paquets_evalues — tous les paquets des règles (fichiers non *_test.rego) de rego/tofu sont dans
# les espaces évalués par la CI (toujours vrai avec --all-namespaces).
_m29x_paquets_evalues() {
  local d p
  local -a a esp
  d="$(_m29x_rapatrier_rego)" || return 1
  mapfile -t a < <(_m29x_args_conftest)
  printf '%s\n' "${a[@]}" | grep -qx -- '--all-namespaces' && return 0
  mapfile -t esp < <(printf '%s\n' "${a[@]}" | grep -v -- '^--namespace$')
  ((${#esp[@]} > 0)) || esp=(main)
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    printf '%s\n' "${esp[@]}" | grep -qx -- "$p" || return 1
  done < <(find "$d/rego/tofu" -name '*.rego' ! -name '*_test.rego' -exec grep -hE '^package[[:space:]]+' {} + |
           awk '{print $2}' | sort -u)
}

# _m29x_allow_failure_validation PROJET — aucun job de validation (conftest, kubeconform, politiques,
# validation:*) n'est surchargé « allow_failure: true » dans le .gitlab-ci.yml du projet.
_m29x_sans_allow_failure() {
  _m29p_fichier_main "$1" .gitlab-ci.yml 2>/dev/null |
    yq -e '[to_entries[] | select(.key | test("conftest|kubeconform|validation|politique|testinfra"))
            | select(.value.allow_failure == true)] | length == 0' >/dev/null 2>&1
}

# --- Chaos (E20, E23, E24, E25) -----------------------------------------------------------------------

# _m29x_netem ESPACE POD — 0 si un qdisc netem est posé dans l'espace réseau du pod (lecture sur le nœud).
_m29x_netem() {
  local n
  n="$(kube -n "$1" get pod "$2" -o jsonpath='{.spec.nodeName}' 2>/dev/null)" || return 1
  [[ -n "$n" ]] || return 1
  _m29x_hote "$n" "id=\$(crictl pods --namespace '$1' --name '^$2\$' --state ready -q | head -n 1);
    [ -n \"\$id\" ] || exit 1;
    pid=\$(crictl inspectp \"\$id\" | sed -n 's/.*\"pid\": *\\([0-9][0-9]*\\).*/\\1/p' | head -n 1);
    [ -n \"\$pid\" ] && nsenter -t \"\$pid\" -n tc qdisc show | grep -q netem"
}

# _m29x_api_pods — pods de l'API MédiAgenda de recette.
_m29x_api_pods() {
  kube -n "$_m29p_recette" get pods -l "$_m29x_api_sel" -o json 2>/dev/null |
    jq -r '.items[] | select(.metadata.deletionTimestamp == null) | .metadata.name'
}

# _m29x_aucun_netem_api — aucun pod de l'API de recette ne porte de netem (code 2 si aucun pod).
_m29x_aucun_netem_api() {
  local p n=0
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    n=$((n + 1))
    _m29x_netem "$_m29p_recette" "$p" && return 1
  done < <(_m29x_api_pods)
  ((n > 0)) || return 2
}

# _m29x_chaos_actifs — objets de chaos « actifs » : ni terminés, ni en pause (tableau JSON).
#   Expérience : desiredPhase == Run. Schedule : non en pause. Workflow : non terminé et non en pause.
_m29x_chaos_actifs() {
  _m29p_chaos_tous | jq '[.[] | select((.metadata.annotations["experiment.chaos-mesh.org/pause"] // "") != "true")
    | select(
        (.kind == "Schedule")
        or (.kind == "Workflow" and (any(.status.conditions[]?; .type == "Accomplished" and .status == "True") | not))
        or (.kind != "Schedule" and .kind != "Workflow" and (.status.experiment.desiredPhase // "") == "Run"))
    | {kind, ns: .metadata.namespace, nom: .metadata.name}]'
}
