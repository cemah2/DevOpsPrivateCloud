# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E38.sh — M20-E38 « Panne : l'application est Degraded après synchronisation »
#
# Cible : l'Application mediagenda-dev. La synchronisation réussit, mais ce qu'elle applique ne
# devient jamais sain :
#   1. digest d'image de l'overlay de dev remplacé par un digest qui n'existe pas dans Harbor
#      (commit de Lucas ; sautée si une porte de la CI — vérification des signatures — refuse la MR) ;
#   2. sonde de disponibilité de l'API pointée sur /ready au lieu de /pret (commit de Lucas) ;
#   3. volume persistant ajouté avec une classe de stockage qui n'existe pas (ceph-rbd-ssd) et monté
#      dans le pod (commit de Lucas) : PVC Pending, nouveau pod Pending ;
#   4. contrôle de santé personnalisé des bases CNPG ajouté à la main dans argocd-cm (Lua qui
#      attend une phase « Healthy » que CNPG ne publie pas) : la base est déclarée Degraded alors
#      qu'elle va bien (dev ET prod affichés Degraded).
# Rolling update : l'ancien pod de dev reste en service pendant les variantes 1 à 3.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m20-commun.sh
source "$WB_ROOT/modules/20-gitops/corrige/pannes/_m20-commun.sh"

_E38_DOSSIER="${WB_M20_OVERLAY_DEV:-overlays/dev}"
_E38_KUSTO="$_E38_DOSSIER/kustomization.yaml"
_E38_FAUX="sha256:9c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d"
_E38_CLE="resource.customizations.health.postgresql.cnpg.io_Cluster"

# _e38_pods_recents 'filtre jq' — un pod de l'API créé depuis l'injection satisfait le filtre.
_e38_pods_recents() {
  local debut
  debut="$(m20_lire E38 debut)"
  wb_kubectl -n "$_M20_NS_DEV" get pods -l app.kubernetes.io/name=mediagenda -o json 2>/dev/null |
    jq -e --argjson t "${debut:-0}" "[.items[] | select((.metadata.creationTimestamp | fromdateiso8601) >= (\$t - 5)) | select($1)] | length > 0" >/dev/null 2>&1
}

