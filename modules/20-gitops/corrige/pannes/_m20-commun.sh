# shellcheck shell=bash
# _m20-commun.sh — fonctions partagées par les scripts de panne du module 20 (M20-E35 à M20-E43).
#
# Sourcé par break-EXX.sh APRÈS lab/lib/pannes-lib.sh (wb_kubectl, wb_exec, wb_avert, WB_EX…).
# Rappel : lab/bin/break tourne avec « set -euo pipefail » ; les fonctions d'annulation sont appelées
# hors de tout « if » : aucune commande ne doit y échouer sans « || true ».
#
# Principes (CONVENTIONS §8, PLAN §4.11 « Pannes des blocs D et E ») :
#   - une panne GitOps modifie un dépôt (plateforme/gitops, mediagenda/deploiement) par un COMMIT
#     IDENTIFIABLE : auteur « Lucas Martin <lucas.martin@medisphere.internal> », marqueur
#     « Réf-workbook: M20-EXX » dans le message. La branche main est protégée (fusion par MR
#     seulement, M01-E11) : le commit part sur une branche lucas/…, une MR est ouverte puis
#     fusionnée avec le jeton d'administration de l'apprenant (M01-E05), pipeline compris. Si le
#     pipeline de la MR échoue (une porte de validation a fait son travail), la variante est
#     déclarée « sans effet sur ce lab » (code 10) et la MR est fermée ;
#   - l'annulation défait ces commits par un commit INVERSE (API « revert » sur une branche
#     wb/annulation-…, MR, fusion), jamais par réécriture d'historique. Si le commit a déjà été
#     annulé ou si l'apprenant a modifié les mêmes lignes, le « revert » échoue proprement : rien
#     n'est forcé, la réparation de l'apprenant est conservée ;
#   - les objets Kubernetes modifiés à la main sont sauvegardés avant (JSON nettoyé, dans
#     ~/.local/state/workbook/M20-EXX/ sur adm01, 600) et ne sont restaurés que s'ils portent
#     encore la marque de la panne ;
#   - jamais la production : aucune panne ne commite dans overlays/prod ni ne désactive la
#     synchronisation automatique ; aucune suppression de données (volumes, bases, compartiments).
#     Une variante qui ferait élaguer (prune) une ressource vérifie d'abord, sur un rendu local
#     des deux versions, que rien de ce qui serait élagué ne porte de données.

_M20_DIR="$(dirname "${BASH_SOURCE[0]}")"
_M20_GITLAB="${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}"
_M20_FQDN_GIT="git01.par1.medisphere.internal"
_M20_NS=argocd
_M20_GITOPS=plateforme/gitops
_M20_DEPLOIEMENT=mediagenda/deploiement
_M20_APP_DEV="${WB_M20_APP_DEV:-mediagenda-dev}"
_M20_APP_RECETTE="${WB_M20_APP_RECETTE:-mediagenda-recette}"
_M20_NS_DEV="${WB_M20_NS_DEV:-mediagenda-dev}"
_M20_NS_RECETTE="${WB_M20_NS_RECETTE:-mediagenda-recette}"
_M20_DELAI_FUSION="${WB_M20_DELAI_FUSION:-900}"
_M20_REGISTRE=registry.par1.medisphere.internal
# shellcheck disable=SC2034  # utilisées par les scripts qui sourcent ce fichier
{
  _M20_LUCAS_NOM="Lucas Martin"
  _M20_LUCAS_COURRIEL="lucas.martin@medisphere.internal"
  _M20_LYO_HOTE="${WB_M20_LYO_HOTE:-10.10.99.61}"
}

# ---------------------------------------------------------------------------
# État local et journal (adm01)
# ---------------------------------------------------------------------------

# m20_etat EXX — affiche (et crée, en 700) le dossier d'état local de la panne.
m20_etat() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/M20-$1"
  mkdir -p "$d" && chmod 700 "$d"
  printf '%s\n' "$d"
}

