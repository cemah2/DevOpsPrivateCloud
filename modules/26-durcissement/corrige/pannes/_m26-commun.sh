# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq/yq et scripts distants entre apostrophes
# _m26-commun.sh — fonctions partagées par les scripts de panne du module 26 (M26-E35 à M26-E43).
#
# Sourcé par break-EXX.sh APRÈS lab/lib/pannes-lib.sh (wb_exec, wb_exec_invite, wb_kubectl, wb_avert,
# WB_EX, WB_VAR…). Rappel : lab/bin/break tourne avec « set -euo pipefail » ; les fonctions d'annulation
# sont appelées hors de tout « if » : aucune commande ne doit y échouer sans « || true ».
#
# Principes (CONVENTIONS §8, PLAN §4.12 « Pannes du bloc F ») :
#   - les politiques Kyverno, les étiquettes d'espaces, les règles Falco/Tetragon et le pare-feu d'hôte
#     vivent dans Git (plateforme/politiques, plateforme/k8s) et sont réconciliés par Argo CD (selfHeal) :
#     une panne « humaine » passe par une MR de lucas.martin (jeton d'emprunt d'identité créé par ton
#     jeton d'administration GitLab WB_GITLAB_ADMIN_TOKEN_FILE, puis révoqué), fusionnée (fusion
#     automatique au succès du pipeline si le projet l'exige) ; le commit porte le marqueur « M26-EXX » ;
#     l'annulation passe par une seconde MR (« revert(M26-EXX) ») qui applique la transformation INVERSE,
#     et seulement si la marque de la panne est encore dans le fichier (une réparation de l'apprenant
#     n'est jamais défaite, l'historique n'est jamais réécrit). Si le pipeline refuse la MR de Lucas, la
#     variante est « sans effet » (la CI a fait son travail) et le script en essaie une autre ;
#   - jamais sur kube-system, kyverno lui-même, argocd, cilium ni les espaces de supervision ;
#   - pour les hôtes : jamais adm01, gw01, gw02 (bordure), pbs01, ni le réseau de pve01 ; les pannes qui
#     cassent sudo ou SSH d'une VM s'annulent par l'agent QEMU (wb_exec_invite, qm guest exec), jamais en
#     dépendant de l'accès cassé ; un objet modifié est toujours sauvegardé avant (fichier sur la VM,
#     objet Kubernetes en JSON sur adm01) ;
#   - aucune destruction de données : pas de Secret supprimé, pas de volume, pas de compartiment S3.
#
# État local (adm01) : ~/.local/state/workbook/M26-EXX/ (700).

_M26_DIR="$(dirname "${BASH_SOURCE[0]}")"
_M26_GL_URL="${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}/api/v4"
_M26_PROJ_POL="plateforme/politiques"
_M26_PROJ_K8S="plateforme/k8s"
_M26_PROJ_GITOPS="plateforme/gitops"   # valeurs des charts (valeurs/<composant>/values.yaml)
_M26_NS_KYVERNO=kyverno
_M26_NS_FALCO=falco
_M26_NS_PANNES=wb-pannes
_M26_LUCAS_NOM="Lucas Martin"
_M26_LUCAS_MEL="lucas.martin@medisphere.internal"
_M26_JETON_LUCAS=""
_M26_LUCAS_IDS=""
# VMs non critiques utilisées par les pannes d'hôte (jamais adm01, gw01/gw02, pbs01).
read -r -a _M26_VMS_SUDO <<<"${WB_M26_VMS_SUDO:-nbx01 dns02 mon01}"
_M26_MON01="${WB_M26_MON01:-mon01}"
_M26_ROCKY="${WB_M26_ROCKY:-ceph01}"   # hôte Rocky (SELinux) non critique pour node_exporter textfile