_e38_tirage_ko() { _e38_pods_recents '[.status.containerStatuses[]?.state.waiting.reason // empty] | any(. == "ErrImagePull" or . == "ImagePullBackOff")'; }
_e38_jamais_pret() {
  _e38_pods_recents '.status.phase == "Running" and ([.status.conditions[]? | select(.type == "Ready" and .status == "False")] | length > 0)' &&
    wb_kubectl -n "$_M20_NS_DEV" get events -o json 2>/dev/null | jq -e '[.items[] | select(.reason == "Unhealthy") | select((.message // "") | test("[Rr]eadiness"))] | length > 0' >/dev/null 2>&1
}
_e38_en_attente() { _e38_pods_recents '.status.phase == "Pending" and ([.status.conditions[]? | select(.type == "PodScheduled" and .status == "False")] | length > 0)'; }
_e38_sante_faussee() {
  m20_rafraichir "$_M20_APP_DEV"
  m20_app "$_M20_APP_DEV" | jq -e '.status.health.status == "Degraded"
    and ([.status.resources[]? | select(.kind == "Cluster" and (.health.status // "") == "Degraded")] | length > 0)' >/dev/null 2>&1
}

_e38_patch_kusto() {
  local t
  t="$(mktemp)"
  m20_brut "$_M20_DEPLOIEMENT" "$_E38_KUSTO" >"$t" 2>/dev/null || { rm -f "$t"; return 1; }
  env "$@" yq -i "$_E38_EXPR" "$t" 2>/dev/null || { rm -f "$t"; return 1; }
  printf '%s\n' "$t"
}

# _e38_rendu_ok KUSTO [CHEMIN FICHIER] — le rendu réussit et ne fait disparaître aucun objet.
_e38_rendu_ok() {
  local d dir avant apres
  d="$(m20_copie "$_M20_DEPLOIEMENT")" || return 1
  dir="$d/$_E38_DOSSIER"
  avant="$(m20_rendu "$dir")"
  cp "$1" "$d/$_E38_KUSTO"
  if [[ -n "${2:-}" ]]; then cp "$3" "$d/$2"; fi
  if ! kubectl kustomize "$dir" >/dev/null 2>&1; then rm -rf -- "$(dirname "$d")"; return 1; fi
  apres="$(m20_rendu "$dir")"
  rm -rf -- "$(dirname "$d")"
  [[ -z "$(comm -23 <(printf '%s\n' "$avant") <(printf '%s\n' "$apres"))" ]]
}

_e38_deploy() { wb_kubectl -n "$_M20_NS_DEV" get deploy mediagenda -o json 2>/dev/null; }

_m20E38_une() {
  local n="$1" f fichier digest t pvc conteneur idx actions lua
  m20_debut E38
  case "$n" in
    1)
      fichier=""
      for f in "$_E38_KUSTO" "$_E38_DOSSIER/livraison.yaml"; do
        if m20_brut "$_M20_DEPLOIEMENT" "$f" 2>/dev/null | grep -Eq 'sha256:[0-9a-f]{64}'; then fichier="$f"; break; fi
      done
      [[ -n "$fichier" ]] || return 10
      t="$(mktemp)"
      m20_brut "$_M20_DEPLOIEMENT" "$fichier" >"$t"
      digest="$(grep -Eo 'sha256:[0-9a-f]{64}' "$t" | head -n 1)"
      sed -i "s/${digest}/${_E38_FAUX}/g" "$t"
      actions="[$(m20_action update "$fichier" "$t")]"
      rm -f "$t"
      m20_commit_lucas E38 "$_M20_DEPLOIEMENT" "lucas/dev-image-reconstruite" \
        "chore(dev): image de l'API reconstruite ce matin" \
        "DEV-2138 : j'ai reconstruit l'image de l'API sur mon poste et recopié le nouveau digest." "$actions" || return $?
      m20_rafraichir "$_M20_APP_DEV"
      m20_attendre 300 _e38_tirage_ko || { _e38_defaire 1; return 10; }
      ;;
    2)
      idx="$(_e38_deploy | jq -r '[.spec.template.spec.containers | to_entries[] | select(.value.readinessProbe.httpGet.path == "/pret") | .key][0] // empty')"
      [[ -n "$idx" ]] || return 10
      _E38_EXPR='.patches += [{"target": {"kind": "Deployment", "name": "mediagenda"}, "patch": strenv(P)}] | .patches[-1].patch style="literal"'
      t="$(_e38_patch_kusto "P=$(printf -- '- op: replace\n  path: /spec/template/spec/containers/%s/readinessProbe/httpGet/path\n  value: /ready\n' "$idx")")" || return 10
      _e38_rendu_ok "$t" || { rm -f "$t"; return 10; }
      actions="[$(m20_action update "$_E38_KUSTO" "$t")]"
      rm -f "$t"
      m20_commit_lucas E38 "$_M20_DEPLOIEMENT" "lucas/dev-sondes-standard" \
        "chore(dev): sondes alignées sur le standard des autres équipes" \
        "DEV-2138 : /ready partout, comme MédiDoc et le reste du marché." "$actions" || return $?
      m20_rafraichir "$_M20_APP_DEV"
      m20_attendre 300 _e38_jamais_pret || { _e38_defaire 2; return 10; }
      ;;
    3)
      if wb_kubectl get storageclass ceph-rbd-ssd >/dev/null 2>&1; then return 10; fi
      if wb_kubectl -n "$_M20_NS_DEV" get pvc mediagenda-exports >/dev/null 2>&1; then return 10; fi
      conteneur="$(_e38_deploy | jq -r '.spec.template.spec.containers[0].name // empty')"
      [[ -n "$conteneur" ]] || return 10
      pvc="$(mktemp)"
      cat >"$pvc" <<'EOF'
# Exports CSV des rendez-vous (DEV-2138) : volume dédié, sur SSD.
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mediagenda-exports
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: ceph-rbd-ssd
  resources:
    requests:
      storage: 1Gi
EOF
      _E38_EXPR='.resources += ["exports.yaml"] | .patches += [{"patch": strenv(P)}] | .patches[-1].patch style="literal"'
      t="$(_e38_patch_kusto "P=$(printf 'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: mediagenda\nspec:\n  template:\n    spec:\n      volumes:\n        - name: exports\n          persistentVolumeClaim:\n            claimName: mediagenda-exports\n      containers:\n        - name: %s\n          volumeMounts:\n            - name: exports\n              mountPath: /var/lib/mediagenda/exports\n' "$conteneur")")" || { rm -f "$pvc"; return 10; }
      _e38_rendu_ok "$t" "$_E38_DOSSIER/exports.yaml" "$pvc" || { rm -f "$t" "$pvc"; return 10; }
      actions="[$(m20_action update "$_E38_KUSTO" "$t"),$(m20_action create "$_E38_DOSSIER/exports.yaml" "$pvc")]"
      rm -f "$t" "$pvc"
      m20_commit_lucas E38 "$_M20_DEPLOIEMENT" "lucas/dev-volume-exports" \
        "feat(dev): volume pour les exports CSV" \
        "DEV-2138 : l'API écrira ses exports dans /var/lib/mediagenda/exports (classe SSD)." "$actions" || return $?
      m20_ecrire E38 pvc mediagenda-exports
      m20_rafraichir "$_M20_APP_DEV"
      m20_attendre 300 _e38_en_attente || { _e38_defaire 3; return 10; }
      ;;
    4)
      m20_app "$_M20_APP_DEV" | jq -e '[.status.resources[]? | select(.group == "postgresql.cnpg.io" and .kind == "Cluster")] | length > 0' >/dev/null 2>&1 || return 10
      wb_kubectl -n "$_M20_NS" get configmap argocd-cm -o json 2>/dev/null | jq -e --arg k "$_E38_CLE" '.data[$k] == null' >/dev/null 2>&1 || return 10
      lua="$(cat <<'EOF'
-- Santé des bases PostgreSQL (DEV-2138, Lucas) : reprise de notre ancien opérateur.
hs = {}
hs.status = "Degraded"
hs.message = "La base n'est pas encore prête"
if obj.status ~= nil and obj.status.phase == "Healthy" then
  hs.status = "Healthy"
  hs.message = "Base prête"
end
return hs
EOF
)"
      m20_sauver_objet E38 configmap argocd-cm "$_M20_NS" || return 1
      wb_kubectl -n "$_M20_NS" patch configmap argocd-cm --type merge \
        -p "$(jq -nc --arg k "$_E38_CLE" --arg v "$lua" '{data: {($k): $v}}')" >/dev/null || return 1
      m20_ecrire E38 lua posee
      m20_journal E38 "argocd-cm : contrôle de santé CNPG personnalisé ajouté"
      m20_attendre 300 _e38_sante_faussee || { _e38_defaire 4; return 10; }
      ;;
  esac
  m20_journal E38 "variante $n posée"
}

