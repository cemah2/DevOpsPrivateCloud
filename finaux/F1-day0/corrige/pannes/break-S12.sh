# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# break-S12.sh — F1-S12 « Panne : la reconstruction coince » (après F1-S11).
#
# Trois restes typiques d'un Day 0, une variante tirée au hasard (une variante « sans effet » sur le
# lab est défaite et la suivante essayée) :
#   1. CONFIANCE : la configuration de la méthode k8s-par1 d'OpenBao est réécrite avec l'autorité de
#      l'ANCIEN cluster (version précédente de racine/k8s-par1-ca.crt dans l'historique de
#      plateforme/secrets ; à défaut, une autorité « kubernetes » jetable, même effet). Les jetons
#      d'OpenBao déjà délivrés ne sont PAS révoqués (leurs baux, dont les identifiants dynamiques de
#      la production, restent valides) : ESO se connecte à chaque synchronisation, la vérification TLS
#      de l'appel TokenReview échoue, les ExternalSecrets passent en erreur à leur rafraîchissement
#      (forcé sur mediagenda-recette/harbor-pull seulement).
#   2. PROPRIÉTÉ : dans la zone apps.par1.medisphere.internal, l'enregistrement TXT de propriété
#      d'ExternalDNS du nom portail.apps… passe au propriétaire « k8s-par1-essai » et son A vise
#      10.10.41.20 (plage des essais) : ExternalDNS (propriétaire k8s-par1) refuse de corriger un nom
#      qui ne lui appartient plus ; le portail ne répond plus. Écriture par l'API de PowerDNS
#      (~/.config/workbook/powerdns-api.env), sauvegarde des RRsets avant.
#   3. OBJET RESTAURÉ : ValidatingWebhookConfiguration « kyverno-resource-validating-webhook-cfg-restauree »
#      (étiquettes de restauration Velero, gestionnaire de champs velero-server) en failurePolicy Fail,
#      limitée aux pods de mediagenda-recette, qui vise un Service de Kyverno inexistant : plus aucun
#      pod ne se crée dans l'espace ; un pod de l'API de recette est supprimé (le ReplicaSet ne peut
#      pas le recréer).
#
# Règles (PLAN §4.14 « Pannes des finaux », §4.12-4.13) : contrôle préalable que le lab est sain ;
# jamais kms01, jamais la production, aucune donnée ; état sauvegardé dans
# ~/.local/state/workbook/F1-S12/ (700) avant toute modification ; --annuler idempotent, qui ne défait
# pas une réparation déjà faite (il remet seulement ce qui avait été sauvegardé, identique au code).
#
# Prérequis sur adm01 : kubectl (WB_K8S_ADMIN_KUBECONFIG, défaut ~/.kube/config), jq, yq (mikefarah),
# curl, dig, openssl ; variante 1 : jeton OpenBao « plateforme-admin » (BAO_TOKEN, sinon ~/.vault-token,
# au moins 20 min de vie) ; variante 2 : ~/.config/workbook/powerdns-api.env (M06-E14).
# Variables (facultatives) : WB_OPENBAO_URL, WB_F1_S12_NOM (portail.apps.par1.medisphere.internal),
# WB_F1_S12_ADRESSE (10.10.41.20), WB_F1_S12_ESPACE (mediagenda-recette).

# shellcheck source=../../../../lab/lib/pannes-lib.sh disable=SC1091
source "$WB_ROOT/lab/lib/pannes-lib.sh"

_S12_BAO_URL="${WB_OPENBAO_URL:-https://openbao.par1.medisphere.internal:8200}"
_S12_ZONE="apps.par1.medisphere.internal"
_S12_NOM="${WB_F1_S12_NOM:-portail.$_S12_ZONE}"
_S12_ADRESSE="${WB_F1_S12_ADRESSE:-10.10.41.20}"
_S12_ESPACE="${WB_F1_S12_ESPACE:-mediagenda-recette}"
_S12_ES=harbor-pull
_S12_T_ES=externalsecrets.external-secrets.io
_S12_VWC=kyverno-resource-validating-webhook-cfg-restauree
_S12_API_SEL='app.kubernetes.io/name=mediagenda,app.kubernetes.io/component=api'
_S12_JETON=""