# m20_lire EXX CLÉ / m20_ecrire EXX CLÉ VALEUR (écrase) / m20_oublier EXX CLÉ
m20_lire() {
  local f
  f="$(m20_etat "$1")/$2"
  if [[ -f "$f" ]]; then cat "$f"; fi
}
m20_ecrire() {
  local d
  d="$(m20_etat "$1")"
  printf '%s\n' "$3" >"$d/$2"
  chmod 600 "$d/$2"
}
m20_oublier() {
  local d
  d="$(m20_etat "$1")"
  rm -f -- "${d:?}/$2"
}

# m20_journal EXX "message" — journal local (et /var/lib/workbook/pannes.log de adm01 si sudo -n).
m20_journal() {
  local ex="$1" ligne
  shift
  ligne="$(date -Is) $(hostname -s) [M20-$ex variante ${WB_VAR:-?}] $*"
  printf '%s\n' "$ligne" >>"$(m20_etat "$ex")/journal"
  if sudo -n true 2>/dev/null; then
    printf '%s\n' "$ligne" | sudo -n sh -c 'mkdir -p /var/lib/workbook && chmod 700 /var/lib/workbook && cat >> /var/lib/workbook/pannes.log' 2>/dev/null || true
  fi
}

# m20_debut EXX — date de début de l'injection (epoch), mémorisée une fois.
m20_debut() {
  [[ -n "$(m20_lire "$1" debut)" ]] || m20_ecrire "$1" debut "$(date +%s)"
}

# m20_attendre SECONDES commande… — relance la commande toutes les 10 s jusqu'à succès ou délai.
m20_attendre() {
  local max="$1" t=0
  shift
  while ((t < max)); do
    if "$@"; then return 0; fi
    sleep 10
    t=$((t + 10))
  done
  "$@"
}

# m20_essayer EXX NB DÉPART — essaie les variantes à partir de DÉPART ; une variante qui renvoie 10
# est « sans effet sur ce lab » (configuration différente de celle attendue, porte de CI qui a
# refusé le commit…) : elle a été défaite par sa fonction, on passe à la suivante.
m20_essayer() {
  local ex="$1" nb="$2" depart="$3" i n rc
  for ((i = 0; i < nb; i++)); do
    n=$(((depart - 1 + i) % nb + 1))
    rc=0
    WB_VAR="$n"
    "_m20${ex}_une" "$n" || rc=$?
    if ((rc == 0)); then
      WB_VAR="$n"
      return 0
    fi
    ((rc == 10)) || return 1
    m20_journal "$ex" "variante $n sans effet sur ce lab : suivante"
  done
  wb_avert "aucune variante de M20-$ex ne s'applique à l'état actuel du lab"
  return 1
}

# m20_outils — outils locaux nécessaires (yq doit être celui de mikefarah, PLAN §6).
m20_outils() {
  local c
  for c in curl jq yq kubectl base64 perl openssl tar; do
    command -v "$c" >/dev/null 2>&1 || { wb_avert "outil manquant sur adm01 : $c"; return 1; }
  done
  yq --version 2>/dev/null | grep -q mikefarah || { wb_avert "yq n'est pas celui de mikefarah (PLAN §6)"; return 1; }
}

# ---------------------------------------------------------------------------
# API GitLab (jeton d'ADMINISTRATION de l'apprenant, M01-E05 ; jamais dans la ligne de commande)
# ---------------------------------------------------------------------------

m20_enc() { jq -rn --arg s "$1" '$s|@uri'; }

