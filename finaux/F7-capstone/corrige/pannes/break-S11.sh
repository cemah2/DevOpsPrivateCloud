# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# break-S11.sh — F7-S11 « Panne : la démonstration sous incidents » (journée de jeu pendant la
# démonstration au GHSV, sous charge k6). Trois incidents SUCCESSIFS sur le locataire du client : le
# premier est injecté tout de suite ; un « meneur de jeu » en arrière-plan injecte le suivant quand le
# précédent est réparé ET qu'au moins WB_F7_S11_DELAI_S secondes sont passées, puis prévient le support
# par courriel (Mailpit), comme un utilisateur du GHSV.
#
# Incidents (tous bornés à l'espace ghsv-prod et au fournisseur ghsv-idp du royaume medisphere) :
#   reseau      CiliumNetworkPolicy « protection-donnees-ghsv » (par « Lucas ») qui INTERDIT la sortie de
#               l'API vers la base (egressDeny 5432) → /pret en 503, plus rien ne passe ;
#   route       la route publique « mediagenda » modifiée en direct (port du backend 80 → 8080) → la
#               Gateway répond 500 sur le nom public ; les agents ne voient rien ;
#   cache       le StatefulSet Valkey de ghsv-prod à 0 réplica → /pret exige Valkey : l'API sort du
#               Service alors que la base va bien (le cache est devenu critique sans qu'on le veuille) ;
#   identite    le mappeur de groupe du fournisseur ghsv-idp attend un groupe mal orthographié → à leur
#               reconnexion (≤ 15 min), les agents n'ont plus ghsv-agents : 403 du mandataire ;
#   mandataire  le mandataire du DPI n'accepte plus les jetons porteurs (skip_jwt_bearer_tokens à false
#               dans sa ConfigMap), pods redémarrés → tous les appels du DPI en 401 (api_routes), alors
#               que /pret reste vert.
# Variantes (séquences) : 1 route → cache → identite ; 2 reseau → mandataire → identite ;
#                         3 cache → route → mandataire ; 4 identite → reseau → cache.
# Un incident « sans effet » sur ce lab (objet introuvable : ton implémentation diffère) est sauté ; le
# PREMIER doit réussir, sinon rien n'est injecté.
#
# Règles (CONVENTIONS §8, §11.10-11.11 ; PLAN §4.12-§4.15) : contrôle préalable (lab sain, charge de
# démonstration en cours) ; rien hors de ghsv-prod et du fournisseur ghsv-idp ; jamais le royaume master,
# jamais un compte ; aucune donnée supprimée (Valkey : PVC conservé ; aucune base touchée) ; chaque objet
# est exporté avant modification ; --annuler arrête le meneur (drapeau d'arrêt, puis tout son groupe de
# processus, attente de sa fin) AVANT de défaire, et ne défait QUE ce qui est encore dans l'état injecté
# (une réparation de l'apprenant n'est jamais défaite). Il fonctionne aussi si le meneur a été tué ou si
# adm01 a redémarré : l'état de chaque incident est écrit AVANT la modification.
# Bornes : refus si l'espace visé n'est pas « ghsv-… » ou si le fournisseur n'est pas « ghsv-… ».
# État local : ~/.local/state/workbook/F7-S11/ (700) et ~/.local/state/workbook/k8s/F7-S11/.
# Outils sur adm01 : kubectl (WB_K8S_ADMIN_KUBECONFIG), jq, curl.
# Variables : WB_F7_S11_DELAI_S (défaut 300), WB_F7_S11_DUREE_MAX_S (défaut 7200), WB_F7_CLIENT (ghsv),
#   WB_F7_URL_PROD, WB_F7_IDP_ALIAS (ghsv-idp), WB_F7_KC_ADMIN_FILE (défaut
#   ~/.config/workbook/keycloak-tofu.env : client svc-tofu-keycloak, M24-E08), WB_F7_S11_SMTP
#   (défaut smtp.par1.medisphere.internal:25), WB_F7_S11_COURRIEL (défaut support@medisphere.internal).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"

