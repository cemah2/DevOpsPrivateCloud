# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et SQL entre apostrophes
# break-S03.sh — F3-S03 « Lundi : MédiAgenda rame » (PRODUCTION, mediagenda-prod)
#
# Contrôle préalable : lab sain (contrôle de santé de S01), aucune panne active, sauvegarde CNPG
# « completed » de moins de 26 h de mediagenda-db (prod), sinon une sauvegarde est lancée et attendue.
# Latence de référence mesurée AVANT l'injection (requêtes de créneaux qui manquent le cache).
#
#   1. « Rapport d'activité » de Lucas lancé À LA MAIN dans le conteneur postgres du primaire de prod :
#      session psql (application_name rapport-activite) qui, en boucle, ouvre une transaction,
#      « LOCK TABLE rendez_vous » (sans mode : ACCESS EXCLUSIVE, « pour une extraction cohérente »),
#      dort 8 s, valide, attend 2 s. Les lectures de rendez_vous attendent jusqu'à 8 s, tiennent leur
#      connexion serveur de PgBouncer pendant ce temps (clients en attente). Aucune ligne n'est écrite.
#      Annulation : pg_terminate_backend de la session (repérée par application_name), arrêt du
#      générateur ; la boucle s'arrête seule au bout de 6 h.
#   2. Valkey de prod « allégé » à chaud par Lucas (CONFIG SET, non écrit dans la configuration) :
#      maxmemory ramenée juste au-dessus de la mémoire de base de l'instance, politique d'éviction
#      inchangée : chaque nouvelle clé en évince une autre, le cache ne garde plus rien, toutes les
#      consultations de créneaux vont à PostgreSQL. Annulation : maxmemory d'origine si la valeur
#      injectée est toujours en vigueur. Compte d'administration de Valkey (Secret valkey-admin, M27).
#   3. Ressources CPU de l'API réduites EN PLACE (sous-ressource resize, Kubernetes ≥ 1.35) sur chaque
#      pod de l'API de prod : requests CPU à 10m et limite CPU de 10m AJOUTÉE (le gabarit du M28 n'a
#      pas de limite CPU ; la classe QoS reste Burstable car la mémoire a requête ≠ limite) —
#      « recommandation VPA appliquée à la main ». Le gabarit (Git, Deployment, Rollout) n'est pas
#      touché : un pod recréé repart avec ses vraies ressources. Une limite posée en place ne peut plus
#      être retirée en place (limite documentée de Kubernetes) : l'annulation SUPPRIME, un à la fois,
#      les pods encore réduits (recréés depuis le gabarit) en attendant chaque fois que le nombre de
#      pods prêts soit revenu.
#
# Constat (toutes variantes) : la médiane de requêtes de créneaux « cache manqué » dépasse 1,5 s et le
# triple de la référence (variantes 1 et 3) ; variante 2 : la valeur injectée est en vigueur et des clés
# sont évincées pendant la mesure.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_f3-commun.sh
source "$WB_ROOT/finaux/F3-astreinte/corrige/pannes/_f3-commun.sh"

_S03_APP=rapport-activite
_S03_VALKEY_POD="${WB_F3_VALKEY_POD:-valkey-0}"
_S03_VALKEY_USER="${WB_F3_VALKEY_ADMIN_USER:-${WB_M27_VALKEY_ADMIN_USER:-admin}}"
_S03_VALKEY_SECRET="${WB_F3_VALKEY_ADMIN_SECRET:-${WB_M27_VALKEY_ADMIN_SECRET:-valkey-admin}}"
_S03_VALKEY_CLE="${WB_F3_VALKEY_ADMIN_CLE:-${WB_M27_VALKEY_ADMIN_CLE:-mot_de_passe}}"
_S03_CPU=10m

# --- Variante 1 : session de rapport qui verrouille rendez_vous ----------------------------------------