# ---------------------------------------------------------------------------
# État local et journal (adm01)
# ---------------------------------------------------------------------------
m26_etat() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/M26-$1"
  mkdir -p "$d" && chmod 700 "$d"
  printf '%s\n' "$d"
}
m26_journal() {
  local ex="$1" d
  shift
  d="$(m26_etat "$ex")"
  printf '%s %s [M26-%s variante %s] %s\n' "$(date -Is)" "$(hostname -s)" "$ex" "${WB_VAR:-?}" "$*" >>"$d/journal"
}
m26_lire() { local f; f="$(m26_etat "$1")/$2"; if [[ -f "$f" ]]; then cat "$f"; fi; }
m26_ecrire() { local d; d="$(m26_etat "$1")"; (umask 077 && printf '%s\n' "$3" >"$d/$2"); }
m26_oublier() { local d; d="$(m26_etat "$1")"; rm -f -- "${d:?}/$2"; }

# m26_attendre SECONDES commande… — relance toutes les 10 s jusqu'à succès ou délai.
m26_attendre() {
  local max="$1" t=0
  shift
  while ((t < max)); do
    if "$@"; then return 0; fi
    sleep 10
    t=$((t + 10))
  done
  "$@"
}

# m26_essayer EXX NB DÉPART — essaie les variantes à partir de DÉPART ; une variante qui renvoie 10 est
# « sans effet sur ce lab » (configuration différente, ou MR refusée par la CI) : on passe à la suivante.
# La fonction _m26EXX_une N fait l'injection ET attend son effet.
m26_essayer() {
  local ex="$1" nb="$2" depart="$3" i n rc
  for ((i = 0; i < nb; i++)); do
    n=$(((depart - 1 + i) % nb + 1))
    rc=0
    WB_VAR="$n"
    "_m26${ex}_une" "$n" || rc=$?
    if ((rc == 0)); then WB_VAR="$n"; return 0; fi
    ((rc == 10)) || return 1
    m26_journal "$ex" "variante $n sans effet sur ce lab, suivante"
  done
  wb_avert "aucune variante de M26-$ex n'a d'effet sur ce lab (configuration inattendue)"
  return 1
}
m26_hasard() { local -a l=("$@"); printf '%s\n' "${l[RANDOM % ${#l[@]}]}"; }
m26_maintenant() { date +%s; }

# ---------------------------------------------------------------------------
# Objets Kubernetes : sauvegarde nettoyée et restauration (adm01, kubeconfig d'administration)
# ---------------------------------------------------------------------------
_m26_fichier_objet() { printf '%s/%s_%s_%s.json\n' "$(m26_etat "$1")" "${4:-_cluster}" "${2//\//-}" "$3"; }

# m26_sauver_objet EXX TYPE NOM [ESPACE] — une seule fois par panne ; « ABSENT » si l'objet n'existe pas.
m26_sauver_objet() {
  local ex="$1" type="$2" nom="$3" ns="${4:-}" f
  f="$(_m26_fichier_objet "$ex" "$type" "$nom" "$ns")"
  [[ -e "$f" ]] && return 0
  if wb_kubectl get "$type" "$nom" ${ns:+-n "$ns"} -o json 2>/dev/null | jq '
      del(.metadata.resourceVersion, .metadata.uid, .metadata.creationTimestamp, .metadata.generation,
          .metadata.managedFields, .metadata.selfLink, .status)
      | if .metadata.annotations then .metadata.annotations |= del(."kubectl.kubernetes.io/last-applied-configuration") else . end' >"$f.tmp" 2>/dev/null &&
    [[ -s "$f.tmp" ]]; then
    mv "$f.tmp" "$f"
  else
    rm -f "$f.tmp"; printf 'ABSENT\n' >"$f"
  fi
  chmod 600 "$f"
}
# m26_restaurer_objet EXX TYPE NOM [ESPACE] — remet la copie (replace simple, jamais --force), ou supprime
# l'objet s'il n'existait pas, puis oublie la copie.
m26_restaurer_objet() {
  local ex="$1" type="$2" nom="$3" ns="${4:-}" f
  f="$(_m26_fichier_objet "$ex" "$type" "$nom" "$ns")"
  [[ -e "$f" ]] || return 0
  if [[ "$(head -c 6 "$f")" == ABSENT ]]; then
    wb_kubectl delete "$type" "$nom" ${ns:+-n "$ns"} --ignore-not-found >/dev/null 2>&1 || wb_avert "suppression de $type/$nom impossible"
  elif wb_kubectl get "$type" "$nom" ${ns:+-n "$ns"} >/dev/null 2>&1; then
    wb_kubectl replace -f "$f" >/dev/null 2>&1 || wb_avert "restauration de $type/$nom impossible (copie : $f)"
  else
    wb_kubectl create -f "$f" >/dev/null 2>&1 || wb_avert "recréation de $type/$nom impossible (copie : $f)"
  fi
  rm -f -- "$f"
}
m26_oublier_objet() { rm -f -- "$(_m26_fichier_objet "$@")"; }