_S11_CLIENT="${WB_F7_CLIENT:-ghsv}"
_S11_NS="${_S11_CLIENT}-prod"
_S11_URL="${WB_F7_URL_PROD:-https://ghsv.apps.par1.medisphere.internal}"
_S11_ALIAS="${WB_F7_IDP_ALIAS:-ghsv-idp}"
_S11_SSO="${WB_KEYCLOAK_URL:-https://sso.par1.medisphere.internal}"
_S11_KC_FICHIER="${WB_F7_KC_ADMIN_FILE:-$HOME/.config/workbook/keycloak-tofu.env}"
_S11_DELAI="${WB_F7_S11_DELAI_S:-300}"
_S11_DUREE_MAX="${WB_F7_S11_DUREE_MAX_S:-7200}"
_S11_SMTP="${WB_F7_S11_SMTP:-smtp.par1.medisphere.internal:25}"
_S11_COURRIEL="${WB_F7_S11_COURRIEL:-support@medisphere.internal}"
_S11_API_SEL='app.kubernetes.io/name=mediagenda,app.kubernetes.io/component=api'
_S11_CNP=protection-donnees-ghsv
_S11_ETIQ='medisphere.internal/panne=F7-S11'

# _s11_borne — la panne ne touche QUE un espace ghsv-… et un fournisseur ghsv-… (variables WB_F7_*
# mal réglées : refus, plutôt que de casser mediagenda-prod).
_s11_borne() {
  [[ "$_S11_NS" =~ ^ghsv-[a-z0-9-]+$ && "$_S11_ALIAS" =~ ^ghsv-[a-z0-9-]+$ ]] && return 0
  echo "F7-S11 ne vise que les espaces et le fournisseur du GHSV (ghsv-…) : espace « $_S11_NS », fournisseur « $_S11_ALIAS » refusés." >&2
  return 1
}
_s11_arret_demande() { [[ -e "$(_s11_etat)/arret" ]]; }

# ---------------------------------------------------------------------------
# État local
# ---------------------------------------------------------------------------
_s11_etat() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/F7-S11"
  mkdir -p "$d" && chmod 700 "$d"
  printf '%s\n' "$d"
}
_s11_poser() { (umask 077 && printf '%s\n' "$2" >"$(_s11_etat)/$1"); }
_s11_lire() {
  local f
  f="$(_s11_etat)/$1"
  if [[ -f "$f" ]]; then cat "$f"; fi
}
_s11_oublier() { rm -f -- "$(_s11_etat)/$1"; }
_s11_journal() { printf '%s [F7-S11 variante %s] %s\n' "$(date -Is)" "${WB_VAR:-?}" "$*" >>"$(_s11_etat)/journal"; }

_s11_attendre() {
  local max="$1" t=0
  shift
  while ((t < max)); do
    if "$@"; then return 0; fi
    sleep 10
    t=$((t + 10))
  done
  "$@"
}

_s11_code_pret() { curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$_S11_URL/pret" 2>/dev/null || true; }

# ---------------------------------------------------------------------------
# Keycloak : API d'administration du royaume medisphere SEULEMENT (fournisseur du client)
# ---------------------------------------------------------------------------
_S11_KC_JETON=""
_S11_KC_T=0
_s11_kc_jeton() {
  local KEYCLOAK_CLIENT_ID="" KEYCLOAK_CLIENT_SECRET="" r
  if [[ -n "$_S11_KC_JETON" ]] && (($(date +%s) - _S11_KC_T < 40)); then return 0; fi
  [[ -r "$_S11_KC_FICHIER" ]] || return 1
  # shellcheck disable=SC1090
  source "$_S11_KC_FICHIER"
  r="$(curl -sf --max-time 20 -K <(printf 'user = "%s:%s"\n' "$KEYCLOAK_CLIENT_ID" "$KEYCLOAK_CLIENT_SECRET") \
    -d grant_type=client_credentials "$_S11_SSO/realms/master/protocol/openid-connect/token" 2>/dev/null |
    jq -r '.access_token // empty' 2>/dev/null)" || r=""
  [[ -n "$r" ]] || return 1
  _S11_KC_JETON="$r"
  _S11_KC_T="$(date +%s)"
}

# _s11_kc MÉTHODE CHEMIN [options curl] — /admin/realms/medisphere/identity-provider/instances/<alias>/CHEMIN
_s11_kc() {
  local m="$1" p="$2"
  shift 2
  [[ "$p" != *..* ]] || return 1
  _s11_kc_jeton || return 1
  curl -sS --fail --max-time 30 -X "$m" -K <(printf 'header = "Authorization: Bearer %s"\n' "$_S11_KC_JETON") \
    -H 'Accept: application/json' "$_S11_SSO/admin/realms/medisphere/identity-provider/instances/$_S11_ALIAS${p:+/$p}" "$@"
}

# Mappeur de groupe du fournisseur : « Advanced Claim to Group », sinon « Claim to Group ».
_s11_mappeur() {
  _s11_kc GET mappers 2>/dev/null | jq -c '
    ([.[] | select(.identityProviderMapper == "oidc-advanced-group-idp-mapper")] +
     [.[] | select(.identityProviderMapper | test("group"))])[0] // empty' 2>/dev/null
}

