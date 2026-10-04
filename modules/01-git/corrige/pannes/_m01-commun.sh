# shellcheck shell=bash
# _m01-commun.sh — fonctions partagées par les scripts de panne du module 01 (M01-E36 à M01-E43).
#
# Sourcé par break-EXX.sh APRÈS lab/lib/pannes-lib.sh (wb_avert, WB_EX…).
#   - m01_api / m01_api_json : appels à l'API GitLab avec le jeton d'ADMINISTRATION de l'apprenant
#     (fichier WB_GITLAB_ADMIN_TOKEN_FILE, portée api). Le jeton ne passe jamais dans la ligne de
#     commande (en-tête lu par curl dans un descripteur), il n'apparaît donc pas dans `ps`.
#   - m01_etat EXX : dossier d'état local de la panne sur adm01 (700), pour les sauvegardes
#     faites côté poste (dépôts, ~/.ssh, identifiants de ressources GitLab).
#   - m01_ssh_fermer_maitre : ferme la connexion SSH maîtresse (ControlMaster de M00-E15) vers la
#     forge, sinon une panne SSH resterait masquée jusqu'à 5 minutes.

_M01_GITLAB="${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}"
_M01_FQDN_GIT="git01.par1.medisphere.internal"
_M01_PROJET="plateforme/medisphere"
# Jeton utilisé par m01_api : vide = jeton d'administration ; sinon (emprunt d'identité) ce jeton.
_M01_JETON=""

# m01_prerequis — outils locaux nécessaires aux pannes du module.
m01_prerequis() {
  local c
  for c in curl jq git ssh; do
    command -v "$c" >/dev/null 2>&1 || { wb_avert "outil manquant sur adm01 : $c"; return 1; }
  done
}

# m01_enc CHAÎNE — encodage URL (chemins de projets, noms de branches protégées…).
m01_enc() { jq -rn --arg s "$1" '$s|@uri'; }

# m01_api MÉTHODE CHEMIN [options curl…] — corps de la réponse sur stdout ; code ≠ 0 si HTTP ≥ 400.
m01_api() {
  local m="$1" p="$2" t f
  shift 2
  if [[ -n "$_M01_JETON" ]]; then
    t="$_M01_JETON"
  else
    f="${WB_GITLAB_ADMIN_TOKEN_FILE:-$HOME/.config/workbook/gitlab-admin.token}"
    [[ -r "$f" ]] || { wb_avert "jeton d'administration GitLab illisible : $f"; return 1; }
    t="$(<"$f")"
  fi
  curl -sf --max-time 30 -X "$m" -H @<(printf 'PRIVATE-TOKEN: %s\n' "$t") \
    "$_M01_GITLAB/api/v4/$p" "$@"
}

# m01_api_json MÉTHODE CHEMIN 'JSON' — requête avec un corps JSON.
m01_api_json() {
  local m="$1" p="$2" j="$3"
  m01_api "$m" "$p" -H 'Content-Type: application/json' --data-binary "$j"
}

# m01_projet_id [CHEMIN] — identifiant numérique d'un projet (défaut : plateforme/medisphere).
m01_projet_id() {
  local id
  id="$(m01_api GET "projects/$(m01_enc "${1:-$_M01_PROJET}")" | jq -r '.id // empty')" || return 1
  [[ -n "$id" ]] || return 1
  printf '%s\n' "$id"
}

# m01_etat EXX — affiche (et crée, en 700) le dossier d'état local de la panne.
m01_etat() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/M01-$1"
  mkdir -p "$d" && chmod 700 "$d"
  printf '%s\n' "$d"
}

# m01_jeton_emprunt IDENTIFIANT — crée un jeton d'emprunt d'identité (impersonation token,
# portée api, expire demain) pour un personnage. Affiche « id_utilisateur id_jeton jeton ».
m01_jeton_emprunt() {
  local u="$1" uid r
  uid="$(m01_api GET "users?username=$(m01_enc "$u")" | jq -r '.[0].id // empty')" || return 1
  [[ -n "$uid" ]] || return 1
  r="$(m01_api POST "users/$uid/impersonation_tokens" \
        --data-urlencode "name=workbook-${WB_EX:-M01}" \
        --data-urlencode "expires_at=$(date -d '+1 day' +%F)" \
        --data-urlencode "scopes[]=api")" || return 1
  printf '%s %s %s\n' "$uid" "$(jq -r '.id' <<<"$r")" "$(jq -r '.token' <<<"$r")"
}

# m01_jeton_emprunt_revoquer ID_UTILISATEUR ID_JETON
m01_jeton_emprunt_revoquer() {
  m01_api DELETE "users/$1/impersonation_tokens/$2" >/dev/null 2>&1 || true
}

# m01_ssh_fermer_maitre — ferme la connexion maîtresse SSH vers git@<forge> si elle existe.
m01_ssh_fermer_maitre() {
  ssh -O exit -o BatchMode=yes "git@$_M01_FQDN_GIT" >/dev/null 2>&1 || true
}

# m01_ssh_forge_ok — 0 si « ssh -T git@<forge> » accueille l'utilisateur (sans multiplexage).
m01_ssh_forge_ok() {
  local out
  out="$(ssh -o BatchMode=yes -o ControlPath=none -o ConnectTimeout=10 -T "git@$_M01_FQDN_GIT" 2>&1)" || true
  grep -q 'Welcome to GitLab' <<<"$out"
}