# m20_api MÉTHODE CHEMIN [options curl…] — corps sur stdout ; code ≠ 0 si HTTP ≥ 400.
m20_api() {
  local m="$1" p="$2" f t
  shift 2
  f="${WB_GITLAB_ADMIN_TOKEN_FILE:-$HOME/.config/workbook/gitlab-admin.token}"
  [[ -r "$f" ]] || { wb_avert "jeton d'administration GitLab illisible : $f"; return 1; }
  t="$(tr -d '[:space:]' <"$f")"
  curl -sf --max-time 60 -X "$m" -H @<(printf 'PRIVATE-TOKEN: %s\n' "$t") "$_M20_GITLAB/api/v4/$p" "$@"
}

# m20_api_json MÉTHODE CHEMIN 'JSON'
m20_api_json() {
  m20_api "$1" "$2" -H 'Content-Type: application/json' --data-binary "$3"
}

# m20_brut PROJET CHEMIN — contenu brut d'un fichier sur main.
m20_brut() {
  m20_api GET "projects/$(m20_enc "$1")/repository/files/$(m20_enc "$2")/raw?ref=main"
}

# m20_existe PROJET CHEMIN — 0 si le fichier existe sur main.
m20_existe() {
  m20_api GET "projects/$(m20_enc "$1")/repository/files/$(m20_enc "$2")?ref=main" >/dev/null 2>&1
}

# m20_arbre PROJET — chemins des fichiers YAML de main (arbre récursif, paginé).
m20_arbre() {
  local p page=1 r n
  p="$(m20_enc "$1")"
  while :; do
    r="$(m20_api GET "projects/$p/repository/tree?ref=main&recursive=true&per_page=100&page=$page")" || return 1
    jq -r '.[] | select(.type == "blob") | .path | select(test("\\.ya?ml$"))' <<<"$r"
    n="$(jq 'length' <<<"$r")"
    ((n < 100)) && break
    page=$((page + 1))
    ((page > 20)) && break
  done
}

# m20_chercher PROJET 'regex étendue' — fichiers YAML de main dont le contenu correspond.
m20_chercher() {
  local f
  while read -r f; do
    [[ -n "$f" ]] || continue
    if m20_brut "$1" "$f" 2>/dev/null | grep -Eq -- "$2"; then printf '%s\n' "$f"; fi
  done < <(m20_arbre "$1")
}

# m20_action create|update CHEMIN FICHIER_LOCAL — objet JSON d'une action de commit.
m20_action() {
  jq -n --arg a "$1" --arg p "$2" --rawfile c "$3" '{action: $a, file_path: $p, content: $c}'
}

# m20_mr_reglages PROJET — rappel lisible de la protection de main (pour les messages d'erreur).
m20_mr_reglages() {
  m20_api GET "projects/$(m20_enc "$1")" 2>/dev/null |
    jq -r '"merge_method=\(.merge_method) pipeline_obligatoire=\(.only_allow_merge_if_pipeline_succeeds)"' 2>/dev/null || true
}

# m20_fusionner PROJET IID — attend que la MR soit fusionnable puis la fusionne (pipeline compris).
# Code 0 : fusionnée ; 10 : refusée par le pipeline (MR laissée ouverte, à fermer par l'appelant) ;
# 1 : autre échec ou délai dépassé.
m20_fusionner() {
  local pe iid="$2" t=0 mr st hp sha
  pe="$(m20_enc "$1")"
  while ((t < _M20_DELAI_FUSION)); do
    mr="$(m20_api GET "projects/$pe/merge_requests/$iid")" || return 1
    st="$(jq -r '.detailed_merge_status // .merge_status' <<<"$mr")"
    hp="$(jq -r '.head_pipeline.status // empty' <<<"$mr")"
    sha="$(jq -r '.sha // empty' <<<"$mr")"
    case "$st" in
      mergeable | can_be_merged)
        if m20_api PUT "projects/$pe/merge_requests/$iid/merge" \
          --data-urlencode "sha=$sha" --data-urlencode "should_remove_source_branch=true" >/dev/null 2>&1; then
          return 0
        fi
        ;;
      need_rebase)
        m20_api PUT "projects/$pe/merge_requests/$iid/rebase" >/dev/null 2>&1 || true
        ;;
      ci_must_pass | ci_still_running)
        if [[ "$hp" == failed || "$hp" == canceled ]]; then
          wb_avert "le pipeline de la MR !$iid de $1 a échoué : une porte de validation refuse ce changement"
          return 10
        fi
        ;;
      checking | unchecked | preparing | approvals_syncing | cannot_be_merged_recheck) ;;
      merged) return 0 ;;
      *)
        wb_avert "MR !$iid de $1 non fusionnable ($st ; $(m20_mr_reglages "$1"))"
        return 1
        ;;
    esac
    sleep 5
    t=$((t + 5))
  done
  wb_avert "MR !$iid de $1 toujours pas fusionnée après ${_M20_DELAI_FUSION} s (WB_M20_DELAI_FUSION)"
  return 1
}