# ---------------------------------------------------------------------------
# Contrôle préalable : le lab doit être sain et la démonstration lancée
# ---------------------------------------------------------------------------
_s11_api_pretes() {
  wb_kubectl -n "$_S11_NS" get pods -l "$_S11_API_SEL" -o json 2>/dev/null |
    jq '[.items[] | select(.metadata.deletionTimestamp == null)
      | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))] | length' 2>/dev/null || echo 0
}

_s11_app() {
  wb_kubectl -n argocd get applications.argoproj.io -o json 2>/dev/null |
    jq -r --arg ns "$_S11_NS" '[.items[] | select(.spec.destination.namespace == $ns) | .metadata.name][0] // empty'
}

_s11_charge_en_cours() {
  wb_kubectl -n k6 get testruns.k6.io -o json 2>/dev/null |
    jq -e 'any(.items[]; ((.spec.arguments // "") | test("testid=demo-ghsv")) and ((.status.stage // "") == "started"))' >/dev/null 2>&1
}

_s11_sain() {
  local c a
  _s11_borne || return 1
  for c in kubectl jq curl; do
    command -v "$c" >/dev/null 2>&1 || { echo "outil manquant sur adm01 : $c" >&2; return 1; }
  done
  wb_kubectl get --raw /readyz >/dev/null 2>&1 || { echo "L'API de k8s-par1 ne répond pas avec ${WB_K8S_ADMIN_KUBECONFIG:-~/.kube/config}." >&2; return 1; }
  if (($(_s11_api_pretes) < 2)); then
    echo "Il faut au moins deux pods prêts de l'API dans $_S11_NS." >&2
    return 1
  fi
  [[ "$(_s11_code_pret)" == 200 ]] || { echo "$_S11_URL/pret ne répond pas 200 : répare d'abord l'instance du client." >&2; return 1; }
  a="$(_s11_app)"
  if [[ -z "$a" ]] || ! wb_kubectl -n argocd get applications.argoproj.io "$a" -o json 2>/dev/null |
    jq -e '.status.sync.status == "Synced" and .status.health.status == "Healthy"' >/dev/null 2>&1; then
    echo "L'Application Argo CD de $_S11_NS doit être Synced/Healthy." >&2
    return 1
  fi
  _s11_poser app "$a"
  _s11_charge_en_cours || { echo "Aucune charge de démonstration en cours (TestRun k6 « testid=demo-ghsv… » à l'étape started)." >&2; return 1; }
  if wb_kubectl -n "$_S11_NS" get ciliumnetworkpolicies.cilium.io "$_S11_CNP" >/dev/null 2>&1; then
    echo "Une politique $_S11_CNP existe déjà : lance d'abord lab/bin/break F7 11 --annuler." >&2
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Incident « reseau » : la sortie de l'API vers la base est interdite
# ---------------------------------------------------------------------------
_s11_reseau_injecter() {
  local grappe
  grappe="$(wb_kubectl -n "$_S11_NS" get clusters.postgresql.cnpg.io -o json 2>/dev/null | jq -r '.items[0].metadata.name // empty')"
  [[ -n "$grappe" ]] || return 10
  wb_k8s_sauver ciliumnetworkpolicies.cilium.io "$_S11_CNP" "$_S11_NS"
  cat <<EOF | wb_kubectl apply -f - >/dev/null || return 1
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: $_S11_CNP
  namespace: $_S11_NS
  labels: {medisphere.internal/auteur: lucas.martin, medisphere.internal/panne: F7-S11}
  annotations:
    medisphere.internal/note: "Durcissement : l'API ne parle à la base que par le pooler (Lucas, à valider)"
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: mediagenda
      app.kubernetes.io/component: api
  egressDeny:
    - toEndpoints:
        - matchLabels:
            cnpg.io/cluster: $grappe
      toPorts:
        - ports: [{port: "5432", protocol: TCP}]
EOF
  _s11_journal "reseau : CNP $_S11_NS/$_S11_CNP (egressDeny API → $grappe:5432)"
  # Une nouvelle politique Cilium ne coupe pas forcément les connexions DÉJÀ établies (réserve de
  # connexions de l'API) : « Lucas » redémarre les pods de l'API pour « prendre en compte » sa règle
  # (suppression des pods, pas « rollout restart » : aucune trace dans le Deployment).
  if ! _s11_attendre 30 _s11_reseau_actif; then
    wb_kubectl -n "$_S11_NS" delete pods -l "$_S11_API_SEL" --wait=false >/dev/null 2>&1 || return 1
    _s11_journal "reseau : pods de l'API supprimés (connexions établies)"
  fi
  _s11_attendre 150 _s11_reseau_actif || return 1
}
_s11_reseau_actif() {
  wb_kubectl -n "$_S11_NS" get ciliumnetworkpolicies.cilium.io "$_S11_CNP" -o json 2>/dev/null |
    jq -e '.metadata.labels["medisphere.internal/panne"] == "F7-S11" and (.spec.egressDeny | length) > 0' >/dev/null 2>&1 &&
    [[ "$(_s11_code_pret)" != 200 ]]
}
_s11_reseau_present() {
  wb_kubectl -n "$_S11_NS" get ciliumnetworkpolicies.cilium.io "$_S11_CNP" -o json 2>/dev/null |
    jq -e '.metadata.labels["medisphere.internal/panne"] == "F7-S11" and (.spec.egressDeny | length) > 0' >/dev/null 2>&1
}
_s11_reseau_defaire() {
  if _s11_reseau_present; then
    wb_kubectl -n "$_S11_NS" delete ciliumnetworkpolicies.cilium.io "$_S11_CNP" --ignore-not-found >/dev/null 2>&1 || true
    _s11_journal "annulation : CNP $_S11_CNP supprimée"
  fi
}

# ---------------------------------------------------------------------------
# Incident « route » : port du backend de la route publique modifié en direct
# ---------------------------------------------------------------------------
_s11_route_injecter() {
  local port
  port="$(wb_kubectl -n "$_S11_NS" get httproutes.gateway.networking.k8s.io mediagenda -o json 2>/dev/null |
    jq -r '.spec.rules[0].backendRefs[0].port // empty')"
  [[ "$port" =~ ^[0-9]+$ && "$port" != 8080 ]] || return 10
  wb_kubectl -n "$_S11_NS" get httproutes.gateway.networking.k8s.io mediagenda -o json >"$(_s11_etat)/route.json" 2>/dev/null || return 1
  _s11_poser route-port "$port"
  wb_kubectl -n "$_S11_NS" patch httproutes.gateway.networking.k8s.io mediagenda --type=json \
    -p '[{"op":"replace","path":"/spec/rules/0/backendRefs/0/port","value":8080}]' >/dev/null || return 1
  _s11_journal "route : backend de la route mediagenda $port → 8080"
  _s11_attendre 90 _s11_route_actif || return 1
}
_s11_route_present() {
  [[ "$(wb_kubectl -n "$_S11_NS" get httproutes.gateway.networking.k8s.io mediagenda -o json 2>/dev/null |
    jq -r '.spec.rules[0].backendRefs[0].port // empty')" == 8080 ]]
}
_s11_route_actif() { _s11_route_present && [[ "$(_s11_code_pret)" != 200 ]]; }
_s11_route_defaire() {
  local port
  port="$(_s11_lire route-port)"
  if [[ -n "$port" ]] && _s11_route_present; then
    wb_kubectl -n "$_S11_NS" patch httproutes.gateway.networking.k8s.io mediagenda --type=json \
      -p "[{\"op\":\"replace\",\"path\":\"/spec/rules/0/backendRefs/0/port\",\"value\":$port}]" >/dev/null 2>&1 || true
    _s11_journal "annulation : backend de la route remis à $port"
  fi
  _s11_oublier route-port
}

# ---------------------------------------------------------------------------
# Incident « cache » : Valkey de ghsv-prod à 0 réplica (PVC conservé)
# ---------------------------------------------------------------------------
_s11_valkey() {
  wb_kubectl -n "$_S11_NS" get statefulsets -o json 2>/dev/null |
    jq -r '[.items[] | select(.metadata.name == "valkey" or (.metadata.labels["app.kubernetes.io/name"] // "") == "valkey") | .metadata.name][0] // empty'
}
_s11_cache_injecter() {
  local sts n
  sts="$(_s11_valkey)"
  [[ -n "$sts" ]] || return 10
  n="$(wb_kubectl -n "$_S11_NS" get statefulset "$sts" -o jsonpath='{.spec.replicas}' 2>/dev/null)"
  [[ "$n" =~ ^[1-9][0-9]*$ ]] || return 10
  _s11_poser cache "$sts $n"
  wb_kubectl -n "$_S11_NS" scale statefulset "$sts" --replicas=0 >/dev/null || return 1
  _s11_journal "cache : statefulset $sts $n → 0 (PVC conservé)"
  _s11_attendre 120 _s11_cache_actif || return 1
}
_s11_cache_present() {
  local sts n
  read -r sts n <<<"$(_s11_lire cache)"
  [[ -n "${sts:-}" ]] || return 1
  [[ "$(wb_kubectl -n "$_S11_NS" get statefulset "$sts" -o jsonpath='{.spec.replicas}' 2>/dev/null)" == 0 ]]
}
_s11_cache_actif() { _s11_cache_present && [[ "$(_s11_code_pret)" != 200 ]]; }
_s11_cache_defaire() {
  local sts n
  read -r sts n <<<"$(_s11_lire cache)"
  if [[ -n "${sts:-}" ]] && _s11_cache_present; then
    wb_kubectl -n "$_S11_NS" scale statefulset "$sts" --replicas="$n" >/dev/null 2>&1 || true
    _s11_journal "annulation : statefulset $sts remis à $n"
  fi
  _s11_oublier cache
}

# ---------------------------------------------------------------------------
# Incident « identite » : groupe attendu du GHSV mal orthographié dans le mappeur
# ---------------------------------------------------------------------------
_s11_identite_injecter() {
  local m neuf id
  m="$(_s11_mappeur)"
  [[ -n "$m" ]] || return 10
  id="$(jq -r '.id' <<<"$m")"
  (umask 077 && printf '%s\n' "$m" >"$(_s11_etat)/mappeur.json")
  # « claims » (Advanced Claim to Group, JSON en texte) ou « claim.value » (Claim to Group).
  neuf="$(jq -c '
    if (.config.claims // "") != "" then
      .config.claims |= (fromjson | map(.value += "e") | tojson)
    elif (.config["claim.value"] // "") != "" then
      .config["claim.value"] += "e"
    else empty end' <<<"$m")"
  [[ -n "$neuf" ]] || return 10
  (umask 077 && printf '%s\n' "$neuf" >"$(_s11_etat)/mappeur-injecte.json")
  _s11_kc PUT "mappers/$id" -H 'Content-Type: application/json' --data-binary "$neuf" >/dev/null || return 1
  _s11_journal "identite : mappeur $(jq -r '.name' <<<"$m") du fournisseur $_S11_ALIAS (groupe attendu altéré)"
  _s11_identite_present
}
_s11_identite_present() {
  local id actuel injecte
  [[ -s "$(_s11_etat)/mappeur-injecte.json" ]] || return 1
  id="$(jq -r '.id' "$(_s11_etat)/mappeur-injecte.json")"
  actuel="$(_s11_kc GET "mappers/$id" 2>/dev/null | jq -cS '.config' 2>/dev/null)" || return 1
  injecte="$(jq -cS '.config' "$(_s11_etat)/mappeur-injecte.json")"
  [[ -n "$actuel" && "$actuel" == "$injecte" ]]
}
_s11_identite_actif() { _s11_identite_present; }
_s11_identite_defaire() {
  local id
  if [[ -s "$(_s11_etat)/mappeur.json" ]] && _s11_identite_present; then
    id="$(jq -r '.id' "$(_s11_etat)/mappeur.json")"
    _s11_kc PUT "mappers/$id" -H 'Content-Type: application/json' --data-binary @"$(_s11_etat)/mappeur.json" >/dev/null 2>&1 ||
      wb_avert "mappeur du fournisseur $_S11_ALIAS non rétabli (export : $(_s11_etat)/mappeur.json)"
    _s11_journal "annulation : mappeur rétabli"
  fi
  rm -f -- "$(_s11_etat)/mappeur.json" "$(_s11_etat)/mappeur-injecte.json"
}

# ---------------------------------------------------------------------------
# Incident « mandataire » : le mandataire du DPI n'accepte plus les jetons porteurs
# ---------------------------------------------------------------------------
# ConfigMap de ghsv-prod dont une clé active « skip_jwt_bearer_tokens » (mandataire du DPI).
_s11_cm_dpi() {
  wb_kubectl -n "$_S11_NS" get configmaps -o json 2>/dev/null |
    jq -r '[.items[] | . as $c | (.data // {}) | to_entries[]
      | select(.value | test("(^|\n)[ \t]*skip_jwt_bearer_tokens[ \t]*=[ \t]*true"))
      | "\($c.metadata.name) \(.key)"][0] // empty'
}
_s11_deploiements_cm() {
  wb_kubectl -n "$_S11_NS" get deployments -o json 2>/dev/null |
    jq -r --arg cm "$1" '.items[] | select(any(.spec.template.spec.volumes[]?; .configMap.name == $cm)) | .metadata.name'
}
_s11_mandataire_injecter() {
  local l cm cle d
  l="$(_s11_cm_dpi)"
  [[ -n "$l" ]] || return 10
  read -r cm cle <<<"$l"
  wb_kubectl -n "$_S11_NS" get configmap "$cm" -o json >"$(_s11_etat)/cm-dpi.json" 2>/dev/null || return 1
  _s11_poser mandataire "$cm $cle"
  jq --arg k "$cle" '.data[$k] |= sub("(?<a>(^|\n)[ \t]*skip_jwt_bearer_tokens[ \t]*=[ \t]*)true"; "\(.a)false")' \
    "$(_s11_etat)/cm-dpi.json" | wb_kubectl replace -f - >/dev/null || return 1
  for d in $(_s11_deploiements_cm "$cm"); do
    wb_kubectl -n "$_S11_NS" rollout restart deployment "$d" >/dev/null 2>&1 || true
  done
  _s11_journal "mandataire : jetons porteurs refusés dans $cm (skip_jwt_bearer_tokens = false), pods redémarrés"
  _s11_attendre 150 _s11_mandataire_actif
}
_s11_mandataire_present() {
  local cm cle
  read -r cm cle <<<"$(_s11_lire mandataire)"
  [[ -n "${cm:-}" ]] || return 1
  wb_kubectl -n "$_S11_NS" get configmap "$cm" -o json 2>/dev/null |
    jq -e --arg k "$cle" '.data[$k] | test("(^|\n)[ \t]*skip_jwt_bearer_tokens[ \t]*=[ \t]*false")' >/dev/null 2>&1
}
# Actif : configuration altérée ET tous les pods des mandataires concernés recréés depuis (déploiement
# terminé : les nouveaux pods ont lu la ConfigMap altérée).
_s11_mandataire_actif() {
  local cm cle d
  _s11_mandataire_present || return 1
  read -r cm cle <<<"$(_s11_lire mandataire)"
  for d in $(_s11_deploiements_cm "$cm"); do
    wb_kubectl -n "$_S11_NS" rollout status deployment "$d" --timeout=5s >/dev/null 2>&1 || return 1
  done
}
_s11_mandataire_defaire() {
  local cm cle d
  read -r cm cle <<<"$(_s11_lire mandataire)"
  if [[ -n "${cm:-}" ]] && _s11_mandataire_present; then
    wb_kubectl -n "$_S11_NS" get configmap "$cm" -o json 2>/dev/null |
      jq --arg k "$cle" '.data[$k] |= sub("(?<a>(^|\n)[ \t]*skip_jwt_bearer_tokens[ \t]*=[ \t]*)false"; "\(.a)true")' |
      wb_kubectl replace -f - >/dev/null 2>&1 || wb_avert "ConfigMap $cm non rétablie (copie : $(_s11_etat)/cm-dpi.json)"
    for d in $(_s11_deploiements_cm "$cm"); do
      wb_kubectl -n "$_S11_NS" rollout restart deployment "$d" >/dev/null 2>&1 || true
    done
    _s11_journal "annulation : jetons porteurs de nouveau acceptés par le mandataire"
  fi
  _s11_oublier mandataire
}

# ---------------------------------------------------------------------------
# Séquences, meneur de jeu, courriels
# ---------------------------------------------------------------------------
_s11_sequence() {
  case "$1" in
    1) echo "route cache identite" ;;
    2) echo "reseau mandataire identite" ;;
    3) echo "cache route mandataire" ;;
    *) echo "identite reseau cache" ;;
  esac
}

