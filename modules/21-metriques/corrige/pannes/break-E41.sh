# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# break-E41.sh — M21-E41 « Panne : une règle ne se charge pas »
#
# Lucas ajoute pour l'équipe MédiAgenda une règle d'alerte d'équipe (PrometheusRule « mediagenda-valkey »,
# alerte MediagendaValkeyMemoireHaute) dans le composant components/supervision de mediagenda/deploiement
# (MR fusionnée : le pipeline de ce dépôt ne fait que kustomize build et kubeconform). La règle part en
# dev et en recette ; elle ne se charge jamais dans Prometheus :
#   1. elle ne porte pas l'étiquette exigée par ruleSelector (« oubliée ») ;
#   2. elle porte l'étiquette, mais l'espace mediagenda-dev a perdu l'étiquette exigée par
#      ruleNamespaceSelector (« ménage des étiquettes d'espace », fait à la main par Lucas) ;
#   3. son expression PromQL ne se lit pas : le webhook d'admission de prometheus-operator la refuse,
#      la synchronisation d'Argo CD échoue pour mediagenda-dev et mediagenda-recette.
# Annulation : MR inverse qui retire la règle et sa ligne du kustomization.yaml SEULEMENT si le fichier
# est encore celui de Lucas (sinon la réparation de l'apprenant est gardée) ; étiquettes d'espace remises
# si l'annotation de la panne est encore là.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m21-commun.sh
source "$WB_ROOT/modules/21-metriques/corrige/pannes/_m21-commun.sh"

_E41_ALERTE=MediagendaValkeyMemoireHaute
_E41_NS=mediagenda-dev
_E41_MARQUE="medisphere.internal/nettoyage-etiquettes"

# _e41_regle N — manifeste de la règle de Lucas pour la variante N.
_e41_regle() {
  local n="$1" etiq expr
  if ((n == 1)); then
    etiq='{"app.kubernetes.io/part-of": "mediagenda", "medisphere.internal/equipe": "mediagenda"}'
  else
    etiq="$(m21_etiquettes_objet ruleSelector | jq -c '. + {"app.kubernetes.io/part-of": "mediagenda", "medisphere.internal/equipe": "mediagenda"}')"
  fi
  if ((n == 3)); then
    expr='max by (namespace, pod) container_memory_working_set_bytes{namespace=~"mediagenda-.*", container="valkey"}
  / on (namespace, pod, container)
  kube_pod_container_resource_limits{namespace=~"mediagenda-.*", container="valkey", resource="memory"} > 0.9'
  else
    expr='max by (namespace, pod) (
  container_memory_working_set_bytes{namespace=~"mediagenda-.*", container="valkey"}
  / on (namespace, pod, container)
  kube_pod_container_resource_limits{namespace=~"mediagenda-.*", container="valkey", resource="memory"}
) > 0.9'
  fi
  jq -n --argjson l "$etiq" --arg e "$expr" --arg a "$_E41_ALERTE" '{
    apiVersion: "monitoring.coreos.com/v1", kind: "PrometheusRule",
    metadata: {name: "mediagenda-valkey", labels: $l},
    spec: {groups: [{name: "mediagenda-valkey", rules: [{
      alert: $a, expr: $e, for: "10m",
      labels: {gravite: "avertissement", equipe: "mediagenda"},
      annotations: {
        resume: "Valkey de {{ $labels.namespace }} au-delà de 90 % de sa limite mémoire",
        description: "Le pod {{ $labels.pod }} utilise {{ $value | humanizePercentage }} de sa limite mémoire depuis 10 min : risque d\u0027éviction des sessions.",
        runbook_url: "https://git01.par1.medisphere.internal/plateforme/medisphere/-/blob/main/docs/observabilite/metriques/runbooks/RB-211-mediagenda-erreurs.md"}}]}]}}' |
    yq -P -o=yaml '.'
}

# _e41_composant — « dossier kustomization » du composant de supervision de mediagenda/deploiement.
_e41_composant() {
  local k
  for k in components/supervision/kustomization.yaml components/supervision/kustomization.yml; do
    if m21_git_lire "$_M21_PROJ_DEP" "$k" >/dev/null 2>&1; then
      printf '%s %s\n' "${k%/*}" "$k"
      return 0
    fi
  done
  k="$(m21_git_trouver "$_M21_PROJ_DEP" '.kind == "Component" and ((.resources // []) | length > 0)' components)" || return 1
  printf '%s %s\n' "${k%/*}" "$k"
}