# m20_mr_fermer PROJET IID BRANCHE — ferme une MR non fusionnée et supprime sa branche.
m20_mr_fermer() {
  local pe
  pe="$(m20_enc "$1")"
  m20_api PUT "projects/$pe/merge_requests/$2" --data-urlencode "state_event=close" >/dev/null 2>&1 || true
  m20_api DELETE "projects/$pe/repository/branches/$(m20_enc "$3")" >/dev/null 2>&1 || true
}

# m20_commit_lucas EXX PROJET BRANCHE "titre" "corps" 'ACTIONS_JSON' — commit au nom de Lucas sur
# une nouvelle branche partie de main, MR, fusion. Enregistre « projet branche sha iid » dans
# l'état (fichier commit-N) pour l'annulation. Code 10 si la CI refuse la MR (MR fermée).
m20_commit_lucas() {
  local ex="$1" projet="$2" br="$3" titre="$4" corps="$5" actions="$6" pe n msg r sha iid rc
  pe="$(m20_enc "$projet")"
  if m20_api GET "projects/$pe/repository/branches/$(m20_enc "$br")" >/dev/null 2>&1; then
    wb_avert "la branche $br existe déjà dans $projet (panne précédente non annulée ?) : supprime-la d'abord"
    return 1
  fi
  n=1
  while [[ -e "$(m20_etat "$ex")/commit-$n" ]]; do n=$((n + 1)); done
  msg="$(printf '%s\n\n%s\n\nRéf-workbook: M20-%s' "$titre" "$corps" "$ex")"
  r="$(jq -n --arg b "$br" --arg m "$msg" --arg an "$_M20_LUCAS_NOM" --arg ae "$_M20_LUCAS_COURRIEL" \
    --argjson a "$actions" '{branch: $b, start_branch: "main", commit_message: $m,
      author_name: $an, author_email: $ae, actions: $a}')"
  sha="$(m20_api_json POST "projects/$pe/repository/commits" "$r" | jq -r '.id // empty')" || sha=""
  [[ -n "$sha" ]] || { wb_avert "commit refusé par GitLab dans $projet ($br)"; return 1; }
  m20_ecrire "$ex" "commit-$n" "$projet $br $sha -"
  iid="$(m20_api POST "projects/$pe/merge_requests" \
    --data-urlencode "source_branch=$br" --data-urlencode "target_branch=main" \
    --data-urlencode "title=$titre" --data-urlencode "description=$corps" \
    --data-urlencode "remove_source_branch=true" | jq -r '.iid // empty')" || iid=""
  [[ -n "$iid" ]] || { wb_avert "MR impossible à ouvrir dans $projet"; return 1; }
  m20_ecrire "$ex" "commit-$n" "$projet $br $sha $iid"
  rc=0
  m20_fusionner "$projet" "$iid" || rc=$?
  if ((rc != 0)); then
    m20_mr_fermer "$projet" "$iid" "$br"
    m20_oublier "$ex" "commit-$n"
    return "$rc"
  fi
  # Après un éventuel rebase, le commit de Lucas a changé d'empreinte : on relit celle de main.
  sha="$(m20_api GET "projects/$pe/merge_requests/$iid/commits" | jq -r '.[0].id // empty')" || true
  [[ -n "$sha" ]] && m20_ecrire "$ex" "commit-$n" "$projet $br $sha $iid"
  m20_journal "$ex" "commit $sha de Lucas fusionné dans $projet (MR !$iid) : $titre"
}

