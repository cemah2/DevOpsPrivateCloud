# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq, yq et scripts distants entre apostrophes
# _m29-commun.sh — fonctions partagées par les scripts de panne du module 29 (M29-E19 à M29-E23).
#
# Sourcé par break-EXX.sh APRÈS lab/lib/pannes-lib.sh (wb_exec, wb_kubectl, wb_avert, WB_EX, WB_VAR…).
# lab/bin/break tourne avec « set -euo pipefail » : les fonctions d'annulation sont appelées hors de
# tout « if », aucune commande n'y échoue sans « || true ».
#
# Principes (CONVENTIONS §8, PLAN §4.13 « Pannes du bloc G ») :
#   - cibles : dépôts plateforme/politiques, plateforme/infra, plateforme/gitops, mediagenda/deploiement
#     (overlay recette seulement) ; objets de chaos-experiences, mediagenda-recette, medinotif-recette,
#     wb-essais ; VMs 2298-2299 du pool lab ; un fichier temporaire d'adm01 ; une VM non critique du socle
#     (nbx01 ou mon01). JAMAIS *-prod, messagerie, kube-system, argocd, kyverno ;
#   - une modification de dépôt est un COMMIT IDENTIFIABLE : auteur « Lucas Martin »
#     (lucas.martin@medisphere.internal), marqueur « M29-EXX » ; l'annulation est un commit inverse,
#     fait SEULEMENT si chaque fichier est encore exactement dans l'état injecté ; jamais de réécriture
#     d'historique ; si main refuse la poussée directe, MR fusionnée après son pipeline ;
#   - toute expérience de chaos posée par une panne a une durée (ou un deadline) et est supprimée par
#     --annuler, qui vérifie ensuite sur le nœud qu'aucun qdisc netem ne reste sur les pods visés ;
#   - état local de chaque panne : ~/.local/state/workbook/M29-EXX/ (700) sur adm01.
#
# Outils requis sur adm01 : kubectl, jq, curl, yq (mikefarah v4), ssh (+ opa et conftest pour E19).

_M29_GITLAB="${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}"
_M29_LUCAS_NOM="Lucas Martin"
_M29_LUCAS_COURRIEL="lucas.martin@medisphere.internal"
_M29_CHAOS_NS="${WB_M29_CHAOS_NS:-chaos-experiences}"
_M29_RECETTE=mediagenda-recette
_M29_NOTIF_RECETTE=medinotif-recette
_M29_API_SEL='app.kubernetes.io/name=mediagenda,app.kubernetes.io/component=api'
read -r -a _M29_W <<<"${WB_K8S_WORKERS:-k8s-w01 k8s-w02 k8s-w03}"

# ---------------------------------------------------------------------------
# État local et journal (adm01)
# ---------------------------------------------------------------------------

m29_etat() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/M29-$1"
  mkdir -p "$d" && chmod 700 "$d"
  printf '%s\n' "$d"
}
m29_poser() { printf '%s\n' "$3" >"$(m29_etat "$1")/$2"; }
m29_lire() {
  local f
  f="$(m29_etat "$1")/$2"
  if [[ -f "$f" ]]; then cat "$f"; fi
}
m29_oublier() { rm -f -- "$(m29_etat "$1")/$2"; }
m29_journal() {
  local ex="$1"
  shift
  printf '%s %s [M29-%s variante %s] %s\n' "$(date -Is)" "$(hostname -s)" "$ex" "${WB_VAR:-?}" "$*" >>"$(m29_etat "$ex")/journal"
}

# m29_attendre SECONDES commande… — relance la commande toutes les 10 s jusqu'à succès ou délai.
m29_attendre() {
  local max="$1" t=0
  shift
  while ((t < max)); do
    if "$@"; then return 0; fi
    sleep 10
    t=$((t + 10))
  done
  "$@"
}