_s03_v1_session() {
  _f3p_psql "$_F3P_PROD" "SELECT pid FROM pg_stat_activity WHERE datname = 'mediagenda'
     AND application_name = '$_S03_APP' AND pid <> pg_backend_pid() LIMIT 1;" | grep -E '^[0-9]+$'
}
_s03_v1_poser() {
  local p
  [[ "$(_f3p_psql "$_F3P_PROD" "SELECT to_regclass('public.rendez_vous') IS NOT NULL;")" == t ]] || return 10
  p="$(_f3p_pg_primaire "$_F3P_PROD")" || return 1
  # Processus détaché DANS le conteneur postgres (il survit à la fin de kubectl exec). Le générateur
  # cadence les ordres : psql exécute chaque bloc à son arrivée. 2160 tours de 10 s = 6 h au plus.
  wb_kubectl -n "$_F3P_PROD" exec -i "$p" -c postgres -- bash -s >/dev/null 2>&1 <<SH || return 1
nohup setsid bash -c '{ printf "%s\n" "SET application_name = '"'"'$_S03_APP'"'"';"; for i in \$(seq 1 2160); do printf "%s\n" "BEGIN;" "LOCK TABLE public.rendez_vous;" "SELECT pg_sleep(8);" "COMMIT;"; sleep 10; done; } | psql -X -q -d mediagenda' </dev/null >/dev/null 2>&1 &
SH
  _f3p_ecrire S03 v1-primaire "$p"
  _f3p_attendre 60 _s03_v1_session >/dev/null || return 1
  _f3p_journal S03 "session $_S03_APP ouverte sur $p (LOCK TABLE rendez_vous en boucle)"
}
_s03_v1_defaire() {
  local pid p
  pid="$(_s03_v1_session 2>/dev/null)" || pid=""
  if [[ -n "$pid" ]]; then
    _f3p_psql "$_F3P_PROD" "SELECT pg_terminate_backend($pid);" >/dev/null 2>&1 || true
    _f3p_journal S03 "session $pid terminée"
  fi
  p="$(_f3p_lire S03 v1-primaire)"
  if [[ -n "$p" ]]; then
    # Le générateur reçoit SIGPIPE à sa prochaine écriture une fois psql sorti ; on l'arrête aussi
    # explicitement (seulement les « bash -c { printf … rapport-activite » de cette panne : la commande
    # qui cherche ne commence pas par « bash -c { printf », elle ne se tue pas elle-même).
    wb_kubectl -n "$_F3P_PROD" exec "$p" -c postgres -- sh -c \
      'for d in /proc/[0-9]*; do tr "\0" " " <"$d/cmdline" 2>/dev/null | grep -q "^bash -c { printf.*rapport-activite" && kill "${d#/proc/}" 2>/dev/null; done; exit 0' \
      >/dev/null 2>&1 || true
  fi
  _f3p_oublier S03 v1-primaire
}

# --- Variante 2 : Valkey qui ne garde plus rien -------------------------------------------------------

_s03_valkey_conteneur() {
  wb_kubectl -n "$_F3P_PROD" get pod "$_S03_VALKEY_POD" -o json 2>/dev/null |
    jq -r '[.spec.containers[] | select(.image | test("valkey/valkey"))][0].name // empty' | grep .
}
# _s03_cli ARGS… — valkey-cli dans le pod avec le compte d'administration (mot de passe par l'entrée
# standard, jamais en argument ; TLS sans vérification : on est DANS le pod), comme M27-E22.
_s03_cli() {
  local c mdp
  c="$(_s03_valkey_conteneur)" || return 1
  mdp="$(wb_kubectl -n "$_F3P_PROD" get secret "$_S03_VALKEY_SECRET" -o json 2>/dev/null | jq -r --arg k "$_S03_VALKEY_CLE" '.data[$k] // empty | @base64d')" || return 1
  [[ -n "$mdp" ]] || return 1
  printf '%s\n' "$mdp" | wb_kubectl -n "$_F3P_PROD" exec -i "$_S03_VALKEY_POD" -c "$c" -- sh -c '
    read -r VALKEYCLI_AUTH; export VALKEYCLI_AUTH
    out=$(valkey-cli --tls --insecure --user "$0" --no-auth-warning "$@" 2>&1) &&
      ! printf "%s" "$out" | grep -qiE "^(ERR|Error)|could not|NOAUTH|WRONGPASS|tls|ssl|handshake" && { printf "%s\n" "$out"; exit 0; }
    valkey-cli --user "$0" --no-auth-warning "$@"' "$_S03_VALKEY_USER" "$@"
}
_s03_info() { _s03_cli INFO "$1" 2>/dev/null | tr -d '\r' | sed -n "s/^$2:\([0-9]*\)$/\1/p"; }

