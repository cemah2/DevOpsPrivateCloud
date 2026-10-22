# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # « $patch: delete » et filtres jq littéraux entre apostrophes
# break-E35.sh — M20-E35 « Panne : l'application reste OutOfSync »
#
# Cible : l'Application mediagenda-dev (overlay overlays/dev de mediagenda/deploiement) et, pour la
# variante 3, l'ApplicationSet mediagenda de plateforme/gitops. Chaque variante est un commit de
# Lucas, fusionné par MR ; l'annulation le défait par un commit inverse.
#   1. PVC « mediagenda-archives » ajouté en vague -2 avec une classe de stockage qui n'existe pas
#      (ceph-rbd-ssd), plus un paramètre changé : Argo CD attend que la vague -2 soit saine avant
#      d'appliquer la suite ; elle ne le sera jamais. L'opération reste « Running », l'application
#      OutOfSync (le Deployment n'est jamais mis à jour) ;
#   2. la base CNPG de dev retirée de l'overlay par un correctif « $patch: delete » : elle porte
#      Prune=false (vérifié avant), Argo CD ne l'élague pas et l'application reste OutOfSync,
#      « requires pruning » ;
#   3. version de Kustomize épinglée dans l'ApplicationSet (v5.8.1) alors qu'aucune version
#      supplémentaire n'est déclarée dans argocd-cm : génération des manifestes en erreur, statut
#      Unknown, les changements de Git ne passent plus (les trois environnements) ;
#   4. demande mémoire de la base CNPG de dev réécrite dans une autre notation (« 0.25Gi » au lieu de
#      « 256Mi ») : sans comparaison côté serveur, le webhook de CNPG la normalise et Git ne ressemble
#      jamais au cluster. Avec ServerSideDiff + IncludeMutationWebhook (ApplicationSet de M20-E12),
#      la différence disparaît : la variante est alors déclarée sans effet et une autre est tirée
#      (démonstration que ce réglage protège).
# Une variante sans effet sur ce lab (différences déjà absorbées, version déjà déclarée, porte de CI
# qui refuse la MR…) est défaite et la suivante est essayée.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m20-commun.sh
source "$WB_ROOT/modules/20-gitops/corrige/pannes/_m20-commun.sh"

_E35_DOSSIER="${WB_M20_OVERLAY_DEV:-overlays/dev}"
_E35_KUSTO="$_E35_DOSSIER/kustomization.yaml"
_E35_KVER=v5.8.1

# _e35_cluster_dev — nom de la base CNPG suivie par l'Application de dev.
_e35_cluster_dev() {
  m20_app "$_M20_APP_DEV" | jq -r '[.status.resources[]? | select(.group == "postgresql.cnpg.io" and .kind == "Cluster") | .name][0] // empty'
}

# _e35_kusto_modifier 'expression yq' [VAR=valeur…] — kustomization de dev modifiée (fichier local
# affiché) ; code 1 si le fichier ne se lit pas ou si l'expression n'a rien changé.
_e35_kusto_modifier() {
  local expr="$1" t
  shift
  t="$(mktemp)"
  m20_brut "$_M20_DEPLOIEMENT" "$_E35_KUSTO" >"$t" 2>/dev/null || { rm -f "$t"; return 1; }
  cp "$t" "$t.orig"
  env "$@" yq -i "$expr" "$t" 2>/dev/null || { rm -f "$t" "$t.orig"; return 1; }
  if cmp -s "$t" "$t.orig"; then rm -f "$t" "$t.orig"; return 1; fi
  rm -f "$t.orig"
  printf '%s\n' "$t"
}

# _e35_rendu_ok KUSTO [CHEMIN FICHIER] — le rendu de l'overlay de dev ainsi modifié réussit ;
# affiche les objets qui disparaîtraient par rapport à main.
_e35_rendu_ok() {
  local nouveau="$1" d dir avant apres
  d="$(m20_copie "$_M20_DEPLOIEMENT")" || return 1
  dir="$d/$_E35_DOSSIER"
  avant="$(m20_rendu "$dir")"
  cp "$nouveau" "$d/$_E35_KUSTO"
  if [[ -n "${2:-}" ]]; then cp "$3" "$d/$2"; fi
  if ! kubectl kustomize "$dir" >/dev/null 2>&1; then rm -rf -- "$(dirname "$d")"; return 1; fi
  apres="$(m20_rendu "$dir")"
  rm -rf -- "$(dirname "$d")"
  comm -23 <(printf '%s\n' "$avant") <(printf '%s\n' "$apres")
}

