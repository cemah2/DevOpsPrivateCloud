# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et yq entre apostrophes
# _f3-fin.sh — fonctions partagées par les vérifications de jeudi, vendredi et du bilan du final F3
# (check-S10 à check-S16). Préfixe _f3f_. Sourcé, jamais lancé seul. Charge _f3-sante.sh (préfixe
# _f3s_ : contrôle de santé, main courante, documents de plateforme/medisphere).
#
# Lecture seule : « kube » (compte wb-checks : jamais un Secret), API GitLab en GET (jeton des checks),
# OpenBao par bao_api (métadonnées, jamais une valeur) et sys/health sans jeton, RabbitMQ par
# rabbitmq_api (étiquette monitoring), Alertmanager en GET, dig, SSH « admin » sur les passerelles et
# les nœuds du coffre (commandes de lecture : ip, nft list avec sudo -n), S3 en LISTE seulement
# (compartiment preuves, identité de dépôt du M26 en liste seulement), état local des pannes (~/.local/state/workbook/F3-SXX/)
# en lecture.
# Rappel : les checks tournent sous « set -euo pipefail » ; tout ce qui peut échouer est protégé.
#
# Variables de lab/lab.env (facultatives, défauts ci-dessous) :
#   WB_F3_RECETTE_URL            MédiAgenda de recette (https://mediagenda-recette.apps.par1.medisphere.internal)
#   WB_F3_PASSERELLES            passerelles de bordure (« gw01 gw02 »)
#   WB_F3_S11_CIBLES             « IP:port » joints depuis adm01 en S11 (Gateway, Prometheus, Alertmanager, Loki)
#   WB_F3_S12_PREUVES_ENV        identité S3 qui LISTE le compartiment preuves (~/.config/workbook/s3-preuves-depot.env,
#                                celle de RB-262 / M26-E33 : écrire et lister, jamais supprimer ; le check ne fait que lister)
#   WB_F3_S3_URL                 point d'accès S3 de s3-01 (https://s3-01.par1.medisphere.internal:8333)
#   WB_F3_S13_SEUIL              messages en attente tolérés dans notifications (prod) après réparation (2000)
#   WB_F3_PROJET_NOTIF           dépôt de déploiement de MédiNotif (medinotif/deploiement)
#   WB_F3_PROJET_OBSERVABILITE   dépôt de la supervision (plateforme/observabilite)

# shellcheck source=_f3-sante.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f3-sante.sh"

_f3f_recette="${WB_F3_RECETTE_URL:-https://mediagenda-recette.apps.par1.medisphere.internal}"
read -r -a _f3f_passerelles <<<"${WB_F3_PASSERELLES:-gw01 gw02}"
_f3f_s3="${WB_F3_S3_URL:-https://s3-01.par1.medisphere.internal:8333}"
_f3f_notif="${WB_F3_PROJET_NOTIF:-medinotif/deploiement}"
_f3f_obs="${WB_F3_PROJET_OBSERVABILITE:-plateforme/observabilite}"

# ---------------------------------------------------------------------------------------------
# Outils
# ---------------------------------------------------------------------------------------------

# _f3f_k ARGS… — kubectl en lecture (compte des checks) ; sortie vide en cas d'erreur.
_f3f_k() { kube "$@" 2>/dev/null || true; }

# _f3f_json JSON FILTRE [args jq…] — OK si le filtre (jq -e) est vrai.
_f3f_json() {
  local d="$1" f="$2"
  shift 2
  [[ -n "$d" ]] && jq -e "$@" "$f" <<<"$d" >/dev/null 2>&1
}

# _f3f_condition JSON TYPE [STATUT=True]
_f3f_condition() {
  _f3f_json "$1" '[.status.conditions[]? | select(.type == $t and .status == $s)] | length > 0' --arg t "$2" --arg s "${3:-True}"
}

# _f3f_secondes DURÉE — durée Go (« 30m », « 1h », « 1h30m0s ») ou secondes → secondes.
_f3f_secondes() {
  local d="$1" n=0
  [[ "$d" =~ ^[0-9]+$ ]] && { echo "$d"; return; }
  [[ "$d" =~ ([0-9]+)h ]] && n=$((n + BASH_REMATCH[1] * 3600))
  [[ "$d" =~ ([0-9]+)m([0-9]|s|$) ]] && n=$((n + BASH_REMATCH[1] * 60))
  [[ "$d" =~ ([0-9]+)s$ ]] && n=$((n + BASH_REMATCH[1]))
  echo "$n"
}

