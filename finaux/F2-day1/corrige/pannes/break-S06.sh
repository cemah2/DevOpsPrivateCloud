# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et yq entre apostrophes
# break-S06.sh — F2-S06 : « les premiers pas qui coincent » (la recette de MédiVisio ne démarre plus).
# ⚠️ CORRIGÉ : ce script révèle la panne. Lancé par « lab/bin/break F2 06 [--variante N] [--annuler] ».
#
# Variantes (toutes par UN commit identifiable dans medivisio/consultation-deploiement, overlay de
# recette, auteur Lucas Martin, marqueur F2-S06 ; jamais dans dev ni prod, jamais un objet écrit à la main) :
#   1. quota : réplicas et requests mémoire relevés au-delà du ResourceQuota de medivisio-recette
#      → ReplicaSet « exceeded quota », déploiement bloqué à mi-chemin ;
#   2. image désignée par son ÉTIQUETTE au lieu de son empreinte → refus de la politique Kyverno
#      exiger-signature-medisphere (verifyDigest) ;
#   3. nouveau secret lu dans kv/medivisio/commun/visio, hors de la politique eso-medivisio-recette
#      → ExternalSecret en SecretSyncedError, nouveaux pods en CreateContainerConfigError.
#
# Règles (CONVENTIONS §8, §11.10-11 ; PLAN §4.11 à §4.14 « Pannes ») : contrôle préalable que la recette
# est saine ; sauvegarde du contenu d'origine avant le commit ; constat sur place (verifier_S06) sinon
# annulation ; --annuler = commit INVERSE, seulement si le fichier est encore exactement dans l'état
# injecté (empreinte SHA-256), jamais de réécriture d'historique ; rien sur *-prod, rien dans le coffre,
# aucun Secret lu ni modifié.
#
# Outils sur adm01 : kubectl, jq, curl, yq (mikefarah v4). Variables : WB_GITLAB_URL,
# WB_GITLAB_ADMIN_TOKEN_FILE, WB_K8S_ADMIN_KUBECONFIG, WB_F2_PROJET_DEPLOIEMENT, WB_F2_DEPLOIEMENT, WB_F2_IMAGE.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"

_F2S06_NS=medivisio-recette
_F2S06_PROJET="${WB_F2_PROJET_DEPLOIEMENT:-medivisio/consultation-deploiement}"
_F2S06_DEPLOY="${WB_F2_DEPLOIEMENT:-consultation}"
_F2S06_IMAGE="${WB_F2_IMAGE:-medisphere/medivisio-consultation}"
_F2S06_GITLAB="${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}"
_F2S06_SECRET_HORS=medivisio/commun/visio

# --- État local -----------------------------------------------------------------------------------------
f2s06_etat() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/F2-S06"
  mkdir -p "$d" && chmod 700 "$d"
  printf '%s\n' "$d"
}
f2s06_poser() { (umask 077 && printf '%s\n' "$2" >"$(f2s06_etat)/$1"); }
f2s06_lire() { local f; f="$(f2s06_etat)/$1"; if [[ -f "$f" ]]; then cat "$f"; fi; }
f2s06_journal() { printf '%s [F2-S06 variante %s] %s\n' "$(date -Is)" "${WB_VAR:-?}" "$*" >>"$(f2s06_etat)/journal"; }

# --- GitLab (jeton d'administration de l'apprenant ; jamais en argument) ---------------------------------
_f2s06_enc() { jq -rn --arg s "$1" '$s|@uri'; }
f2s06_api() {
  local m="$1" p="$2" f t
  shift 2
  f="${WB_GITLAB_ADMIN_TOKEN_FILE:-$HOME/.config/workbook/gitlab-admin.token}"
  [[ -r "$f" ]] || { wb_avert "jeton d'administration GitLab illisible : $f"; return 1; }
  t="$(tr -d '[:space:]' <"$f")"
  curl -sf --max-time 30 -X "$m" -H @<(printf 'PRIVATE-TOKEN: %s\n' "$t") "$_F2S06_GITLAB/api/v4/$p" "$@"
}
f2s06_lire_git() { f2s06_api GET "projects/$(_f2s06_enc "$_F2S06_PROJET")/repository/files/$(_f2s06_enc "$1")/raw?ref=main"; }

