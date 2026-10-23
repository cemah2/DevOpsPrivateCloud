# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et scripts distants entre apostrophes
# _m25-commun.sh — fonctions partagées par les scripts de panne du module 25 (palier 4 : M25-E35 à
# M25-E43 ; préfixe m25_). break-E34.sh (CHRONO du palier 3) reste autonome.
#
# Sourcé par break-E35.sh à break-E43.sh APRÈS lab/lib/pannes-lib.sh (wb_exec, wb_kubectl, wb_avert,
# WB_EX, WB_VAR…). Reprend les décisions de PLAN §4.12 et de la fiche du module.
# Rappel : lab/bin/break tourne sous « set -euo pipefail » ; les fonctions d'annulation sont appelées
# hors de tout « if » : aucune commande ne doit y échouer sans « || true ».
#
# Règles (CONVENTIONS §8, PLAN §4.12 « Pannes du bloc F ») :
#   - jamais kms01 scellé ni redémarré, jamais les parts, les clés de récupération ni la clé racine,
#     jamais /var/lib/openbao ; au plus UN nœud de la grappe arrêté, et toujours un nœud EN ATTENTE ;
#   - la configuration d'OpenBao modifiée est sauvegardée en JSON dans ~/.local/state/workbook/M25-EXX/
#     (700) avant toute modification ; les fichiers d'un nœud par sauver() (pannes-lib) ;
#   - JETON D'ADMINISTRATION (décision du module) : BAO_TOKEN exporté, sinon ~/.vault-token ; validé par
#     auth/token/lookup-self (politique plateforme-admin dans policies ou identity_policies, au moins
#     20 min de vie), sinon rien n'est cassé. Jamais en argument d'une commande (en-têtes curl par -K
#     <(…)), jamais affiché, jamais écrit sur disque ;
#   - kms01 : jeton d'administration dans BAO_KMS_TOKEN (racine régénérée de kms01, M25-E28). Une
#     panne qui modifie kms01 crée d'abord un jeton d'ANNULATION orphelin, étroit et daté (politique
#     wb-pannes de kms01), rangé en 600 dans l'état local : --annuler n'a pas besoin de BAO_KMS_TOKEN.
#
# Variables de lab/lab.env (facultatives) : WB_OPENBAO_URL, WB_M25_NOEUDS (« vault01 vault02 vault03 »),
# WB_M25_KMS (kms01), WB_M25_DOMAINE (par1.medisphere.internal), WB_M25_PORT (8200),
# WB_K8S_ADMIN_KUBECONFIG (kubeconfig d'administration, pour cmctl).

_M25_URL="${WB_OPENBAO_URL:-https://openbao.par1.medisphere.internal:8200}"
_M25_DOMAINE="${WB_M25_DOMAINE:-par1.medisphere.internal}"
_M25_PORT="${WB_M25_PORT:-8200}"
read -r -a _M25_NOEUDS <<<"${WB_M25_NOEUDS:-vault01 vault02 vault03}"
_M25_KMS="${WB_M25_KMS:-kms01}"
_M25_KMS_URL="https://$_M25_KMS.$_M25_DOMAINE:$_M25_PORT"
_M25_JETON=""

# ---------------------------------------------------------------------------
# État local (adm01)
# ---------------------------------------------------------------------------
m25_etat() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/M25-$1"
  mkdir -p "$d" && chmod 700 "$d"
  printf '%s\n' "$d"
}
m25_lire() { local f; f="$(m25_etat "$1")/$2"; if [[ -f "$f" ]]; then cat "$f"; fi; }
m25_ecrire() { local d; d="$(m25_etat "$1")"; (umask 077 && printf '%s\n' "$3" >"$d/$2"); }
# m25_ecrire_si_absent EX FICHIER VALEUR — une seule sauvegarde par panne (jamais un état déjà cassé).
m25_ecrire_si_absent() { local d; d="$(m25_etat "$1")"; [[ -e "$d/$2" ]] || (umask 077 && printf '%s\n' "$3" >"$d/$2"); }
m25_existe() { [[ -e "$(m25_etat "$1")/$2" ]]; }
m25_oublier() { local d; d="$(m25_etat "$1")"; rm -f -- "${d:?}/$2"; }
m25_journal() {
  local ex="$1" d
  shift
  d="$(m25_etat "$ex")"
  printf '%s %s [M25-%s variante %s] %s\n' "$(date -Is)" "$(hostname -s)" "$ex" "${WB_VAR:-?}" "$*" >>"$d/journal"
}

