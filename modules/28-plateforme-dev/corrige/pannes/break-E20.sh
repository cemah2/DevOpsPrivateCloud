# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# break-E20.sh — M28-E20 « Panne : des pods redémarrent en boucle depuis l'autoscaling » (RECETTE).
#
# Toujours par des commits de Lucas (overlays de RECETTE ; pour la variante 2, aussi le modèle de
# l'ApplicationSet medinotif dans plateforme/gitops) :
#   1. VPA « mediagenda » de mediagenda-recette passé en updateMode Recreate, alors que l'HPA
#      « mediagenda » pilote le même Rollout sur le CPU : l'updater du VPA évince des pods pour changer
#      leurs requests, ce qui déplace l'utilisation vue par l'HPA. Sans effet (→ autre variante) si
#      aucune éviction du VPA n'est observée en 12 min (requests déjà dans les bornes recommandées) ;
#   2. « replicas » remis dans Git pour MédiNotif de recette (correctif « add /spec/replicas: 2 » après
#      le « remove » de M28-E03) ET entrée ignoreDifferences du Deployment medinotif retirée du modèle de
#      l'ApplicationSet (« nettoyage ») : Argo CD (selfHeal) remet 2, KEDA remet 0 (aucune activité), en
#      boucle. La prod n'a pas de « replicas » dans Git (M28-E13) : la ligne retirée n'y change rien ;
#   3. VPA « mediagenda » de recette en Recreate, minReplicas 1, mémoire seule, plafonnée à 40 Mi :
#      combinaison VPA mémoire + HPA CPU admissible, mais bornes absurdes → requests et limites
#      (proportionnelles) réduites à la création des pods → OOMKilled.
# Annulation : commits inverses (si les fichiers n'ont pas bougé) ; pour 1 et 3, redémarrage du Rollout
# de recette (spec.restartAt) pour que les pods retrouvent les requests du gabarit.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m28-commun.sh
source "$WB_ROOT/modules/28-plateforme-dev/corrige/pannes/_m28-commun.sh"

_E20_MA=mediagenda-recette
_E20_MN=medinotif-recette

# _e20_overlay TYPE NOM ESPACE — « projet<TAB>kustomization.yaml » de l'Application qui gère l'objet.
_e20_overlay() {
  local app src
  app="$(m28_app_de "$1" "$2" "$3")"
  [[ -n "$app" ]] || return 1
  src="$(m28_source_app "$app")"
  [[ "$src" == *$'\t'?* ]] || return 1
  m28_poser E20 "app-$3" "$app"
  printf '%s\t%s/kustomization.yaml\n' "${src%%$'\t'*}" "${src#*$'\t'}"
}

_e20_sain() {
  m28_outils || return 1
  if ! wb_kubectl -n "$_E20_MA" get verticalpodautoscalers.autoscaling.k8s.io mediagenda -o json 2>/dev/null |
    jq -e '.spec.updatePolicy.updateMode == "Off"' >/dev/null 2>&1; then
    echo "Le VPA mediagenda de $_E20_MA doit exister en mode Off (M28-E04) : lab/bin/check 28 20." >&2
    return 1
  fi
  if ! wb_kubectl -n "$_E20_MA" get hpa mediagenda >/dev/null 2>&1; then
    echo "L'HPA mediagenda de $_E20_MA est absent (M28-E02) : lab/bin/check 28 20." >&2
    return 1
  fi
}

