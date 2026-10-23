# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et yq entre apostrophes
# _m28-commun.sh — fonctions partagées par les scripts de panne du module 28 (M28-E19 à M28-E23).
#
# Sourcé par break-EXX.sh APRÈS lab/lib/pannes-lib.sh (wb_kubectl, wb_k8s_sauver, wb_k8s_restaurer,
# wb_avert, WB_EX, WB_VAR…). Rappel : lab/bin/break tourne avec « set -euo pipefail » ; les fonctions
# d'annulation sont appelées hors de tout « if » : aucune commande ne doit y échouer sans « || true ».
#
# Principes (CONVENTIONS §8, PLAN §4.10 à §4.13 « Pannes ») :
#   - cibles : recette et dev des applications (medinotif-recette, mediagenda-recette, medidoc-dev),
#     objets ajoutés dans capsule-system (E21 v4, sur accord explicite) et medidoc-dev (E23) ; dépôts medinotif/deploiement et
#     mediagenda/deploiement (overlays de recette), plateforme/k8s (locataires/),
#     plateforme/gitops (valeurs/capsule/, applications/medinotif), plateforme/portail-modeles ;
#     appartenance de svc-portail aux groupes GitLab. JAMAIS *-prod, kube-system,
#     kyverno, argocd ; jamais les droits de la plateforme ni d'Argo CD ;
#   - une modification de dépôt est un COMMIT IDENTIFIABLE : auteur « Lucas Martin »
#     (lucas.martin@medisphere.internal), marqueur « M28-EXX » dans le message ; l'annulation est un
#     commit inverse fait SEULEMENT si le fichier est encore exactement dans l'état injecté (empreinte
#     SHA-256) ; jamais de réécriture d'historique. Si main refuse la poussée directe : MR fusionnée
#     automatiquement après son pipeline (jeton d'administration GitLab de l'apprenant) ;
#   - AUCUNE panne ne modifie un secret (OpenBao, Secret Kubernetes) ni ne redémarre ou ne coupe un
#     composant partagé avec la production (opérateur KEDA, webhooks par défaut) ; un droit GitLab
#     réduit (E22) est noté et remis à l'identique à l'annulation ;
#   - un objet Kubernetes ajouté ou modifié est sauvegardé par wb_k8s_sauver (pannes-lib) ;
#   - l'état local de chaque panne est dans ~/.local/state/workbook/M28-EXX/ (700) sur adm01.
#
# Outils requis sur adm01 : kubectl, jq, curl, yq (mikefarah v4).
# Variables (lab/lab.env, facultatives) : WB_GITLAB_URL, WB_GITLAB_ADMIN_TOKEN_FILE,
#   WB_K8S_ADMIN_KUBECONFIG, WB_M28_E21_WEBHOOK (oui pour autoriser la variante 4 de E21),
#   WB_M28_IMAGE_BB (image busybox du cache Harbor, E23).

_M28_GITLAB="${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}"
_M28_LUCAS_NOM="Lucas Martin"
_M28_LUCAS_COURRIEL="lucas.martin@medisphere.internal"
_M28_IMAGE_BB="${WB_M28_IMAGE_BB:-registry.par1.medisphere.internal/dockerhub/library/busybox:1.37}"

# ---------------------------------------------------------------------------
# État local et journal (adm01)
# ---------------------------------------------------------------------------
m28_etat() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/M28-$1"
  mkdir -p "$d" && chmod 700 "$d"
  printf '%s\n' "$d"
}
m28_poser() { (umask 077 && printf '%s\n' "$3" >"$(m28_etat "$1")/$2"); }
m28_lire() {
  local f
  f="$(m28_etat "$1")/$2"
  if [[ -f "$f" ]]; then cat "$f"; fi
}
m28_oublier() { rm -f -- "$(m28_etat "$1")/$2"; }
m28_journal() {
  local ex="$1"
  shift
  printf '%s %s [M28-%s variante %s] %s\n' "$(date -Is)" "$(hostname -s)" "$ex" "${WB_VAR:-?}" "$*" >>"$(m28_etat "$ex")/journal"
}

# m28_attendre SECONDES commande… — relance la commande toutes les 10 s jusqu'à succès ou délai.
m28_attendre() {
  local max="$1" t=0
  shift
  while ((t < max)); do
    if "$@"; then return 0; fi
    sleep 10
    t=$((t + 10))
  done
  "$@"
}

