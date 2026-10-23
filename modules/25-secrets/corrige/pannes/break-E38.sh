# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et SQL entre apostrophes
# break-E38.sh — M25-E38 « Panne : MédiAgenda perd sa base »
#
# En RECETTE seulement (jamais mediagenda-prod, jamais les rôles ni la connexion de prod), l'API de
# MédiAgenda perd l'accès à PostgreSQL : ses identifiants dynamiques (moteur db-mediagenda, rôle
# mediagenda-api-recette, générateur VaultDynamicSecret mediagenda-api, ExternalSecret mediagenda-db-api
# rafraîchi toutes les 30 min, Reloader) cessent d'être valables ou d'être délivrés. Variantes :
#   1. max_ttl du rôle mediagenda-api-recette ramené à 10 min (sous l'intervalle de rafraîchissement
#      d'ESO, 30 min) : chaque compte meurt 20 min avant d'être remplacé ; rafraîchissement forcé pour
#      que le premier compte « court » soit délivré tout de suite ;
#   2. « ménage » des baux : sys/leases/revoke-prefix sur db-mediagenda/creds/mediagenda-api-recette
#      (repli : révocation bail par bail si la politique n'a pas revoke-prefix, M25-E23) ; DROP ROLE
#      immédiat des comptes en service ; ESO ne s'en aperçoit qu'au rafraîchissement suivant ;
#   3. mot de passe du rôle PostgreSQL « openbao » changé directement dans la base de recette (valeur
#      tirée DANS PostgreSQL, connue de personne), sessions d'openbao coupées (sinon le pool de
#      connexions d'OpenBao survit au changement) ; rafraîchissement forcé : ESO passe en erreur ;
#   4. CiliumNetworkPolicy « mediagenda-db-quarantaine » (ingressDeny 10.10.20.0/24 → 5432 sur les
#      instances) : le coffre ne joint plus 10.10.41.64:5432 ; sessions d'openbao coupées (une
#      connexion déjà établie survivrait à la politique) ; rafraîchissement forcé.
#
# Sauvegardes : ~/.local/state/workbook/M25-E38/ (TTL du rôle, baux révoqués, journal) ; la politique
# réseau par wb_k8s_sauver (ABSENT : supprimée à l'annulation). Annulation (idempotente) : TTL remis,
# politique supprimée, connexion vérifiée et, si OpenBao ne s'authentifie plus, reprise par le
# superutilisateur de CNPG (mot de passe provisoire tiré dans PostgreSQL, passé à OpenBao par un tube,
# puis rotate-root : plus personne ne le connaît), rafraîchissement forcé de l'ExternalSecret.
# Accès : jeton plateforme-admin (voir _m25-commun-b.sh), kubeconfig d'administration (wb_kubectl :
# exec dans le primaire en superutilisateur local, annotation de l'ExternalSecret, politique réseau).

# shellcheck source=../../../../lab/lib/pannes-lib.sh disable=SC1091
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m25-commun-b.sh
source "$WB_ROOT/modules/25-secrets/corrige/pannes/_m25-commun-b.sh"

_E38_NS=mediagenda-recette
_E38_CLUSTER=mediagenda-db
_E38_CONNEXION=mediagenda-recette
_E38_ROLE=mediagenda-api-recette
_E38_PREFIXE=db-mediagenda/creds/mediagenda-api-recette
_E38_ES=mediagenda-db-api
_E38_CNP=mediagenda-db-quarantaine
_E38_MAX_TTL_COURT=600

# --- Coffre ------------------------------------------------------------------------------------------
_e38_role() { m25b_api GET "db-mediagenda/roles/$_E38_ROLE" 2>/dev/null || true; }
_e38_baux() {
  m25b_api GET "sys/leases/lookup/$_E38_PREFIXE?list=true" 2>/dev/null | jq -r '.data.keys[]? // empty' 2>/dev/null || true
}

# _e38_essai_creds — demande un identifiant de recette et le révoque aussitôt. 0 si délivré ; sinon
#   le message d'erreur d'OpenBao (jamais de valeur) sur la sortie standard.
_e38_essai_creds() {
  local r l
  if ! r="$(m25b_api GET "db-mediagenda/creds/$_E38_ROLE")"; then
    jq -r '.errors[]? // empty' <<<"$r" 2>/dev/null || true
    return 1
  fi
  l="$(jq -r '.lease_id // empty' <<<"$r" 2>/dev/null || true)"
  r=""
  if [[ -n "$l" ]]; then
    jq -nc --arg l "$l" '{lease_id: $l}' | m25b_api PUT sys/leases/revoke - >/dev/null || true
  fi
  return 0
}

