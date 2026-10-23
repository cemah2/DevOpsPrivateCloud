# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et scripts distants entre apostrophes
# break-S10.sh — F3-S10 « Jeudi : les secrets ne suivent plus » (INC-5910)
#
# MédiAgenda de RECETTE perd peu à peu l'accès à PostgreSQL : ses identifiants dynamiques (moteur
# db-mediagenda, bail d'une heure, générateur VaultDynamicSecret « mediagenda-api », ExternalSecret
# « mediagenda-db-api ») ne sont plus renouvelés ; chaque compte meurt à la fin de son bail. Variantes :
#   1. VIP du coffre perdue : keepalived ARRÊTÉ sur le nœud ACTIF d'OpenBao (« maintenance » de
#      keepalived). Les nœuds en attente sont en FAULT par construction (script chk_openbao_actif :
#      seul l'actif répond 200) : plus personne ne porte 10.10.20.200. OpenBao lui-même va bien
#      (chaque nœud répond par son nom). ⚠️ Effet de bord assumé et annoncé dans le corrigé : la
#      production, la CI et Ansible passent aussi par la VIP (la prod perdrait ses identifiants dans
#      l'heure) : c'est ce qui fait monter la gravité ;
#   2. rôle eso-mediagenda-recette de la méthode k8s-par1 « restreint » à la main (dérive par rapport à
#      plateforme/secrets) : ses token_policies passent de eso-mediagenda-recette à une nouvelle
#      politique eso-mediagenda-recette-kv (KV seulement, « moindre privilège », PLAT-3310) : les
#      ExternalSecret KV marchent, les générateurs d'identifiants dynamiques reçoivent « permission
#      denied » ;
#   3. deux causes : le SecretStore « openbao » et les deux VaultDynamicSecret de mediagenda-recette
#      sont ÉPINGLÉS sur un nœud en attente (https://vaultNN…:8200 au lieu de la VIP, « essai » laissé
#      en place), puis openbao est ARRÊTÉ sur ce nœud (systemctl stop, pas la VM). La grappe garde son
#      quorum (actif + un nœud en attente) ; seul le client épinglé est privé de coffre. Redémarrer le
#      nœud rend le service mais laisse l'épinglage (fragilité) : le check exige les deux corrections.
#
# Jamais kms01, jamais /var/lib/openbao, jamais bao operator seal, au plus UN nœud arrêté.
# Sauvegardes : ~/.local/state/workbook/F3-S10/ (rôle, nœud visé) ; objets Kubernetes par wb_k8s_sauver.
# Accès : SSH admin + sudo sur vault01-03 ; kubeconfig d'administration ; jeton plateforme-admin
# d'OpenBao pour la variante 2 seulement (BAO_TOKEN ou ~/.vault-token, voir _m25-commun.sh).
# Annulation (idempotente) : keepalived relancé là où il est arrêté, rôle et politique restaurés,
# objets Kubernetes restaurés, openbao relancé sur le nœud arrêté, rafraîchissement de l'ExternalSecret.

# shellcheck source=../../../../lab/lib/pannes-lib.sh disable=SC1091
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=../../../../modules/25-secrets/corrige/pannes/_m25-commun.sh disable=SC1091
source "$WB_ROOT/modules/25-secrets/corrige/pannes/_m25-commun.sh"
# shellcheck source=_f3-fin-pannes.sh
source "$WB_ROOT/finaux/F3-astreinte/corrige/pannes/_f3-fin-pannes.sh"

_S10_NS=mediagenda-recette
_S10_ES=mediagenda-db-api
_S10_ROLE=eso-mediagenda-recette
_S10_POL_KV=eso-mediagenda-recette-kv
_S10_GENERATEURS=(mediagenda-api mediagenda-migrateur)

_s10_vip_sert() {
  [[ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$_M25_URL/v1/sys/health" 2>/dev/null || true)" == 200 ]]
}
_s10_porteurs_vip() {
  local n c=0
  for n in "${_M25_NOEUDS[@]}"; do
    if remote "$n" "ip -o -4 addr show" 2>/dev/null </dev/null | grep -q ' 10\.10\.20\.200/'; then c=$((c + 1)); fi
  done
  echo "$c"
}
_s10_role() { m25_api GET "auth/k8s-par1/role/$_S10_ROLE" 2>/dev/null || true; }

# _s10_sain — état d'entrée : santé commune, grappe saine (un actif, deux en attente, kms01 descellé),
#   VIP servie, ExternalSecret prêt, aucun autre incident ouvert.
_s10_sain() {
  f3fp_preparer S10 || return 1
  m25_grappe_saine || { f3fp_refus "grappe OpenBao pas saine (un actif, deux en attente, kms01 descellé attendus)"; return 1; }
  _s10_vip_sert || { f3fp_refus "la VIP du coffre (10.10.20.200) ne sert pas"; return 1; }
  f3fp_es_pret "$_S10_NS" "$_S10_ES" || { f3fp_refus "ExternalSecret $_S10_ES pas Ready dans $_S10_NS (M25-E14/E15)"; return 1; }
}

