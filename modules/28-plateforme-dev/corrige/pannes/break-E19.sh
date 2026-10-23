# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# break-E19.sh — M28-E19 « Panne : MédiNotif ne monte plus en charge » (RECETTE seulement).
#
# Deux variantes, toutes deux par un commit de Lucas dans l'overlay de recette de medinotif/deploiement
# (fichier kustomization.yaml de la source de l'Application qui gère le ScaledObject) :
#   1. correctif qui pose l'annotation autoscaling.keda.sh/paused: "true" sur le ScaledObject
#      (« pendant mes essais ») : KEDA cesse d'interroger, l'effectif est figé ;
#   2. correctif JSON qui force vhostName à « medinotif » (vhost inexistant) dans le déclencheur
#      rabbitmq : l'API de gestion répond 404, la métrique n'est plus servie.
# Aucun secret n'est touché, KEDA (partagé avec la production) n'est ni redémarré ni coupé.
# Annulation : commit inverse, seulement si le fichier est encore exactement dans l'état injecté.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m28-commun.sh
source "$WB_ROOT/modules/28-plateforme-dev/corrige/pannes/_m28-commun.sh"

_E19_NS=medinotif-recette

# _e19_overlay — « projet<TAB>chemin du kustomization.yaml » de l'Application qui gère le ScaledObject.
_e19_overlay() {
  local app src
  app="$(m28_app_de scaledobjects.keda.sh medinotif "$_E19_NS")"
  [[ -n "$app" ]] || return 1
  src="$(m28_source_app "$app")"
  [[ "$src" == *$'\t'?* ]] || return 1
  m28_poser E19 app "$app"
  printf '%s\t%s/kustomization.yaml\n' "${src%%$'\t'*}" "${src#*$'\t'}"
}

_e19_sain() {
  m28_outils || return 1
  local so
  so="$(m28_so "$_E19_NS")"
  if [[ -z "$so" ]]; then
    echo "Pas de ScaledObject medinotif dans $_E19_NS : termine M28-E03 et M28-E13 d'abord." >&2
    return 1
  fi
  if ! jq -e '(.metadata.annotations // {} | (has("autoscaling.keda.sh/paused") or has("autoscaling.keda.sh/paused-replicas")) | not)
              and any(.status.conditions[]?; .type == "Ready" and .status == "True")' >/dev/null <<<"$so"; then
    echo "Le ScaledObject medinotif de recette n'est pas sain (Ready, sans pause) : lab/bin/check 28 19." >&2
    return 1
  fi
}

_e19_v1_effective() {
  m28_so "$_E19_NS" | jq -e '.metadata.annotations["autoscaling.keda.sh/paused"] == "true"' >/dev/null 2>&1
}
_e19_v2_effective() {
  m28_so "$_E19_NS" |
    jq -e '[.spec.triggers[] | select(.type == "rabbitmq") | .metadata.vhostName] | index("medinotif") != null' >/dev/null 2>&1
}

_m28E19_une() {
  local n="$1" ov projet chemin idx
  ov="$(_e19_overlay)" || return 10
  projet="${ov%%$'\t'*}"
  chemin="${ov#*$'\t'}"
  case "$n" in
    1)
      _m28_transformer() {
        m28_kustomize_ajouter_patch '{"group":"keda.sh","kind":"ScaledObject","name":"medinotif"}' \
          'apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: medinotif
  annotations:
    autoscaling.keda.sh/paused: "true"'
      }
      m28_git_modifier E19 "$projet" "$chemin" "chore(recette): pause de l'autoscaling de MédiNotif pendant mes essais (M28-E19)

Je rallume après mes mesures. -- Lucas" || return $?
      m28_rafraichir "$(m28_lire E19 app)"
      m28_attendre 480 _e19_v1_effective || return 1
      ;;
    2)
      idx="$(m28_so "$_E19_NS" | jq -r '[.spec.triggers | to_entries[] | select(.value.type == "rabbitmq") | .key][0] // empty')"
      [[ -n "$idx" ]] || return 10
      _m28_transformer() {
        m28_kustomize_ajouter_patch '{"group":"keda.sh","kind":"ScaledObject","name":"medinotif"}' \
          "- op: add
  path: /spec/triggers/$idx/metadata/vhostName
  value: medinotif"
      }
      m28_git_modifier E19 "$projet" "$chemin" "fix(recette): vhost du déclencheur aligné sur le nom de l'application (M28-E19)

Plus lisible. -- Lucas" || return $?
      m28_rafraichir "$(m28_lire E19 app)"
      m28_attendre 480 _e19_v2_effective || return 1
      ;;
  esac
  m28_journal E19 "variante $n posée ($projet:$chemin)"
}

panne_E19_v1() { _e19_sain && m28_essayer E19 2 1; }
panne_E19_v2() { _e19_sain && m28_essayer E19 2 2; }

verifier_E19() {
  case "$WB_VAR" in
    1) _e19_v1_effective ;;
    2) _e19_v2_effective ;;
    *) return 1 ;;
  esac
}

annuler_E19() {
  m28_git_annuler E19 || true
  local app
  app="$(m28_lire E19 app)"
  if [[ -n "$app" ]]; then m28_rafraichir "$app"; fi
  m28_journal E19 "annulation"
}

resume_E19() { echo "En recette, MédiNotif ne se réveille plus quand la file de notifications grossit."; }

symptome_E19() {
  wb_symptome "Ticket INC-5519 — De : Julien Petit" \
    "La mini-campagne de recette de 14 h n'est pas partie : la file « notifications » du vhost" \
    "medinotif-recette grossit et MédiNotif ne bouge pas (zéro ou un pod, jamais plus). Rien n'a" \
    "changé de notre côté. La prod a l'air normale. Vous pouvez regarder ? On recette demain matin." \
    "" \
    "Pour constater : modules/28-plateforme-dev/ressources/E13-campagne/campagne.sh 300" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 28 19"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 28 E19 2 "$@"; }
fi
