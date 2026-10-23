# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq, requêtes LogQL et commandes distantes entre apostrophes
# shellcheck source-path=SCRIPTDIR
# _m25-expert-b.sh — fonctions partagées par les vérifications M25-E40 à M25-E46 (palier 4, seconde
# moitié, et mini-projet). Sourcé par ces check-EXX.sh, jamais lancé seul. Préfixe _m25y_.
# S'appuie sur _m25-production.sh (préfixe _m25p_ : santé des nœuds, bao_api, GitLab, Loki, SSH).
# LECTURE SEULE : OpenBao (sys/health, sys/seal-status sans jeton ; le reste par l'AppRole wb-checks :
# politiques, groupes, rôles, configuration de la PKI, état de Raft et du trousseau — jamais une
# valeur), points publics de la PKI (ca/pem, crl/pem), kube (compte wb-checks), GitLab en lecture,
# Prometheus, Loki (locataire audit), SSH en consultation (sudo -n) sur vault01-03.
# Rappel : lab/bin/check tourne sous « set -euo pipefail ».
#
# Lectures ajoutées à la politique wb-checks par ce palier (extraits du corrigé, configuration seulement) :
#   pki-services/issuer/+, pki-services/config/crl, pki-services/config/issuers (M25-E41),
#   sys/key-status (M25-E44). Si elles manquent, les contrôles concernés sont « ignorés » avec la raison.

# shellcheck source=_m25-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m25-production.sh"

_M25Y_BAO="${WB_OPENBAO_URL:-https://$_M25P_SERVICE:$_M25P_PORT}"
_M25Y_KMS_IP="${WB_M25_KMS_IP:-10.10.20.24}"
# Dossiers où peuvent se trouver les journaux de diagnostic et post-mortems (plateforme/medisphere).
_M25Y_JOURNAUX=(docs/socle/journal docs/kubernetes/journal docs/securite/secrets/journal)
_M25Y_PM=(docs/socle/post-mortems docs/kubernetes/post-mortems docs/securite/secrets/post-mortems)

# --- OpenBao : politiques et groupes -------------------------------------------------------------------

# _m25y_politique NOM — texte de la politique ACL (vide si illisible).
_m25y_politique() { _m25p_bao "sys/policies/acl/$1" | jq -r '.data.policy // empty' 2>/dev/null || true; }