# m20_defaire_commit EXX N — défait le commit-N enregistré : MR encore ouverte → fermée ; MR
# fusionnée → commit inverse (revert) sur une branche wb/annulation-…, MR, fusion. Si GitLab refuse
# le revert (déjà annulé, lignes retouchées par l'apprenant), rien n'est forcé.
m20_defaire_commit() {
  local ex="$1" n="$2" ligne projet br sha iid pe etat brA r iidA
  ligne="$(m20_lire "$ex" "commit-$n")"
  [[ -n "$ligne" ]] || return 0
  read -r projet br sha iid <<<"$ligne"
  pe="$(m20_enc "$projet")"
  etat=""
  if [[ "$iid" != - ]]; then
    etat="$(m20_api GET "projects/$pe/merge_requests/$iid" 2>/dev/null | jq -r '.state // empty')" || etat=""
  fi
  if [[ "$etat" == opened || "$iid" == - ]]; then
    [[ "$iid" != - ]] && m20_mr_fermer "$projet" "$iid" "$br"
    m20_api DELETE "projects/$pe/repository/branches/$(m20_enc "$br")" >/dev/null 2>&1 || true
    m20_oublier "$ex" "commit-$n"
    return 0
  fi
  if [[ "$etat" != merged ]]; then
    m20_oublier "$ex" "commit-$n"
    return 0
  fi
  brA="wb/annulation-m20-${ex,,}-$n-$(date +%s)"
  if ! m20_api POST "projects/$pe/repository/branches" --data-urlencode "branch=$brA" --data-urlencode "ref=main" >/dev/null 2>&1; then
    wb_avert "branche d'annulation impossible dans $projet : défais toi-même le commit ${sha:0:8} (git revert, MR)"
    return 0
  fi
  if ! r="$(m20_api POST "projects/$pe/repository/commits/$sha/revert" --data-urlencode "branch=$brA" 2>/dev/null)" ||
    [[ -z "$(jq -r '.id // empty' <<<"$r" 2>/dev/null)" ]]; then
    m20_api DELETE "projects/$pe/repository/branches/$(m20_enc "$brA")" >/dev/null 2>&1 || true
    m20_journal "$ex" "revert de ${sha:0:8} refusé par GitLab (déjà annulé ou lignes modifiées) : rien n'est forcé"
    m20_oublier "$ex" "commit-$n"
    return 0
  fi
  iidA="$(m20_api POST "projects/$pe/merge_requests" \
    --data-urlencode "source_branch=$brA" --data-urlencode "target_branch=main" \
    --data-urlencode "title=Revert : annulation de la panne M20-$ex (commit ${sha:0:8})" \
    --data-urlencode "remove_source_branch=true" | jq -r '.iid // empty')" || iidA=""
  if [[ -z "$iidA" ]] || ! m20_fusionner "$projet" "$iidA"; then
    wb_avert "MR d'annulation de ${sha:0:8} non fusionnée dans $projet : fusionne-la toi-même (branche $brA)"
    return 0
  fi
  m20_journal "$ex" "annulation : commit inverse de ${sha:0:8} fusionné dans $projet (MR !$iidA)"
  m20_oublier "$ex" "commit-$n"
}

# m20_defaire_commits EXX — défait tous les commits enregistrés, du plus récent au plus ancien.
m20_defaire_commits() {
  local ex="$1" d n
  d="$(m20_etat "$ex")"
  for n in $(find "$d" -maxdepth 1 -name 'commit-*' -printf '%f\n' 2>/dev/null | sed 's/^commit-//' | sort -rn); do
    m20_defaire_commit "$ex" "$n" || true
  done
}