# ---------------------------------------------------------------------------
# GitLab : lecture, MR de Lucas, fusion, transformation inverse (identique dans l'esprit à _m21-commun)
# ---------------------------------------------------------------------------
_m26_enc() { jq -rn --arg v "$1" '$v|@uri'; }

m26_gl() {
  local jeton
  if [[ "$1" == --lucas ]]; then shift; jeton="$_M26_JETON_LUCAS"
  else jeton="$(<"${WB_GITLAB_ADMIN_TOKEN_FILE:-$HOME/.config/workbook/gitlab-admin.token}")" || return 1
  fi
  local m="$1" p="$2"
  shift 2
  curl -sS --fail --max-time 30 -X "$m" -H @<(printf 'PRIVATE-TOKEN: %s\n' "$jeton") "$_M26_GL_URL/$p" "$@"
}
m26_git_lire() { m26_gl GET "projects/$(_m26_enc "$1")/repository/files/$(_m26_enc "$2")/raw?ref=main"; }
m26_git_arbre() {
  local p=1 r
  while ((p < 50)); do
    r="$(m26_gl GET "projects/$(_m26_enc "$1")/repository/tree?ref=main&recursive=true&per_page=100&page=$p${2:+&path=$(_m26_enc "$2")}")" || return 1
    [[ "$(jq 'length' <<<"$r")" -gt 0 ]] || break
    jq -r '.[] | select(.type == "blob") | .path' <<<"$r"
    p=$((p + 1))
  done
}
m26_git_tete() { m26_gl GET "projects/$(_m26_enc "$1")/repository/branches/main" | jq -r '.commit.id'; }

_m26_lucas_jeton() {
  local uid r
  uid="$(m26_gl GET 'users?username=lucas.martin' | jq -r '.[0].id // empty')" || return 1
  [[ -n "$uid" ]] || return 1
  r="$(m26_gl POST "users/$uid/impersonation_tokens" --data-urlencode "name=workbook-${WB_EX:-M26}" \
    --data-urlencode "expires_at=$(date -d tomorrow +%F)" --data-urlencode 'scopes[]=api')" || return 1
  _M26_JETON_LUCAS="$(jq -r '.token' <<<"$r")"
  _M26_LUCAS_IDS="$uid $(jq -r '.id' <<<"$r")"
}
_m26_lucas_revoquer() {
  local uid jid
  read -r uid jid <<<"${_M26_LUCAS_IDS:-}"
  if [[ -n "${jid:-}" ]]; then m26_gl DELETE "users/$uid/impersonation_tokens/$jid" >/dev/null 2>&1 || true; fi
  _M26_JETON_LUCAS=""
  _M26_LUCAS_IDS=""
}
_m26_mr_etat() {
  m26_gl GET "projects/$(_m26_enc "$1")/merge_requests/$2" |
    jq -r '"\(.state) \(.detailed_merge_status // .merge_status // "?") \(.head_pipeline.status // "aucun")"'
}