_s11_message() {
  case "$1" in
    reseau) printf '%s\n' "Objet : la démonstration est bloquée" \
      "Plus aucune page de prise de rendez-vous ne répond depuis quelques minutes, et notre DPI remonte des erreurs" \
      "« 503 » en série. Mes agents sont aussi bloqués. — Élodie Marchand, DSI du GHSV" ;;
    route) printf '%s\n' "Objet : l'API du DPI répond en erreur" \
      "Notre éditeur de DPI voit des erreurs 500 sur toutes les opérations depuis quelques minutes ; nos secrétaires," \
      "elles, travaillent normalement dans l'interface des agents. — Élodie Marchand, DSI du GHSV" ;;
    cache) printf '%s\n' "Objet : tout est tombé ?" \
      "La prise de rendez-vous ne répond plus du tout. Vos tableaux disent que la base va bien, paraît-il. — Élodie Marchand, DSI du GHSV" ;;
    identite) printf '%s\n' "Objet : nos secrétaires n'ont plus accès" \
      "Depuis un quart d'heure, les secrétaires qui se reconnectent tombent sur une page « 403 Forbidden » après la" \
      "double authentification. Celles qui étaient déjà connectées travaillaient… jusqu'à il y a peu. — Élodie Marchand" ;;
    mandataire) printf '%s\n' "Objet : le DPI est refusé" \
      "Notre DPI reçoit des 401 sur toutes ses requêtes alors que son jeton est tout neuf, et votre page de" \
      "disponibilité dit que tout va bien. — Élodie Marchand, DSI du GHSV" ;;
  esac
}