# ---------------------------------------------------------------------------
# État local (adm01)
# ---------------------------------------------------------------------------
s12_etat() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/F1-S12"
  mkdir -p "$d" && chmod 700 "$d"
  printf '%s\n' "$d"
}
s12_ecrire() { (umask 077 && printf '%s\n' "$2" >"$(s12_etat)/$1"); }
# s12_ecrire_si_absent FICHIER VALEUR — une seule sauvegarde par panne (jamais un état déjà cassé).
s12_ecrire_si_absent() { [[ -e "$(s12_etat)/$1" ]] || s12_ecrire "$1" "$2"; }
s12_lire() { local f; f="$(s12_etat)/$1"; if [[ -f "$f" ]]; then cat "$f"; fi; }
s12_existe() { [[ -e "$(s12_etat)/$1" ]]; }
s12_oublier() { rm -f -- "$(s12_etat)/$1"; }
s12_journal() { printf '%s [F1-S12 variante %s] %s\n' "$(date -Is)" "${WB_VAR:-?}" "$*" >>"$(s12_etat)/journal"; }

# s12_attendre SECONDES COMMANDE… — réessaie toutes les 10 s jusqu'au succès ou au délai.
s12_attendre() {
  local delai="$1" fin
  shift
  fin=$((SECONDS + delai))
  while ((SECONDS < fin)); do
    if "$@" >/dev/null 2>&1; then return 0; fi
    sleep 10
  done
  "$@" >/dev/null 2>&1
}

s12_outils() {
  local c
  for c in kubectl jq yq curl dig openssl; do
    command -v "$c" >/dev/null 2>&1 || { wb_avert "outil manquant sur adm01 : $c"; return 1; }
  done
}

# ---------------------------------------------------------------------------
# OpenBao (jeton jamais affiché, jamais en argument)
# ---------------------------------------------------------------------------
# _s12_bao MÉTHODE CHEMIN [-] — corps de la réponse ; code 0 si HTTP 2xx (« - » : corps JSON sur stdin).
_s12_bao() {
  local methode="$1" chemin="$2" donnees="${3:-}" corps code
  corps="$(mktemp)"
  if [[ "$donnees" == - ]]; then
    code="$(curl -s -o "$corps" -w '%{http_code}' --max-time 20 -X "$methode" \
      -K <(printf 'header = "X-Vault-Token: %s"\n' "$_S12_JETON") -H 'Content-Type: application/json' \
      --data-binary @- "$_S12_BAO_URL/v1/$chemin" 2>/dev/null)" || code=000
  else
    code="$(curl -s -o "$corps" -w '%{http_code}' --max-time 20 -X "$methode" \
      -K <(printf 'header = "X-Vault-Token: %s"\n' "$_S12_JETON") "$_S12_BAO_URL/v1/$chemin" 2>/dev/null)" || code=000
  fi
  cat "$corps"
  rm -f "$corps"
  [[ "$code" == 2* ]]
}