# m26_git_livrer PROJET TITRE ACTIONS_JSON [lucas|workbook] — branche, commit, MR, fusion (auto au succès
# du pipeline). Affiche le sha de main après fusion. Code 10 : MR non fusionnée (pipeline/conflit).
m26_git_livrer() {
  local proj="$1" titre="$2" actions="$3" qui="${4:-lucas}" pe br corps iid t=0 e st pl opt=() rc=0
  pe="$(_m26_enc "$proj")"
  br="wb/${WB_EX:-M26}-$(date +%Y%m%d%H%M%S)"
  [[ "$qui" == lucas ]] && br="lucas/${WB_EX:-M26}-$(date +%Y%m%d%H%M%S)"
  if [[ "$qui" == lucas ]] && _m26_lucas_jeton && m26_gl --lucas POST "projects/$pe/repository/branches" \
    --data-urlencode "branch=$br" --data-urlencode ref=main >/dev/null 2>&1; then
    opt=(--lucas)
  else
    m26_gl POST "projects/$pe/repository/branches" --data-urlencode "branch=$br" --data-urlencode ref=main >/dev/null || { _m26_lucas_revoquer; return 1; }
  fi
  corps="$(jq -n --arg b "$br" --arg m "$titre" --argjson a "$actions" --arg qui "$qui" \
    --arg n "$_M26_LUCAS_NOM" --arg e "$_M26_LUCAS_MEL" '
      {branch: $b, commit_message: $m, actions: $a}
      + (if $qui == "lucas" then {author_name: $n, author_email: $e} else {} end)')"
  if ! m26_gl "${opt[@]}" POST "projects/$pe/repository/commits" -H 'Content-Type: application/json' --data "$corps" >/dev/null; then
    m26_gl DELETE "projects/$pe/repository/branches/$(_m26_enc "$br")" >/dev/null 2>&1 || true
    _m26_lucas_revoquer
    return 1
  fi
  iid="$(m26_gl "${opt[@]}" POST "projects/$pe/merge_requests" --data-urlencode "source_branch=$br" \
    --data-urlencode target_branch=main --data-urlencode "title=$titre" --data-urlencode remove_source_branch=true \
    --data-urlencode "description=${WB_EX:-M26} — modification injectée par lab/bin/break (workbook)." | jq -r '.iid')" || iid=""
  _m26_lucas_revoquer
  [[ -n "$iid" && "$iid" != null ]] || return 1
  m26_journal "${WB_EX#M26-}" "MR !$iid ouverte sur $proj ($titre)"
  while ((t < 900)); do
    read -r e st pl <<<"$(_m26_mr_etat "$proj" "$iid" 2>/dev/null || echo "? ? ?")"
    case "$e" in merged) break ;; closed) rc=10; break ;; esac
    if [[ "$pl" =~ ^(failed|canceled)$ ]]; then rc=10; break; fi
    if [[ "$st" =~ ^(conflict|need_rebase|broken_status)$ ]]; then rc=10; break; fi
    if [[ ! "$st" =~ ^(checking|unchecked|preparing|approvals_syncing)$ ]]; then
      m26_gl PUT "projects/$pe/merge_requests/$iid/merge" --data-urlencode should_remove_source_branch=true \
        --data-urlencode auto_merge=true --data-urlencode merge_when_pipeline_succeeds=true >/dev/null 2>&1 || true
    fi
    sleep 15
    t=$((t + 15))
  done
  if [[ "$e" != merged ]]; then
    ((rc == 10)) || rc=10
    m26_gl PUT "projects/$pe/merge_requests/$iid" --data-urlencode state_event=close >/dev/null 2>&1 || true
    m26_gl DELETE "projects/$pe/repository/branches/$(_m26_enc "$br")" >/dev/null 2>&1 || true
    m26_journal "${WB_EX#M26-}" "MR !$iid de $proj non fusionnée (pipeline : $pl, état : $st) : fermée"
    return "$rc"
  fi
  m26_git_tete "$proj"
}