# _s11_courriel INCIDENT — message de l'utilisateur au support (Mailpit), sans bloquer en cas d'échec.
_s11_courriel() {
  {
    printf 'From: Élodie Marchand <elodie.marchand@ghsv.example>\r\nTo: %s\r\n' "$_S11_COURRIEL"
    printf 'Subject: [GHSV] %s\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\n' "$(_s11_message "$1" | head -n 1 | sed 's/^Objet : //')"
    _s11_message "$1" | tail -n +2
  } | curl -s --max-time 20 --ssl-reqd --url "smtp://$_S11_SMTP" --mail-from elodie.marchand@ghsv.example \
    --mail-rcpt "$_S11_COURRIEL" --upload-file - >/dev/null 2>&1 || true
}

_s11_injecter() { "_s11_${1}_injecter"; }
_s11_actif() { "_s11_${1}_actif"; }
_s11_present() { "_s11_${1}_present"; }
_s11_defaire() { "_s11_${1}_defaire"; }

# Meneur de jeu (arrière-plan) : injecte les incidents 2 et 3 de la séquence.
_s11_meneur() {
  local debut t0 i p rc
  debut="$(date +%s)"
  t0="$debut"
  for i in 2 3; do
    p="$(_s11_lire "incident-$((i - 1))")"
    # Attendre la réparation du précédent ET le délai minimal.
    while :; do
      _s11_arret_demande && { _s11_journal "meneur : arrêt demandé, fin"; return 0; }
      (($(date +%s) - debut > _S11_DUREE_MAX)) && { _s11_journal "meneur : durée maximale atteinte, fin"; return 0; }
      if [[ -z "$p" ]] || ! _s11_present "$p"; then
        (($(date +%s) - t0 >= _S11_DELAI)) && break
      fi
      sleep 20
    done
    # Lab redevenu sain avant l'incident suivant (sinon on attend encore un peu, puis on abandonne).
    _s11_attendre 300 _s11_sain_leger || { _s11_journal "meneur : instance non saine, fin sans injection"; return 0; }
    for p in $(_s11_lire "reste"); do
      _s11_arret_demande && { _s11_journal "meneur : arrêt demandé, fin"; return 0; }
      _s11_poser reste "$(_s11_lire reste | sed "s/^$p *//")"
      rc=0
      _s11_injecter "$p" || rc=$?
      if ((rc == 0)); then
        _s11_poser "incident-$i" "$p"
        _s11_journal "meneur : incident $i ($p) injecté"
        _s11_courriel "$p"
        t0="$(date +%s)"
        break
      fi
      _s11_defaire "$p"
      _s11_journal "meneur : incident $p sans effet ici (code $rc), suivant"
    done
  done
  _s11_journal "meneur : fin de la séquence"
}

