# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et yq entre apostrophes
# break-E23.sh — M28-E23 « Astreinte : un locataire sature le cluster » (espace medidoc-dev seulement).
#
# Une seule variante, en deux temps :
#   (a) commit de Lucas dans plateforme/k8s (fichiers d'espaces/ qui déclarent la LimitRange et le
#       ResourceQuota de medidoc-dev) : LimitRange retirée, quota relevé (« pour le lot d'indexation ») ;
#       dans le MÊME commit, medidoc-dev est exclu (NotIn sur kubernetes.io/metadata.name) des blocs de
#       la GlobalTenantResource de locataires/ qui répliquent une LimitRange (plancher « limites-locataire »
#       de M28-E05, protégé par Capsule : on ne le supprime jamais à la main, c'est Capsule qui le retire
#       quand l'espace ne correspond plus, policy.deletion: Remove). L'état correspondant est appliqué dans
#       le cluster, comme l'aurait fait « task espaces » suivi d'une suppression à la main (task espaces
#       n'élague pas) : LimitRange de l'espace supprimée, quota relevé ; Argo CD (Application locataires)
#       synchronise l'exclusion, et le script attend que medidoc-dev n'ait plus AUCUNE LimitRange ;
#   (b) dans medidoc-dev uniquement, un Deployment « medidoc-indexation » de 2 réplicas qui DÉCLARE des
#       requests à zéro (clés présentes : la ValidatingPolicy exiger-limites du M26 ne vérifie que leur
#       présence) et des limites de 500m CPU / 256 Mi par conteneur : un conteneur boucle sur le CPU,
#       l'autre dépasse sa limite mémoire et se fait tuer (OOMKilled) en boucle.
#
# Garanties (PLAN §4.13 « Pannes ») :
#   - consommation BORNÉE par les limites : au plus 4 × 500m CPU et 4 × 256 Mi pour toute la charge ;
#     le seul conteneur tué est celui de la charge (OOM dans SA limite, pas de pression sur le nœud) ;
#   - classe medisphere-lot (créée en M28-E14, la seule classe basse que le locataire medidoc autorise :
#     une classe dédiée serait refusée par le webhook de Capsule) : le script vérifie avant d'injecter
#     qu'elle est en « preemptionPolicy: Never » et sous medisphere-standard → AUCUNE préemption ;
#     requests à zéro → l'ordonnanceur place toujours les pods, rien n'est évincé pour eux ;
#   - jamais *-prod, kube-system, kyverno, argocd ; aucun secret touché ; le locataire n'est pas modifié.
# Annulation (ne défait jamais la réparation de l'apprenant) : Deployment supprimé s'il est encore celui
# créé par la panne (même uid) ; LimitRange recréée seulement si elle manque ; quota remis seulement s'il
# a encore les valeurs injectées ; commit inverse seulement pour les fichiers encore dans l'état injecté
# (l'exclusion retirée, Capsule recrée le plancher dans medidoc-dev).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m28-commun.sh
source "$WB_ROOT/modules/28-plateforme-dev/corrige/pannes/_m28-commun.sh"

_E23_NS=medidoc-dev
_E23_DEPLOY=medidoc-indexation
_E23_PRIO=medisphere-lot
_E23_PROJET=plateforme/k8s
# Valeurs « relevées » posées sur les clés déjà présentes du quota (Git et cluster, mêmes valeurs).
_E23_RELEVE='{"requests.cpu":"8","limits.cpu":"16","requests.memory":"16Gi","limits.memory":"32Gi","pods":"60"}'
# Filtre yq : l'objet vise medidoc-dev (espace explicite, ou implicite dans espaces/medidoc-dev/).
_E23_YQ_NS='((.metadata.namespace // "") == strenv(NS) or ((.metadata.namespace // "") == "" and strenv(DANS) == "oui"))'
# Filtre yq : blocs (resources[]) d'une GlobalTenantResource qui répliquent une LimitRange.
_E23_YQ_GTR_LR='select(.kind == "GlobalTenantResource") | .spec.resources[] | select(((.rawItems // []) | any_c(.kind == "LimitRange")) or ((.generators // []) | any_c((.template // "") | test("kind: *LimitRange"))))'
# Marqueurs posés par Capsule sur les objets répliqués (matchConditions du webhook « replications »,
# chart 0.15.1) : ces LimitRange-là ne sont jamais supprimées à la main (protégées).
_E23_JQ_REPLIQUE='((.metadata.labels // {}) as $l | ($l["projectcapsule.dev/created-by"] == "replications"
  or $l["projectcapsule.dev/managed-by"] == "replications" or $l["projectcapsule.dev/protected-by"] == "replications"
  or $l["protection.projectcapsule.dev/replications"] == "true"))'

