# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq, yq et scripts distants entre apostrophes
# _m22-commun.sh — fonctions partagées par les scripts de panne du module 22 (M22-E19 à M22-E23).
#
# Sourcé par break-EXX.sh APRÈS lab/lib/pannes-lib.sh (wb_exec, wb_kubectl, wb_avert, WB_EX, WB_VAR…).
# Rappel : lab/bin/break tourne avec « set -euo pipefail » ; les fonctions d'annulation sont appelées
# hors de tout « if » : aucune commande ne doit y échouer sans « || true ».
#
# Principes (CONVENTIONS §8, PLAN §4.10 et §4.11 « Pannes des blocs D et E ») :
#   - cibles : nœuds de k8s-par1 (SSH, admin + sudo), objets des espaces journaux, wb-pannes,
#     mediagenda-recette (E23 seulement : un Role et un RoleBinding ajoutés, jamais un objet de l'équipe
#     modifié), et le dépôt GitLab plateforme/observabilite ;
#   - une modification du dépôt est un COMMIT IDENTIFIABLE : auteur « Lucas Martin »
#     (lucas.martin@medisphere.internal), marqueur « M22-EXX » dans le message ; l'annulation est un
#     commit inverse (contenu d'origine remis), fait SEULEMENT si le fichier est encore exactement dans
#     l'état injecté (une réparation de l'apprenant n'est jamais défaite) ; jamais de réécriture
#     d'historique. Si main est protégée contre la poussée directe, le commit passe par une MR fusionnée
#     automatiquement après son pipeline (jeton d'administration de l'apprenant, WB_GITLAB_ADMIN_TOKEN_FILE) ;
#   - aucune donnée n'est supprimée : ni dans loki-k8s-par1, ni dans journald (le répertoire du journal
#     est renommé, jamais vidé), ni dans la base de MédiAgenda (E23 ne supprime que des rendez-vous qu'il
#     a lui-même créés) ; JAMAIS de rétention raccourcie ;
#   - l'état local de chaque panne est dans ~/.local/state/workbook/M22-EXX/ (700) sur adm01 ; les
#     fichiers modifiés sur les nœuds sont sauvegardés dans /var/lib/workbook/ du nœud (prélude de
#     pannes-lib.sh : sauver, restaurer_fichiers, journal).
#
# Outils requis sur adm01 : kubectl, jq, curl, yq (mikefarah v4), ssh.

_M22_DIR="$(dirname "${BASH_SOURCE[0]}")"
_M22_NS=journaux
_M22_PANNES=wb-pannes
_M22_LOKI="${WB_LOKI_URL:-http://loki.apps.par1.medisphere.internal:3100}"
_M22_GITLAB="${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}"
_M22_PROJET=plateforme/observabilite
_M22_LUCAS_NOM="Lucas Martin"
_M22_LUCAS_COURRIEL="lucas.martin@medisphere.internal"
_M22_REGISTRE=registry.par1.medisphere.internal
read -r -a _M22_CP <<<"${WB_K8S_CP:-k8s-cp01 k8s-cp02 k8s-cp03}"
read -r -a _M22_W <<<"${WB_K8S_WORKERS:-k8s-w01 k8s-w02 k8s-w03}"
# Chemins des fichiers du dépôt plateforme/observabilite créés par le palier 1 (M22-E02 : loki/values.yaml
# et grafana/sources-loki.yaml ; M22-E03 : alloy/values.yaml et alloy/config.alloy) ; surchargeables par
# lab/lab.env si le dépôt de l'apprenant les range ailleurs.
_M22_F_LOKI="${WB_M22_FICHIER_LOKI:-loki/values.yaml}"
_M22_F_ALLOY="${WB_M22_FICHIER_ALLOY:-alloy/values.yaml}"
_M22_F_ALLOY_CONFIG="${WB_M22_FICHIER_ALLOY_CONFIG:-alloy/config.alloy}"
_M22_F_SOURCES="${WB_M22_FICHIER_SOURCES:-grafana/sources-loki.yaml}"
# Applications Argo CD rafraîchies après un commit
_M22_APPS=(loki alloy observabilite kube-prometheus-stack)

