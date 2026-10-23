# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# break-E22.sh — M27-E22 « Panne : le cache ne sert plus » (Valkey de mediagenda-recette seulement)
#
# Variantes 1 et 2 : réglages faits À CHAUD dans Valkey par « Lucas » (non écrits dans la configuration :
# un redémarrage de valkey-0 les efface), avec le compte d'administration de Valkey
# (WB_M27_VALKEY_ADMIN_USER / _SECRET / _CLE) ; sans lui, ces variantes sont sautées.
#   1. ACL SETUSER mediagenda resetkeys ~session:* : l'utilisateur de l'API ne peut plus toucher
#      « mediagenda:* » (NOPERM … no permissions to access one of the keys) ; les lectures du cache échouent
#      (« cache indisponible », mediagenda_cache_total{resultat="erreur"}), l'API recalcule depuis la base.
#   2. CONFIG SET maxmemory-policy noeviction et maxmemory = mémoire utilisée : toute écriture est refusée
#      (« OOM command not allowed when used memory > 'maxmemory' ») ; plus rien n'entre dans le cache.
#   Annulation : les règles ACL d'origine (ACL LIST sauvegardé, empreintes comprises) et les valeurs
#   CONFIG d'origine, seulement si les valeurs injectées sont encore en vigueur.
# Variante 3 : le Certificate du TLS de Valkey passe sur une autre ClusterIssuer (commit de Lucas, ou objet
#   modifié en place si Argo CD ne le suit pas), cert-manager réémet, valkey-0 redémarre (c'est un cache) :
#   le certificat servi n'est plus signé par l'autorité qu'attend MédiAgenda (certificate verify failed),
#   /pret répond 503. Annulation : retour à l'émetteur d'origine, réémission, redémarrage de valkey-0.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m27-commun.sh
source "$WB_ROOT/modules/27-donnees-messaging/corrige/pannes/_m27-commun.sh"

_E22_POD=valkey-0

# _e22_conteneur — nom du conteneur Valkey de valkey-0 (celui dont l'image contient « valkey/valkey »).
_e22_conteneur() {
  wb_kubectl -n "$_M27_NS_AGENDA" get pod "$_E22_POD" -o json 2>/dev/null |
    jq -r '[.spec.containers[] | select(.image | test("valkey/valkey"))][0].name // empty' | grep .
}

# _e22_cli ARGS… — valkey-cli dans valkey-0 avec le compte d'administration ; mot de passe passé par l'entrée
# standard (VALKEYCLI_AUTH), jamais en argument. Essaie TLS (sans vérification : on est DANS le pod), puis clair.
_e22_cli() {
  local c u s k mdp
  c="$(_e22_conteneur)" || return 1
  u="${WB_M27_VALKEY_ADMIN_USER:-admin}"
  s="${WB_M27_VALKEY_ADMIN_SECRET:-valkey-admin}"
  k="${WB_M27_VALKEY_ADMIN_CLE:-mot_de_passe}"
  mdp="$(wb_kubectl -n "$_M27_NS_AGENDA" get secret "$s" -o json 2>/dev/null | jq -r --arg k "$k" '.data[$k] // empty | @base64d')" || return 1
  [[ -n "$mdp" ]] || return 1
  printf '%s\n' "$mdp" | wb_kubectl -n "$_M27_NS_AGENDA" exec -i "$_E22_POD" -c "$c" -- sh -c '
    read -r VALKEYCLI_AUTH; export VALKEYCLI_AUTH
    out=$(valkey-cli --tls --insecure --user "$0" --no-auth-warning "$@" 2>&1) &&
      ! printf "%s" "$out" | grep -qiE "^(ERR|Error)|could not|NOAUTH|WRONGPASS|tls|ssl|handshake" && { printf "%s\n" "$out"; exit 0; }
    valkey-cli --user "$0" --no-auth-warning "$@"' "$u" "$@"
}

_e22_admin_ok() { [[ "$(_e22_cli PING 2>/dev/null)" == PONG ]]; }

# --- Variante 1 : ACL de l'utilisateur mediagenda -----------------------------------------------------