# _f3f_code URL — code HTTP (000 si pas de réponse).
_f3f_code() {
  local c
  c="$(curl -s -o /dev/null -w '%{http_code}' --max-time "$WB_TIMEOUT" "$1" 2>/dev/null || true)"
  echo "${c:-000}"
}

# _f3f_etat SXX CLÉ — valeur notée par l'injection (état local de la panne, lecture seule) ; vide sinon.
_f3f_etat() {
  local f="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/F3-$1/$2"
  if [[ -r "$f" ]]; then cat "$f"; fi
}

# _f3f_journal_cite INC 'regex' — une entrée de main courante de INC correspond à la regex (casse ignorée).
_f3f_journal_cite() { _f3s_journal_lignes "$1" | grep -Eiq -- "$2"; }

# _f3f_rb_present RB-NNN — un runbook docs/exploitation/runbooks/RB-NNN-*.md existe sur main.
_f3f_rb_present() { _f3s_arbre "$_f3s_doc/runbooks" | grep -Eq "/$1([-_.].*)?\.md$"; }

# ---------------------------------------------------------------------------------------------
# GitLab (projets autres que plateforme/medisphere)
# ---------------------------------------------------------------------------------------------

_f3f_gl_fichier() {
  gitlab_api "projects/$(_f3s_enc "$1")/repository/files/$(_f3s_enc "$2")/raw?ref=$(_f3s_enc "${3:-main}")" 2>/dev/null || true
}

# _f3f_mr_fusionnee PROJET 'texte' — JSON de la dernière MR fusionnée dont le titre ou la description
#   contient le texte (vide sinon).
_f3f_mr_fusionnee() {
  gitlab_api "projects/$(_f3s_enc "$1")/merge_requests?state=merged&search=$(_f3s_enc "$2")&in=title,description&per_page=20&order_by=updated_at" 2>/dev/null |
    jq -c '.[0] // empty' 2>/dev/null || true
}

# _f3f_mr_diffs PROJET IID — diffs de la MR (tableau JSON de {old_path, new_path, diff}).
_f3f_mr_diffs() {
  gitlab_api "projects/$(_f3s_enc "$1")/merge_requests/$2/diffs?per_page=100" 2>/dev/null || echo '[]'
}

# _f3f_pipeline_job_ok PROJET PIPELINE_ID 'regex du job' — un job du pipeline correspond et a réussi.
_f3f_pipeline_job_ok() {
  gitlab_api "projects/$(_f3s_enc "$1")/pipelines/$2/jobs?per_page=100" 2>/dev/null |
    jq -e --arg re "$3" 'any(.[]; (.name | test($re)) and .status == "success")' >/dev/null 2>&1
}

# _f3f_dernier_pipeline PROJET [RÉF=main] — JSON du dernier pipeline de la branche.
_f3f_dernier_pipeline() {
  gitlab_api "projects/$(_f3s_enc "$1")/pipelines?ref=$(_f3s_enc "${2:-main}")&per_page=1" 2>/dev/null | jq -c '.[0] // empty' 2>/dev/null || true
}

# _f3f_fichiers_doc 'regex de chemin' [RÉF=main] — fichiers de plateforme/medisphere qui correspondent.
_f3f_fichiers_doc() { _f3s_arbre "$_f3s_doc" "${2:-main}" | grep -E -- "$1" || true; }

# ---------------------------------------------------------------------------------------------
# Accès en lecture aux hôtes
# ---------------------------------------------------------------------------------------------

# _f3f_ssh HÔTE 'commande' — commande de LECTURE par SSH (compte admin), sortie vide si échec.
_f3f_ssh() { remote "$1" "$2" 2>/dev/null </dev/null || true; }

# _f3f_bao_noeud HÔTE — code HTTP de /v1/sys/health du nœud (200 actif, 429 en attente).
_f3f_bao_noeud() {
  local c
  c="$(curl -s -o /dev/null -w '%{http_code}' --max-time "$WB_TIMEOUT" \
    "https://$1.par1.medisphere.internal:8200/v1/sys/health" 2>/dev/null || true)"
  echo "${c:-000}"
}