_e41_regle_chargee() {
  m21_prom_api 'rules?type=alert' 2>/dev/null | jq -e --arg a "$_E41_ALERTE" '[.data.groups[]?.rules[]? | select(.name == $a)] | length > 0' >/dev/null 2>&1
}
_e41_objet_present() { wb_kubectl -n "$_E41_NS" get prometheusrules.monitoring.coreos.com mediagenda-valkey >/dev/null 2>&1; }
_e41_effet() {
  case "$1" in
    1 | 2) _e41_objet_present && sleep 120 && ! _e41_regle_chargee ;;
    3) m21_app_synchro_echouee "$_E41_NS" && ! _e41_objet_present ;;
  esac
}

_m21E41_une() {
  local n="$1" l dir kust t act sha cles k
  m21_ecrire E41 variante "$n"
  m21_espace_retenu ruleNamespaceSelector "$_E41_NS" || return 10
  _e41_regle_chargee && return 10
  m21_app_json "$_E41_NS" | jq -e '.spec.syncPolicy.automated' >/dev/null 2>&1 || return 10
  if ((n == 2)); then
    cles="$(m21_prom_cr_json | jq -r '.spec.ruleNamespaceSelector.matchLabels // {} | keys[]')"
    [[ -n "$cles" ]] || return 10
  fi
  l="$(_e41_composant)" || return 10
  read -r dir kust <<<"$l"
  m21_git_lire "$_M21_PROJ_DEP" "$dir/regle-valkey.yaml" >/dev/null 2>&1 && return 10
  t="$(mktemp -d)"
  _e41_regle "$n" >"$t/regle.yaml"
  m21_git_lire "$_M21_PROJ_DEP" "$kust" | yq '.resources += ["regle-valkey.yaml"]' >"$t/kust.yaml" || { rm -rf -- "$t"; return 10; }
  sha256sum "$t/regle.yaml" | cut -d' ' -f1 >"$(m21_etat E41)/empreinte"
  m21_ecrire E41 fichiers "$dir/regle-valkey.yaml $kust"
  act="$(jq -n --arg r "$dir/regle-valkey.yaml" --arg k "$kust" --rawfile rc "$t/regle.yaml" --rawfile kc "$t/kust.yaml" '
    [{action: "create", file_path: $r, content: $rc}, {action: "update", file_path: $k, content: $kc}]')"
  rm -rf -- "$t"
  if ((n == 2)); then
    m21_sauver_objet E41 namespace "$_E41_NS"
    m21_ecrire E41 etiquettes "$(wb_kubectl get namespace "$_E41_NS" -o json | jq -c --arg c "$cles" '.metadata.labels as $l | [$c | split("\n")[] | select(. != "") | {(.): $l[.]}] | add')"
    for k in $cles; do
      wb_kubectl label namespace "$_E41_NS" "$k-" >/dev/null || return 1
    done
    wb_kubectl annotate namespace "$_E41_NS" "$_E41_MARQUE=PLAT-2241 lucas.martin" --overwrite >/dev/null || return 1
    m21_journal E41 "variante 2 : étiquettes $cles retirées de $_E41_NS"
  fi
  sha="$(m21_git_livrer "$_M21_PROJ_DEP" "feat(supervision): alerte mémoire Valkey pour l'équipe (M21-E41)" "$act")" || {
    local rc=$?
    m21_oublier E41 fichiers
    _e41_defaire_espace
    return "$rc"
  }
  m21_ecrire E41 livre oui
  m21_apps_attendre "$_M21_PROJ_DEP" "$sha"
  m21_journal E41 "variante $n posée (${sha:0:8})"
  m21_attendre 240 _e41_effet "$n" || { _e41_defaire; return 10; }
}