_s11_sain_leger() { (($(_s11_api_pretes) >= 1)) && [[ "$(_s11_code_pret)" == 200 ]]; }

# _s11_debut_processus PID — date de démarrage du processus (champ 22 de /proc/PID/stat) : distingue
# le meneur d'un processus qui aurait repris son numéro après un redémarrage d'adm01.
_s11_debut_processus() {
  local st
  st="$(cat "/proc/$1/stat" 2>/dev/null)" || return 1
  st="${st##*) }"
  awk '{ print $20 }' <<<"$st"
}

_s11_lancer_meneur() {
  local d pid
  d="$(_s11_etat)"
  rm -f -- "$d/arret"
  # « set -m » : le meneur dans SON groupe de processus (numéro = son PID), pour que --annuler l'arrête
  # avec tous ses enfants (kubectl, curl, sleep), sans toucher au reste de la session.
  set -m
  (
    # Hérité de lab/bin/break : « set -e » arrêterait le meneur au premier contrôle négatif.
    set +e +o pipefail
    trap '' HUP
    _s11_meneur
    rm -f -- "$d/meneur.pid"
  ) </dev/null >>"$d/meneur.log" 2>&1 &
  pid=$!
  set +m
  printf '%s %s\n' "$pid" "$(_s11_debut_processus "$pid")" >"$d/meneur.pid"
  disown "$pid" 2>/dev/null || true
}