# m29_essayer EXX NB DÉPART — essaie les variantes à partir de DÉPART ; une variante qui renvoie 10 est
# « sans effet sur ce lab » : on la défait (fonction _m29EXX_defaire) et on passe à la suivante.
m29_essayer() {
  local ex="$1" nb="$2" depart="$3" i n rc
  for ((i = 0; i < nb; i++)); do
    n=$(((depart - 1 + i) % nb + 1))
    rc=0
    WB_VAR="$n"
    "_m29${ex}_une" "$n" || rc=$?
    if ((rc == 0)); then
      WB_VAR="$n"
      return 0
    fi
    if declare -F "_m29${ex}_defaire" >/dev/null; then "_m29${ex}_defaire" || true; fi
    ((rc == 10)) || return 1
  done
  wb_avert "aucune variante de M29-$ex n'a d'effet sur ce lab (configuration inattendue)"
  return 1
}

m29_hasard() { local -a l=("$@"); printf '%s\n' "${l[RANDOM % ${#l[@]}]}"; }

# m29_outils [outils supplémentaires…] — outils présents (yq de mikefarah, pas le yq Python).
m29_outils() {
  local c
  for c in kubectl jq curl yq ssh "$@"; do
    command -v "$c" >/dev/null 2>&1 || { echo "outil manquant sur adm01 : $c" >&2; return 1; }
  done
  yq --version 2>/dev/null | grep -q 'mikefarah' || { echo "yq de mikefarah (v4) attendu sur adm01" >&2; return 1; }
}

# ---------------------------------------------------------------------------
# GitLab (jeton d'administration de l'apprenant, jamais en argument)
# ---------------------------------------------------------------------------

m29_enc() { jq -rn --arg s "$1" '$s|@uri'; }

# m29_api MÉTHODE CHEMIN [options curl…] — corps sur stdout ; code ≠ 0 si HTTP ≥ 400.
m29_api() {
  local m="$1" p="$2" f t
  shift 2
  f="${WB_GITLAB_ADMIN_TOKEN_FILE:-$HOME/.config/workbook/gitlab-admin.token}"
  [[ -r "$f" ]] || { wb_avert "jeton d'administration GitLab illisible : $f"; return 1; }
  t="$(tr -d '[:space:]' <"$f")"
  curl -sf --max-time 30 -X "$m" -H @<(printf 'PRIVATE-TOKEN: %s\n' "$t") "$_M29_GITLAB/api/v4/$p" "$@"
}

# m29_git_lire PROJET CHEMIN [RÉF=main] — contenu du fichier.
m29_git_lire() {
  m29_api GET "projects/$(m29_enc "$1")/repository/files/$(m29_enc "$2")/raw?ref=${3:-main}"
}

# m29_git_arbre PROJET [DOSSIER] — chemins des fichiers (récursif) sur main.
m29_git_arbre() {
  local p page=1 r
  p="$(m29_enc "$1")"
  while ((page <= 10)); do
    r="$(m29_api GET "projects/$p/repository/tree?ref=main&recursive=true&per_page=100&page=$page${2:+&path=$(m29_enc "$2")}" 2>/dev/null)" || return 0
    jq -r '.[]? | select(.type == "blob") | .path' <<<"$r"
    (($(jq 'length' <<<"$r" 2>/dev/null || echo 0) < 100)) && return 0
    page=$((page + 1))
  done
}

# _m29_commit PROJET BRANCHE "message" FICHIER_ACTIONS [lucas] — commit de plusieurs actions (JSON
# [{action, file_path, content?}]) ; affiche le sha.
_m29_commit() {
  local p="$1" br="$2" msg="$3" actions="$4" qui="${5:-}" corps
  if [[ "$qui" == lucas ]]; then
    corps="$(jq -n --arg b "$br" --arg m "$msg" --slurpfile a "$actions" \
      --arg an "$_M29_LUCAS_NOM" --arg ae "$_M29_LUCAS_COURRIEL" \
      '{branch: $b, commit_message: $m, author_name: $an, author_email: $ae, actions: $a[0]}')"
  else
    corps="$(jq -n --arg b "$br" --arg m "$msg" --slurpfile a "$actions" \
      '{branch: $b, commit_message: $m, actions: $a[0]}')"
  fi
  m29_api POST "projects/$(m29_enc "$p")/repository/commits" \
    -H 'Content-Type: application/json' --data-binary "$corps" | jq -r '.id // empty'
}