panne_S10_v1() {
  local a
  _s10_sain || return 1
  a="$(m25_actif)" || return 1
  f3fp_ecrire S10 noeud-keepalived "$a"
  m25_exec "$a" >/dev/null <<'EOF' || return 1
systemctl stop keepalived
journal "keepalived arrêté sur le nœud actif"
EOF
  f3fp_journal S10 "keepalived arrêté sur $a (nœud actif)"
  f3fp_es_rafraichir "$_S10_NS" "$_S10_ES" || true
}

panne_S10_v2() {
  local r p
  _s10_sain || return 1
  m25_jeton_charger || { f3fp_refus "jeton OpenBao plateforme-admin requis pour cette variante"; return 1; }
  r="$(_s10_role)"
  jq -e --arg p "$_S10_ROLE" '(.data.token_policies // []) == [$p]' >/dev/null 2>&1 <<<"$r" ||
    { f3fp_refus "rôle $_S10_ROLE inattendu (token_policies ≠ [$_S10_ROLE])"; return 1; }
  p="$(m25_api GET "sys/policies/acl/$_S10_ROLE" 2>/dev/null | jq -r '.data.policy // empty' 2>/dev/null || true)"
  grep -q 'db-mediagenda/creds/' <<<"$p" || { f3fp_refus "la politique $_S10_ROLE ne donne pas les identifiants dynamiques (M25-E14)"; return 1; }
  f3fp_ecrire_si_absent S10 role.json "$(jq -c '.data | {bound_service_account_names, bound_service_account_namespaces,
    audience, alias_name_source, token_ttl, token_max_ttl, token_type, token_policies}' <<<"$r")"
  # Politique « KV seulement » : celle d'origine sans les blocs db-mediagenda (un bloc path = une
  # ligne d'ouverture jusqu'à l'accolade fermante en début de ligne).
  awk 'BEGIN { print "# eso-mediagenda-recette-kv — moindre privilège pour ESO en recette (PLAT-3310, F3-S10)." }
       /^path "db-mediagenda\// { saute = 1 }
       !saute { print }
       saute && /^}/ { saute = 0 }' <<<"$p" | jq -Rs '{policy: .}' |
    m25_api PUT "sys/policies/acl/$_S10_POL_KV" - >/dev/null || return 1
  f3fp_lire S10 role.json | jq -c --arg k "$_S10_POL_KV" '.token_policies = [$k]' |
    m25_api POST "auth/k8s-par1/role/$_S10_ROLE" - >/dev/null || return 1
  f3fp_journal S10 "rôle $_S10_ROLE : token_policies = [$_S10_POL_KV] (politique sans db-mediagenda)"
  f3fp_es_rafraichir "$_S10_NS" "$_S10_ES" || true
}

panne_S10_v3() {
  local n url g
  _s10_sain || return 1
  n="$(m25_en_attente_au_hasard)" || return 1
  url="https://$n.$_M25_DOMAINE:$_M25_PORT"
  f3fp_ecrire S10 noeud-arrete "$n"
  wb_k8s_sauver secretstores.external-secrets.io openbao "$_S10_NS"
  wb_kubectl -n "$_S10_NS" patch secretstores.external-secrets.io openbao --type=merge \
    -p "{\"spec\":{\"provider\":{\"vault\":{\"server\":\"$url\"}}}}" >/dev/null || return 1
  for g in "${_S10_GENERATEURS[@]}"; do
    wb_kubectl -n "$_S10_NS" get vaultdynamicsecrets.generators.external-secrets.io "$g" >/dev/null 2>&1 || continue
    wb_k8s_sauver vaultdynamicsecrets.generators.external-secrets.io "$g" "$_S10_NS"
    wb_kubectl -n "$_S10_NS" patch vaultdynamicsecrets.generators.external-secrets.io "$g" --type=merge \
      -p "{\"spec\":{\"provider\":{\"server\":\"$url\"}}}" >/dev/null || return 1
  done
  f3fp_journal S10 "SecretStore et générateurs de $_S10_NS épinglés sur $url"
  m25_exec "$n" >/dev/null <<'EOF' || return 1
systemctl stop openbao
journal "openbao arrêté (nœud en attente épinglé par les clients de recette)"
EOF
  f3fp_journal S10 "openbao arrêté sur $n (nœud en attente)"
  f3fp_es_rafraichir "$_S10_NS" "$_S10_ES" || true
}