# --- Kubernetes et PostgreSQL ------------------------------------------------------------------------
# _e38_primaire — nom du pod primaire du Cluster de recette (vide si introuvable).
_e38_primaire() {
  local p
  p="$(wb_kubectl -n "$_E38_NS" get pods -l "cnpg.io/cluster=$_E38_CLUSTER,cnpg.io/instanceRole=primary" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  if [[ -z "$p" ]]; then
    p="$(wb_kubectl -n "$_E38_NS" get pods -l "cnpg.io/cluster=$_E38_CLUSTER,role=primary" \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  fi
  printf '%s' "$p"
}
# _e38_sql — SQL lu sur l'entrée standard, joué en superutilisateur local (comme « kubectl cnpg psql »)
#   dans la base mediagenda du primaire ; jamais d'argument sensible sur la ligne de commande.
_e38_sql() {
  local p
  p="$(_e38_primaire)"
  [[ -n "$p" ]] || return 1
  wb_kubectl -n "$_E38_NS" exec -i "$p" -c postgres -- psql -X -v ON_ERROR_STOP=1 -qAt -d mediagenda
}
_e38_couper_sessions_openbao() {
  printf '%s\n' "SELECT count(pg_terminate_backend(pid)) FROM pg_stat_activity WHERE usename = 'openbao';" \
    | _e38_sql >/dev/null
}
_e38_es() { wb_kubectl -n "$_E38_NS" get externalsecrets.external-secrets.io "$_E38_ES" -o json 2>/dev/null || true; }
_e38_es_pret() {
  _e38_es | jq -e '[.status.conditions[]? | select(.type == "Ready" and .status == "True")] | length > 0' >/dev/null 2>&1
}
# _e38_rafraichir — rafraîchissement immédiat de l'ExternalSecret (annotation force-sync d'ESO).
_e38_rafraichir() {
  wb_kubectl -n "$_E38_NS" annotate externalsecrets.external-secrets.io "$_E38_ES" \
    "force-sync=$(date +%s)" --overwrite >/dev/null 2>&1
}

# _e38_pret — état d'entrée conforme à M25-E14/E15 ; sauvegarde des TTL du rôle (une seule fois).
_e38_pret() {
  local r err
  m25b_jeton_charger || return 1
  r="$(_e38_role)"
  jq -e '.data.db_name == "mediagenda-recette" and (.data.max_ttl // 0) > 1800' >/dev/null 2>&1 <<<"$r" \
    || { wb_avert "rôle $_E38_ROLE absent ou déjà raccourci (M25-E14 fait ? panne déjà là ?)"; return 1; }
  [[ -n "$(_e38_primaire)" ]] || { wb_avert "primaire du Cluster $_E38_CLUSTER introuvable dans $_E38_NS"; return 1; }
  _e38_es_pret || { wb_avert "ExternalSecret $_E38_ES pas Ready dans $_E38_NS (M25-E14/E15 faits ?)"; return 1; }
  err="$(_e38_essai_creds)" || { wb_avert "OpenBao ne délivre déjà plus d'identifiant de recette : $err"; return 1; }
  m25b_ecrire_si_absent E38 role.json "$(jq -c '{default_ttl: .data.default_ttl, max_ttl: .data.max_ttl}' <<<"$r")"
}

panne_E38_v1() {
  _e38_pret || return 1
  jq -nc --argjson t "$_E38_MAX_TTL_COURT" '{max_ttl: $t}' \
    | m25b_api POST "db-mediagenda/roles/$_E38_ROLE" - >/dev/null || return 1
  m25b_journal E38 "rôle $_E38_ROLE : max_ttl ramené à $_E38_MAX_TTL_COURT s"
  _e38_rafraichir || wb_avert "rafraîchissement forcé de $_E38_ES impossible : la panne se verra au prochain cycle"
}

