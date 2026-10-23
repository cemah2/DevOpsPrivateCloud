# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# break-E37.sh — M25-E37 « Panne : un ExternalSecret en erreur »
#
# En recette, l'ExternalSecret harbor-pull de mediagenda-recette passe en SecretSyncedError : le Secret
# n'est plus mis à jour. Variantes :
#   1. SecretStore « openbao » de l'espace en « version: v1 » : ESO lit kv/mediagenda/recette/… (sans
#      data/), chemin qu'aucune politique n'ouvre → 403 « permission denied », le magasin reste « Valid » ;
#   2. audience du rôle eso-mediagenda-recette (méthode k8s-par1) changée DANS OpenBao
#      (openbao.par1.medisphere.internal) : la connexion d'ESO est refusée ; les jetons d'ESO de ce rôle
#      sont révoqués pour que l'effet soit immédiat (sinon : à l'expiration du jeton en cache, 15 min) ;
#   3. CiliumNetworkPolicy SUPPLÉMENTAIRE « external-secrets-telemetrie » (espace external-secrets) dont
#      un egressDeny couvre 10.10.20.192/26 port 8200 : ESO ne joint plus la VIP 10.10.20.200 ; le pod du
#      contrôleur est recréé (connexions établies et cache de jetons perdus) ; TOUS les magasins du
#      cluster finissent en erreur ;
#   4. SecretStore qui référence un compte de service inexistant (external-secrets au lieu de eso) :
#      le magasin passe « InvalidProviderConfig », l'ExternalSecret « SecretStore … is not ready ».
#
# Objets Kubernetes touchés : SecretStore (appliqué par « task appliquer » de plateforme/k8s, pas par
# Argo CD) et CNP créée hors Git (Argo CD ne la suit pas). L'ExternalSecret (Argo CD, selfHeal) n'est
# PAS modifié dans sa spec : seule l'annotation « force-sync » est posée pour déclencher la
# synchronisation tout de suite (métadonnée hors du manifeste : Argo CD ne la voit pas comme une dérive) ;
# elle est retirée à l'annulation.
# Sauvegardes : wb_k8s_sauver (~/.local/state/workbook/k8s/M25-E37/) ; audience du rôle dans
# ~/.local/state/workbook/M25-E37/ (700). Annulation : restauration de ces valeurs (identiques au dépôt :
# une réparation par « task appliquer » ou par le pipeline de plateforme/secrets n'est pas défaite).

# shellcheck source=../../../../lab/lib/pannes-lib.sh disable=SC1091
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m25-commun-b.sh
source "$WB_ROOT/modules/25-secrets/corrige/pannes/_m25-commun-b.sh"

_E37_NS=mediagenda-recette
_E37_ES=harbor-pull
_E37_SS=openbao
_E37_ROLE=eso-mediagenda-recette
_E37_AUD=openbao.medisphere.internal
_E37_AUD_FAUSSE=openbao.par1.medisphere.internal
_E37_CNP=external-secrets-telemetrie
_E37_SA_FAUX=external-secrets
_E37_T_ES=externalsecrets.external-secrets.io
_E37_T_SS=secretstores.external-secrets.io
_E37_T_CNP=ciliumnetworkpolicies.cilium.io

_e37_ss() { wb_kubectl -n "$_E37_NS" get "$_E37_T_SS" "$_E37_SS" -o json 2>/dev/null; }
_e37_es() { wb_kubectl -n "$_E37_NS" get "$_E37_T_ES" "$_E37_ES" -o json 2>/dev/null; }
_e37_role() { m25b_api GET "auth/k8s-par1/role/$_E37_ROLE" 2>/dev/null; }

# _e37_cond JSON True|False — condition Ready du statut (magasin ou ExternalSecret) à cette valeur.
_e37_cond() { jq -e --arg s "$2" '[.status.conditions[]? | select(.type == "Ready" and .status == $s)] | length > 0' >/dev/null 2>&1 <<<"$1"; }
_e37_es_en_erreur() { local j; j="$(_e37_es)" && jq -e '[.status.conditions[]? | select(.type == "Ready" and .status == "False" and .reason == "SecretSyncedError")] | length > 0' >/dev/null 2>&1 <<<"$j"; }
_e37_ss_en_erreur() { local j; j="$(_e37_ss)" && _e37_cond "$j" False; }
_e37_es_pret() { local j; j="$(_e37_es)" && _e37_cond "$j" True; }

