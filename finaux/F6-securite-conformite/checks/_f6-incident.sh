# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et requêtes LogQL/PromQL entre apostrophes
# _f6-incident.sh — fonctions partagées par les vérifications des phases 3 à 5 du final F6
# (check-S08 à check-S14). Sourcé, jamais lancé seul. Préfixe _f6i_.
#
# Lecture seule :
#   - GitLab en GET (jeton des checks) : documents de docs/conformite/ et docs/securite/incidents/ de
#     plateforme/medisphere, code des dépôts plateforme/* ;
#   - Kubernetes par « kube » (compte wb-checks : jamais les Secrets) ;
#   - Loki (locataire « audit »), Prometheus/Thanos, Alertmanager, Mailpit, OpenBao (métadonnées) par
#     les fonctions de lab/lib/check-lib.sh ;
#   - compartiment de preuves du RGW listé avec l'identité de LECTURE des checks (jamais d'écriture) ;
#   - pve01 en root (pvesh/qm en lecture) et l'état local de l'injection de S11 (lecture seule).
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui peut
# échouer hors des fonctions check_* est protégée.
#
# Variables de lab/lab.env (défauts ci-dessous) ; préfixe WB_F6_ :
#   WB_F6_PROJET_DOC   projet GitLab de la doc MédiSphère      (défaut : plateforme/medisphere)
#   WB_F6_DOC          dossier de la conformité                (défaut : docs/conformite)
#   WB_F6_INCIDENTS    dossier des incidents de sécurité       (défaut : docs/securite/incidents)
#   WB_F6_INCIDENT     identifiant de l'incident simulé        (défaut : INC-6211)
#   WB_F6_RECETTE_NS   espace de l'incident                    (défaut : mediagenda-recette)
#   WB_F6_RGW_URL      point d'accès S3 du RGW de ceph-par1    (défaut : https://rgw.par1.medisphere.internal)
#   WB_F6_PREUVES_BUCKET  compartiment de preuves verrouillé   (défaut : preuves-conformite)
#   WB_F6_PREUVES_ENV  identité S3 de LECTURE des preuves      (défaut : ~/.config/workbook/s3-preuves-conformite-lecture.env)
#   WB_F6_C2_VMID      VMID du « C2 » simulé                   (défaut : 3601)
#   WB_F6_C2_IP        adresse du « C2 » simulé                (défaut : 10.10.99.66)
# + WB_PVE_HOST, WB_GITLAB_*, WB_K8S_KUBECONFIG, WB_LOKI_URL, WB_PROM_URL, WB_AM_URL, WB_MAILPIT_*,
#   WB_OPENBAO_*, WB_TIMEOUT (lab/lib/check-lib.sh).

_f6i_doc_projet="${WB_F6_PROJET_DOC:-plateforme/medisphere}"
_f6i_doc_dir="${WB_F6_DOC:-docs/conformite}"
_f6i_inc_dir="${WB_F6_INCIDENTS:-docs/securite/incidents}"
_f6i_inc="${WB_F6_INCIDENT:-INC-6211}"
_f6i_recette_ns="${WB_F6_RECETTE_NS:-mediagenda-recette}"
_f6i_rgw="${WB_F6_RGW_URL:-https://rgw.par1.medisphere.internal}"
_f6i_bucket="${WB_F6_PREUVES_BUCKET:-preuves-conformite}"
_f6i_preuves_env="${WB_F6_PREUVES_ENV:-$HOME/.config/workbook/s3-preuves-conformite-lecture.env}"
_f6i_c2_vmid="${WB_F6_C2_VMID:-3601}"
_f6i_c2_ip="${WB_F6_C2_IP:-10.10.99.66}"

# --- GitLab (lecture) ------------------------------------------------------------------------------

_f6i_enc() { jq -rn --arg s "$1" '$s|@uri'; }

# _f6i_fichier PROJET CHEMIN [RÉF=main] — contenu brut du fichier.
_f6i_fichier() {
  gitlab_api "projects/$(_f6i_enc "$1")/repository/files/$(_f6i_enc "$2")/raw?ref=$(_f6i_enc "${3:-main}")"
}

# _f6i_arbre PROJET [DOSSIER] — chemins des fichiers (récursif) sur main.
_f6i_arbre() {
  local p page=1 r
  p="$(_f6i_enc "$1")"
  while ((page <= 10)); do
    r="$(gitlab_api "projects/$p/repository/tree?ref=main&recursive=true&per_page=100&page=$page${2:+&path=$(_f6i_enc "$2")}" 2>/dev/null)" || return 0
    jq -r '.[]? | select(.type == "blob") | .path' <<<"$r"
    (($(jq 'length' <<<"$r" 2>/dev/null || echo 0) < 100)) && return 0
    page=$((page + 1))
  done
}