# ---------------------------------------------------------------------------
# État local et journal (adm01)
# ---------------------------------------------------------------------------

m22_etat() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/M22-$1"
  mkdir -p "$d" && chmod 700 "$d"
  printf '%s\n' "$d"
}
# m22_ecrire EXX CLÉ VALEUR — n'écrase pas une valeur déjà posée (on ne capture jamais un état cassé).
m22_ecrire() {
  local d
  d="$(m22_etat "$1")"
  [[ -f "$d/$2" ]] || printf '%s\n' "$3" >"$d/$2"
}
# m22_poser EXX CLÉ VALEUR — écrit (écrase).
m22_poser() { printf '%s\n' "$3" >"$(m22_etat "$1")/$2"; }
m22_lire() {
  local f
  f="$(m22_etat "$1")/$2"
  if [[ -f "$f" ]]; then cat "$f"; fi
}
m22_oublier() { rm -f -- "$(m22_etat "$1")/$2"; }
m22_journal() {
  local ex="$1"
  shift
  printf '%s %s [M22-%s variante %s] %s\n' "$(date -Is)" "$(hostname -s)" "$ex" "${WB_VAR:-?}" "$*" >>"$(m22_etat "$ex")/journal"
}

# m22_attendre SECONDES commande… — relance la commande toutes les 10 s jusqu'à succès ou délai.
m22_attendre() {
  local max="$1" t=0
  shift
  while ((t < max)); do
    if "$@"; then return 0; fi
    sleep 10
    t=$((t + 10))
  done
  "$@"
}

# m22_essayer EXX NB DÉPART — essaie les variantes à partir de DÉPART ; une variante qui renvoie 10 est
# « sans effet sur ce lab » (configuration différente de celle du corrigé) : on passe à la suivante.
m22_essayer() {
  local ex="$1" nb="$2" depart="$3" i n rc
  for ((i = 0; i < nb; i++)); do
    n=$(((depart - 1 + i) % nb + 1))
    rc=0
    WB_VAR="$n"
    "_m22${ex}_une" "$n" || rc=$?
    if ((rc == 0)); then
      WB_VAR="$n"
      return 0
    fi
    ((rc == 10)) || return 1
  done
  wb_avert "aucune variante de M22-$ex n'a d'effet sur ce lab (configuration inattendue)"
  return 1
}

m22_hasard() { local -a l=("$@"); printf '%s\n' "${l[RANDOM % ${#l[@]}]}"; }

# m22_outils — outils présents (yq de mikefarah, pas le yq Python).
m22_outils() {
  local c
  for c in kubectl jq curl yq ssh; do
    command -v "$c" >/dev/null 2>&1 || { echo "outil manquant sur adm01 : $c" >&2; return 1; }
  done
  yq --version 2>/dev/null | grep -q 'mikefarah' || { echo "yq de mikefarah (v4) attendu sur adm01" >&2; return 1; }
}

# ---------------------------------------------------------------------------
# Loki (lecture, depuis adm01 par le Service 10.10.41.62)
# ---------------------------------------------------------------------------

# m22_loki CHEMIN [LOCATAIRE] — GET sur Loki (chemin depuis la racine, ex. /config), corps sur stdout.
m22_loki() {
  curl -sf --max-time 20 ${2:+-H "X-Scope-OrgID: $2"} "$_M22_LOKI$1"
}

# m22_loki_pret — /ready répond 200.
m22_loki_pret() { [[ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$_M22_LOKI/ready" 2>/dev/null)" == 200 ]]; }

# m22_metrique 'regex de série' — somme des valeurs des séries de /metrics dont la ligne correspond.
m22_metrique() {
  m22_loki /metrics 2>/dev/null | awk -v re="$1" '$0 !~ /^#/ && $0 ~ re { s += $NF } END { printf "%.0f\n", s + 0 }'
}