# s12_bao_jeton — charge et valide le jeton d'administration (plateforme-admin, ≥ 20 min).
s12_bao_jeton() {
  [[ -n "$_S12_JETON" ]] && return 0
  local j="${BAO_TOKEN:-}" info
  if [[ -z "$j" && -r "$HOME/.vault-token" ]]; then j="$(<"$HOME/.vault-token")"; fi
  [[ -n "$j" ]] || { wb_avert "aucun jeton OpenBao (bao login -method=oidc, ou BAO_TOKEN)"; return 1; }
  _S12_JETON="$j"
  info="$(_s12_bao GET auth/token/lookup-self)" || { _S12_JETON=""; wb_avert "jeton OpenBao refusé (expiré ?)"; return 1; }
  if ! jq -e '(((.data.policies // []) + (.data.identity_policies // [])) | index("plateforme-admin")) != null
              and ((.data.ttl // 0) >= 1200)' >/dev/null 2>&1 <<<"$info"; then
    _S12_JETON=""
    wb_avert "le jeton OpenBao doit porter plateforme-admin et vivre encore au moins 20 min"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Kubernetes et autorités
# ---------------------------------------------------------------------------
_s12_empreinte() { openssl x509 -noout -fingerprint -sha256 2>/dev/null | sed 's/^.*=//'; }
_s12_ca_cluster_pem() { wb_kubectl -n default get configmap kube-root-ca.crt -o jsonpath='{.data.ca\.crt}' 2>/dev/null; }
_s12_es() { wb_kubectl -n "$_S12_ESPACE" get "$_S12_T_ES" "$_S12_ES" -o json 2>/dev/null; }
_s12_es_cond() { local j; j="$(_s12_es)" && jq -e --arg s "$1" 'any(.status.conditions[]?; .type == "Ready" and .status == $s)' >/dev/null 2>&1 <<<"$j"; }
_s12_es_pret() { _s12_es_cond True; }
_s12_es_ko() { _s12_es_cond False; }
_s12_forcer_es() { wb_kubectl -n "$_S12_ESPACE" annotate --overwrite "$_S12_T_ES" "$_S12_ES" "force-sync=$(date +%s)" >/dev/null 2>&1; }
_s12_api_pods_prets() {
  wb_kubectl -n "$_S12_ESPACE" get pods -l "$_S12_API_SEL" -o json 2>/dev/null |
    jq '[.items[] | select(.metadata.deletionTimestamp == null) | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))] | length' 2>/dev/null || echo 0
}

# s12_sain — contrôle préalable commun (F1-S11 terminé, lab sain sur ce que la panne touche).
s12_sain() {
  s12_outils || return 1
  wb_kubectl get --raw /readyz >/dev/null 2>&1 || { wb_avert "API du cluster injoignable avec le kubeconfig d'administration"; return 1; }
  _s12_es_pret || { wb_avert "ExternalSecret $_S12_ESPACE/$_S12_ES absent ou en erreur : termine F1-S11 (lab/bin/check F1 11) d'abord"; return 1; }
  wb_kubectl get clustersecretstores.external-secrets.io openbao -o json 2>/dev/null |
    jq -e 'any(.status.conditions[]?; .type == "Ready" and .status == "True")' >/dev/null 2>&1 ||
    { wb_avert "ClusterSecretStore openbao pas prêt : répare d'abord"; return 1; }
  (($(_s12_api_pods_prets) >= 2)) || { wb_avert "MédiAgenda de recette : moins de deux pods prêts, répare d'abord"; return 1; }
}

# ---------------------------------------------------------------------------
# Variante 1 : confiance (autorité de l'ancien cluster dans auth/k8s-par1/config)
# ---------------------------------------------------------------------------
# _s12_ca_ancienne — PEM d'une autorité différente de l'actuelle : version précédente de
#   racine/k8s-par1-ca.crt dans plateforme/secrets, sinon une autorité « kubernetes » jetable.
_s12_ca_ancienne() {
  local actuelle="$1" p sha pem tmp k
  p="$(jq -rn --arg s plateforme/secrets '$s|@uri')"
  while IFS= read -r sha; do
    [[ -n "$sha" ]] || continue
    pem="$(gitlab_api "projects/$p/repository/files/racine%2Fk8s-par1-ca.crt/raw?ref=$sha" 2>/dev/null || true)"
    if [[ -n "$pem" && "$(_s12_empreinte <<<"$pem")" != "$actuelle" && -n "$(_s12_empreinte <<<"$pem")" ]]; then
      s12_journal "autorité ancienne trouvée dans plateforme/secrets ($sha)"
      printf '%s\n' "$pem"
      return 0
    fi
  done < <(gitlab_api "projects/$p/repository/commits?ref_name=main&path=racine%2Fk8s-par1-ca.crt&per_page=10" 2>/dev/null | jq -r '.[]?.id' 2>/dev/null || true)
  tmp="$(mktemp -d)"
  k="$tmp/cle.pem"
  if openssl req -x509 -newkey rsa:2048 -nodes -keyout "$k" -subj "/CN=kubernetes" -days 3650 -out "$tmp/ca.crt" >/dev/null 2>&1; then
    s12_journal "aucune ancienne autorité dans l'historique : autorité jetable « kubernetes »"
    cat "$tmp/ca.crt"
  fi
  rm -rf -- "$tmp"
}

_s12_v1() {
  local cfg actuelle ca_pem
  s12_bao_jeton || return 10
  cfg="$(_s12_bao GET auth/k8s-par1/config)" || { wb_avert "auth/k8s-par1/config illisible"; return 10; }
  actuelle="$(_s12_ca_cluster_pem | _s12_empreinte)"
  [[ -n "$actuelle" ]] || return 1
  [[ "$(jq -r '.data.kubernetes_ca_cert // empty' <<<"$cfg" | _s12_empreinte)" == "$actuelle" ]] ||
    { wb_avert "auth/k8s-par1 ne vise pas l'autorité actuelle du cluster : F1-S09 à refaire, rien n'est cassé"; return 1; }
  # Sauvegarde : les seuls champs que l'API relit et réécrit (le jeton de relecture, s'il y en avait
  # un, n'est jamais renvoyé : on refuse d'écrire si la configuration en déclare un).
  if jq -e '.data.token_reviewer_jwt_set == true' >/dev/null 2>&1 <<<"$cfg"; then
    wb_avert "auth/k8s-par1 utilise un jeton de relecture dédié (différent du corrigé de M25) : variante sans effet sûr"
    return 10
  fi
  s12_ecrire_si_absent v1-config.json "$(jq -c '.data | {kubernetes_host, kubernetes_ca_cert, pem_keys: (.pem_keys // []), disable_local_ca_jwt: (.disable_local_ca_jwt // false)}
      + (if has("issuer") and (.issuer // "") != "" then {issuer} else {} end)
      + (if has("disable_iss_validation") then {disable_iss_validation} else {} end)' <<<"$cfg")"
  ca_pem="$(_s12_ca_ancienne "$actuelle")"
  [[ -n "$ca_pem" ]] || return 1
  jq -c --arg ca "$ca_pem" '.kubernetes_ca_cert = $ca' <<<"$(s12_lire v1-config.json)" | _s12_bao POST auth/k8s-par1/config - >/dev/null || return 1
  s12_ecrire v1-posee "$(_s12_empreinte <<<"$ca_pem")"
  # Aucun jeton révoqué : révoquer les jetons de la méthode révoquerait aussi leurs baux (identifiants
  # dynamiques des bases, production comprise). La synchronisation forcée d'un ExternalSecret de
  # recette suffit : ESO se reconnecte à chaque synchronisation et la connexion échoue.
  _s12_forcer_es || return 1
  s12_journal "auth/k8s-par1/config : autorité ancienne posée ; synchronisation forcée de $_S12_ESPACE/$_S12_ES"
}

_s12_v1_verifier() {
  s12_bao_jeton || return 1
  [[ "$(_s12_bao GET auth/k8s-par1/config | jq -r '.data.kubernetes_ca_cert // empty' | _s12_empreinte)" == "$(s12_lire v1-posee)" ]] || return 1
  s12_attendre 360 _s12_es_ko
}

_s12_v1_annuler() {
  s12_existe v1-config.json || return 0
  if ! s12_bao_jeton; then
    wb_avert "configuration de auth/k8s-par1 NON restaurée : connecte-toi (bao login -method=oidc) puis relance « lab/bin/break F1 12 --annuler »"
    wb_avert "(ou rejoue le pipeline de plateforme/secrets : il remet l'autorité de racine/k8s-par1-ca.crt)"
    return 0
  fi
  # Une réparation de l'apprenant (pipeline rejoué, autorité actuelle) est respectée.
  if [[ "$(_s12_bao GET auth/k8s-par1/config | jq -r '.data.kubernetes_ca_cert // empty' | _s12_empreinte)" == "$(s12_lire v1-posee)" ]]; then
    if s12_lire v1-config.json | _s12_bao POST auth/k8s-par1/config - >/dev/null; then
      s12_journal "annulation : configuration de auth/k8s-par1 restaurée"
    else
      wb_avert "configuration de auth/k8s-par1 non restaurée : rejoue le pipeline de plateforme/secrets"
      return 0
    fi
  fi
  s12_oublier v1-config.json
  s12_oublier v1-posee
}

# ---------------------------------------------------------------------------
# Variante 2 : propriété (TXT d'ExternalDNS et A du nom portail)
# ---------------------------------------------------------------------------
_s12_pdns() {
  local methode="$1" chemin="$2" f="$HOME/.config/workbook/powerdns-api.env" PDNS_SERVER_URL="" PDNS_API_KEY=""
  [[ -r "$f" ]] || { wb_avert "fichier illisible : $f (M06-E14)"; return 1; }
  # shellcheck disable=SC1090
  source "$f"
  # shellcheck disable=SC2086  # ${3:+…} : deux mots voulus (--data-binary @-) ou rien
  curl -sf --max-time 20 -X "$methode" -K <(printf 'header = "X-API-Key: %s"\n' "$PDNS_API_KEY") \
    -H 'Content-Type: application/json' ${3:+--data-binary @-} \
    "${PDNS_SERVER_URL:-http://dns01.par1.medisphere.internal:8081}/api/v1/servers/localhost/$chemin"
}
_s12_dig() { dig +short +norec +time=3 +tries=1 -p 5300 @10.10.20.10 "$1" "${2:-A}" 2>/dev/null; }

# _s12_rrsets — RRsets A et TXT (ancien et nouveau format) du nom visé, depuis l'API de PowerDNS.
_s12_rrsets() {
  _s12_pdns GET "zones/$_S12_ZONE." | jq -c --arg n "$_S12_NOM." --arg t "a-$_S12_NOM." \
    '[.rrsets[] | select((.name == $n and (.type == "A" or .type == "TXT")) or (.name == $t and .type == "TXT"))]'
}

_s12_v2() {
  local rr txt neuf
  _s12_pdns GET "zones/$_S12_ZONE." >/dev/null || return 10
  [[ "$(_s12_dig "$_S12_NOM" | sort -u | paste -sd, -)" == 10.10.41.10 ]] ||
    { wb_avert "$_S12_NOM ne vise pas 10.10.41.10 avant la panne : variante sans effet"; return 10; }
  rr="$(_s12_rrsets)" || return 1
  txt="$(jq -c '[.[] | select(.type == "TXT" and any(.records[]; .content | test("heritage=external-dns") and test("external-dns/owner=k8s-par1([,\"]|$)")))] | first // empty' <<<"$rr")"
  [[ -n "$txt" ]] || { wb_avert "aucun enregistrement de propriété k8s-par1 pour $_S12_NOM : variante sans effet"; return 10; }
  s12_ecrire_si_absent v2-rrsets.json "$rr"
  neuf="$(jq -c --arg ip "$_S12_ADRESSE" --arg n "$_S12_NOM." --argjson txt "$txt" '{rrsets: [
      ($txt | .changetype = "REPLACE" | del(.comments)
        | .records |= map(.content |= sub("external-dns/owner=k8s-par1(?<f>[,\"]|$)"; "external-dns/owner=k8s-par1-essai\(.f)"))),
      {name: $n, type: "A", ttl: 60, changetype: "REPLACE", records: [{content: $ip, disabled: false}]}]}' <<<"{}")"
  _s12_pdns PATCH "zones/$_S12_ZONE." - <<<"$neuf" >/dev/null || return 1
  s12_journal "$_S12_NOM : TXT de propriété → k8s-par1-essai, A → $_S12_ADRESSE"
}

_s12_v2_verifier() {
  # Deux intervalles d'ExternalDNS (1 min) : le nom vise toujours la mauvaise adresse.
  sleep 150
  [[ "$(_s12_dig "$_S12_NOM" | sort -u | paste -sd, -)" == "$_S12_ADRESSE" ]]
}

_s12_v2_annuler() {
  local rr corps
  s12_existe v2-rrsets.json || return 0
  rr="$(s12_lire v2-rrsets.json)"
  # Les RRsets sauvegardés (A vers la Gateway, TXT de k8s-par1) sont ceux qu'ExternalDNS écrit :
  # les remettre ne défait pas une réparation, qui les aurait remis à l'identique.
  corps="$(jq -c '{rrsets: [.[] | .changetype = "REPLACE" | del(.comments)]}' <<<"$rr")"
  if _s12_pdns PATCH "zones/$_S12_ZONE." - <<<"$corps" >/dev/null; then
    # Un TXT de propriété au nouveau format créé par la panne et absent avant : rien à faire (REPLACE).
    s12_oublier v2-rrsets.json
    s12_journal "annulation : RRsets de $_S12_NOM restaurés"
  else
    wb_avert "RRsets de $_S12_NOM non restaurés (API de PowerDNS) : sauvegarde gardée dans $(s12_etat)/v2-rrsets.json"
  fi
}

# ---------------------------------------------------------------------------
# Variante 3 : objet restauré (webhook d'admission en Fail vers un service absent)
# ---------------------------------------------------------------------------
_s12_v3() {
  local ca pod
  wb_kubectl -n kyverno get service kyverno-svc-ancien >/dev/null 2>&1 && return 10
  ca="$(_s12_ca_cluster_pem | base64 -w0)"
  [[ -n "$ca" ]] || return 1
  wb_k8s_sauver validatingwebhookconfigurations.admissionregistration.k8s.io "$_S12_VWC"
  wb_kubectl apply --server-side --field-manager=velero-server -f - >/dev/null <<EOF || return 1
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: $_S12_VWC
  labels:
    app.kubernetes.io/part-of: kyverno
    velero.io/backup-name: k8s-par1-avant-day0
    velero.io/restore-name: day0-complement-$(date +%Y%m%d)
webhooks:
  - name: validate.kyverno.svc-fail
    admissionReviewVersions: ["v1"]
    sideEffects: None
    failurePolicy: Fail
    timeoutSeconds: 10
    matchPolicy: Equivalent
    namespaceSelector:
      matchExpressions:
        - key: kubernetes.io/metadata.name
          operator: In
          values: ["$_S12_ESPACE"]
    rules:
      - apiGroups: [""]
        apiVersions: ["v1"]
        operations: ["CREATE"]
        resources: ["pods"]
        scope: Namespaced
    clientConfig:
      caBundle: $ca
      service:
        namespace: kyverno
        name: kyverno-svc-ancien
        path: /validate/fail
        port: 443
EOF
  pod="$(wb_kubectl -n "$_S12_ESPACE" get pods -l "$_S12_API_SEL" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
  [[ -n "$pod" ]] || return 1
  s12_ecrire v3-pod "$pod"
  wb_kubectl -n "$_S12_ESPACE" delete pod "$pod" --wait=false >/dev/null || return 1
  s12_journal "webhook $_S12_VWC posé (Fail, service kyverno/kyverno-svc-ancien) ; pod $pod supprimé"
}

_s12_v3_refus() {
  wb_kubectl -n "$_S12_ESPACE" get events -o json 2>/dev/null |
    jq -e '.items | any(.reason == "FailedCreate" and (.message | test("kyverno-svc-ancien|failed calling webhook")))' >/dev/null 2>&1
}
_s12_v3_verifier() {
  wb_kubectl get validatingwebhookconfigurations "$_S12_VWC" >/dev/null 2>&1 || return 1
  s12_attendre 120 _s12_v3_refus
}

_s12_v3_annuler() {
  # Restaure l'état sauvegardé : l'objet n'existait pas, il est supprimé (s'il l'est déjà, rien).
  wb_k8s_restaurer || wb_avert "webhook $_S12_VWC non supprimé : voir ~/.local/state/workbook/k8s/F1-S12/"
  s12_oublier v3-pod
}

# ---------------------------------------------------------------------------
# Enchaînement (une variante sans effet sur ce lab est défaite, la suivante essayée)
# ---------------------------------------------------------------------------
_s12_une() {
  case "$1" in
    1) _s12_v1 ;;
    2) _s12_v2 ;;
    3) _s12_v3 ;;
    *) return 1 ;;
  esac
}
_s12_defaire() {
  _s12_v1_annuler || true
  _s12_v2_annuler || true
  _s12_v3_annuler || true
}