# _e35_vague_bloquee — une opération lancée depuis l'injection tourne depuis plus de deux minutes et
# l'application est toujours OutOfSync.
_e35_vague_bloquee() {
  local debut
  debut="$(m20_lire E35 debut)"
  m20_app "$_M20_APP_DEV" | jq -e --argjson t "${debut:-0}" --argjson n "$(date +%s)" '
    ((.status.operationState.startedAt // "1970-01-01T00:00:00Z") | fromdateiso8601) as $d
    | .status.sync.status == "OutOfSync" and (.status.operationState.phase // "") == "Running"
      and $d >= ($t - 5) and ($n - $d) >= 120' >/dev/null 2>&1
}

# _e35_outofsync_persistant — dev OutOfSync alors qu'une synchronisation a réussi depuis l'injection.
_e35_outofsync_persistant() {
  local debut
  debut="$(m20_lire E35 debut)"
  m20_rafraichir "$_M20_APP_DEV"
  m20_app "$_M20_APP_DEV" | jq -e --argjson t "${debut:-0}" '
    .status.sync.status == "OutOfSync"
    and (.status.operationState.phase // "") == "Succeeded"
    and ((.status.operationState.finishedAt // "1970-01-01T00:00:00Z") | fromdateiso8601) >= $t' >/dev/null 2>&1
}

_e35_elagage_attendu() {
  local c
  c="$(m20_lire E35 cluster)"
  m20_rafraichir "$_M20_APP_DEV"
  m20_app "$_M20_APP_DEV" | jq -e --arg c "$c" '.status.sync.status == "OutOfSync"
    and ([.status.resources[]? | select(.kind == "Cluster" and .name == $c and (.requiresPruning // false))] | length == 1)' >/dev/null 2>&1
}

_e35_version_refusee() {
  m20_rafraichir "$_M20_APP_DEV"
  m20_app "$_M20_APP_DEV" | jq -e '[.status.conditions[]? | select(.type == "ComparisonError")
    | select(.message | test("kustomize version .* not registered"))] | length > 0' >/dev/null 2>&1
}

_m20E35_une() {
  local n="$1" c mem alt t f p fichier actions perdus
  m20_debut E35
  case "$n" in
    1)
      if wb_kubectl get storageclass ceph-rbd-ssd >/dev/null 2>&1; then return 10; fi
      if wb_kubectl -n "$_M20_NS_DEV" get pvc mediagenda-archives >/dev/null 2>&1; then return 10; fi
      f="$(mktemp)"
      cat >"$f" <<'EOF'
# Archives des rendez-vous de dev (DEV-2135) : volume créé avec les dépendances (vague -2), sur SSD.
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mediagenda-archives
  annotations:
    argocd.argoproj.io/sync-wave: "-2"
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: ceph-rbd-ssd
  resources:
    requests:
      storage: 1Gi
EOF
      t="$(_e35_kusto_modifier '.resources += ["archives.yaml"]
        | .configMapGenerator += [{"name": "mediagenda-parametres", "behavior": "merge", "literals": ["MEDIAGENDA_FUSEAU=Europe/Paris"]}]')" || { rm -f "$f"; return 10; }
      perdus="$(_e35_rendu_ok "$t" "$_E35_DOSSIER/archives.yaml" "$f")" || { rm -f "$t" "$f"; return 10; }
      [[ -z "$perdus" ]] || { rm -f "$t" "$f"; return 10; }
      actions="[$(m20_action update "$_E35_KUSTO" "$t"),$(m20_action create "$_E35_DOSSIER/archives.yaml" "$f")]"
      rm -f "$t" "$f"
      m20_ecrire E35 pvc mediagenda-archives
      m20_commit_lucas E35 "$_M20_DEPLOIEMENT" "lucas/dev-archives" \
        "feat(dev): volume d'archives et fuseau explicite" \
        "DEV-2135 : volume d'archives créé avec les dépendances ; fuseau horaire écrit en clair." "$actions" || return $?
      m20_rafraichir "$_M20_APP_DEV"
      m20_attendre 300 _e35_vague_bloquee || { _e35_defaire; return 10; }
      ;;
    2)
      c="$(_e35_cluster_dev)"
      [[ -n "$c" ]] || return 10
      # Garde-fou (PLAN §4.11) : la base doit porter Prune=false AVANT qu'on la retire de Git.
      wb_kubectl -n "$_M20_NS_DEV" get clusters.postgresql.cnpg.io "$c" -o json 2>/dev/null |
        jq -e '(.metadata.annotations["argocd.argoproj.io/sync-options"] // "") | test("(^|,)\\s*Prune=false\\s*(,|$)")' >/dev/null 2>&1 || return 10
      p="$(printf '$patch: delete\napiVersion: postgresql.cnpg.io/v1\nkind: Cluster\nmetadata:\n  name: %s\n' "$c")"
      t="$(_e35_kusto_modifier '.patches += [{"patch": strenv(P)}] | .patches[-1].patch style="literal"' "P=$p")" || return 10
      perdus="$(_e35_rendu_ok "$t")" || { rm -f "$t"; return 10; }
      # Seule la base doit disparaître du rendu (et elle ne sera pas élaguée : Prune=false).
      [[ "$perdus" == "Cluster/$c" ]] || { rm -f "$t"; return 10; }
      actions="[$(m20_action update "$_E35_KUSTO" "$t")]"
      rm -f "$t"
      m20_ecrire E35 cluster "$c"
      m20_commit_lucas E35 "$_M20_DEPLOIEMENT" "lucas/dev-base-partagee" \
        "refactor(dev): la base de dev sera fournie par la plateforme" \
        "DEV-2135 : on retire mediagenda-db de l'overlay de dev, la base partagée arrive bientôt." "$actions" || return $?
      m20_rafraichir "$_M20_APP_DEV"
      m20_attendre 300 _e35_elagage_attendu || { _e35_defaire; return 10; }
      ;;
    3)
      if wb_kubectl -n "$_M20_NS" get configmap argocd-cm -o json 2>/dev/null |
        jq -e --arg k "kustomize.path.$_E35_KVER" '.data[$k] != null' >/dev/null 2>&1; then
        return 10
      fi
      fichier="$(m20_chercher "$_M20_GITOPS" '^kind:[[:space:]]*ApplicationSet' | while read -r f; do
        m20_brut "$_M20_GITOPS" "$f" | yq -e 'select(.kind == "ApplicationSet" and .metadata.name == "mediagenda") | .spec.template.spec.source.repoURL' >/dev/null 2>&1 && printf '%s\n' "$f"
      done | head -n 1)"
      [[ -n "$fichier" ]] || return 10
      t="$(mktemp)"
      m20_brut "$_M20_GITOPS" "$fichier" >"$t" || { rm -f "$t"; return 1; }
      V="$_E35_KVER" yq -i '(select(.kind == "ApplicationSet" and .metadata.name == "mediagenda") | .spec.template.spec.source.kustomize.version) = strenv(V)' "$t" || { rm -f "$t"; return 10; }
      actions="[$(m20_action update "$fichier" "$t")]"
      rm -f "$t"
      m20_commit_lucas E35 "$_M20_GITOPS" "lucas/kustomize-epingle" \
        "chore(mediagenda): épingler Kustomize $_E35_KVER comme dans la CI" \
        "DEV-2135 : même version de Kustomize que kubectl 1.36 et que le pipeline de validation de mediagenda/deploiement." "$actions" || return $?
      m20_rafraichir racine applications
      m20_rafraichir hard "$_M20_APP_DEV"
      m20_attendre 300 _e35_version_refusee || { _e35_defaire; return 10; }
      ;;
    4)
      c="$(_e35_cluster_dev)"
      [[ -n "$c" ]] || return 10
      mem="$(wb_kubectl -n "$_M20_NS_DEV" get clusters.postgresql.cnpg.io "$c" -o jsonpath='{.spec.resources.requests.memory}' 2>/dev/null)" || mem=""
      # Même valeur, autre écriture (la forme canonique de l'API est celle que le cluster montre) :
      # 256Mi → 0.25Gi, 384Mi → 393216Ki, 1Gi → 1024Mi.
      if [[ "$mem" =~ ^([0-9]+)Mi$ ]]; then
        if ((BASH_REMATCH[1] % 256 == 0)); then
          alt="$(awk -v m="${BASH_REMATCH[1]}" 'BEGIN { printf "%gGi\n", m / 1024 }')"
        else
          alt="$((BASH_REMATCH[1] * 1024))Ki"
        fi
      elif [[ "$mem" =~ ^([0-9]+)Gi$ ]]; then
        alt="$((BASH_REMATCH[1] * 1024))Mi"
      else
        return 10
      fi
      p="$(printf -- '- op: replace\n  path: /spec/resources/requests/memory\n  value: %s\n' "$alt")"
      t="$(_e35_kusto_modifier '.patches += [{"target": {"group": "postgresql.cnpg.io", "kind": "Cluster", "name": strenv(C)}, "patch": strenv(P)}]
        | .patches[-1].patch style="literal"' "C=$c" "P=$p")" || return 10
      perdus="$(_e35_rendu_ok "$t")" || { rm -f "$t"; return 10; }
      [[ -z "$perdus" ]] || { rm -f "$t"; return 10; }
      actions="[$(m20_action update "$_E35_KUSTO" "$t")]"
      rm -f "$t"
      m20_ecrire E35 cluster "$c"
      m20_commit_lucas E35 "$_M20_DEPLOIEMENT" "lucas/dev-memoire-base-gi" \
        "chore(dev): demande mémoire de la base exprimée comme en prod" \
        "DEV-2135 : homogénéiser l'écriture des ressources de $c entre les environnements." "$actions" || return $?
      m20_rafraichir "$_M20_APP_DEV"
      m20_attendre 300 _e35_outofsync_persistant || { _e35_defaire; return 10; }
      ;;
  esac
  m20_journal E35 "variante $n posée"
}

_e35_defaire() {
  local p
  # Une opération bloquée (variante 1) empêcherait la synchronisation du commit inverse : on la
  # termine d'abord (équivalent de « argocd app terminate-op »).
  if m20_app_jq "$_M20_APP_DEV" '(.status.operationState.phase // "") == "Running"'; then
    wb_kubectl -n "$_M20_NS" patch applications.argoproj.io "$_M20_APP_DEV" --type merge \
      -p '{"status":{"operationState":{"phase":"Terminating"}}}' >/dev/null 2>&1 || true
    sleep 10
  fi
  m20_defaire_commits E35
  m20_rafraichir racine applications
  m20_rafraichir hard "$_M20_APP_DEV"
  p="$(m20_lire E35 pvc)"
  if [[ -n "$p" ]]; then
    # Le PVC de la panne n'a jamais été lié (classe inexistante) : il ne contient aucune donnée.
    sleep 30
    if wb_kubectl -n "$_M20_NS_DEV" get pvc "$p" -o json 2>/dev/null | jq -e '.status.phase == "Pending" and .spec.storageClassName == "ceph-rbd-ssd"' >/dev/null 2>&1; then
      wb_kubectl -n "$_M20_NS_DEV" delete pvc "$p" --wait=false >/dev/null 2>&1 || true
    fi
    m20_oublier E35 pvc
  fi
}

panne_E35_v1() { m20_preparer "$_M20_APP_DEV" && m20_essayer E35 4 1; }
panne_E35_v2() { m20_preparer "$_M20_APP_DEV" && m20_essayer E35 4 2; }
panne_E35_v3() { m20_preparer "$_M20_APP_DEV" && m20_essayer E35 4 3; }
panne_E35_v4() { m20_preparer "$_M20_APP_DEV" && m20_essayer E35 4 4; }

verifier_E35() {
  case "${WB_VAR:-}" in
    1) _e35_vague_bloquee ;;
    2) _e35_elagage_attendu ;;
    3) _e35_version_refusee ;;
    *) m20_app_jq "$_M20_APP_DEV" '.status.sync.status == "OutOfSync"' ;;
  esac
}