# f2s06_commit BRANCHE "message" ACTIONS_JSON — un commit (auteur Lucas Martin) ; affiche son identifiant.
f2s06_commit() {
  jq -n --arg b "$1" --arg m "$2" --argjson a "$3" \
    '{branch: $b, commit_message: $m, author_name: "Lucas Martin", author_email: "lucas.martin@medisphere.internal", actions: $a}' |
    f2s06_api POST "projects/$(_f2s06_enc "$_F2S06_PROJET")/repository/commits" -H 'Content-Type: application/json' --data-binary @- |
    jq -r '.id // empty'
}

# f2s06_pousser "message" ACTIONS_JSON — commit direct sur main s'il est accepté, sinon MR fusionnée.
f2s06_pousser() {
  local msg="$1" actions="$2" p br iid etat i sha
  sha="$(f2s06_commit main "$msg" "$actions" 2>/dev/null)" || sha=""
  [[ -n "$sha" ]] && return 0
  p="$(_f2s06_enc "$_F2S06_PROJET")"
  br="lucas/f2-s06-$(date +%s)"
  f2s06_api POST "projects/$p/repository/branches" --data-urlencode "branch=$br" --data-urlencode "ref=main" >/dev/null || return 1
  sha="$(f2s06_commit "$br" "$msg" "$actions")" || sha=""
  [[ -n "$sha" ]] || return 1
  iid="$(f2s06_api POST "projects/$p/merge_requests" --data-urlencode "source_branch=$br" --data-urlencode "target_branch=main" \
    --data-urlencode "title=${msg%%$'\n'*}" --data-urlencode "remove_source_branch=true" | jq -r '.iid // empty')" || iid=""
  [[ -n "$iid" ]] || return 1
  sleep 5
  f2s06_api PUT "projects/$p/merge_requests/$iid/merge" --data-urlencode "auto_merge=true" >/dev/null 2>&1 ||
    f2s06_api PUT "projects/$p/merge_requests/$iid/merge" --data-urlencode "merge_when_pipeline_succeeds=true" >/dev/null 2>&1 ||
    f2s06_api PUT "projects/$p/merge_requests/$iid/merge" >/dev/null 2>&1 || true
  for ((i = 0; i < 40; i++)); do
    etat="$(f2s06_api GET "projects/$p/merge_requests/$iid" | jq -r '.state // empty')" || etat=""
    [[ "$etat" == merged ]] && return 0
    [[ "$etat" == closed ]] && break
    sleep 15
  done
  wb_avert "MR !$iid de $_F2S06_PROJET non fusionnée (pipeline, approbation ?) : fermée"
  f2s06_api PUT "projects/$p/merge_requests/$iid" --data-urlencode "state_event=close" >/dev/null 2>&1 || true
  f2s06_api DELETE "projects/$p/repository/branches/$(_f2s06_enc "$br")" >/dev/null 2>&1 || true
  return 1
}

# --- Argo CD et cluster (kubeconfig d'administration) -----------------------------------------------------

