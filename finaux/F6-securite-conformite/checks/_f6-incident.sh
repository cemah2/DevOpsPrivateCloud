# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et requêtes LogQL/PromQL entre apostrophes
# _f6-incident.sh — fonctions des vérifications des phases 3 à 5 du final F6 (check-S08 à check-S14).
# Sourcé, jamais lancé seul. Préfixe _f6i_. Il source d'abord _f6-conformite.sh (socle commun : variables
# WB_F6_* partagées, GitLab, documents de docs/conformite/, fiches d'écart, compartiment de preuves,
# Kubernetes, passerelles) et n'y ajoute que ce qui est propre à la remédiation et à l'incident.
#
# Lecture seule :
#   - GitLab en GET (jeton des checks) : docs/securite/incidents/ de plateforme/medisphere, code des
#     dépôts plateforme/* ;
#   - Kubernetes par « kube » (compte wb-checks : jamais les Secrets) ;
#   - Loki (locataire « audit »), Alertmanager, Mailpit, Grafana par les fonctions de lab/lib/check-lib.sh ;
#   - compartiments RGW listés avec des identités de LECTURE (jamais d'écriture ni de suppression) ;
#   - pve01 (qm status en lecture) et l'état local de l'injection de S11 (lecture seule).
#
# Variables propres aux phases 3 à 5 (défauts ci-dessous ; les autres : _f6-conformite.sh) :
#   WB_F6_INCIDENTS       dossier des incidents de sécurité      (défaut : docs/securite/incidents)
#   WB_F6_INCIDENT        identifiant de l'incident simulé       (défaut : INC-6211)
#   WB_F6_RECETTE_NS      espace de l'incident                   (défaut : mediagenda-recette)
#   WB_F6_C2_VMID         VMID du « C2 » simulé                  (défaut : 3601)
#   WB_F6_C2_IP           adresse du « C2 » simulé               (défaut : 10.10.99.66)
#   WB_F6_ARCHIVE_BUCKET  compartiment d'archive de l'audit      (défaut : archive-audit)
#   WB_F6_ARCHIVE_ENV     identité S3 de LECTURE de l'archive    (défaut : ~/.config/workbook/s3-archive-audit-lecture.env)
# + WB_PVE_HOST, WB_LOKI_URL, WB_AM_URL, WB_MAILPIT_*, WB_GRAFANA_* (lab/lib/check-lib.sh).

# shellcheck source=_f6-conformite.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f6-conformite.sh"

_f6i_inc_dir="${WB_F6_INCIDENTS:-docs/securite/incidents}"
_f6i_inc="${WB_F6_INCIDENT:-INC-6211}"
_f6i_recette_ns="${WB_F6_RECETTE_NS:-mediagenda-recette}"
_f6i_c2_vmid="${WB_F6_C2_VMID:-3601}"
_f6i_c2_ip="${WB_F6_C2_IP:-10.10.99.66}"
_f6i_archive_bucket="${WB_F6_ARCHIVE_BUCKET:-archive-audit}"
_f6i_archive_env="${WB_F6_ARCHIVE_ENV:-$HOME/.config/workbook/s3-archive-audit-lecture.env}"

# --- GitLab (lecture) : chemins depuis la racine d'un dépôt ------------------------------------------

# _f6i_existe PROJET CHEMIN — le fichier existe sur main.
_f6i_existe() { _f6c_fichier "$1" "$2" >/dev/null 2>&1; }

# _f6i_doc DOSSIER MOTIF_NOM REGEX… — un fichier de plateforme/medisphere sous DOSSIER (chemin depuis la
# racine du dépôt, ex. docs/securite/incidents/runbooks) dont le nom correspond à MOTIF_NOM contient
# chaque motif (casse ignorée). Pour docs/conformite/, utiliser _f6c_doc (chemin relatif).
_f6i_doc() {
  local d="$1" motif="$2" f
  shift 2
  while IFS= read -r f; do
    [[ -n "$f" && "${f##*/}" =~ $motif ]] || continue
    _f6c_contient "$(_f6c_fichier "$_f6c_doc_projet" "$f" 2>/dev/null || true)" "$@" && return 0
  done < <(_f6c_arbre "$_f6c_doc_projet" "$d")
  return 1
}

# _f6i_inc_doc MOTIF_NOM REGEX… — un fichier du dossier de l'incident contient chaque motif.
_f6i_inc_doc() {
  local motif="$1"
  shift
  _f6i_doc "$_f6i_inc_dir/$_f6i_inc" "$motif" "$@"
}

# _f6i_etiquette TAG [PROJET] — l'étiquette (tag git) existe sur le projet (défaut : la doc).
_f6i_etiquette() {
  gitlab_api "projects/$(_f6c_enc "${2:-$_f6c_doc_projet}")/repository/tags/$(_f6c_enc "$1")" >/dev/null 2>&1
}

# --- Kubernetes ------------------------------------------------------------------------------------

# _f6i_json 'JSON' 'FILTRE jq' — le filtre renvoie vrai sur l'objet.
_f6i_json() { jq -e "$2" >/dev/null 2>&1 <<<"$1"; }

# --- Archive d'audit (S08, identité de LECTURE dédiée) -----------------------------------------------

_f6i_archive_identite() { [[ -r "$_f6i_archive_env" ]]; }

# _f6i_archive_s3 ARGS… — commande aws avec l'identité de lecture de l'archive.
_f6i_archive_s3() { _f6c_s3_id "$_f6i_archive_env" "$@"; }

# --- pve01 (lecture) -------------------------------------------------------------------------------

# _f6i_c2_absent — le « C2 » simulé (VMID WB_F6_C2_VMID) n'existe plus sur pve01 (détruit par l'annulation).
_f6i_c2_absent() { ! remote "$WB_PVE_HOST" "qm status $_f6i_c2_vmid" >/dev/null 2>&1; }

# --- État local de l'injection de S11 (lecture seule) ----------------------------------------------
# L'injection écrit dans ~/.local/state/workbook/F6-S11/ (700) ; les checks le LISENT, jamais ne le modifient.

_f6i_etat_dir="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/F6-S11"
_f6i_etat() {
  [[ -r "$_f6i_etat_dir/$1" ]] || return 1
  cat "$_f6i_etat_dir/$1"
}