# ---------------------------------------------------------------------------
# État sain
# ---------------------------------------------------------------------------
_e23_sain() {
  m28_outils || return 1
  local e std lot
  for e in E19 E20 E21 E22; do
    if ! _e23_libre "$e"; then
      echo "La panne M28-$e est encore ouverte : répare-la puis lance lab/bin/break 28 ${e#E} --annuler." >&2
      return 1
    fi
  done
  if ! wb_kubectl get namespace "$_E23_NS" >/dev/null 2>&1; then
    echo "Espace $_E23_NS absent (M14-E33) : rien à faire." >&2
    return 1
  fi
  if ! wb_kubectl get tenants.capsule.clastix.io medidoc >/dev/null 2>&1; then
    echo "Locataire medidoc absent : termine M28-E05 et M28-E14." >&2
    return 1
  fi
  lot="$(wb_kubectl get priorityclasses.scheduling.k8s.io "$_E23_PRIO" -o json 2>/dev/null)" || lot=""
  std="$(wb_kubectl get priorityclasses.scheduling.k8s.io medisphere-standard -o jsonpath='{.value}' 2>/dev/null)" || std=""
  if [[ -z "$lot" || -z "$std" ]] ||
    ! jq -e --argjson s "$std" '.preemptionPolicy == "Never" and .value < $s' >/dev/null <<<"$lot"; then
    echo "La classe $_E23_PRIO doit exister, être en « preemptionPolicy: Never » et valoir moins que" >&2
    echo "medisphere-standard (M28-E14) : la panne refuse de lancer une charge qui pourrait préempter." >&2
    return 1
  fi
  if ! wb_kubectl get tenants.capsule.clastix.io medidoc -o json 2>/dev/null |
    jq -e --arg p "$_E23_PRIO" '(.spec.priorityClasses.allowed // [$p]) | index($p) != null' >/dev/null; then
    echo "Le locataire medidoc n'autorise pas $_E23_PRIO (M28-E14) : la charge serait refusée." >&2
    return 1
  fi
  if ! wb_kubectl -n "$_E23_NS" get limitranges -o json 2>/dev/null | jq -e '.items | length >= 1' >/dev/null; then
    echo "$_E23_NS n'a pas de LimitRange : le lab n'est pas dans l'état attendu (lab/bin/check 28 14)." >&2
    return 1
  fi
  if wb_kubectl -n "$_E23_NS" get deployment "$_E23_DEPLOY" >/dev/null 2>&1; then
    echo "Un Deployment $_E23_DEPLOY existe déjà dans $_E23_NS : supprime-le ou lance --annuler." >&2
    return 1
  fi
  if ! wb_kubectl get nodes -o json 2>/dev/null |
    jq -e 'all(.items[]; all(.status.conditions[]; .type != "MemoryPressure" or .status != "True"))' >/dev/null; then
    echo "Un nœud est déjà en pression mémoire : la panne n'est pas lancée." >&2
    return 1
  fi
}

# _e23_libre EXX — aucune panne EXX du module 28 n'est marquée active sur adm01.
_e23_libre() { [[ ! -e "$WB_ETAT_DIR/M28-$1" ]]; }

