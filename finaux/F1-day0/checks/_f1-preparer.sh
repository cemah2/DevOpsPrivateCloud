# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
# _f1-preparer.sh — fonctions partagées par les vérifications des phases 1 et 2 du final F1
# (check-S01 à check-S06). Sourcé, jamais lancé seul. Préfixe _f1p_ (aucune collision quand un
# check en charge un autre, ou quand la recette S14 les rejoue).
#
# Lecture seule : GitLab en GET (jeton read_api des checks), NetBox en GET (wb-checks), « kube »
# (compte wb-checks, jamais les Secrets), Prometheus en GET, LDAP de l'annuaire en lecture,
# SSH + « sudo -n » de commandes de CONSULTATION sur les VMs (stat, grep, dig, ip, klist -k),
# SSH root sur pve01 (qm/pvesh en lecture) et sur pbs01 (listage des instantanés du datastore).
#
# Variables de lab/lab.env (toutes facultatives, défauts adaptés au lab de référence) :
#   WB_F1_PROJET_DOC (plateforme/medisphere)   WB_F1_DOC (docs/day0)
#   WB_F1_JOURS (7)            fraîcheur exigée des pipelines de contrôle de dérive (S02)
#   WB_F1_HEURES (24)          âge maximal des sauvegardes du filet (S04)
#   WB_F1_DEBUT                date de référence (époque Unix) qui remplace le premier commit de
#                              docs/day0/reference-avant.md (S05) ; à ne poser qu'en cas de reprise

_f1p_projet_doc="${WB_F1_PROJET_DOC:-plateforme/medisphere}"
_f1p_doc="${WB_F1_DOC:-docs/day0}"
_f1p_jours="${WB_F1_JOURS:-7}"
_f1p_heures="${WB_F1_HEURES:-24}"

# --- GitLab (lecture) --------------------------------------------------------------------------

_f1p_enc() { jq -rn --arg s "$1" '$s|@uri'; }

# _f1p_fichier PROJET CHEMIN [RÉF=main] — contenu du fichier.
_f1p_fichier() {
  gitlab_api "projects/$(_f1p_enc "$1")/repository/files/$(_f1p_enc "$2")/raw?ref=$(_f1p_enc "${3:-main}")"
}

# _f1p_arbre PROJET [DOSSIER] [RÉF=main] — chemins des fichiers (récursif).
_f1p_arbre() {
  local p page=1 r ref
  p="$(_f1p_enc "$1")"
  ref="$(_f1p_enc "${3:-main}")"
  while ((page <= 10)); do
    r="$(gitlab_api "projects/$p/repository/tree?ref=$ref&recursive=true&per_page=100&page=$page${2:+&path=$(_f1p_enc "$2")}" 2>/dev/null)" || return 0
    jq -r '.[]? | select(.type == "blob") | .path' <<<"$r" 2>/dev/null
    (($(jq 'length' <<<"$r" 2>/dev/null || echo 0) < 100)) && return 0
    page=$((page + 1))
  done
}

# _f1p_contient TEXTE REGEX… — le texte contient chaque motif (ERE, insensible à la casse).
_f1p_contient() {
  local t="$1" m
  shift
  [[ -n "$t" ]] || return 1
  for m in "$@"; do grep -Eqi -- "$m" <<<"$t" || return 1; done
}

# _f1p_doc_chemin MOTIF_NOM [DOSSIER] — premier fichier de la documentation (main) dont le nom
# correspond à l'expression régulière étendue ; vide si aucun.
_f1p_doc_chemin() {
  local motif="$1" d="${2:-$_f1p_doc}" f
  while IFS= read -r f; do
    [[ -n "$f" && "${f##*/}" =~ $motif ]] && { printf '%s\n' "$f"; return 0; }
  done < <(_f1p_arbre "$_f1p_projet_doc" "$d")
  return 1
}

# _f1p_doc MOTIF_NOM REGEX… — un document de docs/day0 (récursif, main) dont le nom correspond
# contient chaque motif.
_f1p_doc() {
  local motif="$1" f
  shift
  while IFS= read -r f; do
    [[ -n "$f" && "${f##*/}" =~ $motif ]] || continue
    _f1p_contient "$(_f1p_fichier "$_f1p_projet_doc" "$f" 2>/dev/null)" "$@" && return 0
  done < <(_f1p_arbre "$_f1p_projet_doc" "$_f1p_doc")
  return 1
}

# _f1p_premier_commit PROJET CHEMIN — date (époque Unix) du PREMIER commit de main qui touche le
# chemin ; vide si aucun.
_f1p_premier_commit() {
  local p page=1 r d=""
  p="$(_f1p_enc "$1")"
  while ((page <= 10)); do
    r="$(gitlab_api "projects/$p/repository/commits?ref_name=main&path=$(_f1p_enc "$2")&per_page=100&page=$page" 2>/dev/null)" || break
    [[ "$(jq 'length' <<<"$r" 2>/dev/null || echo 0)" -gt 0 ]] || break
    d="$(jq -r '.[-1].committed_date // empty' <<<"$r")"
    (($(jq 'length' <<<"$r") < 100)) && break
    page=$((page + 1))
  done
  [[ -n "$d" ]] || return 1
  date -d "$d" +%s
}