panne_E38_v2() {
  local b
  _e38_pret || return 1
  b="$(_e38_baux)"
  [[ -n "$b" ]] || { wb_avert "aucun bail $_E38_ROLE actif : rien à révoquer (ESO tourne-t-il ?)"; return 1; }
  m25b_ecrire E38 baux-revoques "$b"
  if ! m25b_api PUT "sys/leases/revoke-prefix/$_E38_PREFIXE" >/dev/null 2>&1; then
    # Politique sans revoke-prefix (M25-E23 pas fait) : même « ménage », bail par bail.
    while IFS= read -r b; do
      [[ -n "$b" ]] || continue
      jq -nc --arg l "$_E38_PREFIXE/$b" '{lease_id: $l}' | m25b_api PUT sys/leases/revoke - >/dev/null || return 1
    done < <(m25b_lire E38 baux-revoques)
  fi
  m25b_journal E38 "baux de $_E38_PREFIXE révoqués ($(m25b_lire E38 baux-revoques | grep -c .) bail(s))"
}

panne_E38_v3() {
  _e38_pret || return 1
  printf '%s\n' \
    "DO \$\$ BEGIN EXECUTE format('ALTER ROLE openbao PASSWORD %L', encode(sha256((gen_random_uuid()::text || gen_random_uuid()::text)::bytea), 'hex')); END \$\$;" \
    | _e38_sql >/dev/null || return 1
  _e38_couper_sessions_openbao || true
  m25b_journal E38 "mot de passe du rôle PostgreSQL openbao changé dans $_E38_NS, sessions coupées"
  _e38_rafraichir || true
}

panne_E38_v4() {
  _e38_pret || return 1
  wb_k8s_sauver ciliumnetworkpolicies.cilium.io "$_E38_CNP" "$_E38_NS"
  wb_kubectl apply -f - >/dev/null <<EOF || return 1
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: $_E38_CNP
  namespace: $_E38_NS
  annotations:
    medisphere.internal/ticket: SEC-2638
    workbook.medisphere.internal/panne: M25-E38
spec:
  description: "Durcissement SEC-2638 : plus de connexion directe à la base de recette depuis le VLAN INFRA"
  endpointSelector:
    matchLabels:
      cnpg.io/cluster: $_E38_CLUSTER
  ingressDeny:
    - fromCIDR:
        - 10.10.20.0/24
      toPorts:
        - ports:
            - port: "5432"
              protocol: TCP
EOF
  sleep 5
  _e38_couper_sessions_openbao || true
  m25b_journal E38 "CiliumNetworkPolicy $_E38_CNP (ingressDeny 10.10.20.0/24:5432) créée, sessions d'openbao coupées"
  _e38_rafraichir || true
}

verifier_E38() {
  local err
  m25b_jeton_charger || return 1
  case "$WB_VAR" in
    1) _e38_role | jq -e --argjson t "$_E38_MAX_TTL_COURT" '.data.max_ttl == $t' >/dev/null 2>&1 ;;
    2)
      local b
      m25b_existe E38 baux-revoques || return 1
      while IFS= read -r b; do
        [[ -z "$b" ]] || ! grep -qxF -- "$b" < <(_e38_baux) || return 1
      done < <(m25b_lire E38 baux-revoques)
      ;;
    3) err="$(_e38_essai_creds)" && return 1; grep -qi 'password authentication failed' <<<"$err" ;;
    4)
      wb_kubectl -n "$_E38_NS" get ciliumnetworkpolicies.cilium.io "$_E38_CNP" >/dev/null 2>&1 || return 1
      ! _e38_essai_creds >/dev/null
      ;;
    *) return 1 ;;
  esac
}