# _m29_mr_fusionner PROJET BRANCHE "titre" — MR vers main, fusion après le pipeline (≤ 15 min).
_m29_mr_fusionner() {
  local p br="$2" titre="$3" iid etat i
  p="$(m29_enc "$1")"
  iid="$(m29_api POST "projects/$p/merge_requests" --data-urlencode "source_branch=$br" \
    --data-urlencode "target_branch=main" --data-urlencode "title=$titre" \
    --data-urlencode "remove_source_branch=true" | jq -r '.iid // empty')" || iid=""
  [[ -n "$iid" ]] || return 1
  sleep 5
  m29_api PUT "projects/$p/merge_requests/$iid/merge" --data-urlencode "auto_merge=true" >/dev/null 2>&1 ||
    m29_api PUT "projects/$p/merge_requests/$iid/merge" --data-urlencode "merge_when_pipeline_succeeds=true" >/dev/null 2>&1 ||
    m29_api PUT "projects/$p/merge_requests/$iid/merge" >/dev/null 2>&1 || true
  for ((i = 0; i < 60; i++)); do
    etat="$(m29_api GET "projects/$p/merge_requests/$iid" | jq -r '.state // empty')" || etat=""
    [[ "$etat" == merged ]] && return 0
    [[ "$etat" == closed ]] && break
    sleep 15
  done
  wb_avert "la MR !$iid de $1 n'a pas pu être fusionnée (pipeline, approbations ?) : fermée"
  m29_api PUT "projects/$p/merge_requests/$iid" --data-urlencode "state_event=close" >/dev/null 2>&1 || true
  m29_api DELETE "projects/$p/repository/branches/$(m29_enc "$br")" >/dev/null 2>&1 || true
  return 1
}

# _m29_pousser PROJET "message" FICHIER_ACTIONS [lucas] — commit direct sur main si accepté, sinon
# branche + MR fusionnée.
_m29_pousser() {
  local p="$1" msg="$2" actions="$3" qui="${4:-}" br sha
  sha="$(_m29_commit "$p" main "$msg" "$actions" "$qui" 2>/dev/null)" || sha=""
  [[ -n "$sha" ]] && return 0
  br="${qui:-moi}/m29-$(date +%s)"
  m29_api POST "projects/$(m29_enc "$p")/repository/branches" \
    --data-urlencode "branch=$br" --data-urlencode "ref=main" >/dev/null || return 1
  sha="$(_m29_commit "$p" "$br" "$msg" "$actions" "$qui")" || sha=""
  [[ -n "$sha" ]] || return 1
  _m29_mr_fusionner "$p" "$br" "${msg%%$'\n'*}"
}