# f2s06_app — nom de l'Application qui livre medivisio-recette depuis le dépôt de déploiement.
f2s06_app() {
  wb_kubectl -n argocd get applications.argoproj.io -o json 2>/dev/null |
    jq -r --arg ns "$_F2S06_NS" --arg r "/${_F2S06_PROJET}(\\.git)?$" '[.items[]
      | select(.spec.destination.namespace == $ns and ((.spec.source.repoURL // "") | test($r)))][0].metadata.name // empty'
}
f2s06_chemin_overlay() {
  wb_kubectl -n argocd get applications.argoproj.io "$1" -o jsonpath='{.spec.source.path}' 2>/dev/null
}
f2s06_app_saine() {
  wb_kubectl -n argocd get applications.argoproj.io "$1" -o json 2>/dev/null |
    jq -e '.status.sync.status == "Synced" and .status.health.status == "Healthy"' >/dev/null 2>&1
}
f2s06_rafraichir() {
  local a
  a="$(f2s06_lire app)"
  [[ -n "$a" ]] && wb_kubectl -n argocd annotate applications.argoproj.io "$a" argocd.argoproj.io/refresh=normal --overwrite >/dev/null 2>&1
  return 0
}
f2s06_deploy_pret() {
  wb_kubectl -n "$_F2S06_NS" get deployment "$_F2S06_DEPLOY" -o json 2>/dev/null |
    jq -e '(.status.availableReplicas // 0) == .spec.replicas and (.status.updatedReplicas // 0) == .spec.replicas' >/dev/null 2>&1
}

# f2s06_attendre SECONDES commande… — relance toutes les 10 s jusqu'à succès ou délai.
f2s06_attendre() {
  local max="$1" t=0
  shift
  while ((t < max)); do
    "$@" && return 0
    sleep 10
    t=$((t + 10))
    f2s06_rafraichir
  done
  "$@"
}

# --- Préparation commune -----------------------------------------------------------------------------------
f2s06_preparer() {
  local app chemin d c
  for c in kubectl jq curl yq; do command -v "$c" >/dev/null 2>&1 || { wb_avert "outil manquant sur adm01 : $c"; return 1; }; done
  yq --version 2>/dev/null | grep -q mikefarah || { wb_avert "yq de mikefarah (v4) attendu"; return 1; }
  app="$(f2s06_app)"
  [[ -n "$app" ]] || { wb_avert "aucune Application ne livre $_F2S06_NS depuis $_F2S06_PROJET (F2-S05 fait ?)"; return 1; }
  f2s06_app_saine "$app" || { wb_avert "l'Application $app n'est pas Synced/Healthy : répare d'abord (lab/bin/check F2 05)"; return 1; }
  f2s06_deploy_pret || { wb_avert "le Deployment $_F2S06_DEPLOY de $_F2S06_NS n'est pas prêt : le lab doit être sain"; return 1; }
  chemin="$(f2s06_chemin_overlay "$app")"
  [[ -n "$chemin" ]] || { wb_avert "chemin de l'overlay de $app illisible"; return 1; }
  d="$(f2s06_etat)"
  f2s06_lire_git "$chemin/kustomization.yaml" >"$d/kustomization.orig" 2>/dev/null || { wb_avert "$chemin/kustomization.yaml introuvable dans $_F2S06_PROJET"; return 1; }
  [[ -s "$d/kustomization.orig" ]] || return 1
  chmod 600 "$d/kustomization.orig"
  f2s06_poser app "$app"
  f2s06_poser chemin "$chemin"
  f2s06_poser debut "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

# f2s06_injecter "message" FICHIER_NEUF [FICHIER_AJOUTÉ CONTENU] — commit de la nouvelle kustomization
# (et d'un fichier ajouté) ; mémorise les empreintes pour l'annulation.
f2s06_injecter() {
  local msg="$1" neuf="$2" ajout="${3:-}" ajout_contenu="${4:-}" chemin actions
  chemin="$(f2s06_lire chemin)"
  actions="$(jq -n --arg p "$chemin/kustomization.yaml" --rawfile c "$neuf" '[{action: "update", file_path: $p, content: $c}]')"
  if [[ -n "$ajout" ]]; then
    actions="$(jq --arg p "$chemin/$ajout" --arg c "$ajout_contenu" '. + [{action: "create", file_path: $p, content: $c}]' <<<"$actions")"
    f2s06_poser ajout "$chemin/$ajout"
  fi
  f2s06_pousser "$msg

Marqueur : F2-S06 (lab/bin/break F2 06)." "$actions" || return 1
  f2s06_poser empreinte "$(sha256sum <"$neuf" | cut -d' ' -f1)"
  f2s06_journal "commit de Lucas sur $_F2S06_PROJET:$chemin/kustomization.yaml${ajout:+ (+ $ajout)}"
  f2s06_rafraichir
}

# --- Variantes ----------------------------------------------------------------------------------------------

# 1. Quota : 3 réplicas à (quota requests.memory / 2 + 64 Mi) chacun : au plus un nouveau pod passe.
panne_S06_v1() {
  local d hard mi r neuf
  f2s06_preparer || return 1
  d="$(f2s06_etat)"
  hard="$(wb_kubectl -n "$_F2S06_NS" get resourcequotas -o json 2>/dev/null |
    jq -r '[.items[].spec.hard["requests.memory"] // empty][0] // empty')"
  [[ -n "$hard" ]] || { wb_avert "aucun ResourceQuota sur requests.memory dans $_F2S06_NS : variante sans effet"; return 1; }
  mi="$(jq -rn --arg q "$hard" '$q | capture("^(?<n>[0-9.]+)(?<u>Ki|Mi|Gi)?$") as $c
       | ($c.n | tonumber) * (if $c.u == null then (1 / 1048576) else {"Ki": (1 / 1024), "Mi": 1, "Gi": 1024}[$c.u] end) | floor' 2>/dev/null || true)"
  if ! [[ "$mi" =~ ^[0-9]+$ ]] || ((mi == 0)); then
    wb_avert "quota mémoire illisible : $hard"
    return 1
  fi
  r=$((mi / 2 + 64))
  neuf="$d/kustomization.neuf"
  R="${r}Mi" DEP="$_F2S06_DEPLOY" yq '.patches = ((.patches // []) + [{
      "target": {"kind": "Deployment", "name": strenv(DEP)},
      "patch": "- op: replace\n  path: /spec/replicas\n  value: 3\n- op: replace\n  path: /spec/template/spec/containers/0/resources/requests/memory\n  value: " + strenv(R) + "\n- op: replace\n  path: /spec/template/spec/containers/0/resources/limits/memory\n  value: " + strenv(R) + "\n"
    }])' "$d/kustomization.orig" >"$neuf" || return 1
  f2s06_injecter "chore(recette): trois réplicas et plus de mémoire pour la démonstration de jeudi" "$neuf"
}