# _s12_essayer DÉPART — essaie les variantes à partir de DÉPART ; code 10 = « sans effet ».
_s12_essayer() {
  local depart="$1" i n rc
  s12_sain || return 1
  for ((i = 0; i < 3; i++)); do
    n=$(((depart - 1 + i) % 3 + 1))
    WB_VAR="$n"
    rc=0
    _s12_une "$n" || rc=$?
    if ((rc == 0)); then
      s12_ecrire variante "$n"
      return 0
    fi
    _s12_defaire
    ((rc == 10)) || return 1
  done
  wb_avert "aucune variante de F1-S12 n'a d'effet sur ce lab (configuration différente du corrigé)"
  return 1
}

panne_S12_v1() { _s12_essayer 1; }
panne_S12_v2() { _s12_essayer 2; }
panne_S12_v3() { _s12_essayer 3; }

verifier_S12() {
  case "$(s12_lire variante)" in
    1) _s12_v1_verifier ;;
    2) _s12_v2_verifier ;;
    3) _s12_v3_verifier ;;
    *) return 1 ;;
  esac
}

annuler_S12() {
  local v
  v="$(s12_lire variante)"
  _s12_defaire
  # Retrait de l'annotation de synchronisation forcée (variante 1) : ESO resynchronise.
  wb_kubectl -n "$_S12_ESPACE" annotate "$_S12_T_ES" "$_S12_ES" force-sync- >/dev/null 2>&1 || true
  if [[ "$v" == 1 ]]; then
    _s12_forcer_es || true
    s12_attendre 180 _s12_es_pret || wb_avert "ExternalSecret $_S12_ESPACE/$_S12_ES pas encore prêt : ESO réessaie seul (quelques minutes)"
    wb_kubectl -n "$_S12_ESPACE" annotate "$_S12_T_ES" "$_S12_ES" force-sync- >/dev/null 2>&1 || true
  fi
  s12_oublier variante
  s12_journal "annulation"
}