# Préparation d'un commit de Lucas en plusieurs fichiers :
#   m29_git_debut EXX PROJET
#   m29_git_fichier EXX CHEMIN FICHIER_NEUF   (fichier existant modifié, ou nouveau fichier)
#   m29_git_valider EXX "message"
# L'original de chaque fichier est gardé (ou noté ABSENT) pour l'annulation.
m29_git_debut() {
  local d
  d="$(m29_etat "$1")"
  rm -rf -- "$d/git"
  mkdir -p "$d/git" && chmod 700 "$d/git"
  printf '%s\n' "$2" >"$d/git/projet"
  : >"$d/git/liste"
}
m29_git_fichier() {
  local d n chemin="$2" neuf="$3" p
  d="$(m29_etat "$1")/git"
  p="$(cat "$d/projet")"
  n="$(wc -l <"$d/liste")"
  n=$((n + 1))
  if m29_git_lire "$p" "$chemin" >"$d/$n.orig" 2>/dev/null; then
    printf '%s\tupdate\n' "$chemin" >>"$d/liste"
  else
    rm -f "$d/$n.orig"
    printf '%s\tcreate\n' "$chemin" >>"$d/liste"
  fi
  cp -- "$neuf" "$d/$n.neuf"
  chmod 600 "$d/$n".*
}
m29_git_valider() {
  local ex="$1" msg="$2" d p actions n=0 chemin action
  d="$(m29_etat "$ex")/git"
  p="$(cat "$d/projet")"
  actions="$d/actions.json"
  echo '[]' >"$actions"
  while IFS=$'\t' read -r chemin action; do
    n=$((n + 1))
    jq --arg a "$action" --arg p "$chemin" --rawfile c "$d/$n.neuf" '. + [{action: $a, file_path: $p, content: $c}]' \
      "$actions" >"$actions.tmp" && mv "$actions.tmp" "$actions"
  done <"$d/liste"
  ((n > 0)) || return 10
  _m29_pousser "$p" "$msg" "$actions" lucas || return 1
  : >"$d/injecte"
  m29_journal "$ex" "commit de Lucas sur $p ($n fichier(s))"
}

# m29_git_injecte EXX — tous les fichiers du commit sont encore exactement dans l'état injecté.
m29_git_injecte() {
  local d p n=0 chemin action
  d="$(m29_etat "$1")/git"
  [[ -f "$d/injecte" ]] || return 1
  p="$(cat "$d/projet")"
  while IFS=$'\t' read -r chemin action; do
    n=$((n + 1))
    cmp -s <(m29_git_lire "$p" "$chemin" 2>/dev/null) "$d/$n.neuf" || return 1
  done <"$d/liste"
}

# m29_git_annuler EXX — commit inverse si l'état injecté est intact ; sinon rien (réparation respectée).
m29_git_annuler() {
  local ex="$1" d p actions n=0 chemin action
  d="$(m29_etat "$ex")/git"
  [[ -f "$d/injecte" ]] || { rm -rf -- "$d"; return 0; }
  p="$(cat "$d/projet")"
  if m29_git_injecte "$ex"; then
    actions="$d/inverse.json"
    echo '[]' >"$actions"
    while IFS=$'\t' read -r chemin action; do
      n=$((n + 1))
      if [[ "$action" == create ]]; then
        jq --arg p "$chemin" '. + [{action: "delete", file_path: $p}]' "$actions" >"$actions.tmp"
      else
        jq --arg p "$chemin" --rawfile c "$d/$n.orig" '. + [{action: "update", file_path: $p, content: $c}]' \
          "$actions" >"$actions.tmp"
      fi
      mv "$actions.tmp" "$actions"
    done <"$d/liste"
    if _m29_pousser "$p" "Revert du commit de Lucas (lab/bin/break 29 ${ex#E} --annuler, M29-$ex)" "$actions"; then
      m29_journal "$ex" "annulation : $p remis dans son état d'origine"
    else
      wb_avert "annulation du commit sur $p impossible : remets les fichiers à la main (copies : $d)"
      return 0
    fi
  else
    m29_journal "$ex" "annulation : $p déjà modifié depuis la panne, rien à défaire"
  fi
  rm -rf -- "$d"
}

# ---------------------------------------------------------------------------
# Kubernetes et Argo CD (kubeconfig d'administration)
# ---------------------------------------------------------------------------

m29_app_saine() {
  wb_kubectl -n argocd get applications.argoproj.io "$1" -o json 2>/dev/null |
    jq -e '.status.sync.status == "Synced" and .status.health.status == "Healthy"' >/dev/null 2>&1
}

# m29_rafraichir APP… — demande à Argo CD de relire Git tout de suite.
m29_rafraichir() {
  local a
  for a in "$@"; do
    wb_kubectl -n argocd annotate applications.argoproj.io "$a" argocd.argoproj.io/refresh=normal --overwrite >/dev/null 2>&1 || true
  done
}