# m26_git_transformer EXX CLÉ PROJET CHEMIN TITRE FONCTION [lucas|workbook] — lit CHEMIN sur main, le passe
# dans FONCTION (entrée → sortie standard), livre le résultat par MR s'il diffère, attend les Applications
# qui suivent ce dépôt. Mémorise « PROJET CHEMIN » sous CLÉ. Code 10 : rien à changer ou MR refusée.
m26_git_transformer() {
  local ex="$1" cle="$2" proj="$3" chemin="$4" titre="$5" fn="$6" qui="${7:-lucas}" t sha rc=0 act
  t="$(mktemp -d)"
  if ! m26_git_lire "$proj" "$chemin" >"$t/avant"; then rm -rf -- "$t"; return 10; fi
  "$fn" <"$t/avant" >"$t/apres" 2>/dev/null || { rm -rf -- "$t"; return 10; }
  if [[ ! -s "$t/apres" ]] || cmp -s "$t/avant" "$t/apres"; then rm -rf -- "$t"; return 10; fi
  act="$(jq -n --arg p "$chemin" --rawfile c "$t/apres" '[{action: "update", file_path: $p, content: $c}]')"
  rm -rf -- "$t"
  [[ "$qui" == lucas ]] && m26_ecrire "$ex" "git-$cle" "$proj $chemin"
  sha="$(m26_git_livrer "$proj" "$titre" "$act" "$qui")" || rc=$?
  if ((rc != 0)); then [[ "$qui" == lucas ]] && m26_oublier "$ex" "git-$cle"; return "$rc"; fi
  m26_journal "$ex" "$proj:$chemin modifié (${sha:0:8})"
  m26_apps_attendre "$proj" "$sha"
}
# m26_git_defaire EXX CLÉ FONCTION_INVERSE TITRE — applique la fonction inverse au fichier COURANT
# (elle ne change rien si la marque de la panne n'y est plus).
m26_git_defaire() {
  local ex="$1" cle="$2" fn="$3" titre="$4" l proj chemin
  l="$(m26_lire "$ex" "git-$cle")"
  [[ -n "$l" ]] || return 0
  read -r proj chemin <<<"$l"
  m26_git_transformer "$ex" "annul-$cle" "$proj" "$chemin" "$titre" "$fn" workbook >/dev/null ||
    m26_journal "$ex" "annulation $cle : rien à défaire (déjà réparé ?) ou MR d'annulation refusée"
  m26_oublier "$ex" "git-$cle"
}
# m26_git_trouver PROJET 'filtre yq (vrai/faux)' [DOSSIER] — premier fichier YAML dont un document
# satisfait le filtre (ex. '.kind == "ValidatingPolicy"').
m26_git_trouver() {
  local proj="$1" f="$2" d="${3:-}" p t
  t="$(mktemp)"
  while read -r p; do
    [[ "$p" =~ \.ya?ml$ ]] || continue
    m26_git_lire "$proj" "$p" >"$t" 2>/dev/null || continue
    if [[ "$(yq "[$f] | any" "$t" 2>/dev/null | grep -c true)" -gt 0 ]]; then
      rm -f "$t"; printf '%s\n' "$p"; return 0
    fi
  done < <(m26_git_arbre "$proj" "$d")
  rm -f "$t"
  return 1
}