# m22_limite LOCATAIRE CLÉ — valeur publiée par /config/tenant/v1/limits.
m22_limite() { m22_loki /config/tenant/v1/limits "$1" 2>/dev/null | yq ".$2" 2>/dev/null; }

# m22_requete LOCATAIRE 'LogQL' [DEPUIS=15m] — query_range, JSON (code HTTP dans .http).
m22_requete() {
  local corps code
  corps="$(curl -s --max-time 60 -G -w '\n%{http_code}' -H "X-Scope-OrgID: $1" \
    --data-urlencode "query=$2" --data-urlencode "since=${3:-15m}" --data-urlencode "limit=1000" \
    "$_M22_LOKI/loki/api/v1/query_range" 2>/dev/null)" || true
  code="${corps##*$'\n'}"
  corps="${corps%$'\n'*}"
  jq -c --arg c "$code" '. + {http: ($c | tonumber? // 0)}' <<<"$corps" 2>/dev/null || jq -nc --arg c "$code" --arg b "$corps" '{http: ($c | tonumber? // 0), erreur: $b}'
}

# m22_nb_lignes LOCATAIRE 'LogQL' [DEPUIS] — nombre de lignes renvoyées (0 si erreur).
m22_nb_lignes() {
  m22_requete "$@" | jq '[.data.result[]?.values[]?] | length' 2>/dev/null || echo 0
}

# m22_motif_present LOCATAIRE MOTIF [DEPUIS] — une ligne contenant MOTIF est arrivée (sélecteurs usuels).
m22_motif_present() {
  local s
  for s in '{node=~".+"}' '{job=~".+"}' '{host=~".+"}' '{namespace=~".+"}'; do
    (($(m22_nb_lignes "$1" "$s |= \"$2\"" "${3:-10m}") > 0)) && return 0
  done
  return 1
}

# ---------------------------------------------------------------------------
# Kubernetes et Argo CD (kubeconfig d'administration)
# ---------------------------------------------------------------------------

# m22_app_saine NOM — Application Argo CD Synced et Healthy.
m22_app_saine() {
  wb_kubectl -n argocd get applications.argoproj.io "$1" -o json 2>/dev/null |
    jq -e '.status.sync.status == "Synced" and .status.health.status == "Healthy"' >/dev/null 2>&1
}

# m22_rafraichir — demande à Argo CD de relire Git tout de suite (au lieu d'attendre l'interrogation).
m22_rafraichir() {
  local a
  for a in "${_M22_APPS[@]}"; do
    wb_kubectl -n argocd annotate applications.argoproj.io "$a" argocd.argoproj.io/refresh=normal --overwrite >/dev/null 2>&1 || true
  done
}

# m22_alloy_complet — le DaemonSet alloy tourne et est prêt sur tous les nœuds Ready.
m22_alloy_complet() {
  local n
  n="$(wb_kubectl get nodes -o json 2>/dev/null | jq '[.items[] | select(any(.status.conditions[]; .type == "Ready" and .status == "True"))] | length' 2>/dev/null)" || return 1
  wb_kubectl -n "$_M22_NS" get daemonset alloy -o json 2>/dev/null |
    jq -e --argjson n "${n:-0}" '.status.desiredNumberScheduled == $n and .status.numberReady == $n and $n > 0' >/dev/null 2>&1
}

# m22_alloy_sur NŒUD — un pod alloy existe sur ce nœud (code 0) ou non.
m22_alloy_sur() {
  wb_kubectl -n "$_M22_NS" get pods -l app.kubernetes.io/name=alloy --field-selector "spec.nodeName=$1" -o json 2>/dev/null |
    jq -e '.items | length > 0' >/dev/null 2>&1
}