_e41_defaire_espace() {
  local j e
  j="$(wb_kubectl get namespace "$_E41_NS" -o json 2>/dev/null)" || return 0
  e="$(m21_lire E41 etiquettes)"
  if jq -e --arg m "$_E41_MARQUE" '.metadata.annotations[$m] != null' >/dev/null 2>&1 <<<"$j"; then
    if [[ -n "$e" && "$e" != null ]]; then
      # shellcheck disable=SC2046  # une étiquette par mot
      wb_kubectl label namespace "$_E41_NS" $(jq -r 'to_entries[] | "\(.key)=\(.value)"' <<<"$e") --overwrite >/dev/null 2>&1 ||
        wb_avert "étiquettes de $_E41_NS non rétablies ($e)"
    fi
    wb_kubectl annotate namespace "$_E41_NS" "$_E41_MARQUE-" >/dev/null 2>&1 || true
  fi
  m21_oublier_objet E41 namespace "$_E41_NS"
  m21_oublier E41 etiquettes
}

_e41_defaire() {
  local f r k emp t act sha
  _e41_defaire_espace
  f="$(m21_lire E41 fichiers)"
  [[ -n "$f" && "$(m21_lire E41 livre)" == oui ]] || { m21_oublier E41 fichiers; return 0; }
  read -r r k <<<"$f"
  emp="$(cat "$(m21_etat E41)/empreinte" 2>/dev/null)" || emp=""
  t="$(mktemp -d)"
  if m21_git_lire "$_M21_PROJ_DEP" "$r" >"$t/regle.yaml" 2>/dev/null &&
    [[ "$(sha256sum "$t/regle.yaml" | cut -d' ' -f1)" == "$emp" ]] &&
    m21_git_lire "$_M21_PROJ_DEP" "$k" | yq 'del(.resources[] | select(. == "regle-valkey.yaml"))' >"$t/kust.yaml"; then
    act="$(jq -n --arg r "$r" --arg k "$k" --rawfile kc "$t/kust.yaml" '
      [{action: "delete", file_path: $r}, {action: "update", file_path: $k, content: $kc}]')"
    if sha="$(m21_git_livrer "$_M21_PROJ_DEP" "revert(supervision): règle Valkey de Lucas retirée (M21-E41, annulation)" "$act" workbook)"; then
      m21_apps_attendre "$_M21_PROJ_DEP" "$sha"
    else
      wb_avert "MR d'annulation refusée sur $_M21_PROJ_DEP : retire $r à la main"
    fi
  else
    m21_journal E41 "annulation : la règle a été modifiée par l'apprenant, elle est gardée"
  fi
  rm -rf -- "$t"
  m21_oublier E41 fichiers
  m21_oublier E41 livre
  rm -f -- "$(m21_etat E41)/empreinte"
}

panne_E41_v1() { m21_preparer && m21_essayer E41 3 1; }
panne_E41_v2() { m21_preparer && m21_essayer E41 3 2; }
panne_E41_v3() { m21_preparer && m21_essayer E41 3 3; }

verifier_E41() {
  case "$WB_VAR" in
    3) m21_app_synchro_echouee "$_E41_NS" ;;
    *) _e41_objet_present && ! _e41_regle_chargee ;;
  esac
}

annuler_E41() {
  _e41_defaire
  m21_oublier E41 variante
  m21_journal E41 "annulation"
}

resume_E41() {
  case "${WB_VAR:-}" in
    3) echo "Argo CD signale mediagenda-dev et mediagenda-recette en échec de synchronisation depuis la MR de Lucas." ;;
    *) echo "La nouvelle alerte d'équipe MediagendaValkeyMemoireHaute n'apparaît pas dans Prometheus." ;;
  esac
}

symptome_E41() {
  local l
  case "${WB_VAR:-}" in
    3) l="Argo CD affiche mediagenda-dev et mediagenda-recette en échec de synchronisation, et j'ai reçu ses courriels." ;;
    *) l="Argo CD est tout vert, l'objet existe dans mediagenda-dev, mais l'alerte n'est nulle part dans Prometheus." ;;
  esac
  wb_symptome "Ticket INC-4841 — De : Julien Petit" \
    "Lucas nous a ajouté hier une alerte d'équipe, MediagendaValkeyMemoireHaute (MR fusionnée dans" \
    "mediagenda/deploiement, pipeline vert). $l" \
    "On a eu une éviction de Valkey cette nuit sans alerte. Je veux cette règle chargée en dev et en" \
    "recette, et une protection pour que ça ne se reproduise pas." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 21 41"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 21 E41 3 "$@"; }
fi