annuler_E35() {
  _e35_defaire
  m20_oublier E35 debut
  m20_oublier E35 cluster
  m20_journal E35 "annulation"
}

resume_E35() {
  case "${WB_VAR:-}" in
    1) echo "MédiAgenda dev est « Syncing » depuis une heure et reste OutOfSync : le dernier changement n'arrive pas." ;;
    3) echo "Les trois environnements de MédiAgenda sont « Unknown » dans Argo CD et plus aucun changement ne passe." ;;
    *) echo "MédiAgenda dev reste OutOfSync dans Argo CD, même juste après une synchronisation réussie." ;;
  esac
}

symptome_E35() {
  case "${WB_VAR:-}" in
    1)
      wb_symptome "Ticket INC-4735 — De : Julien Petit" \
        "mediagenda-dev est « OutOfSync » et la synchronisation automatique est « en cours » depuis" \
        "plus d'une heure : la dernière MR de Lucas n'est jamais arrivée (le fuseau horaire n'a pas" \
        "changé dans les pods). Lucas a « cliqué sur Sync », Argo CD lui répond qu'une opération est" \
        "déjà en cours. Débloque dev, sans masquer une vraie différence." \
        "" \
        "Temps cible : 30 min. Contrôle : lab/bin/check 20 35"
      ;;
    3)
      wb_symptome "Ticket INC-4735 — De : Julien Petit" \
        "Dans Argo CD, mediagenda-dev, mediagenda-recette et mediagenda-prod affichent un statut de" \
        "synchronisation « Unknown » avec un message d'erreur, et la dernière MR fusionnée dans" \
        "mediagenda/deploiement n'est pas arrivée en dev. Rien n'a changé dans le cluster depuis hier," \
        "le dépôt est lisible. On ne peut plus rien livrer : remets la chaîne en état." \
        "" \
        "Temps cible : 30 min. Contrôle : lab/bin/check 20 35"
      ;;
    *)
      wb_symptome "Ticket INC-4735 — De : Julien Petit" \
        "mediagenda-dev est « OutOfSync » en permanence dans Argo CD. La synchronisation automatique" \
        "passe, se termine en « Succeeded », et l'application reste OutOfSync. Lucas a « cliqué sur" \
        "Sync une dizaine de fois ». Personne ne sait plus si dev reflète Git : trouve pourquoi et" \
        "remets l'application Synced, sans masquer une vraie différence." \
        "" \
        "Temps cible : 30 min. Contrôle : lab/bin/check 20 35"
      ;;
  esac
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 20 E35 4 "$@"; }
fi