# 2. Image par étiquette : l'empreinte de l'overlay est remplacée par l'étiquette de la même image.
panne_S06_v2() {
  local d dig tag neuf lbl
  f2s06_preparer || return 1
  d="$(f2s06_etat)"
  lbl="$(wb_kubectl get namespace "$_F2S06_NS" -o jsonpath='{.metadata.labels.medisphere\.internal/signature-exigee}' 2>/dev/null || true)"
  if [[ "$lbl" != oui ]] && ! wb_kubectl get imagevalidatingpolicies.policies.kyverno.io exiger-signature-medisphere -o json 2>/dev/null |
      jq -e --arg n "$_F2S06_NS" 'tostring | contains($n)' >/dev/null 2>&1; then
    wb_avert "la politique de signature ne couvre pas $_F2S06_NS : variante 2 sans effet, variante 1 à la place"
    WB_VAR=1
    panne_S06_v1
    return
  fi
  dig="$(DEP="$_F2S06_IMAGE" yq -r '.images[] | select(.name | contains(strenv(DEP))) | .digest // ""' "$d/kustomization.orig" | head -n1)"
  [[ "$dig" =~ ^sha256:[0-9a-f]{64}$ ]] || { wb_avert "l'overlay de recette ne désigne pas l'image par empreinte (images[].digest)"; return 1; }
  tag="$(harbor_api "projects/${_F2S06_IMAGE%%/*}/repositories/${_F2S06_IMAGE#*/}/artifacts/$dig?with_tag=true" 2>/dev/null |
    jq -r '[.tags[]?.name | select(test("^v[0-9]"))][0] // .tags[0].name // empty' 2>/dev/null || true)"
  tag="${tag:-latest}"
  neuf="$d/kustomization.neuf"
  DEP="$_F2S06_IMAGE" TAG="$tag" yq '(.images[] | select(.name | contains(strenv(DEP)))) |= (del(.digest) | .newTag = strenv(TAG))' \
    "$d/kustomization.orig" >"$neuf" || return 1
  f2s06_journal "étiquette utilisée : $tag"
  f2s06_injecter "chore(recette): plus lisible avec l'étiquette de version qu'avec une empreinte" "$neuf"
}

# 3. Secret hors politique : ExternalSecret vers kv/medivisio/commun/visio + variable obligatoire.
panne_S06_v3() {
  local d neuf es
  f2s06_preparer || return 1
  d="$(f2s06_etat)"
  es="# Clé du fournisseur de visioconférence, commune à tous les environnements (« plus simple »).
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: consultation-visio
spec:
  refreshInterval: 15m
  secretStoreRef:
    kind: SecretStore
    name: openbao
  target:
    name: consultation-visio
    creationPolicy: Owner
  data:
    - secretKey: cle
      remoteRef:
        key: $_F2S06_SECRET_HORS
        property: cle
"
  neuf="$d/kustomization.neuf"
  DEP="$_F2S06_DEPLOY" yq '.resources = ((.resources // []) + ["visio.yaml"])
    | .patches = ((.patches // []) + [{
      "target": {"kind": "Deployment", "name": strenv(DEP)},
      "patch": "- op: add\n  path: /spec/template/spec/containers/0/env/-\n  value:\n    name: CONSULTATION_CLE_VISIO\n    valueFrom:\n      secretKeyRef:\n        name: consultation-visio\n        key: cle\n"
    }])' "$d/kustomization.orig" >"$neuf" || return 1
  f2s06_injecter "feat(recette): clé du fournisseur de visio (préparation de l'intégration)" "$neuf" visio.yaml "$es"
}