# _f1p_pipelines PROJET [SOURCE] [NB=20] — derniers pipelines de main (ou de la source donnée).
_f1p_pipelines() {
  local q="ref=main&per_page=${3:-20}"
  [[ -n "${2:-}" ]] && q="source=$2&per_page=${3:-20}"
  gitlab_api "projects/$(_f1p_enc "$1")/pipelines?$q" 2>/dev/null
}

# _f1p_jobs PROJET PIPELINE — travaux d'un pipeline (tableau JSON).
_f1p_jobs() {
  gitlab_api "projects/$(_f1p_enc "$1")/pipelines/$2/jobs?per_page=100&include_retried=false" 2>/dev/null
}

# _f1p_journal_job PROJET JOB — journal d'un travail (texte).
_f1p_journal_job() {
  gitlab_api "projects/$(_f1p_enc "$1")/jobs/$2/trace" 2>/dev/null
}

# _f1p_recent DATE_ISO [JOURS=_f1p_jours] — la date est plus récente que N jours.
_f1p_recent() {
  local e
  e="$(date -d "$1" +%s 2>/dev/null)" || return 1
  (($(date +%s) - e <= ${2:-$_f1p_jours} * 86400))
}

# _f1p_dernier_job PROJET REGEX_NOM [SOURCE] — JSON du travail le plus récent (parmi les 20 derniers
# pipelines de main ou de la source) dont le nom correspond ; vide si aucun.
_f1p_dernier_job() {
  local pid j
  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    j="$(_f1p_jobs "$1" "$pid" | jq -c --arg r "$2" '[.[]? | select(.name | test($r))]')" || continue
    if [[ "$(jq 'length' <<<"$j")" -gt 0 ]]; then
      printf '%s\n' "$j"
      return 0
    fi
  done < <(_f1p_pipelines "$1" "${3:-}" | jq -r '.[]?.id' 2>/dev/null)
  return 1
}

# _f1p_plan_vide PROJET REGEX_NOM — les travaux de plan correspondants du pipeline le plus récent
# qui en contient sont réussis, récents (_f1p_jours), et leur journal dit « No changes ».
_f1p_plan_vide() {
  local jobs id n
  jobs="$(_f1p_dernier_job "$1" "$2")" || return 1
  n="$(jq 'length' <<<"$jobs")"
  ((n > 0)) || return 1
  jq -e 'all(.[]; .status == "success")' <<<"$jobs" >/dev/null || return 1
  _f1p_recent "$(jq -r '[.[].finished_at // empty] | min // empty' <<<"$jobs")" || return 1
  while IFS= read -r id; do
    _f1p_journal_job "$1" "$id" | grep -q 'No changes' || return 1
  done < <(jq -r '.[].id' <<<"$jobs")
}

# _f1p_derive_ok PROJET REGEX_NOM — travaux de détection de dérive (pipeline planifié) : le plus
# récent pipeline planifié qui en contient les a tous réussis (un « échec autorisé » compte comme
# un écart), récemment.
_f1p_derive_ok() {
  local jobs
  jobs="$(_f1p_dernier_job "$1" "$2" schedule)" || return 1
  jq -e 'length > 0 and all(.[]; .status == "success")' <<<"$jobs" >/dev/null || return 1
  _f1p_recent "$(jq -r '[.[].finished_at // empty] | min // empty' <<<"$jobs")"
}

# --- Kubernetes (lecture, wb-checks) ---------------------------------------------------------------

_f1p_api_repond() { kube get --raw /livez >/dev/null 2>&1; }

# _f1p_kq 'filtre jq' ARGS… — 0 si « kube get ARGS -o json » satisfait le filtre.
_f1p_kq() {
  local f="$1"
  shift
  kube get "$@" -o json 2>/dev/null | jq -e "$f" >/dev/null 2>&1
}

# --- Hôtes (lecture) ------------------------------------------------------------------------------

# _f1p_hote HÔTE 'commande' — commande de CONSULTATION en root (sudo -n) sur une VM ; code retour.
_f1p_hote() { remote "$1" "sudo -n bash -c $(printf '%q' "$2")" </dev/null >/dev/null 2>&1; }

# _f1p_hote_sortie HÔTE 'commande' — sortie de la commande de consultation (root, sudo -n).
_f1p_hote_sortie() { remote "$1" "sudo -n bash -c $(printf '%q' "$2")" </dev/null 2>/dev/null; }

# _f1p_pve 'commande' — commande de lecture sur pve01 (root) ; sortie.
_f1p_pve() { remote "$WB_PVE_HOST" "$1" </dev/null 2>/dev/null; }

# _f1p_vm_existe VMID — la VM existe sur pve01.
_f1p_vm_existe() { remote "$WB_PVE_HOST" "qm status $1" </dev/null >/dev/null 2>&1; }

# _f1p_age_heures EPOCH — âge en heures (entier), 999999 si la date est vide.
_f1p_age_heures() {
  [[ "${1:-}" =~ ^[0-9]+$ ]] || { echo 999999; return; }
  echo $((($(date +%s) - $1) / 3600))
}

# _f1p_frais EPOCH [HEURES=_f1p_heures] — la date est plus récente que N heures.
_f1p_frais() { (($(_f1p_age_heures "${1:-}") < ${2:-$_f1p_heures})); }

# --- Prometheus -----------------------------------------------------------------------------------

# _f1p_prom_val 'PromQL' — première valeur du résultat, vide si aucune série.
_f1p_prom_val() {
  prom_requete "$1" 2>/dev/null | jq -r '.data.result[0].value[1] // empty' 2>/dev/null
}