_s11_arreter_meneur() {
  local pid debut i
  # 1. Drapeau d'arrêt : le meneur ne lance plus aucune injection, même s'il n'est pas encore tué.
  (umask 077 && : >"$(_s11_etat)/arret")
  read -r pid debut <<<"$(_s11_lire meneur.pid)"
  if [[ "${pid:-}" =~ ^[0-9]+$ && -n "${debut:-}" && "$(_s11_debut_processus "$pid" 2>/dev/null)" == "$debut" ]]; then
    # 2. Tout le groupe de processus du meneur, puis attente de sa fin (au plus 30 s, puis KILL) :
    #    aucune modification ne peut arriver APRÈS l'annulation.
    kill -TERM -- "-$pid" 2>/dev/null || true
    for ((i = 0; i < 30; i++)); do
      kill -0 -- "-$pid" 2>/dev/null || break
      sleep 1
    done
    if kill -0 -- "-$pid" 2>/dev/null; then
      kill -KILL -- "-$pid" 2>/dev/null || true
      sleep 1
    fi
    _s11_journal "meneur $pid arrêté"
  fi
  _s11_oublier meneur.pid
}

# ---------------------------------------------------------------------------
# Points d'entrée de pannes-lib
# ---------------------------------------------------------------------------
_s11_demarrer() {
  local seq p rc
  _s11_sain || return 1
  _s11_oublier arret
  seq="$(_s11_sequence "$1")"
  _s11_poser sequence "$seq"
  _s11_poser reste "$seq"
  for p in $seq; do
    _s11_poser reste "$(_s11_lire reste | sed "s/^$p *//")"
    rc=0
    _s11_injecter "$p" || rc=$?
    if ((rc == 0)); then
      _s11_poser incident-1 "$p"
      _s11_lancer_meneur
      return 0
    fi
    _s11_defaire "$p"
    ((rc == 10)) || return 1
    _s11_journal "incident $p sans effet ici, suivant"
  done
  wb_avert "aucun incident de F7-S11 n'a d'effet sur ce lab (noms des objets du client différents ?)"
  return 1
}