_e22_v1_poser() {
  local acl
  _e22_admin_ok || return 10
  acl="$(_e22_cli ACL LIST | grep -E '^user mediagenda ')" || return 10
  m27_ecrire E22 v1-acl "$acl"
  _e22_cli ACL SETUSER mediagenda resetkeys '~session:*' >/dev/null || return 1
  m27_journal E22 "ACL de mediagenda : clés limitées à session:*"
}
_e22_v1_constat() {
  _e22_cli ACL LIST 2>/dev/null | grep -E '^user mediagenda ' | grep -q '~session:\*' &&
    m27_prom_positif "sum(increase(mediagenda_cache_total{namespace=\"$_M27_NS_AGENDA\", resultat=\"erreur\"}[2m]))"
}
_e22_v1_defaire() {
  # « local - » : l'option -f (pas de développement des motifs « ~clé:* ») ne vaut que dans la fonction.
  local - acl regles
  set -f
  acl="$(m27_lire E22 v1-acl)"
  [[ -n "$acl" ]] || return 0
  if _e22_cli ACL LIST 2>/dev/null | grep -E '^user mediagenda ' | grep -q '~session:\*'; then
    # « user mediagenda <règles> » → ACL SETUSER mediagenda reset <règles> (empreintes #… comprises)
    regles="${acl#user mediagenda }"
    # shellcheck disable=SC2086  # les règles ACL sont des mots séparés par des espaces
    _e22_cli ACL SETUSER mediagenda reset $regles >/dev/null 2>&1 ||
      wb_avert "ACL non rétablie : ACL SETUSER mediagenda reset $regles"
    m27_journal E22 "ACL de mediagenda rétablie"
  fi
  m27_oublier E22 v1-acl
}

# --- Variante 2 : plus d'éviction, mémoire au plafond --------------------------------------------------

_e22_v2_poser() {
  local pol max used
  _e22_admin_ok || return 10
  pol="$(_e22_cli CONFIG GET maxmemory-policy | tail -n 1)" || return 1
  max="$(_e22_cli CONFIG GET maxmemory | tail -n 1)" || return 1
  [[ "$pol" == *lru* || "$pol" == *lfu* || "$pol" == *random* ]] || return 10
  used="$(_e22_cli INFO memory | tr -d '\r' | sed -n 's/^used_memory:\([0-9]*\)$/\1/p')"
  [[ "$used" =~ ^[0-9]+$ ]] || return 1
  m27_ecrire E22 v2-config "$pol|$max|$used"
  _e22_cli CONFIG SET maxmemory-policy noeviction >/dev/null || return 1
  _e22_cli CONFIG SET maxmemory "$used" >/dev/null || return 1
  m27_journal E22 "maxmemory-policy noeviction, maxmemory $used (au lieu de $pol, $max)"
}
_e22_v2_constat() {
  [[ "$(_e22_cli CONFIG GET maxmemory-policy 2>/dev/null | tail -n 1)" == noeviction ]] || return 1
  # Une écriture de test est refusée (clé du témoin, vie courte).
  _e22_cli SET wb:m27:e22 1 EX 10 2>&1 | grep -q '^OOM'
}
_e22_v2_defaire() {
  local pol max used
  IFS='|' read -r pol max used <<<"$(m27_lire E22 v2-config)"
  [[ -n "$pol" ]] || return 0
  if [[ "$(_e22_cli CONFIG GET maxmemory-policy 2>/dev/null | tail -n 1)" == noeviction ]]; then
    _e22_cli CONFIG SET maxmemory-policy "$pol" >/dev/null 2>&1 || wb_avert "CONFIG SET maxmemory-policy $pol à rejouer"
  fi
  if [[ "$(_e22_cli CONFIG GET maxmemory 2>/dev/null | tail -n 1)" == "$used" ]]; then
    _e22_cli CONFIG SET maxmemory "$max" >/dev/null 2>&1 || wb_avert "CONFIG SET maxmemory $max à rejouer"
  fi
  m27_journal E22 "configuration mémoire rétablie"
  m27_oublier E22 v2-config
}

# --- Variante 3 : certificat émis par une autre autorité ------------------------------------------------

# _e22_certificat — nom du Certificate dont le Secret est monté par valkey-0.
_e22_certificat() {
  local secrets
  secrets="$(wb_kubectl -n "$_M27_NS_AGENDA" get pod "$_E22_POD" -o json 2>/dev/null | jq -c '[.spec.volumes[]? | .secret.secretName // empty]')" || return 1
  wb_kubectl -n "$_M27_NS_AGENDA" get certificates.cert-manager.io -o json 2>/dev/null |
    jq -r --argjson s "$secrets" '[.items[] | select(.spec.secretName as $n | $s | index($n))][0].metadata.name // empty' | grep .
}