# ---------------------------------------------------------------------------
# Git : un commit de Lucas qui touche un ou plusieurs fichiers d'espaces/
# ---------------------------------------------------------------------------

# _e23_fichiers — fichiers de plateforme/k8s (espaces/) qui déclarent une LimitRange ou un ResourceQuota
# de medidoc-dev, puis fichiers de locataires/ dont une GlobalTenantResource réplique une LimitRange.
_e23_fichiers() {
  local f dans n
  m28_git_chercher "$_E23_PROJET" 'kind: *(LimitRange|ResourceQuota)' espaces | while IFS= read -r f; do
    dans=non
    [[ "$f" == espaces/"$_E23_NS"/* ]] && dans=oui
    n="$(m28_git_lire "$_E23_PROJET" "$f" 2>/dev/null |
      NS="$_E23_NS" DANS="$dans" yq ea "[select((.kind == \"LimitRange\" or .kind == \"ResourceQuota\") and $_E23_YQ_NS)] | length" 2>/dev/null)" || n=0
    if [[ "$n" =~ ^[0-9]+$ ]] && ((n > 0)); then printf '%s\n' "$f"; fi
  done
  m28_git_chercher "$_E23_PROJET" 'kind: *GlobalTenantResource' locataires | while IFS= read -r f; do
    n="$(m28_git_lire "$_E23_PROJET" "$f" 2>/dev/null | yq ea "[$_E23_YQ_GTR_LR] | length" 2>/dev/null)" || n=0
    if [[ "$n" =~ ^[0-9]+$ ]] && ((n > 0)); then printf '%s\n' "$f"; fi
  done
}

# _e23_transformer CHEMIN — stdin → stdout : retire les LimitRange de medidoc-dev, relève ses quotas,
# exclut medidoc-dev des blocs de GlobalTenantResource qui répliquent une LimitRange.
_e23_transformer() {
  local dans=non
  [[ "$1" == espaces/"$_E23_NS"/* ]] && dans=oui
  NS="$_E23_NS" DANS="$dans" yq "select((.kind == \"LimitRange\" and $_E23_YQ_NS) | not)" |
    NS="$_E23_NS" DANS="$dans" RELEVE="$_E23_RELEVE" \
      yq "(strenv(RELEVE) | from_json) as \$m | (select(.kind == \"ResourceQuota\" and $_E23_YQ_NS) | .spec.hard) |= with_entries(.value = (\$m[.key] // .value))" |
    NS="$_E23_NS" yq "($_E23_YQ_GTR_LR) |= (.namespaceSelector.matchExpressions = ((.namespaceSelector.matchExpressions // []) + [{\"key\": \"kubernetes.io/metadata.name\", \"operator\": \"NotIn\", \"values\": [strenv(NS)]}]))"
}

# _e23_vide FICHIER — le fichier ne contient plus aucun objet (seulement blancs, commentaires, « --- »).
_e23_vide() { ! grep -Eqv '^[[:space:]]*(#.*)?$|^---[[:space:]]*$' "$1"; }

# _e23_commit BRANCHE "message" ACTIONS_JSON [lucas] — un commit à plusieurs actions ; affiche le sha.
_e23_commit() {
  local br="$1" msg="$2" actions="$3" qui="${4:-}" corps
  corps="$(jq -n --arg b "$br" --arg m "$msg" --argjson a "$actions" \
    --arg an "$_M28_LUCAS_NOM" --arg ae "$_M28_LUCAS_COURRIEL" --arg q "$qui" \
    '{branch: $b, commit_message: $m, actions: $a}
     + (if $q == "lucas" then {author_name: $an, author_email: $ae} else {} end)')"
  m28_api POST "projects/$(_m28_enc "$_E23_PROJET")/repository/commits" \
    -H 'Content-Type: application/json' --data-binary "$corps" | jq -r '.id // empty'
}

# _e23_pousser "message" ACTIONS_JSON [lucas] — commit direct sur main si accepté, sinon MR fusionnée.
_e23_pousser() {
  local msg="$1" actions="$2" qui="${3:-}" br sha
  sha="$(_e23_commit main "$msg" "$actions" "$qui" 2>/dev/null)" || sha=""
  [[ -n "$sha" ]] && return 0
  br="${qui:-moi}/m28-e23-$(date +%s)"
  m28_api POST "projects/$(_m28_enc "$_E23_PROJET")/repository/branches" \
    --data-urlencode "branch=$br" --data-urlencode "ref=main" >/dev/null || return 1
  sha="$(_e23_commit "$br" "$msg" "$actions" "$qui")" || sha=""
  [[ -n "$sha" ]] || return 1
  _m28_mr_fusionner "$_E23_PROJET" "$br" "${msg%%$'\n'*}"
}

# _e23_git_injecter — prépare et pousse le commit de Lucas ; mémorise chaque fichier (origine, empreinte).
_e23_git_injecter() {
  local d f i=0 actions='[]' orig neuf
  d="$(m28_etat E23)"
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    i=$((i + 1))
    orig="$d/git-orig-$i"
    neuf="$d/git-neuf-$i"
    m28_git_lire "$_E23_PROJET" "$f" >"$orig" 2>/dev/null || return 1
    _e23_transformer "$f" <"$orig" >"$neuf" || return 1
    chmod 600 "$orig" "$neuf"
    if cmp -s "$orig" "$neuf"; then
      rm -f "$orig" "$neuf"
      i=$((i - 1))
      continue
    fi
    m28_poser E23 "git-chemin-$i" "$f"
    if _e23_vide "$neuf"; then
      m28_poser E23 "git-empreinte-$i" ABSENT
      actions="$(jq --arg p "$f" '. + [{action: "delete", file_path: $p}]' <<<"$actions")"
    else
      m28_poser E23 "git-empreinte-$i" "$(sha256sum "$neuf" | cut -d' ' -f1)"
      actions="$(jq --arg p "$f" --rawfile c "$neuf" '. + [{action: "update", file_path: $p, content: $c}]' <<<"$actions")"
    fi
  done < <(_e23_fichiers)
  ((i > 0)) || { wb_avert "aucun fichier de plateforme/k8s ne déclare la LimitRange ou le quota de $_E23_NS"; return 1; }
  m28_poser E23 git-nb "$i"
  _e23_pousser "chore(medidoc-dev): LimitRange retirée et quota relevé pour le lot d'indexation (M28-E23)

Le lot de vignettes de MédiDoc ne passait pas avec les valeurs par défaut. medidoc-dev
sorti des limites par défaut des locataires le temps du lot. Appliqué avec task espaces.
Je remettrai après la campagne. -- Lucas" "$actions" lucas || return 1
  m28_journal E23 "commit de Lucas sur $_E23_PROJET ($i fichier(s))"
}

# _e23_git_annuler — commit inverse pour les fichiers encore exactement dans l'état injecté.
_e23_git_annuler() {
  local d nb i f emp actions='[]' actuel
  d="$(m28_etat E23)"
  nb="$(m28_lire E23 git-nb)"
  [[ "$nb" =~ ^[0-9]+$ ]] || return 0
  for ((i = 1; i <= nb; i++)); do
    f="$(m28_lire E23 "git-chemin-$i")"
    emp="$(m28_lire E23 "git-empreinte-$i")"
    [[ -n "$f" && -n "$emp" && -f "$d/git-orig-$i" ]] || continue
    if [[ "$emp" == ABSENT ]]; then
      if ! m28_git_lire "$_E23_PROJET" "$f" >/dev/null 2>&1; then
        actions="$(jq --arg p "$f" --rawfile c "$d/git-orig-$i" '. + [{action: "create", file_path: $p, content: $c}]' <<<"$actions")"
      else
        m28_journal E23 "annulation : $f recréé depuis la panne, rien à défaire"
      fi
    else
      actuel="$(m28_git_lire "$_E23_PROJET" "$f" 2>/dev/null | sha256sum | cut -d' ' -f1)"
      if [[ "$actuel" == "$emp" ]]; then
        actions="$(jq --arg p "$f" --rawfile c "$d/git-orig-$i" '. + [{action: "update", file_path: $p, content: $c}]' <<<"$actions")"
      else
        m28_journal E23 "annulation : $f modifié depuis la panne, rien à défaire"
      fi
    fi
  done
  if [[ "$(jq 'length' <<<"$actions")" -gt 0 ]]; then
    if _e23_pousser "Revert du commit de Lucas sur medidoc-dev (lab/bin/break 28 23 --annuler, M28-E23)" "$actions"; then
      m28_journal E23 "annulation : fichiers d'espaces/ remis dans leur état d'origine"
    else
      wb_avert "commit inverse impossible : remets les fichiers à la main (copies : $d/git-orig-*)"
      return 0
    fi
  fi
  for ((i = 1; i <= nb; i++)); do
    rm -f -- "$d/git-orig-$i" "$d/git-neuf-$i"
    m28_oublier E23 "git-chemin-$i"
    m28_oublier E23 "git-empreinte-$i"
  done
  m28_oublier E23 git-nb
}

# ---------------------------------------------------------------------------
# Cluster : garde-fous de l'espace et charge
# ---------------------------------------------------------------------------

# _e23_garde_fous_retirer — sauvegarde puis supprime les LimitRange de l'espace (jamais celles que Capsule
# réplique : Argo CD synchronise l'exclusion et Capsule les retire) ; relève les quotas déclarés en Git.
_e23_garde_fous_retirer() {
  local d lr rq noms nb i f dans
  d="$(m28_etat E23)"
  for lr in $(wb_kubectl -n "$_E23_NS" get limitranges -o json 2>/dev/null |
    jq -r "[.items[] | select($_E23_JQ_REPLIQUE | not) | .metadata.name] | .[]"); do
    wb_kubectl -n "$_E23_NS" get limitrange "$lr" -o json 2>/dev/null |
      jq 'del(.metadata.uid, .metadata.resourceVersion, .metadata.creationTimestamp, .metadata.managedFields, .metadata.generation, .status)' \
        >"$d/lr-$lr.json" || return 1
    chmod 600 "$d/lr-$lr.json"
    # Refus (objet protégé par un webhook, marqueur de réplication inattendu) : on n'insiste pas, l'attente
    # ci-dessous décide si la panne est posée.
    if ! wb_kubectl -n "$_E23_NS" delete limitrange "$lr" --wait=false >/dev/null 2>&1; then
      rm -f -- "$d/lr-$lr.json"
      m28_journal E23 "LimitRange $lr non supprimée (refusée) : laissée à Capsule"
    fi
  done
  # Quotas : ceux que les fichiers de Git déclarent pour medidoc-dev (noms lus dans les originaux).
  noms=""
  nb="$(m28_lire E23 git-nb)"
  for ((i = 1; i <= ${nb:-0}; i++)); do
    f="$(m28_lire E23 "git-chemin-$i")"
    dans=non
    [[ "$f" == espaces/"$_E23_NS"/* ]] && dans=oui
    noms+=" $(NS="$_E23_NS" DANS="$dans" yq "select(.kind == \"ResourceQuota\" and $_E23_YQ_NS) | .metadata.name" "$d/git-orig-$i" 2>/dev/null | grep -v '^---$' | tr '\n' ' ')"
  done
  for rq in $noms; do
    [[ "$rq" =~ ^[a-z0-9.-]+$ ]] || continue
    wb_kubectl -n "$_E23_NS" get resourcequota "$rq" -o jsonpath='{.spec.hard}' >"$d/rq-$rq.orig" 2>/dev/null || continue
    jq -c --argjson m "$_E23_RELEVE" 'with_entries(.value = ($m[.key] // .value))' "$d/rq-$rq.orig" >"$d/rq-$rq.injecte" || return 1
    wb_kubectl -n "$_E23_NS" patch resourcequota "$rq" --type=merge \
      -p "$(jq -c '{spec: {hard: .}}' "$d/rq-$rq.injecte")" >/dev/null || return 1
  done
  # Plancher répliqué par Capsule (M28-E05) : retiré par Capsule après la synchronisation de l'exclusion.
  m28_rafraichir locataires
  if ! m28_attendre 300 _e23_sans_limitrange; then
    wb_avert "$_E23_NS a encore une LimitRange après 5 min (Application locataires synchronisée ? réplication de Capsule ?)"
    return 1
  fi
}

# _e23_sans_limitrange — l'API répond et medidoc-dev n'a plus aucune LimitRange.
_e23_sans_limitrange() {
  wb_kubectl -n "$_E23_NS" get limitranges -o json 2>/dev/null | jq -e '.items | length == 0' >/dev/null 2>&1
}

_e23_garde_fous_rendre() {
  local d f lr rq actuel
  d="$(m28_etat E23)"
  for f in "$d"/lr-*.json; do
    [[ -e "$f" ]] || continue
    lr="$(jq -r '.metadata.name' "$f")"
    if ! wb_kubectl -n "$_E23_NS" get limitrange "$lr" >/dev/null 2>&1 &&
      [[ -z "$(wb_kubectl -n "$_E23_NS" get limitranges -o name 2>/dev/null)" ]]; then
      wb_kubectl create -f "$f" >/dev/null 2>&1 || { wb_avert "LimitRange $lr non recréée (copie : $f)"; continue; }
      m28_journal E23 "annulation : LimitRange $lr recréée"
    fi
    rm -f -- "$f"
  done
  for f in "$d"/rq-*.orig; do
    [[ -e "$f" ]] || continue
    rq="$(basename "$f" .orig)"
    rq="${rq#rq-}"
    actuel="$(wb_kubectl -n "$_E23_NS" get resourcequota "$rq" -o jsonpath='{.spec.hard}' 2>/dev/null | jq -cS . 2>/dev/null)" || actuel=""
    if [[ -n "$actuel" && "$actuel" == "$(jq -cS . "$d/rq-$rq.injecte" 2>/dev/null)" ]]; then
      wb_kubectl -n "$_E23_NS" patch resourcequota "$rq" --type=merge -p "$(jq -c '{spec: {hard: .}}' "$f")" >/dev/null 2>&1 ||
        wb_avert "quota $rq non remis (valeurs d'origine : $f)"
      m28_journal E23 "annulation : quota $rq remis à ses valeurs d'origine"
    fi
    rm -f -- "$f" "$d/rq-$rq.injecte"
  done
}

_e23_lancer_charge() {
  wb_kubectl apply -f - >/dev/null <<EOF || return 1
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $_E23_DEPLOY
  namespace: $_E23_NS
  labels:
    app.kubernetes.io/name: $_E23_DEPLOY
    app.kubernetes.io/part-of: medidoc
    medisphere.internal/equipe: medidoc
  annotations:
    medisphere.internal/auteur: lucas.martin
    kubernetes.io/change-cause: "lot d'indexation des vignettes (essai à la main)"
spec:
  replicas: 2
  selector:
    matchLabels:
      app.kubernetes.io/name: $_E23_DEPLOY
  template:
    metadata:
      labels:
        app.kubernetes.io/name: $_E23_DEPLOY
        medisphere.internal/equipe: medidoc
    spec:
      priorityClassName: $_E23_PRIO
      automountServiceAccountToken: false
      terminationGracePeriodSeconds: 5
      securityContext:
        runAsNonRoot: true
        runAsUser: 65534
        runAsGroup: 65534
        seccompProfile:
          type: RuntimeDefault
      affinity:
        podAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                topologyKey: kubernetes.io/hostname
                labelSelector:
                  matchLabels:
                    app.kubernetes.io/name: $_E23_DEPLOY
      containers:
        - name: indexation
          image: $_M28_IMAGE_BB
          command: ["sh", "-c", "while :; do :; done"]
          resources:
            requests: {cpu: "0", memory: "0"}
            limits: {cpu: 500m, memory: 256Mi}
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities: {drop: [ALL]}
        - name: tampon
          image: $_M28_IMAGE_BB
          command: ["sh", "-c", "sleep 45; dd if=/dev/zero of=/dev/null bs=300M count=1; sleep 86400"]
          resources:
            requests: {cpu: "0", memory: "0"}
            limits: {cpu: 500m, memory: 256Mi}
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities: {drop: [ALL]}
EOF
  m28_poser E23 uid "$(wb_kubectl -n "$_E23_NS" get deployment "$_E23_DEPLOY" -o jsonpath='{.metadata.uid}' 2>/dev/null)"
  m28_journal E23 "Deployment $_E23_DEPLOY créé dans $_E23_NS"
}

_e23_arreter_charge() {
  local uid actuel
  uid="$(m28_lire E23 uid)"
  [[ -n "$uid" ]] || return 0
  actuel="$(wb_kubectl -n "$_E23_NS" get deployment "$_E23_DEPLOY" -o jsonpath='{.metadata.uid}' 2>/dev/null)" || actuel=""
  if [[ "$actuel" == "$uid" ]]; then
    wb_kubectl -n "$_E23_NS" delete deployment "$_E23_DEPLOY" --wait=false >/dev/null 2>&1 || true
    m28_journal E23 "annulation : Deployment $_E23_DEPLOY supprimé"
  fi
  m28_oublier E23 uid
}

# ---------------------------------------------------------------------------
# Constat sur place
# ---------------------------------------------------------------------------
_e23_pods_hors_cadre() {
  wb_kubectl -n "$_E23_NS" get pods -l "app.kubernetes.io/name=$_E23_DEPLOY" -o json 2>/dev/null | jq -e '
    [.items[] | select(.status.phase == "Running")
     | select(any(.spec.containers[]; (.resources.requests.cpu // "0") | test("^0+(\\.0+)?[a-zA-Z]*$")))]
    | length >= 1' >/dev/null 2>&1
}
_e23_effective() {
  [[ -z "$(wb_kubectl -n "$_E23_NS" get limitranges -o name 2>/dev/null)" ]] && _e23_pods_hors_cadre
}

panne_E23_v1() {
  _e23_sain || return 1
  _e23_git_injecter || return 1
  _e23_garde_fous_retirer || return 1
  _e23_lancer_charge || return 1
  m28_attendre 240 _e23_pods_hors_cadre || return 1
  m28_journal E23 "panne posée"
}

verifier_E23() { _e23_effective; }

annuler_E23() {
  _e23_arreter_charge || true
  _e23_garde_fous_rendre || true
  _e23_git_annuler || true
  # Exclusion retirée de la GlobalTenantResource : Argo CD la resynchronise, Capsule recrée le plancher.
  m28_rafraichir locataires
  m28_journal E23 "annulation"
}

resume_E23() { echo "Un travailleur s'emballe et des pods de MédiDoc meurent en boucle ; plusieurs équipes se plaignent."; }

symptome_E23() {
  wb_symptome "Ticket INC-5523 — De : Nadia Roussel — Copie : Claire Morel" \
    "Depuis quelques minutes, plusieurs signaux en même temps : des conteneurs de l'équipe MédiDoc" \
    "redémarrent en boucle, un travailleur affiche un CPU anormalement haut, et Julien trouve la" \
    "recette « poussive ». Personne n'aurait rien déployé. Tu es d'astreinte : endigue d'abord, trouve" \
    "ensuite, corrige par le code, puis le post-mortem. Karim est joignable pour une décision." \
    "" \
    "Temps cible : 1 h 30 à 2 h, post-mortem compris. Contrôle : lab/bin/check 28 23"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 28 E23 1 "$@"; }
fi
