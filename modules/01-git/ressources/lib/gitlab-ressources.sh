# shellcheck shell=bash
# gitlab-ressources.sh — fonctions communes des scripts de ressources du module 01.
#
# Sourcée par les scripts de modules/01-git/ressources/M01-EXX/, jamais exécutée seule.
# Lancement depuis adm01, avec :
#   - lab/lab.env (WB_GITLAB_URL, WB_GITLAB_ADMIN_TOKEN_FILE, WB_SRC, WB_MOI) ;
#   - le jeton d'ADMINISTRATION GitLab (portée api, + admin_mode si le mode admin est actif)
#     dans ~/.config/workbook/gitlab-admin.token (M01-E05) ;
#   - la clé SSH de l'apprenant déclarée dans GitLab (M01-E06), chargée dans l'agent.
#
# Les jetons d'emprunt d'identité (impersonation tokens) créés ici durent un jour au plus
# et sont révoqués à la sortie du script (gl_rendre_jetons, posé en trap EXIT).
# Aucun jeton n'apparaît dans la liste des processus : l'en-tête est passé par un descripteur.

WB_ROOT="${WB_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)}"
# shellcheck disable=SC1091  # configuration locale de l'apprenant, facultative
if [[ -f "$WB_ROOT/lab/lab.env" ]]; then source "$WB_ROOT/lab/lab.env"; fi

WB_GITLAB_URL="${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}"
WB_GITLAB_ADMIN_TOKEN_FILE="${WB_GITLAB_ADMIN_TOKEN_FILE:-$HOME/.config/workbook/gitlab-admin.token}"
WB_SRC="${WB_SRC:-$HOME/src}"
WB_RESS_ETAT="${WB_RESS_ETAT:-$HOME/.local/state/workbook/ressources}"

_GL_JETONS_EMPRUNT=()

gl_msg()    { printf '%s\n' "$*"; }
gl_erreur() { printf 'erreur : %s\n' "$*" >&2; exit 1; }

# gl_hote — nom d'hôte de GitLab (pour les URL SSH)
gl_hote() {
  local h="${WB_GITLAB_URL#*://}"
  printf '%s\n' "${h%%/*}"
}

# gl_url_ssh "groupe/projet" — URL de clonage SSH
gl_url_ssh() { printf 'git@%s:%s.git\n' "$(gl_hote)" "$1"; }

# gl_enc "texte" — encodage pour une URL (chemins de projet, de fichier, noms de branche)
gl_enc() { jq -rn --arg s "$1" '$s|@uri'; }

# _gl_appel JETON METHODE CHEMIN [options curl...] — appel de l'API v4, corps de réponse sur stdout
_gl_appel() {
  local jeton="$1" methode="$2" chemin="$3"; shift 3
  local corps code
  corps="$(mktemp)"
  if ! code="$(curl -sS -o "$corps" -w '%{http_code}' --max-time 60 -X "$methode" \
        -H @<(printf 'PRIVATE-TOKEN: %s\n' "$jeton") "$@" \
        "$WB_GITLAB_URL/api/v4/$chemin")"; then
    rm -f "$corps"
    printf 'erreur : GitLab injoignable (%s)\n' "$WB_GITLAB_URL" >&2
    return 1
  fi
  if [[ "$code" != 2* ]]; then
    printf 'erreur : %s %s → HTTP %s : %s\n' "$methode" "${chemin%%\?*}" "$code" "$(head -c 300 "$corps")" >&2
    if [[ "$code" == 403 && "$jeton" == "$(_gl_jeton_admin 2>/dev/null)" ]]; then
      printf '         (si le mode administrateur est activé, le jeton doit aussi porter la portée admin_mode)\n' >&2
    fi
    rm -f "$corps"
    return 1
  fi
  cat "$corps"
  rm -f "$corps"
}

_gl_jeton_admin() {
  [[ -r "$WB_GITLAB_ADMIN_TOKEN_FILE" ]] || {
    printf 'erreur : jeton d'"'"'administration GitLab illisible : %s (voir M01-E05)\n' "$WB_GITLAB_ADMIN_TOKEN_FILE" >&2
    return 1
  }
  tr -d '[:space:]' < "$WB_GITLAB_ADMIN_TOKEN_FILE"
}

# gl_api METHODE CHEMIN [options curl...] — appel avec le jeton d'administration
gl_api() {
  local jeton
  jeton="$(_gl_jeton_admin)" || return 1
  _gl_appel "$jeton" "$@"
}

# gl_api_json METHODE CHEMIN 'json' — appel avec un corps JSON (jeton d'administration)
gl_api_json() {
  local methode="$1" chemin="$2" json="$3"
  gl_api "$methode" "$chemin" -H 'Content-Type: application/json' --data-binary @- <<<"$json"
}