_e22_secret_emis_par() {   # _e22_secret_emis_par SECRET ÉMETTEUR
  wb_kubectl -n "$_M27_NS_AGENDA" get secret "$1" -o json 2>/dev/null |
    jq -e --arg e "$2" '.metadata.annotations["cert-manager.io/issuer-name"] == $e' >/dev/null 2>&1
}

_e22_redemarrer_valkey() {
  wb_kubectl -n "$_M27_NS_AGENDA" delete pod "$_E22_POD" --wait=false >/dev/null 2>&1 || true
}

_e22_v3_poser() {
  local cert c actuel autre secret app tmp lieu ops
  cert="$(_e22_certificat)" || return 10
  c="$(wb_kubectl -n "$_M27_NS_AGENDA" get certificates.cert-manager.io "$cert" -o json)" || return 1
  actuel="$(jq -r '.spec.issuerRef.name' <<<"$c")"
  [[ "$(jq -r '.spec.issuerRef.kind // "Issuer"' <<<"$c")" == ClusterIssuer ]] || return 10
  secret="$(jq -r '.spec.secretName' <<<"$c")"
  # Une autre ClusterIssuer prête, de type CA ou Vault (pas ACME : un défi ne pourrait pas aboutir).
  autre="$(wb_kubectl get clusterissuers.cert-manager.io -o json 2>/dev/null | jq -r --arg a "$actuel" '
    [.items[] | select(.metadata.name != $a and (.spec.acme == null)
                       and any(.status.conditions[]?; .type == "Ready" and .status == "True")) | .metadata.name]
    | (map(select(. == "buildkit-ca")) + .)[0] // empty')"
  [[ -n "$autre" ]] || return 10
  m27_ecrire E22 v3-cert "$cert|$secret|$actuel|$autre"
  app="$(m27_app_suivie certificates.cert-manager.io "$cert" "$_M27_NS_AGENDA")"
  tmp="$(m27_etat E22)/tmp"
  mkdir -p "$tmp"
  if [[ -n "$app" && "$app" == "$_M27_APP_AGENDA" ]]; then
    ops="$(jq -nc --arg e "$autre" '[{op: "replace", path: "/spec/issuerRef/name", value: $e}]')"
    m27_overlay_avec_patch "$_M27_DEPOT_AGENDA" '{"group":"cert-manager.io","kind":"Certificate","name":"'"$cert"'"}' "$ops" "$tmp/overlay.yaml" || return 10
    m27_commit E22 v3 "$_M27_DEPOT_AGENDA" "recette : certificat du cache émis par l'autorité interne commune" \
      "$_M27_OVERLAY" "$tmp/overlay.yaml" || return 1
    m27_argo_rafraichir "$app"
  elif [[ -z "$app" ]]; then
    wb_k8s_sauver certificates.cert-manager.io "$cert" "$_M27_NS_AGENDA"
    lieu="$(m27_doc_trouver "$_M27_DEPOT_K8S" espaces/mediagenda-recette \
      "(.kind == \"Certificate\") and (.metadata.name == \"$cert\")")" || lieu=""
    if [[ -n "$lieu" ]]; then
      m27_gl_fichier "$_M27_DEPOT_K8S" "${lieu%%$'\t'*}" >"$tmp/orig.yaml" || return 1
      IDX="${lieu##*$'\t'}" E="$autre" yq 'with(select(documentIndex == (strenv(IDX) | to_number)); .spec.issuerRef.name = strenv(E))' \
        "$tmp/orig.yaml" >"$tmp/neuf.yaml" || return 1
      m27_commit E22 v3 "$_M27_DEPOT_K8S" "recette : certificat du cache émis par l'autorité interne commune" \
        "${lieu%%$'\t'*}" "$tmp/neuf.yaml" || return 1
    fi
    wb_kubectl -n "$_M27_NS_AGENDA" patch certificates.cert-manager.io "$cert" --type merge \
      -p "$(jq -nc --arg e "$autre" '{spec: {issuerRef: {name: $e}}}')" >/dev/null || return 1
    m27_ecrire E22 v3-direct oui
  else
    return 10   # suivi par une autre Application : on ne touche pas
  fi
  m27_attendre 300 _e22_secret_emis_par "$secret" "$autre" || return 1
  _e22_redemarrer_valkey
  m27_journal E22 "Certificate $cert : $actuel → $autre, valkey-0 redémarré"
}
_e22_v3_constat() {
  local cert secret actuel autre
  IFS='|' read -r cert secret actuel autre <<<"$(m27_lire E22 v3-cert)"
  [[ -n "$autre" ]] || return 1
  _e22_secret_emis_par "$secret" "$autre" &&
    m27_prom_positif "sum(increase(mediagenda_cache_total{namespace=\"$_M27_NS_AGENDA\", resultat=\"erreur\"}[2m]))"
}
_e22_v3_defaire() {
  local cert secret actuel autre d f
  IFS='|' read -r cert secret actuel autre <<<"$(m27_lire E22 v3-cert)"
  [[ -n "$cert" ]] || return 0
  if m27_commit_actif E22 v3; then
    m27_retablir E22 v3 || true
    m27_argo_rafraichir "$_M27_APP_AGENDA"
  else
    m27_oublier E22 git-v3
  fi
  if [[ -n "$(m27_lire E22 v3-direct)" ]]; then
    if wb_kubectl -n "$_M27_NS_AGENDA" get certificates.cert-manager.io "$cert" -o json 2>/dev/null |
      jq -e --arg e "$autre" '.spec.issuerRef.name == $e' >/dev/null 2>&1; then
      wb_kubectl -n "$_M27_NS_AGENDA" patch certificates.cert-manager.io "$cert" --type merge \
        -p "$(jq -nc --arg e "$actuel" '{spec: {issuerRef: {name: $e}}}')" >/dev/null 2>&1 || true
    fi
    d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/k8s/M27-E22"
    f="$d/${_M27_NS_AGENDA}_certificates.cert-manager.io_${cert}.yaml"
    [[ -f "$f" ]] && rm -rf "$d"
    m27_oublier E22 v3-direct
  fi
  # Réémission par l'émetteur d'origine, puis Valkey recharge son certificat au redémarrage.
  if m27_attendre 300 _e22_secret_emis_par "$secret" "$actuel"; then
    _e22_redemarrer_valkey
  else
    wb_avert "le certificat $cert n'est pas encore réémis par $actuel : supprime valkey-0 quand il le sera"
  fi
  m27_journal E22 "certificat de Valkey rendu à $actuel"
  m27_oublier E22 v3-cert
}