# m25_attendre SECONDES COMMANDE… — réessaie toutes les 3 s jusqu'au succès ou au délai.
m25_attendre() {
  local delai="$1" fin
  shift
  fin=$((SECONDS + delai))
  while ((SECONDS < fin)); do
    if "$@" >/dev/null 2>&1; then return 0; fi
    sleep 3
  done
  "$@" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# API d'OpenBao (jetons jamais affichés ni passés en argument)
# ---------------------------------------------------------------------------

# _m25_requete BASE JETON MÉTHODE CHEMIN [-]  — corps de la réponse sur la sortie standard ;
#   code 0 si HTTP 2xx. Avec « - », le corps JSON de la requête est lu sur l'entrée standard.
_m25_requete() {
  local base="$1" jeton="$2" methode="$3" chemin="$4" donnees="${5:-}" corps code
  corps="$(mktemp)"
  if [[ "$donnees" == - ]]; then
    code="$(curl -s -o "$corps" -w '%{http_code}' --max-time 20 -X "$methode" \
      -K <(printf 'header = "X-Vault-Token: %s"\n' "$jeton") -H 'Content-Type: application/json' \
      --data-binary @- "$base/v1/$chemin" 2>/dev/null)" || code=000
  else
    code="$(curl -s -o "$corps" -w '%{http_code}' --max-time 20 -X "$methode" \
      -K <(printf 'header = "X-Vault-Token: %s"\n' "$jeton") "$base/v1/$chemin" 2>/dev/null)" || code=000
  fi
  cat "$corps"
  rm -f "$corps"
  [[ "$code" == 2* ]]
}

# m25_jeton_charger — trouve et valide le jeton d'administration (voir l'en-tête). 0 si utilisable.
m25_jeton_charger() {
  [[ -n "$_M25_JETON" ]] && return 0
  local j="${BAO_TOKEN:-}" info
  if [[ -z "$j" && -r "$HOME/.vault-token" ]]; then j="$(<"$HOME/.vault-token")"; fi
  if [[ -z "$j" ]]; then
    wb_avert "aucun jeton OpenBao : connecte-toi (bao login -method=oidc) ou exporte BAO_TOKEN, puis relance"
    return 1
  fi
  info="$(_m25_requete "$_M25_URL" "$j" GET auth/token/lookup-self)" || {
    wb_avert "jeton OpenBao refusé (expiré ?) : reconnecte-toi (bao login -method=oidc) puis relance"
    return 1
  }
  if ! jq -e '(((.data.policies // []) + (.data.identity_policies // [])) | index("plateforme-admin")) != null
              and ((.data.ttl // 0) >= 1200)' >/dev/null 2>&1 <<<"$info"; then
    wb_avert "le jeton OpenBao doit porter plateforme-admin et vivre encore au moins 20 min (bao login -method=oidc)"
    return 1
  fi
  _M25_JETON="$j"
}

# m25_api MÉTHODE CHEMIN [-] — requête sur la grappe (VIP) avec le jeton d'administration.
m25_api() { m25_jeton_charger && _m25_requete "$_M25_URL" "$_M25_JETON" "$@"; }

# m25_kms_disponible — BAO_KMS_TOKEN est exporté et accepté par kms01 (au moins 20 min de vie, ou racine).
m25_kms_disponible() {
  [[ -n "${BAO_KMS_TOKEN:-}" ]] || return 1
  _m25_requete "$_M25_KMS_URL" "$BAO_KMS_TOKEN" GET auth/token/lookup-self |
    jq -e '((.data.ttl // 0) == 0 and ((.data.policies // []) | index("root")) != null) or ((.data.ttl // 0) >= 1200)' >/dev/null 2>&1
}
# m25_kms_api MÉTHODE CHEMIN [-] — requête sur kms01 avec BAO_KMS_TOKEN.
m25_kms_api() { _m25_requete "$_M25_KMS_URL" "${BAO_KMS_TOKEN:-}" "$@"; }
# m25_kms_api_jeton FICHIER MÉTHODE CHEMIN [-] — requête sur kms01 avec un jeton rangé dans un fichier.
m25_kms_api_jeton() {
  local f="$1"
  shift
  [[ -r "$f" ]] || return 1
  _m25_requete "$_M25_KMS_URL" "$(<"$f")" "$@"
}

# ---------------------------------------------------------------------------
# Grappe (sans jeton)
# ---------------------------------------------------------------------------
m25_url_noeud() { printf 'https://%s.%s:%s' "$1" "$_M25_DOMAINE" "$_M25_PORT"; }
# m25_code HÔTE — code HTTP de /v1/sys/health (000 si rien).
m25_code() {
  curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$(m25_url_noeud "$1")/v1/sys/health" 2>/dev/null || true
}
m25_kms_code() { curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$_M25_KMS_URL/v1/sys/health" 2>/dev/null || true; }
# m25_descelle HÔTE — le nœud répond et n'est pas scellé.
m25_descelle() {
  curl -s --max-time 5 "$(m25_url_noeud "$1")/v1/sys/seal-status" 2>/dev/null | jq -e '.sealed == false' >/dev/null 2>&1
}
# m25_en_service HÔTE — le nœud répond 200 (actif) ou 429 (en attente).
m25_en_service() { local c; c="$(m25_code "$1")"; [[ "$c" == 200 || "$c" == 429 ]]; }
# m25_hors_service HÔTE — le nœud ne répond ni 200 ni 429 (arrêté, scellé, en échec).
m25_hors_service() { ! m25_en_service "$1"; }
m25_actif() {
  local n
  for n in "${_M25_NOEUDS[@]}"; do [[ "$(m25_code "$n")" == 200 ]] && { printf '%s\n' "$n"; return 0; }; done
  return 1
}
# m25_en_attente_au_hasard — un nœud en attente (429), tiré au hasard.
m25_en_attente_au_hasard() {
  local n
  local -a l=()
  for n in "${_M25_NOEUDS[@]}"; do [[ "$(m25_code "$n")" == 429 ]] && l+=("$n"); done
  ((${#l[@]} > 0)) || return 1
  printf '%s\n' "${l[RANDOM % ${#l[@]}]}"
}
# m25_grappe_saine — exactement un nœud actif, les autres en attente, kms01 descellé (200).
m25_grappe_saine() {
  local n c actifs=0 attente=0
  for n in "${_M25_NOEUDS[@]}"; do
    c="$(m25_code "$n")"
    case "$c" in 200) actifs=$((actifs + 1)) ;; 429) attente=$((attente + 1)) ;; esac
  done
  ((actifs == 1 && attente == ${#_M25_NOEUDS[@]} - 1)) || return 1
  [[ "$(m25_kms_code)" == 200 ]]
}

# ---------------------------------------------------------------------------
# Nœuds (SSH admin + sudo -n)
# ---------------------------------------------------------------------------
m25_ssh() { remote "$1" "sudo -n bash -c $(printf '%q' "$2")" </dev/null; }
m25_exec() { local h="$1"; shift; wb_exec "$h" "$@"; }

# m25_redemarrer_noeud HÔTE — redémarre openbao sur un nœud EN ATTENTE (jamais l'actif, jamais kms01).
m25_redemarrer_noeud() {
  local h="$1"
  [[ "$h" != "$_M25_KMS" ]] || return 1
  [[ "$(m25_code "$h")" == 429 ]] || { wb_avert "$h n'est pas en attente : pas de redémarrage"; return 1; }
  m25_exec "$h" >/dev/null <<'EOF'
systemctl reset-failed openbao 2>/dev/null || true
systemctl restart openbao 2>/dev/null || true
journal "openbao redémarré (panne)"
EOF
}

# m25_relancer_si_besoin HÔTE — annulation : relance openbao seulement si le nœud est hors service
#   (jamais un nœud sain, qui peut être devenu actif entre-temps), puis attend son retour.
m25_relancer_si_besoin() {
  local h="$1"
  [[ -n "$h" ]] || return 0
  if m25_hors_service "$h"; then
    m25_exec "$h" >/dev/null <<'EOF' || true
systemctl reset-failed openbao 2>/dev/null || true
if ! systemctl is-active --quiet openbao; then systemctl start openbao 2>/dev/null || true; fi
journal "annulation : openbao relancé si nécessaire"
EOF
    m25_attendre 60 m25_en_service "$h" || {
      # Processus vivant mais scellé (déchiffrement en échec) : un redémarrage relit kms01 rétabli.
      m25_exec "$h" >/dev/null <<'EOF' || true
systemctl reset-failed openbao 2>/dev/null || true
systemctl restart openbao 2>/dev/null || true
EOF
      m25_attendre 60 m25_en_service "$h" || wb_avert "$h n'est pas revenu : voir RB-251 (journalctl -u openbao sur le nœud)"
    }
  fi
}

# ---------------------------------------------------------------------------
# Kubernetes (cert-manager)
# ---------------------------------------------------------------------------
# m25_renouveler_certificat ESPACE NOM — renouvellement forcé (cmctl renew si présent, sinon la même
#   condition « Issuing » que cmctl pose sur le statut).
m25_renouveler_certificat() {
  local ns="$1" nom="$2" maintenant
  if command -v cmctl >/dev/null 2>&1; then
    KUBECONFIG="${WB_K8S_ADMIN_KUBECONFIG:-$HOME/.kube/config}" cmctl renew -n "$ns" "$nom" >/dev/null 2>&1 && return 0
  fi
  maintenant="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  wb_kubectl -n "$ns" patch certificates.cert-manager.io "$nom" --subresource=status --type=json -p \
    "[{\"op\":\"add\",\"path\":\"/status/conditions/-\",\"value\":{\"type\":\"Issuing\",\"status\":\"True\",\"reason\":\"ManuallyTriggered\",\"message\":\"Certificate re-issuance manually triggered\",\"lastTransitionTime\":\"$maintenant\"}}]" \
    >/dev/null 2>&1
}
# m25_certificat_pret ESPACE NOM — Certificate Ready=True.
m25_certificat_pret() {
  wb_kubectl -n "$1" get certificates.cert-manager.io "$2" -o json 2>/dev/null |
    jq -e '[.status.conditions[]? | select(.type == "Ready" and .status == "True")] | length > 0' >/dev/null 2>&1
}