_e38_defaire() {
  local n="$1" p
  case "$n" in
    1 | 2 | 3)
      m20_defaire_commits E38
      m20_rafraichir hard "$_M20_APP_DEV"
      p="$(m20_lire E38 pvc)"
      if [[ -n "$p" ]]; then
        # Le PVC de la panne n'a jamais été lié (classe inexistante) : il ne contient aucune donnée.
        sleep 20
        if wb_kubectl -n "$_M20_NS_DEV" get pvc "$p" -o json 2>/dev/null | jq -e '.status.phase == "Pending" and .spec.storageClassName == "ceph-rbd-ssd"' >/dev/null 2>&1; then
          wb_kubectl -n "$_M20_NS_DEV" delete pvc "$p" --wait=false >/dev/null 2>&1 || true
        fi
        m20_oublier E38 pvc
      fi
      ;;
    4)
      if [[ -n "$(m20_lire E38 lua)" ]]; then
        if wb_kubectl -n "$_M20_NS" get configmap argocd-cm -o json 2>/dev/null |
          jq -e --arg k "$_E38_CLE" '(.data[$k] // "") | test("DEV-2138")' >/dev/null 2>&1; then
          wb_kubectl -n "$_M20_NS" patch configmap argocd-cm --type json \
            -p "[{\"op\":\"remove\",\"path\":\"/data/$_E38_CLE\"}]" >/dev/null 2>&1 || wb_avert "clé $_E38_CLE non retirée de argocd-cm"
        fi
        m20_oublier E38 lua
      fi
      m20_oublier_objet E38 configmap argocd-cm "$_M20_NS"
      m20_rafraichir "$_M20_APP_DEV"
      ;;
  esac
}

panne_E38_v1() { m20_preparer "$_M20_APP_DEV" && m20_essayer E38 4 1; }
panne_E38_v2() { m20_preparer "$_M20_APP_DEV" && m20_essayer E38 4 2; }
panne_E38_v3() { m20_preparer "$_M20_APP_DEV" && m20_essayer E38 4 3; }
panne_E38_v4() { m20_preparer "$_M20_APP_DEV" && m20_essayer E38 4 4; }

verifier_E38() {
  case "${WB_VAR:-}" in
    1) _e38_tirage_ko ;;
    2) _e38_jamais_pret ;;
    3) _e38_en_attente ;;
    4) _e38_sante_faussee ;;
    *) return 1 ;;
  esac
}

annuler_E38() {
  case "${WB_VAR:-}" in
    [1-4]) _e38_defaire "$WB_VAR" ;;
    *) _e38_defaire 1; _e38_defaire 4 ;;
  esac
  m20_oublier E38 debut
  m20_journal E38 "annulation"
}

resume_E38() {
  case "${WB_VAR:-}" in
    4) echo "Argo CD déclare MédiAgenda dev (et la prod) Degraded, la base en cause ; les équipes disent que tout marche." ;;
    *) echo "MédiAgenda dev est « Synced » mais « Progressing » puis « Degraded » : la nouvelle version ne démarre pas." ;;
  esac
}

symptome_E38() {
  case "${WB_VAR:-}" in
    4)
      wb_symptome "Ticket INC-4738 — De : Nadia Roussel" \
        "Mailpit déborde de notifications « health degraded » d'Argo CD pour mediagenda-dev et pour" \
        "mediagenda-prod. Julien jure que l'application répond, en dev comme en prod, et les clients" \
        "n'ont rien remarqué. Soit Argo CD ment, soit on rate quelque chose : tranche, corrige, et" \
        "fais en sorte que l'alerte de prod redevienne fiable." \
        "" \
        "Temps cible : 30 min. Contrôle : lab/bin/check 20 38"
      ;;
    *)
      wb_symptome "Ticket INC-4738 — De : Julien Petit" \
        "La dernière MR sur l'overlay de dev est fusionnée et Argo CD dit « Synced », mais l'application" \
        "est « Progressing » depuis un moment et va finir « Degraded ». L'ancienne version répond" \
        "encore, la nouvelle ne démarre pas. Ça bloque nos tests de l'après-midi." \
        "" \
        "Temps cible : 30 min. Contrôle : lab/bin/check 20 38"
      ;;
  esac
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 20 E38 4 "$@"; }
fi