# m22_runtime — contenu du fichier de surcharges (ConfigMap loki-runtime).
m22_runtime() { wb_kubectl -n "$_M22_NS" get configmap loki-runtime -o jsonpath='{.data.runtime-config\.yaml}' 2>/dev/null; }

# ---------------------------------------------------------------------------
# Nœuds
# ---------------------------------------------------------------------------

# m22_wb_exec HÔTE [VAR=valeur…] <<'EOF' … EOF — wb_exec (root, prélude de pannes-lib) avec un PATH complet.
m22_wb_exec() {
  local h="$1"
  shift
  { printf 'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\n'; cat; } | wb_exec "$h" "$@"
}

# m22_ligne_temoin NŒUD — écrit une ligne de contrôle dans journald du nœud et affiche son motif.
m22_ligne_temoin() {
  local motif
  motif="controle-$(date +%s)-$RANDOM"
  remote "$1" "logger -t wb-controle 'journal de controle $motif'" </dev/null >/dev/null 2>&1 || return 1
  printf '%s\n' "$motif"
}

# m22_journald_collecte NŒUD [SECONDES=120] — une ligne écrite dans journald du nœud arrive dans Loki.
m22_journald_collecte() {
  local motif
  motif="$(m22_ligne_temoin "$1")" || return 1
  m22_attendre "${2:-120}" m22_motif_present plateforme "$motif" 5m
}

# ---------------------------------------------------------------------------
# GitLab : dépôt plateforme/observabilite (jeton d'administration de l'apprenant)
# ---------------------------------------------------------------------------

_m22_enc() { jq -rn --arg s "$1" '$s|@uri'; }

# m22_api MÉTHODE CHEMIN [options curl…] — corps sur stdout ; code ≠ 0 si HTTP ≥ 400. Le jeton ne
# passe jamais en argument (en-tête lu depuis un descripteur).
m22_api() {
  local m="$1" p="$2" f t
  shift 2
  f="${WB_GITLAB_ADMIN_TOKEN_FILE:-$HOME/.config/workbook/gitlab-admin.token}"
  [[ -r "$f" ]] || { wb_avert "jeton d'administration GitLab illisible : $f"; return 1; }
  t="$(tr -d '[:space:]' <"$f")"
  curl -sf --max-time 30 -X "$m" -H @<(printf 'PRIVATE-TOKEN: %s\n' "$t") "$_M22_GITLAB/api/v4/$p" "$@"
}

# m22_git_lire CHEMIN — contenu du fichier sur main.
m22_git_lire() {
  m22_api GET "projects/$(_m22_enc "$_M22_PROJET")/repository/files/$(_m22_enc "$1")/raw?ref=main"
}

# m22_git_chercher 'regex' — chemins des fichiers texte du dépôt (main) dont le contenu correspond.
m22_git_chercher() {
  local p chemin
  p="$(_m22_enc "$_M22_PROJET")"
  m22_api GET "projects/$p/repository/tree?ref=main&recursive=true&per_page=100" 2>/dev/null |
    jq -r '.[] | select(.type == "blob") | .path | select(test("\\.(ya?ml|alloy|json|jsonnet)$"))' 2>/dev/null |
    while IFS= read -r chemin; do
      if m22_git_lire "$chemin" 2>/dev/null | grep -Eq -- "$1"; then printf '%s\n' "$chemin"; fi
    done
}

# _m22_commit BRANCHE "message" CHEMIN FICHIER [lucas] — un commit (action update) ; affiche le sha.
_m22_commit() {
  local br="$1" msg="$2" chemin="$3" fichier="$4" qui="${5:-}" corps
  if [[ "$qui" == lucas ]]; then
    corps="$(jq -n --arg b "$br" --arg m "$msg" --arg p "$chemin" --rawfile c "$fichier" \
      --arg an "$_M22_LUCAS_NOM" --arg ae "$_M22_LUCAS_COURRIEL" \
      '{branch: $b, commit_message: $m, author_name: $an, author_email: $ae,
        actions: [{action: "update", file_path: $p, content: $c}]}')"
  else
    corps="$(jq -n --arg b "$br" --arg m "$msg" --arg p "$chemin" --rawfile c "$fichier" \
      '{branch: $b, commit_message: $m, actions: [{action: "update", file_path: $p, content: $c}]}')"
  fi
  m22_api POST "projects/$(_m22_enc "$_M22_PROJET")/repository/commits" \
    -H 'Content-Type: application/json' --data-binary "$corps" | jq -r '.id // empty'
}

