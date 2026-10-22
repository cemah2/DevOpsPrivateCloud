# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E36.sh — M20-E36 « Panne : la synchronisation échoue »
#
# Cible : l'Application mediagenda-dev (overlay overlays/dev de mediagenda/deploiement). Chaque
# variante est un commit de Lucas qui passe la validation de la CI (kustomize build, kubeconform,
# signatures) mais que le cluster ou Argo CD refusent au moment de la synchronisation :
#   1. sélecteur du Deployment mediagenda modifié (étiquette ajoutée au sélecteur et au modèle de
#      pod) : champ immuable, l'API refuse ;
#   2. ClusterRole ajoutée à l'overlay : ressource de portée cluster refusée par l'AppProject
#      mediagenda (clusterResourceWhitelist vide, M20-E07) ;
#   3. hook PreSync « verifier-base » qui échoue (nom d'hôte de la base erroné) + un paramètre
#      changé pour que la synchronisation automatique se déclenche : la synchro s'arrête au hook ;
#   4. Service de type LoadBalancer ajouté : refusé par le ResourceQuota de l'espace
#      (services.loadbalancers: 0, M14-E10).
# Rien n'est appliqué en dev tant que la synchronisation échoue : l'application garde la version
# précédente (aucune coupure). Annulation : commit inverse.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m20-commun.sh
source "$WB_ROOT/modules/20-gitops/corrige/pannes/_m20-commun.sh"

_E36_DOSSIER="${WB_M20_OVERLAY_DEV:-overlays/dev}"
_E36_KUSTO="$_E36_DOSSIER/kustomization.yaml"

# _e36_preparer_kusto 'expression yq' [VAR=valeur…] — kustomization modifiée (fichier local affiché).
_e36_preparer_kusto() {
  local expr="$1" t
  shift
  t="$(mktemp)"
  m20_brut "$_M20_DEPLOIEMENT" "$_E36_KUSTO" >"$t" 2>/dev/null || { rm -f "$t"; return 1; }
  env "$@" yq -i "$expr" "$t" 2>/dev/null || { rm -f "$t"; return 1; }
  printf '%s\n' "$t"
}

# _e36_rendu_ok KUSTO_LOCAL [CHEMIN_DÉPÔT FICHIER_LOCAL] — rendu de l'overlay de dev modifié :
# il doit réussir et ne faire disparaître aucun objet (aucun élagage provoqué par la panne).
_e36_rendu_ok() {
  local k="$1" d dir avant apres
  d="$(m20_copie "$_M20_DEPLOIEMENT")" || return 1
  dir="$d/$_E36_DOSSIER"
  avant="$(m20_rendu "$dir")"
  cp "$k" "$d/$_E36_KUSTO"
  if [[ -n "${2:-}" ]]; then cp "$3" "$d/$2"; fi
  if ! kubectl kustomize "$dir" >/dev/null 2>&1; then rm -rf -- "$(dirname "$d")"; return 1; fi
  apres="$(m20_rendu "$dir")"
  rm -rf -- "$(dirname "$d")"
  [[ -z "$(comm -23 <(printf '%s\n' "$avant") <(printf '%s\n' "$apres"))" ]]
}

