# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # « $patch: delete » et filtres jq littéraux entre apostrophes
# break-E41.sh — M20-E41 « Panne : une synchronisation a supprimé des ressources »
#
# Cible : l'Application mediagenda-dev, synchronisée automatiquement avec prune. Un commit de
# Lucas « réorganise » l'overlay de dev ; des objets disparaissent du rendu et Argo CD les élague :
#   1. les composants regroupés dans overlays/dev/composants/ (nouveau Component) que l'overlay ne
#      référence pas : tout le composant « dependances » disparaît du rendu (Valkey et son Service,
#      politiques réseau éventuelles) ; la base CNPG, Prune=false, est seulement signalée ;
#   2. le Service mediagenda renommé (mediagenda-api) par un correctif : l'ancien est élagué, la
#      HTTPRoute pointe toujours sur l'ancien nom ;
#   3. les politiques réseau de dev « déplacées vers plateforme/k8s » (retirées par « $patch:
#      delete ») avant que la plateforme ne les ait appliquées : élaguées, l'API ne joint plus ses
#      dépendances.
# GARDE-FOUS (PLAN §4.11, fiche du module) : jamais en prod ; avant l'injection, le rendu des deux
# versions est calculé sur adm01 et la variante est refusée si un objet qui disparaîtrait porte des
# données (PersistentVolumeClaim, StatefulSet avec volumeClaimTemplates, Namespace) ou si une base
# CNPG disparaîtrait sans porter Prune=false. Rien de ce qui est élagué ne contient de données :
# Valkey de dev tourne sans persistance (emptyDir, --save "").

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m20-commun.sh
source "$WB_ROOT/modules/20-gitops/corrige/pannes/_m20-commun.sh"

_E41_DOSSIER="${WB_M20_OVERLAY_DEV:-overlays/dev}"
_E41_KUSTO="$_E41_DOSSIER/kustomization.yaml"

# _e41_perdus KUSTO [CHEMIN FICHIER] — objets (Kind/nom) qui disparaîtraient du rendu de dev ;
# code 1 si le rendu échoue.
_e41_perdus() {
  local d dir avant apres
  d="$(m20_copie "$_M20_DEPLOIEMENT")" || return 1
  dir="$d/$_E41_DOSSIER"
  avant="$(m20_rendu "$dir")"
  cp "$1" "$d/$_E41_KUSTO"
  if [[ -n "${2:-}" ]]; then mkdir -p "$(dirname "$d/$2")"; cp "$3" "$d/$2"; fi
  if ! kubectl kustomize "$dir" >/dev/null 2>&1; then rm -rf -- "$(dirname "$d")"; return 1; fi
  apres="$(m20_rendu "$dir")"
  rm -rf -- "$(dirname "$d")"
  comm -23 <(printf '%s\n' "$avant") <(printf '%s\n' "$apres")
}

# _e41_sans_donnees LISTE — 0 si aucun objet de la liste (Kind/nom, espace de dev) ne porte de données.
_e41_sans_donnees() {
  local o k nom
  while read -r o; do
    [[ -n "$o" ]] || continue
    k="${o%%/*}"
    nom="${o#*/}"
    case "$k" in
      PersistentVolumeClaim | Namespace | PersistentVolume) return 1 ;;
      StatefulSet)
        wb_kubectl -n "$_M20_NS_DEV" get statefulset "$nom" -o json 2>/dev/null |
          jq -e '(.spec.volumeClaimTemplates // []) | length == 0' >/dev/null 2>&1 || return 1
        ;;
      Cluster)
        wb_kubectl -n "$_M20_NS_DEV" get clusters.postgresql.cnpg.io "$nom" -o json 2>/dev/null |
          jq -e '(.metadata.annotations["argocd.argoproj.io/sync-options"] // "") | test("(^|,)\\s*Prune=false\\s*(,|$)")' >/dev/null 2>&1 || return 1
        ;;
    esac
  done <<<"$1"
}

# _e41_elague — au moins un objet suivi par l'Application a disparu du cluster depuis l'injection
# (la ressource de l'état précédent n'existe plus) et la synchro automatique a tourné.
_e41_elague() {
  local o k nom debut
  debut="$(m20_lire E41 debut)"
  m20_app_jq "$_M20_APP_DEV" "((.status.operationState.finishedAt // \"1970-01-01T00:00:00Z\") | fromdateiso8601) >= ${debut:-0}" || return 1
  while read -r o; do
    [[ -n "$o" ]] || continue
    k="${o%%/*}"
    nom="${o#*/}"
    [[ "$k" == Cluster ]] && continue
    if ! wb_kubectl -n "$_M20_NS_DEV" get "$k" "$nom" >/dev/null 2>&1; then return 0; fi
  done < <(m20_lire E41 perdus)
  return 1
}