# _e20_evenements ESPACE RAISON [MINUTES=12] — somme des « count » des événements récents de cette raison.
_e20_evenements() {
  local depuis
  depuis="$(date -u -d "-${3:-12} minutes" +%Y-%m-%dT%H:%M:%SZ)"
  wb_kubectl -n "$1" get events --field-selector "reason=$2" -o json 2>/dev/null |
    jq --arg d "$depuis" '[.items[] | select((.lastTimestamp // .eventTime // "") >= $d) | (.count // 1)] | add // 0'
}
_e20_v1_effective() { (($(_e20_evenements "$_E20_MA" EvictedByVPA) > 0)); }
_e20_v2_effective() {
  wb_kubectl -n "$_E20_MN" get events --field-selector involvedObject.kind=Deployment,involvedObject.name=medinotif,reason=ScalingReplicaSet -o json 2>/dev/null |
    jq -e --arg d "$(date -u -d '-6 minutes' +%Y-%m-%dT%H:%M:%SZ)" \
      '[.items[] | select((.lastTimestamp // .eventTime // "") >= $d) | (.count // 1)] | (add // 0) >= 4' >/dev/null 2>&1
}
_e20_v3_effective() {
  wb_kubectl -n "$_E20_MA" get pods -l app.kubernetes.io/name=mediagenda -o json 2>/dev/null |
    jq -e '[.items[].status.containerStatuses[]? | select(.lastState.terminated.reason == "OOMKilled")] | length > 0' >/dev/null 2>&1 ||
    _e20_v1_effective
}

# Sans effet constaté : on défait le commit avant de passer à une autre variante.
_e20_sans_effet() {
  m28_git_annuler E20 || true
  return 10
}

_e20_patch_vpa() { m28_kustomize_ajouter_patch '{"group":"autoscaling.k8s.io","kind":"VerticalPodAutoscaler","name":"mediagenda"}' "$1"; }

_m28E20_une() {
  local n="$1" ov projet chemin gproj gfichier
  case "$n" in
    1 | 3)
      ov="$(_e20_overlay verticalpodautoscalers.autoscaling.k8s.io mediagenda "$_E20_MA")" || return 10
      projet="${ov%%$'\t'*}"
      chemin="${ov#*$'\t'}"
      if ((n == 1)); then
        _m28_transformer() {
          _e20_patch_vpa '- op: replace
  path: /spec/updatePolicy/updateMode
  value: Recreate'
        }
        m28_git_modifier E20 "$projet" "$chemin" "feat(recette): le VPA applique ses recommandations à MédiAgenda (M28-E20)

Le rapport mensuel dit que nos requests sont fausses : autant laisser le VPA les corriger. -- Lucas" || return $?
      else
        _m28_transformer() {
          _e20_patch_vpa '- op: replace
  path: /spec/updatePolicy
  value:
    updateMode: Recreate
    minReplicas: 1
- op: replace
  path: /spec/resourcePolicy
  value:
    containerPolicies:
      - containerName: "*"
        controlledResources: ["memory"]
        minAllowed: {memory: 16Mi}
        maxAllowed: {memory: 40Mi}'
        }
        m28_git_modifier E20 "$projet" "$chemin" "perf(recette): VPA sur la mémoire seulement, plafonné (M28-E20)

La mémoire ne compte pas pour l'HPA (CPU) : pas de conflit. Plafond bas pour économiser la recette. -- Lucas" || return $?
      fi
      m28_rafraichir "$(m28_lire E20 "app-$_E20_MA")"
      if ((n == 1)); then
        m28_attendre 720 _e20_v1_effective || _e20_sans_effet || return $?
      else
        m28_attendre 720 _e20_v3_effective || _e20_sans_effet || return $?
      fi
      ;;
    2)
      ov="$(_e20_overlay deployments medinotif "$_E20_MN")" || return 10
      projet="${ov%%$'\t'*}"
      chemin="${ov#*$'\t'}"
      # Modèle de l'ApplicationSet medinotif (plateforme/gitops, applications/) : retirer l'ignoreDifferences.
      gproj=plateforme/gitops
      gfichier="$(m28_git_chercher "$gproj" 'kind: ApplicationSet' applications | while IFS= read -r f; do
        if m28_git_lire "$gproj" "$f" | yq -e 'select(.kind == "ApplicationSet" and .metadata.name == "medinotif")
            | .spec.template.spec.ignoreDifferences[] | select(.kind == "Deployment" and .name == "medinotif")' >/dev/null 2>&1; then
          printf '%s\n' "$f"
        fi
      done | head -n 1)"
      [[ -n "$gfichier" ]] || return 10
      _m28_transformer() {
        yq '(select(.kind == "ApplicationSet" and .metadata.name == "medinotif") | .spec.template.spec.ignoreDifferences) |=
              map(select((.kind == "Deployment" and .name == "medinotif") | not))'
      }
      m28_git_modifier E20 "$gproj" "$gfichier" "chore(medinotif): ménage dans ignoreDifferences (M28-E20)