# m28_essayer EXX NB DÉPART — essaie les variantes à partir de DÉPART ; une variante qui renvoie 10 est
# « sans effet sur ce lab » : on passe à la suivante (après avoir défait ce qu'elle a commencé).
m28_essayer() {
  local ex="$1" nb="$2" depart="$3" i n rc
  for ((i = 0; i < nb; i++)); do
    n=$(((depart - 1 + i) % nb + 1))
    rc=0
    WB_VAR="$n"
    "_m28${ex}_une" "$n" || rc=$?
    if ((rc == 0)); then
      WB_VAR="$n"
      return 0
    fi
    ((rc == 10)) || return 1
    m28_journal "$ex" "variante $n sans effet sur ce lab : suivante"
  done
  wb_avert "aucune variante de M28-$ex n'a d'effet sur ce lab (configuration inattendue)"
  return 1
}

m28_outils() {
  local c
  for c in kubectl jq curl yq; do
    command -v "$c" >/dev/null 2>&1 || { echo "outil manquant sur adm01 : $c" >&2; return 1; }
  done
  yq --version 2>/dev/null | grep -q 'mikefarah' || { echo "yq de mikefarah (v4) attendu sur adm01" >&2; return 1; }
}

m28_aleatoire() { tr -dc 'a-zA-Z0-9' </dev/urandom 2>/dev/null | head -c "${1:-24}"; }

# ---------------------------------------------------------------------------
# Kubernetes et Argo CD (kubeconfig d'administration)
# ---------------------------------------------------------------------------

# m28_app_saine NOM — Application Argo CD Synced et Healthy.
m28_app_saine() {
  wb_kubectl -n argocd get applications.argoproj.io "$1" -o json 2>/dev/null |
    jq -e '.status.sync.status == "Synced" and .status.health.status == "Healthy"' >/dev/null 2>&1
}

# m28_rafraichir APP… — demande à Argo CD de relire Git tout de suite.
m28_rafraichir() {
  local a
  for a in "$@"; do
    wb_kubectl -n argocd annotate applications.argoproj.io "$a" argocd.argoproj.io/refresh=normal --overwrite >/dev/null 2>&1 || true
  done
}

# m28_app_de TYPE NOM ESPACE — Application Argo CD qui gère l'objet (annotation de suivi, M20).
m28_app_de() {
  wb_kubectl -n "$3" get "$1" "$2" -o json 2>/dev/null |
    jq -r '.metadata.annotations["argocd.argoproj.io/tracking-id"] // empty | split(":")[0]'
}

# m28_source_app APP — « projet<TAB>chemin » de la source Git de l'Application (première source).
m28_source_app() {
  wb_kubectl -n argocd get applications.argoproj.io "$1" -o json 2>/dev/null |
    jq -r '(.spec.source // .spec.sources[0]) as $s
           | ($s.repoURL | sub("^https?://[^/]+/"; "") | sub("\\.git$"; "")) + "\t" + ($s.path // "")'
}

# m28_so NS — ScaledObject medinotif de l'espace (JSON) ; vide si absent.
m28_so() { wb_kubectl -n "$1" get scaledobjects.keda.sh medinotif -o json 2>/dev/null || true; }

# ---------------------------------------------------------------------------
# GitLab (jeton d'administration de l'apprenant)
# ---------------------------------------------------------------------------
_m28_enc() { jq -rn --arg s "$1" '$s|@uri'; }

# m28_api MÉTHODE CHEMIN [options curl…] — corps sur stdout ; code ≠ 0 si HTTP ≥ 400. Le jeton ne
# passe jamais en argument (en-tête lu depuis un descripteur).
m28_api() {
  local m="$1" p="$2" f t
  shift 2
  f="${WB_GITLAB_ADMIN_TOKEN_FILE:-$HOME/.config/workbook/gitlab-admin.token}"
  [[ -r "$f" ]] || { wb_avert "jeton d'administration GitLab illisible : $f"; return 1; }
  t="$(tr -d '[:space:]' <"$f")"
  curl -sf --max-time 30 -X "$m" -H @<(printf 'PRIVATE-TOKEN: %s\n' "$t") "$_M28_GITLAB/api/v4/$p" "$@"
}

# m28_git_lire PROJET CHEMIN — contenu du fichier sur main.
m28_git_lire() {
  m28_api GET "projects/$(_m28_enc "$1")/repository/files/$(_m28_enc "$2")/raw?ref=main"
}

# m28_git_arbre PROJET [DOSSIER] — chemins des fichiers (main, récursif, 300 au plus).
m28_git_arbre() {
  local p d page r
  p="$(_m28_enc "$1")"
  d="${2:+&path=$(_m28_enc "$2")}"
  for page in 1 2 3; do
    r="$(m28_api GET "projects/$p/repository/tree?ref=main&recursive=true&per_page=100&page=$page$d" 2>/dev/null)" || return 0
    jq -r '.[] | select(.type == "blob") | .path' <<<"$r"
    (($(jq 'length' <<<"$r") < 100)) && return 0
  done
}

# m28_git_chercher PROJET 'regex' [DOSSIER] — fichiers YAML du dépôt dont le contenu correspond.
m28_git_chercher() {
  local chemin
  m28_git_arbre "$1" "${3:-}" | grep -E '\.ya?ml$' | while IFS= read -r chemin; do
    if m28_git_lire "$1" "$chemin" 2>/dev/null | grep -Eq -- "$2"; then printf '%s\n' "$chemin"; fi
  done
}

# _m28_commit PROJET BRANCHE "message" CHEMIN FICHIER [lucas] — un commit (update) ; affiche le sha.
_m28_commit() {
  local projet="$1" br="$2" msg="$3" chemin="$4" fichier="$5" qui="${6:-}" corps
  if [[ "$qui" == lucas ]]; then
    corps="$(jq -n --arg b "$br" --arg m "$msg" --arg p "$chemin" --rawfile c "$fichier" \
      --arg an "$_M28_LUCAS_NOM" --arg ae "$_M28_LUCAS_COURRIEL" \
      '{branch: $b, commit_message: $m, author_name: $an, author_email: $ae,
        actions: [{action: "update", file_path: $p, content: $c}]}')"
  else
    corps="$(jq -n --arg b "$br" --arg m "$msg" --arg p "$chemin" --rawfile c "$fichier" \
      '{branch: $b, commit_message: $m, actions: [{action: "update", file_path: $p, content: $c}]}')"
  fi
  m28_api POST "projects/$(_m28_enc "$projet")/repository/commits" \
    -H 'Content-Type: application/json' --data-binary "$corps" | jq -r '.id // empty'
}