# m20_a_des_commits EXX — 0 si des commits de la panne sont enregistrés.
m20_a_des_commits() { [[ -n "$(find "$(m20_etat "$1")" -maxdepth 1 -name 'commit-*' 2>/dev/null)" ]]; }

# ---------------------------------------------------------------------------
# Copie locale d'un dépôt (archive de main) pour préparer et vérifier une modification
# ---------------------------------------------------------------------------

# m20_copie PROJET — télécharge l'archive de main dans un dossier temporaire ; affiche son chemin.
m20_copie() {
  local t a
  t="$(mktemp -d)"
  a="$t/archive.tar.gz"
  if ! m20_api GET "projects/$(m20_enc "$1")/repository/archive.tar.gz?sha=main" -o "$a"; then
    rm -rf -- "$t"
    return 1
  fi
  mkdir -p "$t/depot"
  tar -xzf "$a" -C "$t/depot" --strip-components=1 || { rm -rf -- "$t"; return 1; }
  rm -f -- "$a"
  printf '%s\n' "$t/depot"
}

# m20_rendu DOSSIER_OVERLAY — « kind/espace/nom » de chaque objet rendu (kubectl kustomize).
m20_rendu() {
  kubectl kustomize "$1" 2>/dev/null | yq -N '.kind + "/" + (.metadata.name)' - 2>/dev/null | sort -u
}

# ---------------------------------------------------------------------------
# Argo CD (objets lus et annotés avec le kubeconfig d'administration)
# ---------------------------------------------------------------------------

m20_app() { wb_kubectl -n "$_M20_NS" get applications.argoproj.io "$1" -o json 2>/dev/null; }

# m20_app_jq APP 'filtre' — 0 si le JSON de l'Application satisfait le filtre.
m20_app_jq() { m20_app "$1" | jq -e "$2" >/dev/null 2>&1; }