# gl_api_jeton JETON METHODE CHEMIN 'json' — appel avec un autre jeton (emprunt d'identité)
gl_api_jeton() {
  local jeton="$1" methode="$2" chemin="$3" json="${4:-}"
  if [[ -n "$json" ]]; then
    _gl_appel "$jeton" "$methode" "$chemin" -H 'Content-Type: application/json' --data-binary @- <<<"$json"
  else
    _gl_appel "$jeton" "$methode" "$chemin"
  fi
}

# gl_id_utilisateur LOGIN — identifiant numérique d'un compte
gl_id_utilisateur() {
  local id
  id="$(gl_api GET "users?username=$(gl_enc "$1")" | jq -r '.[0].id // empty')" || return 1
  [[ -n "$id" ]] || { printf 'erreur : compte GitLab introuvable : %s (voir M01-E05)\n' "$1" >&2; return 1; }
  printf '%s\n' "$id"
}

# gl_id_projet "groupe/projet" — identifiant numérique d'un projet (vide s'il n'existe pas)
gl_id_projet() {
  gl_api GET "projects/$(gl_enc "$1")" 2>/dev/null | jq -r '.id // empty'
}

# gl_emprunter LOGIN VARIABLE — crée un jeton d'emprunt d'identité (portée api, 1 jour)
#   et le range dans VARIABLE (pas de sous-shell : la liste des jetons à révoquer est globale).
gl_emprunter() {
  local login="$1" __var="$2" uid rep nom
  uid="$(gl_id_utilisateur "$login")" || exit 1
  nom="workbook-${WB_EX:-M01}-$(date +%Y%m%d%H%M%S)"
  rep="$(gl_api_json POST "users/$uid/impersonation_tokens" \
    "$(jq -nc --arg n "$nom" --arg e "$(date -d '+1 day' +%F)" '{name:$n, scopes:["api"], expires_at:$e}')")" \
    || gl_erreur "impossible de créer un jeton d'emprunt d'identité pour $login (emprunt désactivé sur l'instance ? jeton admin sans droits ?)"
  _GL_JETONS_EMPRUNT+=("$uid:$(jq -r .id <<<"$rep")")
  printf -v "$__var" '%s' "$(jq -r .token <<<"$rep")"
}

# gl_rendre_jetons — révoque tous les jetons d'emprunt créés par le script (trap EXIT)
gl_rendre_jetons() {
  local e
  for e in "${_GL_JETONS_EMPRUNT[@]}"; do
    gl_api DELETE "users/${e%%:*}/impersonation_tokens/${e#*:}" >/dev/null 2>&1 \
      || printf 'avertissement : jeton d'"'"'emprunt %s non révoqué, révoque-le dans Admin > Utilisateurs\n' "$e" >&2
  done
  _GL_JETONS_EMPRUNT=()
}

# gl_cloner_temp "groupe/projet" VARIABLE — clone (SSH, compte de l'apprenant) dans un dossier temporaire
gl_cloner_temp() {
  local projet="$1" __var="$2" d
  d="$(mktemp -d)"
  git clone -q "$(gl_url_ssh "$projet")" "$d/depot" \
    || gl_erreur "clonage SSH de $projet impossible (clé SSH chargée ? projet existant ?)"
  gl_git_neutre "$d/depot"
  printf -v "$__var" '%s' "$d/depot"
}

# gl_git_neutre DEPOT — dans un dépôt TEMPORAIRE : pas de signature (ta clé n'est pas forcément
#   dans l'agent), pas de hooks (pre-commit, commitlint) pour les commits fabriqués par le script.
gl_git_neutre() {
  git -C "$1" config commit.gpgsign false
  git -C "$1" config tag.gpgsign false
  git -C "$1" config core.hooksPath /dev/null
}

# gl_prerequis [outil...] — outils nécessaires sur adm01
gl_prerequis() {
  local c
  for c in git curl jq "$@"; do
    command -v "$c" >/dev/null 2>&1 || gl_erreur "outil manquant sur ce poste : $c"
  done
}

# gl_prerequis_api — en plus : jeton d'administration lisible
gl_prerequis_api() {
  gl_prerequis "$@"
  _gl_jeton_admin >/dev/null || exit 1
}

# gl_etat_ecrire EXERCICE "CLE=valeur" — mémorise un état non secret (identifiants, empreintes)
gl_etat_ecrire() {
  mkdir -p "$WB_RESS_ETAT"
  printf '%s\n' "$2" >> "$WB_RESS_ETAT/$1.env"
}