verifier_S10() {
  local n
  case "$WB_VAR" in
    1)
      f3fp_attendre 30 eval '! _s10_vip_sert' || return 1
      [[ "$(_s10_porteurs_vip)" == 0 ]]
      ;;
    2)
      _s10_role | jq -e --arg k "$_S10_POL_KV" '(.data.token_policies // []) == [$k]' >/dev/null 2>&1
      ;;
    3)
      n="$(f3fp_lire S10 noeud-arrete)"
      [[ -n "$n" ]] || return 1
      wb_kubectl -n "$_S10_NS" get secretstores.external-secrets.io openbao -o jsonpath='{.spec.provider.vault.server}' 2>/dev/null |
        grep -q "$n" || return 1
      f3fp_attendre 30 m25_hors_service "$n"
      ;;
    *) return 1 ;;
  esac
}

annuler_S10() {
  local n r p
  # 1. keepalived : relancé là où il est arrêté (la VIP revient sur l'actif ; sans préemption, sans effet
  #    si elle est déjà portée).
  for n in "${_M25_NOEUDS[@]}"; do
    m25_exec "$n" >/dev/null 2>&1 <<'EOF' || true
if systemctl is-enabled --quiet keepalived 2>/dev/null && ! systemctl is-active --quiet keepalived; then
  systemctl start keepalived && journal "annulation : keepalived relancé"
fi
EOF
  done
  # 2. Rôle et politique (variante 2), seulement s'ils portent encore la marque de l'incident.
  r="$(f3fp_lire S10 role.json)"
  if [[ -n "$r" ]]; then
    if m25_jeton_charger; then
      if _s10_role | jq -e --arg k "$_S10_POL_KV" '(.data.token_policies // []) | index($k) != null' >/dev/null 2>&1; then
        printf '%s\n' "$r" | m25_api POST "auth/k8s-par1/role/$_S10_ROLE" - >/dev/null ||
          wb_avert "rôle $_S10_ROLE non restauré : rejoue le pipeline de plateforme/secrets (tofu apply)"
      fi
      p="$(m25_api GET "sys/policies/acl/$_S10_POL_KV" 2>/dev/null | jq -r '.data.policy // empty' 2>/dev/null || true)"
      if grep -q 'F3-S10' <<<"$p"; then
        m25_api DELETE "sys/policies/acl/$_S10_POL_KV" >/dev/null || wb_avert "politique $_S10_POL_KV non supprimée"
      fi
      f3fp_oublier S10 role.json
    else
      wb_avert "annulation incomplète sans jeton plateforme-admin : connecte-toi (bao login -method=oidc) puis relance « lab/bin/break F3 10 --annuler »"
    fi
  fi
  # 3. Objets Kubernetes (variante 3).
  wb_k8s_restaurer || wb_avert "SecretStore ou générateurs de $_S10_NS non restaurés (task appliquer dans plateforme/k8s)"
  # 4. openbao relancé sur le nœud arrêté (variante 3), seulement s'il est hors service.
  n="$(f3fp_lire S10 noeud-arrete)"
  if [[ -n "$n" ]]; then
    m25_relancer_si_besoin "$n"
    f3fp_oublier S10 noeud-arrete
  fi
  f3fp_oublier S10 noeud-keepalived
  f3fp_attendre 60 _s10_vip_sert || wb_avert "la VIP du coffre ne sert pas encore (RB-251, journalctl -u keepalived)"
  f3fp_es_rafraichir "$_S10_NS" "$_S10_ES" || true
  f3fp_attendre 90 f3fp_es_pret "$_S10_NS" "$_S10_ES" ||
    wb_avert "ExternalSecret $_S10_ES pas encore Ready : kubectl -n $_S10_NS describe es $_S10_ES"
  f3fp_journal S10 "annulation"
}

symptome_S10() {
  _f3p_symptome S10 INC-5910 "INC-5910 — Jeudi 9 h 40 — De : Julien Petit (MédiAgenda)" \
    "« En recette, Argo CD montre mediagenda-recette en Degraded à cause d'un ExternalSecret, et nos" \
    "tests de bout en bout commencent à tomber avec \"password authentication failed for user v-…\"." \
    "Pas tout le temps : un pod sur deux, puis de plus en plus. On n'a rien livré depuis hier." \
    "La prod a l'air d'aller, mais elle utilise le même coffre, non ? »" \
    "" \
    "Selon la cause, l'API tombe tout de suite ou dans l'heure (fin des baux en cours)." \
    "Temps cible : 60 min."
}

resume_S10() { echo "MédiAgenda (recette) perd peu à peu sa base : identifiants dynamiques non renouvelés"; }

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main F3 S10 3 "$@"; }
fi