# --- Constat, annulation, symptôme ------------------------------------------------------------------------

f2s06_constat_rs() {  # REGEX — un ReplicaSet de la recette signale un échec de création correspondant
  wb_kubectl -n "$_F2S06_NS" get replicasets -o json 2>/dev/null |
    jq -e --arg r "$1" 'any(.items[]; any(.status.conditions[]?; .type == "ReplicaFailure" and (.message | test($r; "i"))))' >/dev/null 2>&1 ||
    wb_kubectl -n "$_F2S06_NS" get events --field-selector reason=FailedCreate -o json 2>/dev/null |
    jq -e --arg r "$1" --arg t "$(f2s06_lire debut)" \
      'any(.items[]; ((.lastTimestamp // .eventTime // "") >= $t) and (.message | test($r; "i")))' >/dev/null 2>&1
}
f2s06_constat_es() {
  wb_kubectl -n "$_F2S06_NS" get externalsecrets.external-secrets.io consultation-visio -o json 2>/dev/null |
    jq -e 'any(.status.conditions[]?; .type == "Ready" and .status == "False")' >/dev/null 2>&1
}

verifier_S06() {
  case "$WB_VAR" in
    1) f2s06_attendre 360 f2s06_constat_rs 'exceeded quota|forbidden' ;;
    2) f2s06_attendre 360 f2s06_constat_rs 'denied|exiger-signature|digest|admission' ;;
    3) f2s06_attendre 360 f2s06_constat_es ;;
    *) return 1 ;;
  esac
}

annuler_S06() {
  local d chemin ajout emp actions
  d="$(f2s06_etat)"
  chemin="$(f2s06_lire chemin)"
  emp="$(f2s06_lire empreinte)"
  ajout="$(f2s06_lire ajout)"
  if [[ -n "$chemin" && -n "$emp" && -s "$d/kustomization.orig" ]]; then
    if [[ "$(f2s06_lire_git "$chemin/kustomization.yaml" 2>/dev/null | sha256sum | cut -d' ' -f1)" == "$emp" ]]; then
      actions="$(jq -n --arg p "$chemin/kustomization.yaml" --rawfile c "$d/kustomization.orig" '[{action: "update", file_path: $p, content: $c}]')"
      if [[ -n "$ajout" ]] && f2s06_lire_git "$ajout" >/dev/null 2>&1; then
        actions="$(jq --arg p "$ajout" '. + [{action: "delete", file_path: $p}]' <<<"$actions")"
      fi
      if f2s06_pousser "Revert du commit de Lucas sur l'overlay de recette (lab/bin/break F2 06 --annuler, F2-S06)" "$actions"; then
        f2s06_journal "annulation : overlay de recette remis dans son état d'origine"
      else
        wb_avert "annulation impossible par commit : remets $chemin/kustomization.yaml à la main (copie : $d/kustomization.orig)"
        return 0
      fi
    else
      f2s06_journal "annulation : overlay déjà modifié depuis la panne (réparation de l'apprenant), rien à défaire"
    fi
  fi
  f2s06_rafraichir
  rm -f -- "$d/kustomization.orig" "$d/kustomization.neuf" "$d/app" "$d/chemin" "$d/empreinte" "$d/ajout" "$d/debut"
  return 0
}

symptome_S06() {
  wb_symptome "DEV-3206 — Inès Garnier (MédiVisio)" \
    "« Notre déploiement en recette ne démarre pas, alors que ça marchait en dev ce matin." \
    "  Argo CD dit que tout est synchronisé, mais la nouvelle version n'arrive jamais." \
    "  Léo et Lucas ont touché à la configuration hier soir. On a la démonstration jeudi. »" \
    "" \
    "Espace : medivisio-recette — temps cible : 45 min." \
    "Vérification : lab/bin/check F2 06 · abandon : lab/bin/break F2 06 --annuler"
}

resume_S06() { echo "La recette de MédiVisio ne déploie plus sa nouvelle version (« synchronisé » mais rien ne démarre)."; }

if [[ -z "${WB_PANNES_LIB:-}" ]]; then main() { wb_main F2 S06 3 "$@"; }; fi