_s03_v2_poser() {
  local pol max used ds inj
  [[ "$(_s03_cli PING 2>/dev/null)" == PONG ]] || return 10
  pol="$(_s03_cli CONFIG GET maxmemory-policy | tail -n 1)" || return 1
  max="$(_s03_cli CONFIG GET maxmemory | tail -n 1)" || return 1
  [[ "$pol" == allkeys-* || "$pol" == volatile-* ]] || return 10
  used="$(_s03_info memory used_memory)"
  ds="$(_s03_info memory used_memory_dataset)"
  [[ "$used" =~ ^[0-9]+$ && "$ds" =~ ^[0-9]+$ ]] || return 1
  # Mémoire de base (hors données) + 32 Kio : quelques clés tiennent, toutes les autres sont évincées.
  inj=$((used - ds + 32768))
  ((inj > 0)) || return 10
  if [[ "$max" =~ ^[0-9]+$ ]] && ((max != 0 && max <= inj)); then return 10; fi
  _f3p_ecrire S03 v2-config "$max|$inj"
  _s03_cli CONFIG SET maxmemory "$inj" >/dev/null || return 1
  _f3p_journal S03 "Valkey $_F3P_PROD : maxmemory $inj (au lieu de $max), politique $pol inchangée"
}
_s03_v2_defaire() {
  local max inj
  IFS='|' read -r max inj <<<"$(_f3p_lire S03 v2-config)"
  [[ -n "$max" ]] || return 0
  if [[ "$(_s03_cli CONFIG GET maxmemory 2>/dev/null | tail -n 1)" == "$inj" ]]; then
    _s03_cli CONFIG SET maxmemory "$max" >/dev/null 2>&1 || wb_avert "CONFIG SET maxmemory $max à rejouer sur $_S03_VALKEY_POD ($_F3P_PROD)"
    _f3p_journal S03 "maxmemory de Valkey rétablie ($max)"
  fi
  _f3p_oublier S03 v2-config
}
_s03_v2_constat() {
  local e1 e2
  [[ "$(_s03_cli CONFIG GET maxmemory 2>/dev/null | tail -n 1)" == "$(_f3p_lire S03 v2-config | cut -d'|' -f2)" ]] || return 1
  e1="$(_s03_info stats evicted_keys)"
  _f3p_latence "$_F3P_URL_PROD" 20 5 >/dev/null
  e2="$(_s03_info stats evicted_keys)"
  [[ "$e1" =~ ^[0-9]+$ && "$e2" =~ ^[0-9]+$ ]] && ((e2 > e1))
}

# --- Variante 3 : CPU des pods de l'API réduit en place ----------------------------------------------

_s03_pods_api() {
  wb_kubectl -n "$_F3P_PROD" get pods -l "$_F3P_API_SEL" -o json 2>/dev/null |
    jq -r '.items[] | select(.metadata.deletionTimestamp == null) | select(.status.phase == "Running") | .metadata.name'
}
_s03_conteneur_api() {
  wb_kubectl -n "$_F3P_PROD" get pod "$1" -o json 2>/dev/null |
    jq -r '([.spec.containers[] | select(.name == "api")][0] // .spec.containers[0]).name'
}
_s03_v3_poser() {
  local p c res n=0 d
  d="$(_f3p_etat S03)/v3"
  mkdir -p "$d"
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    c="$(_s03_conteneur_api "$p")"
    res="$(wb_kubectl -n "$_F3P_PROD" get pod "$p" -o json | jq -c --arg c "$c" '[.spec.containers[] | select(.name == $c)][0].resources // {}')"
    # Seulement si le conteneur déclare une requête CPU (Burstable) ; l'API refuse le resize s'il
    # changeait la classe QoS (ex. mémoire requête = limite) : le pod est alors laissé tel quel.
    jq -e '.requests.cpu' <<<"$res" >/dev/null 2>&1 || continue
    printf '%s\t%s\t%s\n' "$p" "$c" "$res" >>"$d/pods"
    # Patch stratégique (fusion des conteneurs par nom), comme la documentation de Kubernetes.
    wb_kubectl -n "$_F3P_PROD" patch pod "$p" --subresource resize -p \
      "{\"spec\":{\"containers\":[{\"name\":\"$c\",\"resources\":{\"requests\":{\"cpu\":\"$_S03_CPU\"},\"limits\":{\"cpu\":\"$_S03_CPU\"}}}]}}" \
      >/dev/null 2>&1 || continue
    n=$((n + 1))
  done < <(_s03_pods_api)
  ((n > 0)) || return 10
  _f3p_journal S03 "CPU de $n pod(s) de l'API réduit en place à $_S03_CPU"
}
# _s03_api_pretes N — au moins N pods de l'API de prod sont prêts.
_s03_api_pretes() {
  local n
  n="$(wb_kubectl -n "$_F3P_PROD" get pods -l "$_F3P_API_SEL" -o json 2>/dev/null </dev/null | jq '[.items[]
    | select(.metadata.deletionTimestamp == null)
    | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))] | length' 2>/dev/null)" || n=0
  ((${n:-0} >= $1))
}
_s03_v3_defaire() {
  local d p c res cur avant
  d="$(_f3p_etat S03)/v3"
  [[ -f "$d/pods" ]] || return 0
  while IFS=$'\t' read -r p c res; do
    cur="$(wb_kubectl -n "$_F3P_PROD" get pod "$p" -o json 2>/dev/null </dev/null | jq -r --arg c "$c" '[.spec.containers[] | select(.name == $c)][0].resources.limits.cpu // empty')" || cur=""
    # Pod disparu ou ressources déjà changées (réparation) : rien à faire.
    [[ "$cur" == "$_S03_CPU" ]] || continue
    avant="$(wb_kubectl -n "$_F3P_PROD" get pods -l "$_F3P_API_SEL" -o json 2>/dev/null </dev/null | jq '[.items[]
      | select(.metadata.deletionTimestamp == null)
      | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))] | length' 2>/dev/null)" || avant=1
    wb_kubectl -n "$_F3P_PROD" delete pod "$p" --wait=true --timeout=120s </dev/null >/dev/null 2>&1 ||
      wb_avert "pod $p ($_F3P_PROD) non supprimé : supprime-le toi-même (il sera recréé depuis le gabarit)"
    _f3p_attendre 240 _s03_api_pretes "${avant:-1}" </dev/null ||
      wb_avert "après la suppression de $p, l'API de prod n'a pas retrouvé $avant pod(s) prêt(s) : vérifie le Rollout"
    _f3p_journal S03 "pod $p (CPU réduit) recréé depuis le gabarit"
  done <"$d/pods"
  rm -rf -- "$d"
}