# _f6i_doc DOSSIER MOTIF_NOM REGEX… — un fichier de plateforme/medisphere sous DOSSIER (main) dont le
# nom correspond à MOTIF_NOM contient chaque motif (insensible à la casse). Chemin trouvé dans _F6I_DOC_TROUVE.
_F6I_DOC_TROUVE=""
_f6i_doc() {
  local d="$1" motif="$2" f c m ok
  shift 2
  while IFS= read -r f; do
    [[ -n "$f" && "${f##*/}" =~ $motif ]] || continue
    c="$(_f6i_fichier "$_f6i_doc_projet" "$f" 2>/dev/null)" || continue
    ok=1
    for m in "$@"; do grep -Eqi -- "$m" <<<"$c" || { ok=0; break; }; done
    if ((ok)); then _F6I_DOC_TROUVE="$f"; return 0; fi
  done < <(_f6i_arbre "$_f6i_doc_projet" "$d")
  return 1
}

# _f6i_fichier_existe PROJET CHEMIN — le fichier existe sur main.
_f6i_fichier_existe() {
  _f6i_fichier "$1" "$2" >/dev/null 2>&1
}

# _f6i_etiquette TAG [PROJET] — l'étiquette (tag git) existe sur le projet (défaut : la doc).
_f6i_etiquette() {
  local p="${2:-$_f6i_doc_projet}"
  gitlab_api "projects/$(_f6i_enc "$p")/repository/tags/$(_f6i_enc "$1")" >/dev/null 2>&1
}

# --- Incident (docs/securite/incidents/<INC>/) ------------------------------------------------------

# _f6i_inc_doc MOTIF_NOM REGEX… — un fichier du dossier de l'incident contient chaque motif.
_f6i_inc_doc() {
  local motif="$1"
  shift
  _f6i_doc "$_f6i_inc_dir/$_f6i_inc" "$motif" "$@"
}

# --- Kubernetes ------------------------------------------------------------------------------------

# _f6i_json 'JSON' 'FILTRE jq' — le filtre renvoie vrai sur l'objet.
_f6i_json() { jq -e "$2" >/dev/null 2>&1 <<<"$1"; }

# --- Compartiment de preuves (RGW, lecture seule) --------------------------------------------------

# _f6i_preuves_ls PRÉFIXE — liste récursive de s3://<bucket>/<préfixe> avec l'identité de LECTURE des
#   checks (jamais d'écriture ni de suppression) ; vide si l'identité est absente.
_f6i_preuves_ls() {
  [[ -r "$_f6i_preuves_env" ]] || return 0
  (
    set -a
    # shellcheck disable=SC1090
    source "$_f6i_preuves_env"
    set +a
    aws --endpoint-url "$_f6i_rgw" s3 ls --recursive "s3://$_f6i_bucket/$1" 2>/dev/null
  ) || true
}

# _f6i_bucket_s3api ARGS… — appel s3api en lecture (get-object-lock-configuration, etc.), JSON brut.
_f6i_bucket_s3api() {
  [[ -r "$_f6i_preuves_env" ]] || return 1
  (
    set -a
    # shellcheck disable=SC1090
    source "$_f6i_preuves_env"
    set +a
    aws --endpoint-url "$_f6i_rgw" s3api "$@" 2>/dev/null
  )
}

# --- pve01 (lecture) -------------------------------------------------------------------------------

# _f6i_pve 'commande' — exécute une commande en lecture sur pve01 (root).
_f6i_pve() { remote "$WB_PVE_HOST" "$1"; }

# _f6i_c2_absent — le « C2 » simulé (VMID WB_F6_C2_VMID) n'existe plus sur pve01 (VM détruite par l'annulation).
_f6i_c2_absent() {
  ! _f6i_pve "qm status $_f6i_c2_vmid" >/dev/null 2>&1
}

# --- État local de l'injection de S11 (lecture seule) ----------------------------------------------
# L'injection écrit dans ~/.local/state/workbook/F6-S11/ (700) ; les checks le LISENT, jamais le modifient.

_f6i_etat_dir="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/F6-S11"
_f6i_etat() {
  [[ -r "$_f6i_etat_dir/$1" ]] || return 1
  cat "$_f6i_etat_dir/$1"
}