# _e38_reprendre_connexion — si OpenBao ne s'authentifie plus auprès de la base de recette : nouveau
#   mot de passe tiré dans PostgreSQL (jamais affiché ni écrit), passé à OpenBao par un tube
#   (verify_connection), puis rotate-root. Ne fait rien si la connexion marche.
_e38_reprendre_connexion() {
  local err mdp
  err="$(_e38_essai_creds)" && return 0
  if ! grep -qi 'password authentication failed' <<<"$err"; then
    wb_avert "OpenBao ne délivre pas d'identifiant de recette (cause autre que le mot de passe) : $err"
    return 0
  fi
  # Une rotation par OpenBao suffit si une connexion de son pool est encore ouverte.
  m25b_api POST "db-mediagenda/rotate-root/$_E38_CONNEXION" >/dev/null 2>&1 && return 0
  mdp="$(_e38_sql <<'EOF'
SELECT set_config('medisphere.mdp_openbao', encode(sha256((gen_random_uuid()::text || gen_random_uuid()::text)::bytea), 'hex'), false) \g /dev/null
DO $$ BEGIN EXECUTE format('ALTER ROLE openbao PASSWORD %L', current_setting('medisphere.mdp_openbao')); END $$;
SELECT current_setting('medisphere.mdp_openbao');
EOF
)" || { wb_avert "mot de passe d'openbao non réinitialisé (primaire injoignable ?) : identifiants-dynamiques.md § 4"; return 0; }
  [[ "$mdp" =~ ^[0-9a-f]{64}$ ]] || { mdp=""; wb_avert "réinitialisation d'openbao : réponse inattendue de psql"; return 0; }
  printf '{"password":"%s"}' "$mdp" | m25b_api POST "db-mediagenda/config/$_E38_CONNEXION" - >/dev/null \
    || wb_avert "nouveau mot de passe refusé par OpenBao (verify_connection) : identifiants-dynamiques.md § 4"
  mdp=""
  m25b_api POST "db-mediagenda/rotate-root/$_E38_CONNEXION" >/dev/null \
    || wb_avert "rotate-root de $_E38_CONNEXION en échec : à refaire (bao write -f db-mediagenda/rotate-root/$_E38_CONNEXION)"
  m25b_journal E38 "annulation : connexion $_E38_CONNEXION reprise (mot de passe provisoire puis rotate-root)"
}

annuler_E38() {
  local t
  # 1. Politique réseau (sans jeton).
  wb_k8s_restaurer || wb_avert "politique $_E38_CNP non supprimée (kubectl -n $_E38_NS delete cnp $_E38_CNP)"
  if ! m25b_jeton_charger; then
    wb_avert "annulation incomplète sans jeton plateforme-admin : connecte-toi puis relance « lab/bin/break 25 38 --annuler »"
    return 0
  fi
  # 2. TTL du rôle (valeurs d'entrée = celles de plateforme/secrets : un tofu apply n'est pas défait).
  t="$(m25b_lire E38 role.json)"
  if [[ -n "$t" ]] && ! _e38_role | jq -e --argjson t "$t" '.data.max_ttl == $t.max_ttl and .data.default_ttl == $t.default_ttl' >/dev/null 2>&1; then
    printf '%s\n' "$t" | m25b_api POST "db-mediagenda/roles/$_E38_ROLE" - >/dev/null \
      || wb_avert "TTL du rôle $_E38_ROLE non restaurés (tofu apply de plateforme/secrets)"
  fi
  # 3. Connexion d'OpenBao à la base (variante 3 ; sans effet si elle marche).
  _e38_reprendre_connexion
  # 4. Identifiants neufs pour l'API (Reloader redémarre le Rollout).
  _e38_rafraichir || wb_avert "rafraîchissement de $_E38_ES impossible : attendre le cycle de 30 min"
  m25b_attendre 90 _e38_es_pret || wb_avert "ExternalSecret $_E38_ES pas encore Ready : kubectl -n $_E38_NS describe es $_E38_ES"
  m25b_journal E38 "annulation"
  m25b_oublier E38 role.json
  m25b_oublier E38 baux-revoques
}

symptome_E38() {
  wb_symptome "INC-5238 — De : Julien Petit — MédiAgenda (recette) perd sa base" \
    "Depuis ce matin, en recette, l'API renvoie des 500 par vagues, toutes les heures environ ;" \
    "les journaux disent « password authentication failed for user \"v-…\" ». Parfois ça revient seul," \
    "parfois non. Personne n'a livré. La prod n'est pas touchée (pour l'instant ?)." \
    "Selon la cause, l'API tombe tout de suite ou dans l'heure : l'ExternalSecret, les baux et le" \
    "journal d'OpenBao parlent souvent avant elle." \
    "Temps cible : 50 min. Contrôle : lab/bin/check 25 38"
}

resume_E38() { echo "MédiAgenda (recette) perd sa base : identifiants dynamiques refusés ou non délivrés"; }

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 25 E38 4 "$@"; }
fi