# _m25y_caps TEXTE MOTIF — capacités (une par ligne) du bloc « path "MOTIF" » de la politique ;
#   bloc sur une ou plusieurs lignes ; rien si le motif est absent.
_m25y_caps() {
  awk -v m="path \"$2\"" '
    index($0, m) == 1 || index($0, " " m) { dedans = 1 }
    dedans { tampon = tampon $0; if (index($0, "}")) { dedans = 0; exit } }
    END { if (match(tampon, /capabilities[[:space:]]*=[[:space:]]*\[[^]]*\]/)) {
            s = substr(tampon, RSTART, RLENGTH); sub(/.*\[/, "", s); sub(/\].*/, "", s)
            gsub(/[" ]/, "", s); n = split(s, t, ","); for (i = 1; i <= n; i++) if (t[i] != "") print t[i] } }' <<<"$1"
}

# _m25y_caps_ont TEXTE MOTIF CAPACITÉ… — le bloc existe et porte toutes les capacités citées.
_m25y_caps_ont() {
  local texte="$1" motif="$2" c caps
  shift 2
  caps="$(_m25y_caps "$texte" "$motif")"
  [[ -n "$caps" ]] || return 1
  for c in "$@"; do grep -qx -- "$c" <<<"$caps" || return 1; done
}

# _m25y_politiques — noms des politiques ACL du coffre, une par ligne.
_m25y_politiques() { _m25p_bao 'sys/policies/acl?list=true' | jq -r '.data.keys[]? // empty' 2>/dev/null || true; }

# _m25y_deny_sur REGEX — aucune politique ne pose « deny » sur un motif qui correspond à la regex.
_m25y_aucun_deny_sur() {
  local p t
  while IFS= read -r p; do
    [[ -n "$p" && "$p" != root ]] || continue
    t="$(_m25y_politique "$p")"
    awk -v r="$1" '
      /^[[:space:]]*path[[:space:]]/ { motif = $0 }
      /deny/ && motif ~ r { trouve = 1 }
      END { exit trouve ? 0 : 1 }' <<<"$t" && return 1
  done < <(_m25y_politiques)
  return 0
}

_m25y_groupe() { _m25p_bao "identity/group/name/$1"; }
# _m25y_accessor_auth MONTAGE/ — accessor d'une méthode d'authentification (sys/auth).
_m25y_accessor_auth() {
  _m25p_bao sys/auth | jq -r --arg m "$1" '(.data[$m] // .[$m]).accessor // empty' 2>/dev/null || true
}

# --- PKI -------------------------------------------------------------------------------------------------

# _m25y_crl_marge SECONDES — la CRL publiée est valable encore au moins SECONDES.
_m25y_crl_marge() {
  local p
  p="$(curl -s --max-time "$WB_TIMEOUT" "$_M25Y_BAO/v1/pki-services/crl/pem" 2>/dev/null \
    | openssl crl -noout -nextupdate 2>/dev/null | cut -d= -f2)" || return 1
  [[ -n "$p" ]] && (($(date -d "$p" +%s) - $(date +%s) >= $1))
}

# _m25y_certificat_pret ESPACE NOM — Certificate Ready=True (vu par le compte des checks).
_m25y_certificat_pret() {
  kube get certificates.cert-manager.io "$2" -n "$1" -o json 2>/dev/null |
    jq -e '[.status.conditions[]? | select(.type == "Ready" and .status == "True")] | length > 0' >/dev/null 2>&1
}

# _m25y_aucune_racine — aucun jeton de service vivant ne porte la politique root (300 accessors au plus ;
#   lookup-accessor par POST avec le jeton wb-checks, comme M25-E28). Appeler _m25p_connexion avant.
_m25y_aucune_racine() {
  local acc n=0 r
  [[ -n "$_WB_BAO_JETON" ]] || return 1
  while IFS= read -r acc; do
    [[ -n "$acc" ]] || continue
    n=$((n + 1))
    ((n <= 300)) || break
    r="$(jq -nc --arg a "$acc" '{accessor: $a}' | curl -sf --max-time "$WB_TIMEOUT" \
      -K <(printf 'header = "X-Vault-Token: %s"\n' "$_WB_BAO_JETON") --data @- \
      "$_M25Y_BAO/v1/auth/token/lookup-accessor" 2>/dev/null)" || return 1
    jq -e '.data.policies | index("root")' >/dev/null 2>&1 <<<"$r" && return 1
  done < <(_m25p_bao 'auth/token/accessors?list=true' | jq -r '.data.keys[]? // empty' 2>/dev/null || true)
  ((n > 0))
}

# --- Documents (plateforme/medisphere) ---------------------------------------------------------------------

# _m25y_doc_nomme DOSSIERS… -- MOTIF — un fichier d'un des dossiers a un nom qui contient MOTIF.
_m25y_fichier_nomme() {
  local motif="${*: -1}" d
  for d in "${@:1:$#-1}"; do
    _m25p_arbre "$_M25P_DOC" "$d" | grep -qF -- "$motif" && return 0
  done
  return 1
}
# _m25y_journal INC — un journal de diagnostic nommé avec le numéro du ticket existe sur main.
_m25y_journal() { _m25y_fichier_nomme "${_M25Y_JOURNAUX[@]}" "$1"; }
# _m25y_post_mortem INC — chemin du post-mortem nommé avec le numéro du ticket (vide si absent).
_m25y_post_mortem() {
  local d f
  for d in "${_M25Y_PM[@]}"; do
    f="$(_m25p_arbre "$_M25P_DOC" "$d" | grep -F -- "$1" | head -n 1 || true)"
    [[ -n "$f" ]] && { printf '%s\n' "$f"; return 0; }
  done
  return 0
}

# --- Divers ------------------------------------------------------------------------------------------------

# _m25y_aucune_panne [EXX…] — aucune des pannes listées (ou aucune M25-*) n'est marquée active.
_m25y_aucune_panne() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives" e
  if (($# == 0)); then
    [[ -z "$(find "$d" -maxdepth 1 -name 'M25-E*' 2>/dev/null)" ]]
    return
  fi
  for e in "$@"; do [[ ! -e "$d/M25-$e" ]] || return 1; done
}

# _m25y_sans_secret TEXTE — le texte ne contient ni jeton, ni clé privée, ni identifiant S3.
_m25y_sans_secret() {
  ! grep -Eq '(\b[sbr]\.[A-Za-z0-9]{24}\b|hvs\.[A-Za-z0-9_-]{20}|glpat-[A-Za-z0-9_-]{20}|-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}|AGE-SECRET-KEY-1)' <<<"$1"
}

# _m25y_regle_presente REGEX — une règle d'alerte chargée dans Prometheus a une expression qui
#   correspond (API /api/v1/rules de la vue globale).
_m25y_regle_presente() {
  prom_api rules 2>/dev/null | jq -e --arg r "$1" \
    '[.data.groups[]?.rules[]? | select(.type == "alerting") | select(.query | test($r))] | length > 0' >/dev/null 2>&1
}