Le Deployment n'a plus de replicas dans Git depuis M28-E03 : cette exception ne sert plus. -- Lucas" 1 || return $?
      _m28_transformer() {
        m28_kustomize_ajouter_patch '{"group":"apps","kind":"Deployment","name":"medinotif"}' '- op: add
  path: /spec/replicas
  value: 2'
      }
      if ! m28_git_modifier E20 "$projet" "$chemin" "fix(recette): deux workers MédiNotif minimum, comme demandé par Julien (M28-E20)

-- Lucas" 2; then
        _e20_sans_effet || return $?
      fi
      m28_rafraichir "$(m28_lire E20 "app-$_E20_MN")"
      m28_attendre 480 _e20_v2_effective || _e20_sans_effet || return $?
      ;;
  esac
  m28_journal E20 "variante $n posée"
}

panne_E20_v1() { _e20_sain && m28_essayer E20 3 1; }
panne_E20_v2() { _e20_sain && m28_essayer E20 3 2; }
panne_E20_v3() { _e20_sain && m28_essayer E20 3 3; }

verifier_E20() {
  case "$WB_VAR" in
    1) _e20_v1_effective ;;
    2) _e20_v2_effective ;;
    3) _e20_v3_effective ;;
    *) return 1 ;;
  esac
}

annuler_E20() {
  m28_git_annuler E20 || true
  m28_rafraichir "$(m28_lire E20 "app-$_E20_MA")" "$(m28_lire E20 "app-$_E20_MN")"
  case "${WB_VAR:-}" in
    1 | 3)
      # Les pods créés pendant la panne gardent les requests réduites par le VPA : on les renouvelle.
      sleep 60
      wb_kubectl -n "$_E20_MA" patch rollouts.argoproj.io mediagenda --type merge \
        -p "{\"spec\":{\"restartAt\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}}" >/dev/null 2>&1 || true
      ;;
  esac
  m28_journal E20 "annulation"
}

resume_E20() {
  case "${WB_VAR:-}" in
    2) echo "En recette, des pods MédiNotif apparaissent et disparaissent en boucle." ;;
    *) echo "En recette, les pods de MédiAgenda sont remplacés ou redémarrent sans cesse." ;;
  esac
}

symptome_E20() {
  case "${WB_VAR:-}" in
    2)
      wb_symptome "Ticket INC-5520 — De : Nadia Roussel" \
        "L'alerte de supervision des pods de recette s'affole : dans medinotif-recette, des pods" \
        "MédiNotif naissent et meurent toutes les quelques secondes, sans erreur dans leurs journaux." \
        "Argo CD montre des synchronisations à répétition. Personne n'a touché à MédiNotif, paraît-il." \
        "" \
        "Temps cible : 45 min. Contrôle : lab/bin/check 28 20"
      ;;
    *)
      wb_symptome "Ticket INC-5520 — De : Nadia Roussel" \
        "Depuis ce matin, les pods de MédiAgenda en recette sont remplacés ou redémarrent sans arrêt :" \
        "l'âge des pods ne dépasse jamais quelques minutes, des requêtes échouent pendant les essais de" \
        "Julien. On a mis l'autoscaling partout le mois dernier, c'est peut-être lié ?" \
        "" \
        "Temps cible : 45 min. Contrôle : lab/bin/check 28 20"
      ;;
  esac
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 28 E20 3 "$@"; }
fi