_m20E41_une() {
  local n="$1" t c actions perdus noms p k g nom
  m20_debut E41
  t="$(mktemp)"
  m20_brut "$_M20_DEPLOIEMENT" "$_E41_KUSTO" >"$t" 2>/dev/null || { rm -f "$t"; return 1; }
  case "$n" in
    1)
      yq -e '.components[] | select(test("components/dependances$"))' "$t" >/dev/null 2>&1 || { rm -f "$t"; return 10; }
      c="$(mktemp)"
      yq -n '.apiVersion = "kustomize.config.k8s.io/v1alpha1" | .kind = "Component"
        | .components = ["../../../components/dependances"]' >"$c"
      sed -i '1i # Dépendances de dev regroupées ici (DEV-2141) : base, cache, politiques.' "$c"
      yq -i '.components |= map(select(test("components/dependances$") | not))' "$t"
      perdus="$(_e41_perdus "$t" "$_E41_DOSSIER/composants/kustomization.yaml" "$c")" || { rm -f "$t" "$c"; return 10; }
      actions="[$(m20_action update "$_E41_KUSTO" "$t"),$(m20_action create "$_E41_DOSSIER/composants/kustomization.yaml" "$c")]"
      rm -f "$c"
      ;;
    2)
      [[ -n "$(m20_ressource_app "$_M20_APP_DEV" Service mediagenda)" ]] || { rm -f "$t"; return 10; }
      P="$(printf -- '- op: replace\n  path: /metadata/name\n  value: mediagenda-api\n')" \
        yq -i '.patches += [{"target": {"kind": "Service", "name": "mediagenda"}, "patch": strenv(P), "options": {"allowNameChange": true}}]
          | .patches[-1].patch style="literal"' "$t"
      perdus="$(_e41_perdus "$t")" || { rm -f "$t"; return 10; }
      actions="[$(m20_action update "$_E41_KUSTO" "$t")]"
      ;;
    3)
      noms="$(m20_app "$_M20_APP_DEV" | jq -r '.status.resources[]? | select(.kind == "NetworkPolicy" or .kind == "CiliumNetworkPolicy") | "\(.kind) \(.name)"')"
      [[ -n "$noms" ]] || { rm -f "$t"; return 10; }
      while read -r k nom; do
        [[ -n "$k" ]] || continue
        if [[ "$k" == NetworkPolicy ]]; then g=networking.k8s.io/v1; else g=cilium.io/v2; fi
        p="$(printf '$patch: delete\napiVersion: %s\nkind: %s\nmetadata:\n  name: %s\n' "$g" "$k" "$nom")"
        P="$p" yq -i '.patches += [{"patch": strenv(P)}] | .patches[-1].patch style="literal"' "$t"
      done <<<"$noms"
      perdus="$(_e41_perdus "$t")" || { rm -f "$t"; return 10; }
      actions="[$(m20_action update "$_E41_KUSTO" "$t")]"
      ;;
  esac
  rm -f "$t"
  [[ -n "$perdus" ]] || return 10
  _e41_sans_donnees "$perdus" || { wb_avert "la variante $n ferait élaguer un objet porteur de données : refusée"; return 10; }
  m20_ecrire E41 perdus "$perdus"
  case "$n" in
    1) m20_commit_lucas E41 "$_M20_DEPLOIEMENT" "lucas/dev-composants" \
         "refactor(dev): regrouper les composants de dev dans overlays/dev/composants" \
         "DEV-2141 : un seul endroit pour les dépendances de dev, plus lisible." "$actions" || return $? ;;
    2) m20_commit_lucas E41 "$_M20_DEPLOIEMENT" "lucas/dev-nom-service" \
         "refactor(dev): Service renommé mediagenda-api comme au M14" \
         "DEV-2141 : mes scripts de test de dev visent encore mediagenda-api." "$actions" || return $? ;;
    3) m20_commit_lucas E41 "$_M20_DEPLOIEMENT" "lucas/dev-politiques-plateforme" \
         "refactor(dev): politiques réseau déplacées vers plateforme/k8s" \
         "DEV-2141 : les politiques réseau sont gérées par la plateforme (AppProject mediagenda, M20-E07)." "$actions" || return $? ;;
  esac
  m20_rafraichir "$_M20_APP_DEV"
  m20_attendre 300 _e41_elague || { _e41_defaire; return 10; }
  m20_journal E41 "variante $n posée ; élagués : $(tr '\n' ' ' <<<"$perdus")"
}

_e41_defaire() {
  m20_defaire_commits E41
  m20_rafraichir hard "$_M20_APP_DEV"
  m20_oublier E41 perdus
}

_e41_preparer() {
  if [[ -z "${_M20_ASTREINTE:-}" ]]; then
    m20_sain "$_M20_APP_DEV" || return 1
  fi
  # Jamais sans élagage maîtrisé : dev doit être en synchro automatique avec prune.
  m20_app_jq "$_M20_APP_DEV" '.spec.syncPolicy.automated.prune == true' || {
    echo "mediagenda-dev n'élague pas automatiquement (syncPolicy.automated.prune) : panne sans objet, rien n'est cassé." >&2
    return 1
  }
}

panne_E41_v1() { _e41_preparer && m20_essayer E41 3 1; }
panne_E41_v2() { _e41_preparer && m20_essayer E41 3 2; }
panne_E41_v3() { _e41_preparer && m20_essayer E41 3 3; }

verifier_E41() { _e41_elague; }

annuler_E41() {
  _e41_defaire
  m20_oublier E41 debut
  m20_journal E41 "annulation"
}

resume_E41() {
  echo "MédiAgenda dev ne répond plus (erreurs 5xx) depuis une synchronisation automatique ; des objets ont disparu de l'espace."
}

symptome_E41() {
  wb_symptome "Ticket INC-4741 — De : Julien Petit" \
    "Depuis la dernière synchronisation automatique, MédiAgenda dev renvoie des erreurs 5xx" \
    "(https://mediagenda-dev.apps.par1.medisphere.internal/pret). Des objets ont disparu de" \
    "l'espace mediagenda-dev ; Lucas jure qu'il n'a « rien supprimé, juste rangé des fichiers »." \
    "Rétablis dev, dis-moi exactement ce qui a été supprimé et pourquoi, et fais en sorte qu'une" \
    "telle synchronisation ne puisse jamais emporter la production." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 20 41"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 20 E41 3 "$@"; }
fi