resume_S12() {
  case "$(s12_lire variante)" in
    1) echo "Plusieurs Applications passent Degraded : des ExternalSecrets ne se synchronisent plus." ;;
    2) echo "Le portail ne répond plus (délai dépassé) alors qu'Argo CD est tout vert." ;;
    3) echo "En recette, un pod de l'API a disparu et ne revient pas." ;;
    *) echo "La plateforme reconstruite se comporte mal depuis la réouverture." ;;
  esac
}

symptome_S12() {
  case "$(s12_lire variante)" in
    1) wb_symptome "INC-5712 — De : Nadia Roussel" \
         "Depuis une vingtaine de minutes, Argo CD affiche des Applications « Degraded » les unes après" \
         "les autres, à commencer par mediagenda-recette. Julien me dit que « le secret de tirage des" \
         "images n'est plus mis à jour » et qu'il n'a rien changé. Avant que ça touche la production au" \
         "prochain rafraîchissement, trouve ce qui se passe." ;;
    2) wb_symptome "INC-5712 — De : Nadia Roussel" \
         "Le portail (https://portail.apps.par1.medisphere.internal) ne répond plus depuis le poste du" \
         "support : délai dépassé. Argo CD est tout vert, l'Application portail est Synced et Healthy," \
         "le pod tourne. Les autres sites *.apps répondent. Personne n'a touché au portail." ;;
    3) wb_symptome "INC-5712 — De : Julien Petit" \
         "En recette, le Rollout de MédiAgenda est resté à 2 pods prêts sur 3 depuis tout à l'heure, et le" \
         "troisième ne revient pas. Pas de CrashLoop, pas de Pending : il n'y a juste pas de pod." \
         "Les déploiements de recette de cet après-midi vont échouer si ça reste comme ça." ;;
  esac
  printf '  Temps cible : 45 min. Contrôle : lab/bin/check F1 12\n\n'
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main F1 S12 3 "$@"; }
fi