panne_S11_v1() { _s11_demarrer 1; }
panne_S11_v2() { _s11_demarrer 2; }
panne_S11_v3() { _s11_demarrer 3; }
panne_S11_v4() { _s11_demarrer 4; }

verifier_S11() {
  local p
  p="$(_s11_lire incident-1)"
  [[ -n "$p" ]] && _s11_actif "$p"
}

annuler_S11() {
  local p
  _s11_arreter_meneur
  if _s11_borne 2>/dev/null; then
    for p in reseau route cache identite mandataire; do
      _s11_defaire "$p" || true
    done
    wb_k8s_restaurer >/dev/null 2>&1 || true
  else
    wb_avert "variables WB_F7_* hors du GHSV : rien n'est défait (état gardé dans $(_s11_etat))"
  fi
  _s11_oublier incident-1
  _s11_oublier incident-2
  _s11_oublier incident-3
  _s11_oublier reste
  _s11_oublier sequence
  _s11_oublier app
  # Le drapeau « arret » reste posé jusqu'à la prochaine injection (un meneur qui aurait survécu ne
  # reprendrait pas la main).
  _s11_journal "annulation terminée"
}

resume_S11() {
  case "$(_s11_lire incident-1)" in
    reseau) echo "Pendant la démonstration, la prise de rendez-vous du GHSV ne répond plus (503)." ;;
    route) echo "Pendant la démonstration, l'API du DPI du GHSV répond 500 ; les agents travaillent." ;;
    cache) echo "Pendant la démonstration, la prise de rendez-vous du GHSV ne répond plus alors que la base va bien." ;;
    identite) echo "Pendant la démonstration, les agents du GHSV qui se reconnectent reçoivent un 403." ;;
    *) echo "Pendant la démonstration, le DPI du GHSV reçoit des 401." ;;
  esac
}

symptome_S11() {
  local p
  p="$(_s11_lire incident-1)"
  mapfile -t lignes < <(_s11_message "$p")
  wb_symptome "Journée de jeu PLAT-3711 — démonstration au GHSV, incident 1" \
    "Karim : « C'est parti. Élodie vient d'écrire au support : »" "" \
    "${lignes[@]}" "" \
    "D'autres incidents suivront, un par un, après chaque réparation : ta supervision et la boîte" \
    "$_S11_COURRIEL (Mailpit) te les signaleront. La démonstration continue." \
    "" \
    "Temps cible : 20 min par incident. Fin ou abandon : lab/bin/break F7 11 --annuler" \
    "Contrôle : lab/bin/check F7 11"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main F7 S11 4 "$@"; }
fi