# _e37_pret — état d'entrée conforme au corrigé (M25-E12/E13) : magasin et ExternalSecret prêts.
_e37_pret() {
  local ss es
  ss="$(_e37_ss)" || { wb_avert "SecretStore $_E37_SS introuvable dans $_E37_NS (M25-E13 fait ?)"; return 1; }
  jq -e --arg r "$_E37_ROLE" '.spec.provider.vault | .version == "v2" and .path == "kv"
      and .auth.kubernetes.role == $r and .auth.kubernetes.serviceAccountRef.name == "eso"' >/dev/null 2>&1 <<<"$ss" \
    || { wb_avert "SecretStore $_E37_NS/$_E37_SS différent du corrigé de M25-E13 : rien n'est cassé"; return 1; }
  _e37_cond "$ss" True || { wb_avert "SecretStore $_E37_NS/$_E37_SS pas prêt avant l'injection : répare d'abord"; return 1; }
  es="$(_e37_es)" || { wb_avert "ExternalSecret $_E37_NS/$_E37_ES introuvable (M25-E13 fait ?)"; return 1; }
  _e37_cond "$es" True || { wb_avert "ExternalSecret $_E37_NS/$_E37_ES déjà en erreur : répare d'abord"; return 1; }
}

# _e37_forcer — déclenche la synchronisation de l'ExternalSecret (annotation, hors spec).
_e37_forcer() {
  wb_kubectl -n "$_E37_NS" annotate --overwrite "$_E37_T_ES" "$_E37_ES" "force-sync=$(date +%s)" >/dev/null
}

panne_E37_v1() {
  _e37_pret || return 1
  wb_k8s_sauver "$_E37_T_SS" "$_E37_SS" "$_E37_NS"
  wb_kubectl -n "$_E37_NS" patch "$_E37_T_SS" "$_E37_SS" --type=merge \
    -p '{"spec":{"provider":{"vault":{"version":"v1"}}}}' >/dev/null || return 1
  sleep 5
  _e37_forcer || return 1
  m25b_journal E37 "SecretStore $_E37_NS/$_E37_SS : version v1"
}

panne_E37_v2() {
  local r a n=0
  m25b_jeton_charger || return 1
  _e37_pret || return 1
  r="$(_e37_role)" || { wb_avert "rôle $_E37_ROLE illisible (jeton plateforme-admin ?)"; return 1; }
  jq -e --arg a "$_E37_AUD" '.data.audience == $a' >/dev/null 2>&1 <<<"$r" \
    || { wb_avert "audience du rôle $_E37_ROLE inattendue (M25-E13 fait ?) : rien n'est cassé"; return 1; }
  m25b_ecrire_si_absent E37 audience "$_E37_AUD"
  jq -nc --arg a "$_E37_AUD_FAUSSE" '{audience: $a}' \
    | m25b_api POST "auth/k8s-par1/role/$_E37_ROLE" - >/dev/null || return 1
  # Jetons d'ESO de ce rôle (en cache dans le contrôleur) : révoqués, ESO doit se reconnecter.
  while IFS= read -r a; do
    [[ -n "$a" ]] || continue
    if jq -nc --arg a "$a" '{accessor: $a}' | m25b_api POST auth/token/lookup-accessor - 2>/dev/null \
      | jq -e --arg r "$_E37_ROLE" '.data.meta.role == $r' >/dev/null 2>&1; then
      jq -nc --arg a "$a" '{accessor: $a}' | m25b_api POST auth/token/revoke-accessor - >/dev/null || true
      n=$((n + 1))
    fi
  done < <(m25b_api GET 'auth/token/accessors?list=true' 2>/dev/null | jq -r '.data.keys[]? // empty' 2>/dev/null || true)
  _e37_forcer || return 1
  m25b_journal E37 "rôle $_E37_ROLE : audience $_E37_AUD_FAUSSE ; $n jeton(s) d'ESO révoqué(s)"
}

panne_E37_v3() {
  _e37_pret || return 1
  wb_k8s_sauver "$_E37_T_CNP" "$_E37_CNP" external-secrets
  wb_kubectl apply -f - >/dev/null <<EOF || return 1
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: $_E37_CNP
  namespace: external-secrets
  annotations:
    medisphere.internal/ticket: "OBS-2637"
spec:
  description: "ESO : télémétrie vers le collecteur, anciennes plages de service fermées (OBS-2637)"
  endpointSelector:
    matchLabels:
      app.kubernetes.io/instance: external-secrets
  egressDeny:
    - toCIDR:
        - 10.10.20.192/26
      toPorts:
        - ports:
            - port: "8200"
              protocol: TCP
EOF
  # Connexions établies et jetons en cache : on repart d'un contrôleur neuf (pod recréé par son Deployment).
  wb_kubectl -n external-secrets delete pod \
    -l app.kubernetes.io/name=external-secrets,app.kubernetes.io/instance=external-secrets --wait=false >/dev/null || return 1
  sleep 5
  wb_kubectl -n external-secrets rollout status deployment/external-secrets --timeout=180s >/dev/null || return 1
  _e37_forcer || return 1
  m25b_journal E37 "CNP external-secrets/$_E37_CNP (egressDeny 10.10.20.192/26:8200) ; contrôleur d'ESO recréé"
}