# --- Mécanique commune --------------------------------------------------------------------------------

_m27E22_une() {
  local n="$1" rc=0
  "_e22_v${n}_poser" || rc=$?
  if ((rc != 0)); then
    "_e22_v${n}_defaire" || true
    return "$rc"
  fi
  m27_debut E22
  if ! m27_attendre 420 "_e22_v${n}_constat"; then
    "_e22_v${n}_defaire" || true
    return 10
  fi
}

panne_E22_v1() { m27_preparer valkey && m27_essayer E22 3 1; }
panne_E22_v2() { m27_preparer valkey && m27_essayer E22 3 2; }
panne_E22_v3() { m27_preparer valkey && m27_essayer E22 3 3; }

verifier_E22() {
  case "$WB_VAR" in
    1) _e22_cli ACL LIST 2>/dev/null | grep -E '^user mediagenda ' | grep -q '~session:\*' ;;
    2) [[ "$(_e22_cli CONFIG GET maxmemory-policy 2>/dev/null | tail -n 1)" == noeviction ]] ;;
    3) _e22_v3_constat ;;
    *) return 1 ;;
  esac
}

annuler_E22() {
  case "${WB_VAR:-}" in
    [1-3]) "_e22_v${WB_VAR}_defaire" ;;
    *) local v; for v in 1 2 3; do "_e22_v${v}_defaire" || true; done ;;
  esac
  m27_oublier E22 debut
  m27_oublier E22 tmp
  m27_journal E22 "annulation"
}

resume_E22() {
  echo "La recette de MédiAgenda est lente ; le cache Valkey ne sert plus."
}

symptome_E22() {
  wb_symptome "Ticket INC-5422 — De : Julien Petit" \
    "La recette de MédiAgenda est lente depuis un moment, surtout l'affichage des créneaux, et selon les" \
    "moments la sonde /pret répond 503 ou les journaux parlent de « cache indisponible » ou d'« écriture en" \
    "cache impossible ». La base, elle, va bien. Lucas a « vérifié la configuration du cache » hier soir." \
    "Remets le cache en service, à la racine, et assure-toi qu'il ne reste aucun réglage fait à la main." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 27 22"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 27 E22 3 "$@"; }
fi