m20_app_saine() {
  m20_app_jq "$1" '.status.sync.status == "Synced" and .status.health.status == "Healthy"
    and ((.status.operationState.phase // "Succeeded") | test("Succeeded|Failed|Error"))'
}

# m20_rafraichir [hard] APP… — demande un rafraîchissement (le contrôleur retire l'annotation).
m20_rafraichir() {
  local mode=normal a
  if [[ "${1:-}" == hard ]]; then mode=hard; shift; fi
  for a in "$@"; do
    wb_kubectl -n "$_M20_NS" annotate applications.argoproj.io "$a" \
      "argocd.argoproj.io/refresh=$mode" --overwrite >/dev/null 2>&1 || true
  done
}

# m20_sync_auto_depuis APP EPOCH — nombre d'opérations automatiques terminées depuis EPOCH
# (historique de l'Application, plus l'opération en cours).
m20_sync_auto_depuis() {
  m20_app "$1" | jq --argjson t "$2" '
    [(.status.history // [])[] | select(((.deployStartedAt // .deployedAt) | fromdateiso8601) >= $t)
                                | select((.initiatedBy.automated // false) == true)] | length' 2>/dev/null || echo 0
}

# m20_condition APP 'regex de type' — 0 si l'Application porte une condition de ce type.
m20_condition() {
  m20_app "$1" | jq -e --arg r "$2" '[.status.conditions[]? | select(.type | test($r))] | length > 0' >/dev/null 2>&1
}

# m20_ressource_app APP KIND NOM — JSON de la ressource dans status.resources de l'Application.
m20_ressource_app() {
  m20_app "$1" | jq -c --arg k "$2" --arg n "$3" '[.status.resources[]? | select(.kind == $k and .name == $n)][0] // empty' 2>/dev/null
}

# ---------------------------------------------------------------------------
# Objets Kubernetes modifiés à la main : sauvegarde nettoyée et restauration
# ---------------------------------------------------------------------------

_m20_fichier_objet() { printf '%s/%s_%s_%s.json\n' "$(m20_etat "$1")" "${4:-_cluster}" "${2//\//-}" "$3"; }

# m20_sauver_objet EXX TYPE NOM [ESPACE] — une seule fois par panne ; « ABSENT » si l'objet n'existe pas.
# Code 1 si la sauvegarde n'a pas pu être écrite : on ne casse jamais sans filet.
m20_sauver_objet() {
  local ex="$1" type="$2" nom="$3" ns="${4:-}" f
  f="$(_m20_fichier_objet "$ex" "$type" "$nom" "$ns")"
  [[ -e "$f" ]] && return 0
  if wb_kubectl get "$type" "$nom" ${ns:+-n "$ns"} -o json 2>/dev/null | jq '
      del(.metadata.resourceVersion, .metadata.uid, .metadata.creationTimestamp, .metadata.generation,
          .metadata.managedFields, .metadata.selfLink, .status)
      | if .metadata.annotations then .metadata.annotations |= del(."kubectl.kubernetes.io/last-applied-configuration") else . end' >"$f.tmp" 2>/dev/null &&
    [[ -s "$f.tmp" ]]; then
    mv "$f.tmp" "$f"
  else
    rm -f "$f.tmp"
    printf 'ABSENT\n' >"$f"
  fi
  chmod 600 "$f"
  [[ -s "$f" ]]
}

# m20_objet_sauve EXX TYPE NOM [ESPACE] — copie sauvegardée (JSON) ; code 1 si aucune.
m20_objet_sauve() {
  local f
  f="$(_m20_fichier_objet "$@")"
  [[ -s "$f" ]] && [[ "$(head -c 6 "$f")" != ABSENT ]] && cat "$f"
}

# m20_restaurer_objet EXX TYPE NOM [ESPACE] — remet la copie (replace simple, jamais --force) ou
# supprime l'objet s'il n'existait pas, puis oublie la copie.
m20_restaurer_objet() {
  local ex="$1" type="$2" nom="$3" ns="${4:-}" f
  f="$(_m20_fichier_objet "$ex" "$type" "$nom" "$ns")"
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

# m20_oublier_objet EXX TYPE NOM [ESPACE] — efface la copie sans rien restaurer.
m20_oublier_objet() { rm -f -- "$(_m20_fichier_objet "$@")"; }

# ---------------------------------------------------------------------------
# Santé avant injection
# ---------------------------------------------------------------------------

# m20_sain APP… — refuse de casser un Argo CD ou des applications qui ne vont pas bien.
m20_sain() {
  local a
  m20_outils || return 1
  if ! m20_api GET "projects/$(m20_enc "$_M20_GITOPS")" >/dev/null 2>&1; then
    echo "API GitLab inaccessible avec le jeton d'administration (WB_GITLAB_ADMIN_TOKEN_FILE) : rien n'est cassé." >&2
    return 1
  fi
  if ! wb_kubectl -n "$_M20_NS" get applications.argoproj.io >/dev/null 2>&1; then
    echo "Les Applications d'Argo CD ne se lisent pas (kubeconfig d'administration ?) : rien n'est cassé." >&2
    return 1
  fi
  for a in "$@"; do
    if ! m20_app_saine "$a"; then
      echo "L'Application $a n'est pas Synced et Healthy (argocd app get $a) : répare d'abord, rien n'est cassé." >&2
      return 1
    fi
  done
}

# m20_preparer APP… — précondition commune. Pendant l'astreinte (M20-E43, _M20_ASTREINTE=1),
# break-E43 a fait ces contrôles une fois avant la première panne.
m20_preparer() {
  if [[ -n "${_M20_ASTREINTE:-}" ]]; then return 0; fi
  m20_sain "$@"
}