# _m28_mr_fusionner PROJET BRANCHE "titre" — MR vers main, fusion automatique après le pipeline.
_m28_mr_fusionner() {
  local projet="$1" br="$2" titre="$3" p iid etat i
  p="$(_m28_enc "$projet")"
  iid="$(m28_api POST "projects/$p/merge_requests" --data-urlencode "source_branch=$br" \
    --data-urlencode "target_branch=main" --data-urlencode "title=$titre" \
    --data-urlencode "remove_source_branch=true" | jq -r '.iid // empty')" || iid=""
  [[ -n "$iid" ]] || return 1
  sleep 5
  m28_api PUT "projects/$p/merge_requests/$iid/merge" --data-urlencode "auto_merge=true" >/dev/null 2>&1 ||
    m28_api PUT "projects/$p/merge_requests/$iid/merge" --data-urlencode "merge_when_pipeline_succeeds=true" >/dev/null 2>&1 ||
    m28_api PUT "projects/$p/merge_requests/$iid/merge" >/dev/null 2>&1 || true
  for ((i = 0; i < 60; i++)); do
    etat="$(m28_api GET "projects/$p/merge_requests/$iid" | jq -r '.state // empty')" || etat=""
    [[ "$etat" == merged ]] && return 0
    [[ "$etat" == closed ]] && break
    sleep 15
  done
  wb_avert "la MR !$iid de $projet n'a pas pu être fusionnée (pipeline, approbations ?) : fermée"
  m28_api PUT "projects/$p/merge_requests/$iid" --data-urlencode "state_event=close" >/dev/null 2>&1 || true
  m28_api DELETE "projects/$p/repository/branches/$(_m28_enc "$br")" >/dev/null 2>&1 || true
  return 1
}

# _m28_pousser PROJET "message" CHEMIN FICHIER [lucas] — commit direct sur main si accepté, sinon MR.
_m28_pousser() {
  local projet="$1" msg="$2" chemin="$3" fichier="$4" qui="${5:-}" br sha
  sha="$(_m28_commit "$projet" main "$msg" "$chemin" "$fichier" "$qui" 2>/dev/null)" || sha=""
  [[ -n "$sha" ]] && return 0
  br="${qui:-moi}/m28-$(date +%s)"
  m28_api POST "projects/$(_m28_enc "$projet")/repository/branches" \
    --data-urlencode "branch=$br" --data-urlencode "ref=main" >/dev/null || return 1
  sha="$(_m28_commit "$projet" "$br" "$msg" "$chemin" "$fichier" "$qui")" || sha=""
  [[ -n "$sha" ]] || return 1
  _m28_mr_fusionner "$projet" "$br" "${msg%%$'\n'*}"
}