# --- Mécanique commune ----------------------------------------------------------------------------------

_f3p_S03_une() {
  case "$1" in
    1) _s03_v1_poser ;;
    2) _s03_v2_poser ;;
    3) _s03_v3_poser ;;
  esac
}
_f3p_S03_defaire() {
  case "$1" in
    1) _s03_v1_defaire ;;
    2) _s03_v2_defaire ;;
    3) _s03_v3_defaire ;;
  esac
}

_s03_injecter() {
  local ref
  _f3p_preparer S03 || return 1
  _f3p_cnpg_sain "$_F3P_PROD" || { echo "mediagenda-db (prod) n'est pas sain : $_F3P_REFUS" >&2; return 1; }
  [[ -r "$_F3P_RACINE" ]] || { echo "Racine MédiSphère illisible : $_F3P_RACINE (WB_RACINE_PKI)." >&2; return 1; }
  _f3p_sauvegarde_prod || return 1
  ref="$(_f3p_latence "$_F3P_URL_PROD" 9 3)"
  if _f3p_superieur "$ref" 1; then
    echo "MédiAgenda (prod) répond déjà lentement ($ref s) : $_F3P_REFUS" >&2
    return 1
  fi
  _f3p_ecrire S03 reference "$ref"
  _f3p_essayer S03 3 "$1"
}

panne_S03_v1() { _s03_injecter 1; }
panne_S03_v2() { _s03_injecter 2; }
panne_S03_v3() { _s03_injecter 3; }

verifier_S03() {
  local v ref med seuil
  v="$(_f3p_lire S03 variante)"
  if [[ "$v" == 2 ]]; then
    _s03_v2_constat
    return
  fi
  ref="$(_f3p_lire S03 reference)"
  seuil="$(awk -v r="${ref:-0.1}" 'BEGIN {s = 3 * r; if (s < 1.5) s = 1.5; print s}')"
  sleep 15
  med="$(_f3p_latence "$_F3P_URL_PROD" 10 5)"
  _f3p_journal S03 "constat : médiane $med s (référence $ref s, seuil $seuil s)"
  _f3p_superieur "$med" "$seuil"
}

annuler_S03() {
  local v
  for v in 1 2 3; do _f3p_S03_defaire "$v" || true; done
  _f3p_oublier S03 variante
  _f3p_oublier S03 reference
}

resume_S03() { echo "MédiAgenda (production) très lent pour les cabinets"; }

symptome_S03() {
  local l2
  if [[ "$(_f3p_lire S03 variante)" == 2 ]]; then
    l2="Julien ajoute : « La base de prod n'a jamais reçu autant de requêtes, alors qu'on n'a rien livré. »"
  else
    l2="Julien ajoute : « On n'a rien livré depuis jeudi. Ça ne vient pas de nous. »"
  fi
  _f3p_symptome S03 INC-5903 "Ticket INC-5903 — De : support MédiSphère (file de Nadia Roussel) — lundi 9 h 10" \
    "Trois cabinets ont appelé depuis 9 h : « MédiAgenda met 10 secondes à afficher l'agenda »," \
    "« quand je change de jour, ça tourne ». Les prises de rendez-vous passent, mais lentement." \
    "Le standard en reçoit d'autres. Aucune alerte n'est arrivée sur le téléphone d'astreinte." \
    "$l2" \
    "Environnement : PRODUCTION (mediagenda-prod). Temps cible : 45 min jusqu'au rétablissement."
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main F3 S03 3 "$@"; }
fi