# ---------------------------------------------------------------------------
# Argo CD (Applications lues et rafraîchies avec le kubeconfig d'administration)
# ---------------------------------------------------------------------------
m26_app_json() { wb_kubectl -n argocd get applications.argoproj.io "$1" -o json 2>/dev/null; }
m26_apps_du_depot() {
  wb_kubectl -n argocd get applications.argoproj.io -o json 2>/dev/null | jq -r --arg p "$1" '
    .items[] | select([(.spec.source // empty), (.spec.sources[]? // empty)] | map(.repoURL // "")
                      | any(sub("\\.git$"; "") | endswith("/" + $p)))
    | .metadata.name'
}
m26_app_rafraichir() {
  wb_kubectl -n argocd annotate applications.argoproj.io "$1" argocd.argoproj.io/refresh=normal --overwrite >/dev/null 2>&1 || true
}
m26_app_revision_vue() {
  m26_app_json "$1" | jq -e --arg s "$2" '
    ((.status.sync.revision // "") == $s) or ((.status.sync.revisions // []) | index($s) != null)' >/dev/null 2>&1
}
m26_app_synchro_faite() {
  m26_app_json "$1" | jq -e --arg s "$2" '
    (.status.operationState.phase // "") as $p
    | ($p == "Succeeded" or $p == "Failed" or $p == "Error")
    and (((.status.operationState.syncResult.revision // "") == $s)
         or ((.status.operationState.syncResult.revisions // []) | index($s) != null))' >/dev/null 2>&1
}
# m26_apps_attendre CHEMIN_PROJET SHA — pour chaque Application qui suit ce dépôt (hors *-prod) :
# rafraîchit, déclenche la synchro si elle n'est pas automatique, attend que l'opération sur SHA soit finie.
m26_apps_attendre() {
  local proj="$1" sha="$2" a j
  while read -r a; do
    [[ -n "$a" && "$a" != *-prod ]] || continue
    m26_app_rafraichir "$a"
    if ! m26_attendre 180 m26_app_revision_vue "$a" "$sha"; then
      wb_avert "Argo CD n'a pas vu la révision ${sha:0:8} sur $a"
      continue
    fi
    j="$(m26_app_json "$a")"
    if ! jq -e '.spec.syncPolicy.automated' >/dev/null 2>&1 <<<"$j"; then
      wb_kubectl -n argocd patch applications.argoproj.io "$a" --type merge \
        -p '{"operation":{"initiatedBy":{"username":"lucas.martin"},"sync":{}}}' >/dev/null 2>&1 || true
    fi
    m26_attendre 360 m26_app_synchro_faite "$a" "$sha" || wb_avert "synchronisation de $a non terminée"
  done < <(m26_apps_du_depot "$proj")
}

# ---------------------------------------------------------------------------
# Admission : vérifier qu'un pod conforme est admis / refusé dans un espace (dry-run côté serveur)
# ---------------------------------------------------------------------------
# _m26_pod_conforme NOM ESPACE — manifeste d'un pod « restricted » minimal et signé-compatible (image
# MédiAgenda du cache Harbor ; jamais exécuté, dry-run seulement).
_m26_pod_conforme() {
  local nom="$1" ns="$2" img="${WB_M26_IMAGE_PY:-registry.par1.medisphere.internal/dockerhub/library/python:3.13-slim-trixie}"
  cat <<EOF
apiVersion: v1
kind: Pod
metadata: {name: $nom, namespace: $ns, labels: {app.kubernetes.io/name: $nom, medisphere.internal/equipe: mediagenda}}
spec:
  automountServiceAccountToken: false
  securityContext: {runAsNonRoot: true, runAsUser: 65534, seccompProfile: {type: RuntimeDefault}}
  containers:
    - name: c
      image: $img
      command: ["sleep", "1"]
      resources: {requests: {cpu: 10m, memory: 16Mi}, limits: {cpu: 50m, memory: 64Mi}}
      securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: ["ALL"]}}
EOF
}
# m26_admis ESPACE — 0 si un pod conforme est admis (dry-run serveur), 1 s'il est refusé.
m26_admis() { _m26_pod_conforme wb-sonde-admission "$1" | wb_kubectl -n "$1" apply --dry-run=server -f - >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# Hôtes (VMs du socle et nœuds). Pour une VM dont sudo/SSH peut être cassé : wb_exec_invite (QEMU).
# ---------------------------------------------------------------------------
m26_ssh() { remote "$1" "sudo -n bash -c $(printf '%q' "$2")" </dev/null; }

# VMID d'une VM par son nom (cache dans l'état local). Sert à l'agent QEMU (annulation si sudo cassé).
m26_vmid() {
  local nom="$1" v
  v="$(m26_lire GEN "vmid-$nom")"
  if [[ -z "$v" ]]; then
    v="$(remote "$WB_PVE_HOST" "qm list" 2>/dev/null | awk -v n="$nom" '$2 == n {print $1; exit}')" || v=""
    [[ -n "$v" ]] && m26_ecrire GEN "vmid-$nom" "$v"
  fi
  printf '%s\n' "$v"
}

read -r -d '' _M26_AIDE <<'AIDE' || true
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
unite_de() {
  local u x
  for u in $(systemctl list-units --type=service --all --no-legend --plain 2>/dev/null | awk '{print $1}'); do
    x="$(systemctl show -p ExecStart --value "$u" 2>/dev/null | sed -n 's/.*path=\([^ ;]*\).*/\1/p' | head -n 1)"
    [ "$(basename "${x:-/}")" = "$1" ] && { echo "$u"; return 0; }
  done
  return 1
}
oublier_fichiers() {
  local m="$WB_DIR/$WB_EX.manifeste" src dst
  [ -f "$m" ] || return 0
  while IFS="$(printf '\t')" read -r src dst; do
    [ "$dst" = ABSENT ] || rm -f -- "$dst"
  done < "$m"
  rm -f "$m"
}
AIDE
# m26_wb_exec HÔTE [VAR=valeur…] <<'EOF' … EOF — wb_exec avec l'aide ci-dessus.
m26_wb_exec() { local h="$1"; shift; { printf '%s\n' "$_M26_AIDE"; cat; } | wb_exec "$h" "$@"; }
# m26_wb_exec_invite NOM [VAR=valeur…] — même aide, mais DANS la VM via l'agent QEMU (annulation si sudo cassé).
m26_wb_exec_invite() {
  local nom="$1" vmid
  shift
  vmid="$(m26_vmid "$nom")" || return 1
  [[ -n "$vmid" ]] || { wb_avert "VMID de $nom introuvable (agent QEMU)"; return 1; }
  { printf '%s\n' "$_M26_AIDE"; cat; } | wb_exec_invite "$vmid" "$@"
}

# ---------------------------------------------------------------------------
# Santé avant injection
# ---------------------------------------------------------------------------
# m26_kube_sain — refuse de casser un cluster qui ne va pas bien.
m26_kube_sain() {
  if ! wb_kubectl get --raw='/readyz' >/dev/null 2>&1; then
    echo "L'API de k8s-par1 (kubeconfig d'administration) ne répond pas : rien n'est cassé." >&2
    return 1
  fi
  local a
  for a in kyverno politiques; do
    if ! m26_app_json "$a" | jq -e '.status.health.status == "Healthy" and .status.sync.status == "Synced"' >/dev/null 2>&1; then
      echo "L'Application Argo CD « $a » n'est pas Synced/Healthy : rien n'est cassé (lab/bin/check 26 07)." >&2
      return 1
    fi
  done
  [[ -r "${WB_GITLAB_ADMIN_TOKEN_FILE:-$HOME/.config/workbook/gitlab-admin.token}" ]] || {
    echo "Jeton d'administration GitLab illisible (WB_GITLAB_ADMIN_TOKEN_FILE) : rien n'est cassé." >&2
    return 1
  }
  if ! yq --version 2>/dev/null | grep -q mikefarah; then
    echo "yq (mikefarah, v4) est nécessaire sur adm01 : rien n'est cassé." >&2
    return 1
  fi
}
# m26_hote_sain HÔTE — l'hôte répond en SSH et sudo -n fonctionne (sinon rien n'est cassé).
m26_hote_sain() {
  if ! m26_ssh "$1" 'true' >/dev/null 2>&1; then
    echo "$1 ne répond pas en SSH + sudo -n depuis ce poste : rien n'est cassé." >&2
    return 1
  fi
  # L'agent QEMU doit répondre : c'est le filet de sécurité d'annulation si sudo est cassé.
  local vmid
  vmid="$(m26_vmid "$1")"
  if [[ -z "$vmid" ]] || ! remote "$WB_PVE_HOST" "qm guest exec $vmid -- true" >/dev/null 2>&1; then
    echo "L'agent QEMU de $1 ne répond pas (indispensable pour annuler une panne de sudo) : rien n'est cassé." >&2
    return 1
  fi
}