# m28_git_modifier EXX PROJET CHEMIN "message" [N] — modifie un fichier au nom de Lucas. La modification est
# faite par _m28_transformer (définie par l'appelant : lit l'original sur stdin, écrit sur stdout, renvoie
# 10 si le fichier n'a pas la forme attendue). N (1 par défaut, 2 au plus) : rang de la modification
# quand une panne touche deux fichiers ; chacune est annulée indépendamment.
m28_git_modifier() {
  local ex="$1" projet="$2" chemin="$3" msg="$4" n="${5:-1}" d orig neuf rc=0
  d="$(m28_etat "$ex")"
  orig="$d/git-orig-$n"
  neuf="$d/git-neuf-$n"
  m28_git_lire "$projet" "$chemin" >"$orig" 2>/dev/null || { wb_avert "$chemin introuvable dans $projet (main)"; rm -f "$orig"; return 10; }
  _m28_transformer <"$orig" >"$neuf" || rc=$?
  if ((rc != 0)) || cmp -s "$orig" "$neuf"; then
    rm -f "$orig" "$neuf"
    ((rc != 0)) && return "$rc"
    return 10
  fi
  chmod 600 "$orig" "$neuf"
  if ! _m28_pousser "$projet" "$msg" "$chemin" "$neuf" lucas; then
    rm -f "$orig" "$neuf"
    return 1
  fi
  m28_poser "$ex" "git-projet-$n" "$projet"
  m28_poser "$ex" "git-chemin-$n" "$chemin"
  m28_poser "$ex" "git-empreinte-$n" "$(sha256sum "$neuf" | cut -d' ' -f1)"
  m28_journal "$ex" "commit de Lucas sur $projet:$chemin"
}

# m28_git_injecte EXX [N] — le fichier modifié n° N est encore exactement dans l'état injecté.
m28_git_injecte() {
  local n="${2:-1}" projet chemin emp
  projet="$(m28_lire "$1" "git-projet-$n")"
  chemin="$(m28_lire "$1" "git-chemin-$n")"
  emp="$(m28_lire "$1" "git-empreinte-$n")"
  [[ -n "$projet" && -n "$chemin" && -n "$emp" ]] || return 1
  [[ "$(m28_git_lire "$projet" "$chemin" 2>/dev/null | sha256sum | cut -d' ' -f1)" == "$emp" ]]
}

# m28_git_annuler EXX — pour chaque fichier modifié (dernier d'abord) : commit inverse (contenu d'origine)
# s'il est encore dans l'état injecté ; sinon, rien (la réparation de l'apprenant n'est jamais défaite).
m28_git_annuler() {
  local ex="$1" d projet chemin n
  d="$(m28_etat "$ex")"
  for n in 2 1; do
    projet="$(m28_lire "$ex" "git-projet-$n")"
    chemin="$(m28_lire "$ex" "git-chemin-$n")"
    [[ -n "$projet" && -n "$chemin" ]] || continue
    if m28_git_injecte "$ex" "$n"; then
      if _m28_pousser "$projet" "Revert du commit de Lucas sur $chemin (lab/bin/break 28 ${ex#E} --annuler, M28-$ex)" "$chemin" "$d/git-orig-$n"; then
        m28_journal "$ex" "annulation : $projet:$chemin remis dans son état d'origine"
      else
        wb_avert "annulation du commit sur $projet:$chemin impossible : remets le fichier à la main (copie : $d/git-orig-$n)"
        continue
      fi
    else
      m28_journal "$ex" "annulation : $projet:$chemin déjà modifié depuis la panne, rien à défaire"
    fi
    rm -f -- "$d/git-orig-$n" "$d/git-neuf-$n"
    m28_oublier "$ex" "git-projet-$n"
    m28_oublier "$ex" "git-chemin-$n"
    m28_oublier "$ex" "git-empreinte-$n"
  done
}

# m28_kustomize_ajouter_patch 'cible JSON' 'texte du patch' — transformateur (stdin → stdout) qui ajoute
# une entrée à « patches » d'un kustomization.yaml ; renvoie 10 si le fichier n'est pas une Kustomization.
m28_kustomize_ajouter_patch() {
  local f
  f="$(mktemp)"
  cat >"$f"
  if ! yq -e '.kind == "Kustomization" or has("resources")' "$f" >/dev/null 2>&1; then
    rm -f "$f"
    return 10
  fi
  CIBLE="$1" PATCH="$2" yq '.patches = ((.patches // []) + [{"target": (strenv(CIBLE) | from_json), "patch": strenv(PATCH)}])' "$f"
  rm -f "$f"
}