# _e36_synchro_en_echec — une opération lancée depuis l'injection s'est terminée en échec.
_e36_synchro_en_echec() {
  local debut
  debut="$(m20_lire E36 debut)"
  m20_rafraichir "$_M20_APP_DEV"
  # Opération terminée en échec depuis l'injection, ou refus de l'AppProject signalé en condition
  # (selon la version, Argo CD refuse une ressource non permise avant même de lancer l'opération),
  # ou, variante 1 avec la comparaison côté serveur (ServerSideDiff=true, M20-E12), refus du champ
  # immuable dès l'essai à blanc du diff : ComparisonError, statut Unknown, aucune opération.
  m20_app "$_M20_APP_DEV" | jq -e --argjson t "${debut:-0}" '
    (((.status.operationState.phase // "") | test("Failed|Error"))
      and ((.status.operationState.startedAt // "1970-01-01T00:00:00Z") | fromdateiso8601) >= ($t - 5))
    or ([.status.conditions[]? | select((.message // "") | test("not permitted in project"))] | length > 0)
    or ([.status.conditions[]? | select(.type == "ComparisonError" and ((.message // "") | test("immutable")))] | length > 0)' >/dev/null 2>&1
}

_e36_deploy_json() { wb_kubectl -n "$_M20_NS_DEV" get deploy mediagenda -o json 2>/dev/null; }

_m20E36_une() {
  local n="$1" t f actions img q
  m20_debut E36
  case "$n" in
    1)
      _e36_deploy_json | jq -e '.spec.selector.matchLabels["medisphere.internal/equipe"] == null' >/dev/null 2>&1 || return 10
      t="$(_e36_preparer_kusto '.patches += [{"target": {"kind": "Deployment", "name": "mediagenda"}, "patch": strenv(P)}]
        | .patches[-1].patch style="literal"' \
        "P=$(printf -- '- op: add\n  path: /spec/selector/matchLabels/medisphere.internal~1equipe\n  value: mediagenda\n- op: add\n  path: /spec/template/metadata/labels/medisphere.internal~1equipe\n  value: mediagenda\n')")" || return 10
      _e36_rendu_ok "$t" || { rm -f "$t"; return 10; }
      actions="[$(m20_action update "$_E36_KUSTO" "$t")]"
      rm -f "$t"
      m20_commit_lucas E36 "$_M20_DEPLOIEMENT" "lucas/dev-selecteur-equipe" \
        "feat(dev): sélecteur par équipe pour les tableaux de bord" \
        "DEV-2136 : les futurs tableaux de bord du M21 filtreront les pods par medisphere.internal/equipe." "$actions" || return $?
      ;;
    2)
      wb_kubectl -n "$_M20_NS" get appprojects.argoproj.io mediagenda -o json 2>/dev/null |
        jq -e '(.spec.clusterResourceWhitelist // []) | length == 0' >/dev/null 2>&1 || return 10
      f="$(mktemp)"
      cat >"$f" <<'EOF'
# Lecture des nœuds par l'API (affichage de la zone de disponibilité dans /sante) — DEV-2136
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: mediagenda-lecture-noeuds
rules:
  - apiGroups: [""]
    resources: [nodes]
    verbs: [get, list]
EOF
      t="$(_e36_preparer_kusto '.resources += ["lecture-noeuds.yaml"]')" || { rm -f "$f"; return 10; }
      _e36_rendu_ok "$t" "$_E36_DOSSIER/lecture-noeuds.yaml" "$f" || { rm -f "$t" "$f"; return 10; }
      actions="[$(m20_action update "$_E36_KUSTO" "$t"),$(m20_action create "$_E36_DOSSIER/lecture-noeuds.yaml" "$f")]"
      rm -f "$t" "$f"
      m20_commit_lucas E36 "$_M20_DEPLOIEMENT" "lucas/dev-lecture-noeuds" \
        "feat(dev): l'API lit la zone de son nœud" \
        "DEV-2136 : afficher la baie (par1-baie-a/b/c) dans la réponse de /sante en dev." "$actions" || return $?
      ;;
    3)
      img="$_M20_REGISTRE/dockerhub/library/busybox:1.37"
      f="$(mktemp)"
      cat >"$f" <<EOF
# Contrôle avant chaque synchronisation : la base doit accepter les connexions (DEV-2136).
apiVersion: batch/v1
kind: Job
metadata:
  name: verifier-base
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
spec:
  backoffLimit: 0
  activeDeadlineSeconds: 120
  template:
    spec:
      restartPolicy: Never
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        runAsUser: 65534
        runAsGroup: 65534
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: verifier
          image: $img
          command: ["sh", "-c", "nc -z -w 5 mediagenda-bd-rw 5432 && echo base joignable"]
          resources:
            requests:
              cpu: 10m
              memory: 16Mi
            limits:
              memory: 32Mi
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
EOF
      # L'admission (PSA restricted, VAP medisphere-images, quotas) doit accepter le Job.
      sed '1d' "$f" | wb_kubectl -n "$_M20_NS_DEV" create --dry-run=server -f - >/dev/null 2>&1 || { rm -f "$f"; return 10; }
      t="$(_e36_preparer_kusto '.resources += ["verifier-base.yaml"]
        | .configMapGenerator += [{"name": "mediagenda-parametres", "behavior": "merge", "literals": ["MEDIAGENDA_DELAI_ARRET=25"]}]')" || { rm -f "$f"; return 10; }
      _e36_rendu_ok "$t" "$_E36_DOSSIER/verifier-base.yaml" "$f" || { rm -f "$t" "$f"; return 10; }
      actions="[$(m20_action update "$_E36_KUSTO" "$t"),$(m20_action create "$_E36_DOSSIER/verifier-base.yaml" "$f")]"
      rm -f "$t" "$f"
      m20_commit_lucas E36 "$_M20_DEPLOIEMENT" "lucas/dev-verifier-base" \
        "feat(dev): vérifier la base avant chaque synchronisation" \
        "DEV-2136 : hook PreSync qui s'assure que PostgreSQL répond ; délai d'arrêt porté à 25 s." "$actions" || return $?
      ;;
    4)
      q="$(wb_kubectl -n "$_M20_NS_DEV" get resourcequota -o json 2>/dev/null |
        jq -r '[.items[] | select((.spec.hard["services.loadbalancers"] // "x") == "0") | .metadata.name][0] // empty')"
      [[ -n "$q" ]] || return 10
      f="$(mktemp)"
      cat >"$f" <<'EOF'
# Accès direct à l'API de dev depuis le poste de Julien, sans passer par la Gateway — DEV-2136
apiVersion: v1
kind: Service
metadata:
  name: mediagenda-direct
spec:
  type: LoadBalancer
  selector:
    app.kubernetes.io/name: mediagenda
    app.kubernetes.io/component: api
  ports:
    - name: http
      port: 80
      targetPort: http
EOF
      t="$(_e36_preparer_kusto '.resources += ["acces-direct.yaml"]')" || { rm -f "$f"; return 10; }
      _e36_rendu_ok "$t" "$_E36_DOSSIER/acces-direct.yaml" "$f" || { rm -f "$t" "$f"; return 10; }
      actions="[$(m20_action update "$_E36_KUSTO" "$t"),$(m20_action create "$_E36_DOSSIER/acces-direct.yaml" "$f")]"
      rm -f "$t" "$f"
      m20_commit_lucas E36 "$_M20_DEPLOIEMENT" "lucas/dev-acces-direct" \
        "feat(dev): accès direct à l'API de dev par une IP de service" \
        "DEV-2136 : Julien teste depuis son poste sans passer par la Gateway." "$actions" || return $?
      ;;
  esac
  m20_journal E36 "variante $n posée"
  m20_rafraichir "$_M20_APP_DEV"
  m20_attendre 300 _e36_synchro_en_echec || { _e36_defaire; return 10; }
}

_e36_defaire() {
  m20_defaire_commits E36
  m20_rafraichir hard "$_M20_APP_DEV"
  # Un hook qui a échoué reste en place (BeforeHookCreation) : il disparaîtra à la prochaine
  # synchronisation ; on retire seulement celui de la panne s'il est encore là.
  wb_kubectl -n "$_M20_NS_DEV" delete job verifier-base --ignore-not-found >/dev/null 2>&1 || true
}

panne_E36_v1() { m20_preparer "$_M20_APP_DEV" && m20_essayer E36 4 1; }
panne_E36_v2() { m20_preparer "$_M20_APP_DEV" && m20_essayer E36 4 2; }
panne_E36_v3() { m20_preparer "$_M20_APP_DEV" && m20_essayer E36 4 3; }
panne_E36_v4() { m20_preparer "$_M20_APP_DEV" && m20_essayer E36 4 4; }

verifier_E36() { _e36_synchro_en_echec; }

annuler_E36() {
  _e36_defaire
  m20_oublier E36 debut
  m20_journal E36 "annulation"
}

resume_E36() {
  echo "La synchronisation automatique de MédiAgenda dev échoue : la dernière MR fusionnée n'arrive pas en dev."
}

symptome_E36() {
  local l2="n'a changé en dev. Argo CD affiche « Sync failed » sur mediagenda-dev et l'application reste"
  local l3="OutOfSync. Lucas propose de « forcer » la synchronisation ou de désactiver l'auto-sync de dev."
  # Variante 1 avec la comparaison côté serveur : le refus arrive dès le diff (ComparisonError).
  if m20_condition "$_M20_APP_DEV" '^ComparisonError$'; then
    l2="n'a changé en dev. Argo CD affiche une erreur de comparaison sur mediagenda-dev (statut « Unknown »)."
    l3="Lucas propose de « forcer » la synchronisation ou de désactiver l'auto-sync de dev."
  fi
  wb_symptome "Ticket INC-4736 — De : Julien Petit" \
    "La MR de Lucas a été fusionnée ce matin dans mediagenda/deploiement (pipeline vert), mais rien" \
    "$l2" \
    "$l3" \
    "Fais plutôt passer ce qui doit passer, proprement, et explique-moi pourquoi la CI ne l'a pas vu." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 20 36"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 20 E36 4 "$@"; }
fi