# _m22_mr_fusionner BRANCHE "titre" — MR vers main, fusion automatique après le pipeline (≤ 15 min).
_m22_mr_fusionner() {
  local br="$1" titre="$2" p iid etat i
  p="$(_m22_enc "$_M22_PROJET")"
  iid="$(m22_api POST "projects/$p/merge_requests" --data-urlencode "source_branch=$br" \
    --data-urlencode "target_branch=main" --data-urlencode "title=$titre" \
    --data-urlencode "remove_source_branch=true" | jq -r '.iid // empty')" || iid=""
  [[ -n "$iid" ]] || return 1
  sleep 5
  m22_api PUT "projects/$p/merge_requests/$iid/merge" --data-urlencode "auto_merge=true" >/dev/null 2>&1 ||
    m22_api PUT "projects/$p/merge_requests/$iid/merge" --data-urlencode "merge_when_pipeline_succeeds=true" >/dev/null 2>&1 ||
    m22_api PUT "projects/$p/merge_requests/$iid/merge" >/dev/null 2>&1 || true
  for ((i = 0; i < 60; i++)); do
    etat="$(m22_api GET "projects/$p/merge_requests/$iid" | jq -r '.state // empty')" || etat=""
    [[ "$etat" == merged ]] && return 0
    [[ "$etat" == closed ]] && break
    sleep 15
  done
  wb_avert "la MR !$iid de $_M22_PROJET n'a pas pu être fusionnée (pipeline, approbations ?) : fermée"
  m22_api PUT "projects/$p/merge_requests/$iid" --data-urlencode "state_event=close" >/dev/null 2>&1 || true
  m22_api DELETE "projects/$p/repository/branches/$(_m22_enc "$br")" >/dev/null 2>&1 || true
  return 1
}

# _m22_pousser "message" CHEMIN FICHIER [lucas] — met FICHIER à la place de CHEMIN sur main : commit
# direct si main l'accepte, sinon branche + MR fusionnée automatiquement.
_m22_pousser() {
  local msg="$1" chemin="$2" fichier="$3" qui="${4:-}" br sha
  sha="$(_m22_commit main "$msg" "$chemin" "$fichier" "$qui" 2>/dev/null)" || sha=""
  [[ -n "$sha" ]] && return 0
  br="${qui:-moi}/m22-$(date +%s)"
  m22_api POST "projects/$(_m22_enc "$_M22_PROJET")/repository/branches" \
    --data-urlencode "branch=$br" --data-urlencode "ref=main" >/dev/null || return 1
  sha="$(_m22_commit "$br" "$msg" "$chemin" "$fichier" "$qui")" || sha=""
  [[ -n "$sha" ]] || return 1
  _m22_mr_fusionner "$br" "${msg%%$'\n'*}"
}