# m29_app_de_espace ESPACE — nom de l'Application Argo CD qui déploie dans cet espace (la première).
m29_app_de_espace() {
  wb_kubectl -n argocd get applications.argoproj.io -o json 2>/dev/null |
    jq -r --arg ns "$1" '[.items[] | select(.spec.destination.namespace == $ns) | .metadata.name][0] // empty'
}

# m29_api_pretes — nombre de pods prêts de l'API MédiAgenda en recette.
m29_api_pretes() {
  wb_kubectl -n "$_M29_RECETTE" get pods -l "$_M29_API_SEL" -o json 2>/dev/null |
    jq '[.items[] | select(.metadata.deletionTimestamp == null) | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))] | length' 2>/dev/null || echo 0
}

# m29_api_pods — noms des pods de l'API MédiAgenda en recette (non en cours de suppression).
m29_api_pods() {
  wb_kubectl -n "$_M29_RECETTE" get pods -l "$_M29_API_SEL" -o json 2>/dev/null |
    jq -r '.items[] | select(.metadata.deletionTimestamp == null) | .metadata.name'
}

# m29_types_chaos — types (pluriel.groupe) de l'API chaos-mesh.org.
m29_types_chaos() {
  wb_kubectl api-resources --api-group=chaos-mesh.org -o name 2>/dev/null
}

# m29_chaos_sain — Chaos Mesh répond (contrôleur et daemons prêts) et les espaces de recette sont annotés.
m29_chaos_sain() {
  wb_kubectl -n chaos-mesh get deploy chaos-controller-manager -o json 2>/dev/null |
    jq -e '(.status.readyReplicas // 0) >= 1' >/dev/null 2>&1 || return 1
  wb_kubectl -n chaos-mesh get ds chaos-daemon -o json 2>/dev/null |
    jq -e '.status.desiredNumberScheduled > 0 and .status.numberReady == .status.desiredNumberScheduled' >/dev/null 2>&1 || return 1
  wb_kubectl get namespace "$_M29_RECETTE" -o json 2>/dev/null |
    jq -e '.metadata.annotations["chaos-mesh.org/inject"] == "enabled"' >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Nœuds : espace réseau d'un pod (lecture et retrait d'un netem orphelin)
# ---------------------------------------------------------------------------

# m29_noeud_de ESPACE POD — nœud qui porte le pod.
m29_noeud_de() { wb_kubectl -n "$1" get pod "$2" -o jsonpath='{.spec.nodeName}' 2>/dev/null; }

# _m29_ns_script — fonction distante : PID du bac à sable du pod $POD de l'espace $NS.
read -r -d '' _M29_NS_PID <<'EOF' || true
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
sandbox_pid() {
  local id
  id="$(crictl pods --namespace "$NS" --name "^${POD}\$" --state ready -q 2>/dev/null | head -n 1)"
  [ -n "$id" ] || return 1
  crictl inspectp "$id" 2>/dev/null | sed -n 's/.*"pid": *\([0-9][0-9]*\).*/\1/p' | head -n 1
}
EOF

# m29_netem_present ESPACE POD — 0 si un qdisc netem est posé dans l'espace réseau du pod.
m29_netem_present() {
  local n
  n="$(m29_noeud_de "$1" "$2")"
  [[ -n "$n" ]] || return 1
  { printf '%s\n' "$_M29_NS_PID"; cat <<'EOF'
p="$(sandbox_pid)" || exit 1
[ -n "$p" ] || exit 1
nsenter -t "$p" -n tc qdisc show 2>/dev/null | grep -q netem
EOF
  } | wb_exec "$n" NS="$1" POD="$2" >/dev/null 2>&1
}