panne_E37_v4() {
  _e37_pret || return 1
  wb_k8s_sauver "$_E37_T_SS" "$_E37_SS" "$_E37_NS"
  wb_kubectl -n "$_E37_NS" patch "$_E37_T_SS" "$_E37_SS" --type=merge -p \
    "$(jq -nc --arg sa "$_E37_SA_FAUX" '{spec: {provider: {vault: {auth: {kubernetes: {serviceAccountRef: {name: $sa}}}}}}}')" \
    >/dev/null || return 1
  m25b_attendre 90 _e37_ss_en_erreur || true
  _e37_forcer || return 1
  m25b_journal E37 "SecretStore $_E37_NS/$_E37_SS : compte de service $_E37_SA_FAUX (inexistant)"
}

verifier_E37() {
  local ss
  case "$WB_VAR" in
    1) ss="$(_e37_ss)" && jq -e '.spec.provider.vault.version == "v1"' >/dev/null 2>&1 <<<"$ss" ;;
    2) m25b_jeton_charger && _e37_role | jq -e --arg a "$_E37_AUD_FAUSSE" '.data.audience == $a' >/dev/null 2>&1 ;;
    3) wb_kubectl -n external-secrets get "$_E37_T_CNP" "$_E37_CNP" >/dev/null 2>&1 ;;
    4) ss="$(_e37_ss)" && jq -e --arg sa "$_E37_SA_FAUX" '.spec.provider.vault.auth.kubernetes.serviceAccountRef.name == $sa' >/dev/null 2>&1 <<<"$ss" ;;
    *) return 1 ;;
  esac || return 1
  # Le symptôme lui-même : l'ExternalSecret en SecretSyncedError (délais de connexion compris en v3).
  m25b_attendre 360 _e37_es_en_erreur
}

# _e37_revalider_magasin — fait revalider le magasin tout de suite (deux mises à jour de métadonnée ;
#   sans elles, le contrôleur réessaie à intervalle croissant).
_e37_revalider_magasin() {
  wb_kubectl -n "$_E37_NS" annotate --overwrite "$_E37_T_SS" "$_E37_SS" "wb-revalider=$(date +%s)" >/dev/null 2>&1 || true
  sleep 2
  wb_kubectl -n "$_E37_NS" annotate "$_E37_T_SS" "$_E37_SS" wb-revalider- >/dev/null 2>&1 || true
}

annuler_E37() {
  local a
  # Rôle OpenBao (variante 2).
  if m25b_existe E37 audience; then
    a="$(m25b_lire E37 audience)"
    if m25b_jeton_charger; then
      if jq -nc --arg a "$a" '{audience: $a}' | m25b_api POST "auth/k8s-par1/role/$_E37_ROLE" - >/dev/null; then
        m25b_oublier E37 audience
      else
        wb_avert "audience du rôle $_E37_ROLE non restaurée (ou rejoue plateforme/secrets : tofu apply)"
      fi
    else
      wb_avert "audience du rôle $_E37_ROLE non restaurée : connecte-toi (bao login -method=oidc) puis relance « lab/bin/break 25 37 --annuler »"
      wb_avert "(ou rejoue plateforme/secrets : le pipeline remet audience = $_E37_AUD)"
    fi
  fi
  # SecretStore (variantes 1 et 4), CNP supplémentaire (variante 3, supprimée).
  wb_k8s_restaurer || wb_avert "objets Kubernetes non restaurés : voir ~/.local/state/workbook/k8s/M25-E37/ (ou task appliquer dans plateforme/k8s)"
  _e37_revalider_magasin
  # Retrait de l'annotation posée par l'injection : nouvelle synchronisation.
  wb_kubectl -n "$_E37_NS" annotate "$_E37_T_ES" "$_E37_ES" force-sync- >/dev/null 2>&1 || true
  m25b_attendre 120 _e37_es_pret || wb_avert "ExternalSecret $_E37_NS/$_E37_ES pas encore prêt : ESO réessaie seul (quelques minutes)"
  m25b_journal E37 "annulation"
}

symptome_E37() {
  wb_symptome "INC-5237 — De : Julien Petit — Recette : le Secret de MédiAgenda n'est plus mis à jour" \
    "Argo CD affiche l'application mediagenda-recette « Degraded » : l'ExternalSecret harbor-pull est" \
    "en SecretSyncedError et le Secret harbor-pull n'est plus mis à jour depuis le coffre. Personne de" \
    "l'équipe n'a touché à l'overlay de recette. Les nouveaux pods risquent de ne plus tirer leurs images" \
    "quand le robot Harbor tournera ; dans certaines variantes, les identifiants de base de la recette" \
    "(baux d'une heure) ne sont plus renouvelés non plus : ne laisse pas traîner." \
    "Temps cible : 30 min. Contrôle : lab/bin/check 25 37"
}

resume_E37() { echo "en recette, l'ExternalSecret harbor-pull de MédiAgenda est en SecretSyncedError (Secret plus mis à jour)"; }

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 25 E37 4 "$@"; }
fi