# m22_git_modifier EXX CHEMIN "message" — modifie un fichier du dépôt au nom de Lucas.
# La modification est faite par la fonction _m22_transformer (définie par l'appelant), qui lit
# le fichier d'origine sur stdin et écrit le fichier modifié sur stdout ; elle renvoie 10 si le fichier
# n'a pas la forme attendue. Mémorise l'original et l'empreinte du contenu injecté.
m22_git_modifier() {
  local ex="$1" chemin="$2" msg="$3" d orig neuf rc=0
  d="$(m22_etat "$ex")"
  orig="$d/git-orig"
  neuf="$d/git-neuf"
  m22_git_lire "$chemin" >"$orig" 2>/dev/null || { wb_avert "$chemin introuvable dans $_M22_PROJET (main)"; rm -f "$orig"; return 10; }
  _m22_transformer <"$orig" >"$neuf" || rc=$?
  if ((rc != 0)) || cmp -s "$orig" "$neuf"; then
    rm -f "$orig" "$neuf"
    ((rc != 0)) && return "$rc"
    return 10
  fi
  chmod 600 "$orig" "$neuf"
  if ! _m22_pousser "$msg" "$chemin" "$neuf" lucas; then
    rm -f "$orig" "$neuf"
    return 1
  fi
  m22_poser "$ex" git-chemin "$chemin"
  m22_poser "$ex" git-empreinte "$(sha256sum "$neuf" | cut -d' ' -f1)"
  m22_journal "$ex" "commit de Lucas sur $_M22_PROJET:$chemin"
  m22_rafraichir
}

# m22_git_injecte EXX — le fichier modifié est encore exactement dans l'état injecté.
m22_git_injecte() {
  local chemin emp
  chemin="$(m22_lire "$1" git-chemin)"
  emp="$(m22_lire "$1" git-empreinte)"
  [[ -n "$chemin" && -n "$emp" ]] || return 1
  [[ "$(m22_git_lire "$chemin" 2>/dev/null | sha256sum | cut -d' ' -f1)" == "$emp" ]]
}

# m22_git_annuler EXX — commit inverse (contenu d'origine) si le fichier est encore dans l'état injecté.
m22_git_annuler() {
  local ex="$1" d chemin
  d="$(m22_etat "$ex")"
  chemin="$(m22_lire "$ex" git-chemin)"
  [[ -n "$chemin" ]] || return 0
  if m22_git_injecte "$ex"; then
    if _m22_pousser "Revert du commit de Lucas sur $chemin (lab/bin/break 22 ${ex#E} --annuler, M22-$ex)" "$chemin" "$d/git-orig"; then
      m22_journal "$ex" "annulation : $chemin remis dans son état d'origine"
      m22_rafraichir
    else
      wb_avert "annulation du commit sur $_M22_PROJET:$chemin impossible : remets le fichier à la main (copie : $d/git-orig)"
      return 0
    fi
  else
    m22_journal "$ex" "annulation : $chemin déjà modifié depuis la panne, rien à défaire"
  fi
  rm -f -- "$d/git-orig" "$d/git-neuf"
  m22_oublier "$ex" git-chemin
  m22_oublier "$ex" git-empreinte
}

# ---------------------------------------------------------------------------
# Santé avant injection
# ---------------------------------------------------------------------------

# m22_sain — refuse de casser un lab de journaux qui ne va pas bien.
m22_sain() {
  m22_outils || return 1
  if ! m22_loki_pret; then
    echo "Loki ne répond pas prêt sur $_M22_LOKI/ready : répare d'abord (lab/bin/check 22 02)." >&2
    return 1
  fi
  if ! m22_app_saine loki || ! m22_app_saine alloy; then
    echo "Les Applications Argo CD loki et alloy doivent être Synced/Healthy avant une panne." >&2
    return 1
  fi
  if ! m22_alloy_complet; then
    echo "Alloy ne tourne pas sur tous les nœuds (kubectl -n journaux get ds alloy) : rien n'est cassé." >&2
    return 1
  fi
  if (($(m22_nb_lignes plateforme '{namespace=~".+"}' 5m) == 0)); then
    echo "Aucune ligne récente dans le locataire plateforme : la collecte ne fonctionne pas (lab/bin/check 22 03)." >&2
    return 1
  fi
}

# m22_preparer — précondition commune ; pendant l'astreinte (E23, _M22_ASTREINTE=1), break-E23 l'a
# déjà faite une fois.
m22_preparer() {
  if [[ -n "${_M22_ASTREINTE:-}" ]]; then return 0; fi
  m22_sain
}