# m29_netem_retirer ESPACE POD — retire la racine qdisc de eth0 si (et seulement si) c'est netem ou
# l'arbre prio de Chaos Mesh, posé pour une panne. Journalisé sur le nœud.
m29_netem_retirer() {
  local n
  n="$(m29_noeud_de "$1" "$2")"
  [[ -n "$n" ]] || return 0
  { printf '%s\n' "$_M29_NS_PID"; cat <<'EOF'
p="$(sandbox_pid)" || exit 0
[ -n "$p" ] || exit 0
if nsenter -t "$p" -n tc qdisc show dev eth0 2>/dev/null | grep -q netem; then
  nsenter -t "$p" -n tc qdisc del dev eth0 root 2>/dev/null && journal "netem retiré à la main sur $NS/$POD (pid $p)"
fi
exit 0
EOF
  } | wb_exec "$n" NS="$1" POD="$2" >/dev/null 2>&1 || true
}

# m29_aucun_netem_api — aucun pod de l'API MédiAgenda en recette n'a de netem.
m29_aucun_netem_api() {
  local p
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    if m29_netem_present "$_M29_RECETTE" "$p"; then return 1; fi
  done < <(m29_api_pods)
  return 0
}

# m29_supprimer_chaos ESPACE TYPE NOM — supprime une expérience ; si elle reste bloquée 90 s sur son
# finaliseur, force (annotation documentée de Chaos Mesh) puis retire tout netem resté sur les pods
# de l'API MédiAgenda.
m29_supprimer_chaos() {
  local ns="$1" type="$2" nom="$3" i
  wb_kubectl -n "$ns" delete "$type" "$nom" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  for ((i = 0; i < 9; i++)); do
    wb_kubectl -n "$ns" get "$type" "$nom" >/dev/null 2>&1 || return 0
    sleep 10
  done
  wb_kubectl -n "$ns" annotate "$type" "$nom" chaos-mesh.chaos-mesh.org/cleanFinalizer=forced --overwrite >/dev/null 2>&1 || true
  sleep 10
  if wb_kubectl -n "$ns" get "$type" "$nom" >/dev/null 2>&1; then
    wb_kubectl -n "$ns" patch "$type" "$nom" --type=merge -p '{"metadata":{"finalizers":null}}' >/dev/null 2>&1 || true
  fi
  m29_journal "${WB_EX#M29-}" "suppression forcée de $ns/$type/$nom"
}

# m29_nettoyer_netem_api — dernier filet : retire les netem restés sur les pods de l'API.
m29_nettoyer_netem_api() {
  local p
  while IFS= read -r p; do
    [[ -n "$p" ]] && m29_netem_retirer "$_M29_RECETTE" "$p"
  done < <(m29_api_pods)
}

# ---------------------------------------------------------------------------
# Mesure (Prometheus du cluster, lecture)
# ---------------------------------------------------------------------------

# m29_p95_recette [FENÊTRE=2m] — p95 (s) de l'API MédiAgenda en recette, vide si pas de trafic.
m29_p95_recette() {
  prom_requete "histogram_quantile(0.95, sum by (le) (rate(mediagenda_http_request_duration_seconds_bucket{namespace=\"$_M29_RECETTE\", route!~\"/sante|/pret|/metrics\"}[${1:-2m}])))" 2>/dev/null |
    jq -r '.data.result[0].value[1] // empty' 2>/dev/null
}

# m29_trafic_recette SECONDES — petit trafic de mesure (GET créneaux) depuis adm01, en tâche de fond ;
# affiche le PID. Le trafic s'arrête seul.
m29_trafic_recette() {
  local url="${WB_M29_RECETTE_URL:-https://mediagenda-recette.apps.par1.medisphere.internal}" fin
  fin=$(($(date +%s) + $1))
  (
    while (($(date +%s) < fin)); do
      curl -s -o /dev/null --max-time 5 "$url/api/v1/creneaux?date=$(date -d tomorrow +%F)" || true
      sleep 0.5
    done
  ) >/dev/null 2>&1 &
  printf '%s\n' "$!"
}
