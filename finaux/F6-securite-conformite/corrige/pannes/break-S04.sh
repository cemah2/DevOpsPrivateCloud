# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # expressions jq entre apostrophes
# break-S04.sh — F6-S04 « Panne : les écarts cachés de l'audit à blanc » (BF, LOT d'écarts).
#
# L'injection pose un LOT d'écarts réalistes et réversibles, tirés au hasard parmi sept candidats
# (WB_F6_S04_NB, défaut 4), chacun vérifié sur place. L'apprenant doit les trouver par l'audit (revue
# des accès, preuves, audit technique), les numéroter ECA-3611 et suivants, et les corriger.
#
# Candidats :
#   1. compte réactivé : un compte GitLab d'AxiomDev (bloqué au départ du prestataire, F2-S12) est
#      DÉBLOQUÉ (API d'administration) ;
#   2. bordure : règle nftables d'ouverture posée À CHAUD sur gw01 et gw02 (SANDBOX → git01 en SSH,
#      commentaire « acces-temporaire-infoger »), absente de /etc/nftables.conf et du code ;
#   3. dérogation sans échéance : PolicyException « recette-derogation-temporaire » posée à la main dans
#      kyverno-exceptions : la signature des images n'est plus exigée en recette, sans expiresAt, hors
#      registre et hors Git ;
#   4. secret en clair : ConfigMap « mediagenda-parametres-essai » en recette avec un identifiant et un
#      mot de passe de base (FICTIFS : aucun rôle PostgreSQL ne porte ce nom) en clés séparées — la
#      politique interdire-identifiants-url (M26-E16) ne vise que les URL à identifiants ;
#   5. sauvegarde suspendue : la planification Velero de la recette (recette-quotidienne, sinon la
#      première étiquetée medisphere.internal/sauvegarde=quotidienne) passe en spec.paused: true ;
#   6. droits excessifs : compte de service mediagenda-recette/outil-diagnostic lié à cluster-admin par
#      la ClusterRoleBinding « outil-diagnostic-temporaire » ;
#   7. supervision muette : silence Alertmanager de 60 jours sur les alertes de sécurité
#      (alertname=~"AlerteFalco|Audit.*"), auteur « lucas.martin ».
# (La « rétention d'audit raccourcie » a été écartée des candidats : la raccourcir réellement efface
# des journaux d'audit au passage suivant du compacteur de Loki — perte de données, interdite.)
#
# Règles (CONVENTIONS §8, §11.10-11.11 ; PLAN §4.12 à §4.15) : contrôle préalable (lab sain) ; recette,
# kyverno-exceptions, velero, Alertmanager, bordure et GitLab seulement ; jamais kube-system, kyverno,
# argocd, ni un espace *-prod ; aucune donnée supprimée (une sauvegarde suspendue reprend à la
# planification suivante) ; chaque écart est noté dans l'état local et défait par --annuler SEULEMENT
# s'il est encore dans l'état injecté (une réparation de l'apprenant n'est jamais défaite).
# État local : ~/.local/state/workbook/F6-S04/ (700) et ~/.local/state/workbook/k8s/F6-S04/.
# Outils requis sur adm01 : kubectl (kubeconfig d'administration), jq, curl, yq (mikefarah v4) ;
# jeton GitLab d'administration (WB_GITLAB_ADMIN_TOKEN_FILE, candidat 1) ; SSH admin + sudo vers les
# passerelles (candidat 2). Un candidat dont les prérequis manquent est écarté du tirage.
# Variables : WB_F6_S04_NB (défaut 4, de 3 à 7), WB_F6_S04_ECARTS (liste forcée, ex. « 1,3,5,7 »),
# WB_F6_PASSERELLES, WB_F6_EXTERNES, WB_AM_URL, WB_GITLAB_URL.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"

_S04_NS=mediagenda-recette
_S04_NS_EXC=kyverno-exceptions
_S04_POLEX=recette-derogation-temporaire
_S04_CM=mediagenda-parametres-essai
_S04_SA=outil-diagnostic
_S04_CRB=outil-diagnostic-temporaire
_S04_NFT_COMMENTAIRE=acces-temporaire-infoger
_S04_NB="${WB_F6_S04_NB:-4}"
_S04_GW="${WB_F6_PASSERELLES:-gw01 gw02}"
_S04_EXTERNES="${WB_F6_EXTERNES:-marc.vidal yanis.perrin}"
_S04_AM="${WB_AM_URL:-http://alertmanager.apps.par1.medisphere.internal:9093}"
_S04_GITLAB="${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}"
_S04_TOUS=(1 2 3 4 5 6 7)

# ---------------------------------------------------------------------------
# État local
# ---------------------------------------------------------------------------
_s04_etat() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/F6-S04"
  mkdir -p "$d" && chmod 700 "$d"
  printf '%s\n' "$d"
}
_s04_poser() { printf '%s\n' "$2" >"$(_s04_etat)/$1"; }
_s04_lire() {
  local f
  f="$(_s04_etat)/$1"
  if [[ -f "$f" ]]; then cat "$f"; fi
}
_s04_oublier() { rm -f -- "$(_s04_etat)/$1"; }
_s04_journal() { printf '%s [F6-S04] %s\n' "$(date -Is)" "$*" >>"$(_s04_etat)/journal"; }

# ---------------------------------------------------------------------------
# Contrôle préalable : le lab doit être sain
# ---------------------------------------------------------------------------
_s04_sain() {
  local c
  for c in kubectl jq curl yq; do
    command -v "$c" >/dev/null 2>&1 || { echo "outil manquant sur adm01 : $c" >&2; return 1; }
  done
  yq --version 2>/dev/null | grep -q mikefarah || { echo "yq de mikefarah (v4) attendu sur adm01" >&2; return 1; }
  [[ "$_S04_NB" =~ ^[3-7]$ ]] || { echo "WB_F6_S04_NB doit valoir 3 à 7 (reçu : $_S04_NB)" >&2; return 1; }
  wb_kubectl get --raw /readyz >/dev/null 2>&1 || { echo "L'API de k8s-par1 ne répond pas avec le kubeconfig d'administration." >&2; return 1; }
  wb_kubectl get namespace "$_S04_NS" "$_S04_NS_EXC" >/dev/null 2>&1 ||
    { echo "Les espaces $_S04_NS et $_S04_NS_EXC doivent exister (M26)." >&2; return 1; }
  if [[ -n "$(_s04_lire lot)" ]]; then
    echo "Un lot F6-S04 est déjà noté dans $(_s04_etat) : lance d'abord lab/bin/break F6 4 --annuler." >&2
    return 1
  fi
  if wb_kubectl -n "$_S04_NS_EXC" get policyexceptions.policies.kyverno.io "$_S04_POLEX" >/dev/null 2>&1 ||
    wb_kubectl get clusterrolebinding "$_S04_CRB" >/dev/null 2>&1 ||
    wb_kubectl -n "$_S04_NS" get configmap "$_S04_CM" >/dev/null 2>&1; then
    echo "Des objets d'une injection précédente existent encore : lab/bin/break F6 4 --annuler." >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# 1. Compte d'AxiomDev débloqué dans GitLab
# ---------------------------------------------------------------------------
_s04_enc() { jq -rn --arg s "$1" '$s|@uri'; }
_s04_gitlab() {
  local m="$1" p="$2" f t
  f="${WB_GITLAB_ADMIN_TOKEN_FILE:-$HOME/.config/workbook/gitlab-admin.token}"
  [[ -r "$f" ]] || return 3
  t="$(tr -d '[:space:]' <"$f")"
  curl -sf --max-time 30 -X "$m" -H @<(printf 'PRIVATE-TOKEN: %s\n' "$t") "$_S04_GITLAB/api/v4/$p"
}
_s04_c1() {
  local u id etat
  for u in $_S04_EXTERNES; do
    id="$(_s04_gitlab GET "users?username=$(_s04_enc "$u")" | jq -r '.[0].id // empty')" || return 10
    [[ -n "$id" ]] || continue
    etat="$(_s04_gitlab GET "users/$id" | jq -r '.state // empty')" || continue
    [[ "$etat" == blocked ]] || continue
    _s04_gitlab POST "users/$id/unblock" >/dev/null || return 1
    _s04_poser c1 "$id $u"
    _s04_journal "candidat 1 : compte GitLab $u (id $id) débloqué"
    return 0
  done
  return 10    # aucun compte d'AxiomDev bloqué (F2-S12 non fait ?) : candidat écarté
}
_s04_c1_effectif() {
  local id
  read -r id _ <<<"$(_s04_lire c1)"
  [[ -n "${id:-}" ]] && [[ "$(_s04_gitlab GET "users/$id" | jq -r '.state // empty')" == active ]]
}
_s04_c1_defaire() {
  local id u
  read -r id u <<<"$(_s04_lire c1)"
  [[ -n "${id:-}" ]] || return 0
  if _s04_c1_effectif; then
    if _s04_gitlab POST "users/$id/block" >/dev/null; then _s04_journal "annulation : compte $u rebloqué"
    else wb_avert "compte GitLab $u (id $id) à rebloquer à la main"; fi
  else
    _s04_journal "annulation : compte $u déjà traité par l'apprenant"
  fi
  _s04_oublier c1
}

# ---------------------------------------------------------------------------
# 2. Règle posée à chaud sur la bordure
# ---------------------------------------------------------------------------
_s04_c2() {
  local gw n=0
  for gw in $_S04_GW; do
    if wb_exec "$gw" COMMENTAIRE="$_S04_NFT_COMMENTAIRE" >/dev/null 2>&1 <<'EOF'; then
nft list chain inet filter forward >/dev/null 2>&1 || exit 10
grep -qF "$COMMENTAIRE" /etc/nftables.conf 2>/dev/null && exit 10
nft list chain inet filter forward | grep -qF "comment \"$COMMENTAIRE\"" && exit 0
nft insert rule inet filter forward ip saddr 10.10.99.0/24 ip daddr 10.10.20.12 tcp dport 22 counter accept comment "\"$COMMENTAIRE\"" || exit 1
journal "règle « $COMMENTAIRE » insérée à chaud en tête de inet filter forward (F6-S04)"
EOF
      n=$((n + 1))
    else
      # Une passerelle a refusé : on retire ce qui a été posé ailleurs et on écarte le candidat.
      _s04_c2_defaire
      return 10
    fi
  done
  ((n > 0)) || return 10
  _s04_poser c2 "$_S04_GW"
  _s04_journal "candidat 2 : règle à chaud sur $_S04_GW"
}
_s04_c2_effectif() {
  local gw
  for gw in $_S04_GW; do
    remote "$gw" "sudo -n nft list chain inet filter forward" 2>/dev/null | grep -qF "comment \"$_S04_NFT_COMMENTAIRE\"" || return 1
  done
}
_s04_c2_defaire() {
  local gw
  for gw in $_S04_GW; do
    wb_exec "$gw" COMMENTAIRE="$_S04_NFT_COMMENTAIRE" >/dev/null 2>&1 <<'EOF' || wb_avert "règle « $_S04_NFT_COMMENTAIRE » à vérifier sur $gw (nft -a list chain inet filter forward)"
for h in $(nft -a list chain inet filter forward 2>/dev/null | grep -F "comment \"$COMMENTAIRE\"" | sed -n 's/.*# handle \([0-9][0-9]*\)$/\1/p'); do
  nft delete rule inet filter forward handle "$h" && journal "règle « $COMMENTAIRE » retirée (handle $h, F6-S04)"
done
exit 0
EOF
  done
  _s04_oublier c2
}

# ---------------------------------------------------------------------------
# 3. Dérogation Kyverno sans échéance, hors registre et hors Git
# ---------------------------------------------------------------------------
_s04_c3() {
  wb_k8s_sauver policyexceptions.policies.kyverno.io "$_S04_POLEX" "$_S04_NS_EXC"
  cat <<EOF | wb_kubectl apply -f - >/dev/null || return 10   # refus de l'admission : candidat écarté
apiVersion: policies.kyverno.io/v1
kind: PolicyException
metadata:
  name: $_S04_POLEX
  namespace: $_S04_NS_EXC
  annotations:
    medisphere.internal/note: "le temps de tester l'image de debug en recette"
spec:
  policyRefs:
    - name: exiger-signature-medisphere
      kind: ImageValidatingPolicy
  matchConditions:
    - name: recette
      expression: "object.metadata.namespace == '$_S04_NS'"
EOF
  _s04_poser c3 posee
  _s04_journal "candidat 3 : PolicyException $_S04_NS_EXC/$_S04_POLEX"
}
_s04_c3_effectif() {
  wb_kubectl -n "$_S04_NS_EXC" get policyexceptions.policies.kyverno.io "$_S04_POLEX" -o json 2>/dev/null |
    jq -e '(.spec.expiresAt // "") == ""' >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# 4. Identifiants en clair dans une ConfigMap de recette
# ---------------------------------------------------------------------------
_s04_c4() {
  wb_k8s_sauver configmap "$_S04_CM" "$_S04_NS"
  # Valeurs FICTIVES (aucun rôle PostgreSQL ne s'appelle ainsi) : la découverte compte, pas le secret.
  cat <<EOF | wb_kubectl apply -f - >/dev/null || return 10   # refus de l'admission : candidat écarté
apiVersion: v1
kind: ConfigMap
metadata:
  name: $_S04_CM
  namespace: $_S04_NS
  annotations:
    medisphere.internal/note: "paramètres de l'essai de charge (copiés du poste de Lucas)"
data:
  DB_HOST: mediagenda-db-rw
  DB_NAME: mediagenda
  DB_USER: mediagenda_essai_charge
  DB_PASSWORD: Recette-Charge-2026!
  CHARGE_UTILISATEURS: "200"
EOF
  _s04_poser c4 posee
  _s04_journal "candidat 4 : ConfigMap $_S04_NS/$_S04_CM avec mot de passe en clair (fictif)"
}
_s04_c4_effectif() { wb_kubectl -n "$_S04_NS" get configmap "$_S04_CM" -o jsonpath='{.data.DB_PASSWORD}' 2>/dev/null | grep -q .; }

# ---------------------------------------------------------------------------
# 5. Planification Velero suspendue
# ---------------------------------------------------------------------------
_s04_c5() {
  local s
  if wb_kubectl -n velero get schedules.velero.io recette-quotidienne >/dev/null 2>&1; then
    s=recette-quotidienne
  else
    s="$(wb_kubectl -n velero get schedules.velero.io -l medisphere.internal/sauvegarde=quotidienne -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)" || s=""
  fi
  [[ -n "$s" ]] || return 10
  [[ "$(wb_kubectl -n velero get schedules.velero.io "$s" -o jsonpath='{.spec.paused}' 2>/dev/null)" != true ]] || return 10
  wb_kubectl -n velero patch schedules.velero.io "$s" --type merge -p '{"spec":{"paused":true}}' >/dev/null || return 1
  _s04_poser c5 "$s"
  _s04_journal "candidat 5 : planification Velero $s suspendue"
}
_s04_c5_effectif() {
  local s
  s="$(_s04_lire c5)"
  [[ -n "$s" && "$(wb_kubectl -n velero get schedules.velero.io "$s" -o jsonpath='{.spec.paused}' 2>/dev/null)" == true ]]
}
_s04_c5_defaire() {
  local s
  s="$(_s04_lire c5)"
  [[ -n "$s" ]] || return 0
  if _s04_c5_effectif; then
    if wb_kubectl -n velero patch schedules.velero.io "$s" --type merge -p '{"spec":{"paused":false}}' >/dev/null; then
      _s04_journal "annulation : planification $s reprise"
    else wb_avert "planification Velero $s à reprendre (spec.paused)"; fi
  fi
  _s04_oublier c5
}

# ---------------------------------------------------------------------------
# 6. Compte de service de recette lié à cluster-admin
# ---------------------------------------------------------------------------
_s04_c6() {
  wb_k8s_sauver serviceaccount "$_S04_SA" "$_S04_NS"
  wb_k8s_sauver clusterrolebinding "$_S04_CRB"
  cat <<EOF | wb_kubectl apply -f - >/dev/null || return 10   # refus de l'admission : candidat écarté
apiVersion: v1
kind: ServiceAccount
metadata:
  name: $_S04_SA
  namespace: $_S04_NS
  annotations:
    medisphere.internal/note: "outil de diagnostic de l'éditeur, temporaire"
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: $_S04_CRB
  annotations:
    medisphere.internal/note: "temporaire, pour le diagnostic de la lenteur de la recette"
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: $_S04_SA
    namespace: $_S04_NS
EOF
  _s04_poser c6 posee
  _s04_journal "candidat 6 : $_S04_NS/$_S04_SA lié à cluster-admin ($_S04_CRB)"
}
_s04_c6_effectif() {
  wb_kubectl get clusterrolebinding "$_S04_CRB" -o jsonpath='{.roleRef.name}' 2>/dev/null | grep -qx cluster-admin
}

# ---------------------------------------------------------------------------
# 7. Silence de 60 jours sur les alertes de sécurité
# ---------------------------------------------------------------------------
_s04_c7() {
  local corps id
  curl -sf --max-time 10 "$_S04_AM/api/v2/status" >/dev/null 2>&1 || return 10
  # Début une minute dans le passé : un léger décalage d'horloge entre adm01 et Alertmanager ne laisse
  # pas le silence « pending » (il ne serait pas constaté).
  corps="$(jq -nc --arg d "$(date -u -d '-1 min' +%Y-%m-%dT%H:%M:%SZ)" --arg f "$(date -u -d '+60 days' +%Y-%m-%dT%H:%M:%SZ)" '{
    matchers: [{name: "alertname", value: "AlerteFalco|Audit.*", isRegex: true, isEqual: true}],
    startsAt: $d, endsAt: $f, createdBy: "lucas.martin",
    comment: "Trop de bruit pendant les essais de charge de la recette, je remets après."}')"
  id="$(curl -sf --max-time 10 -X POST -H 'Content-Type: application/json' --data "$corps" "$_S04_AM/api/v2/silences" |
    jq -r '.silenceID // empty')" || return 1
  [[ -n "$id" ]] || return 1
  _s04_poser c7 "$id"
  _s04_journal "candidat 7 : silence $id (60 jours, AlerteFalco|Audit.*)"
}
_s04_c7_effectif() {
  local id
  id="$(_s04_lire c7)"
  [[ -n "$id" ]] && curl -sf --max-time 10 "$_S04_AM/api/v2/silence/$id" | jq -e '.status.state == "active"' >/dev/null 2>&1
}
_s04_c7_defaire() {
  local id
  id="$(_s04_lire c7)"
  [[ -n "$id" ]] || return 0
  if _s04_c7_effectif; then
    if curl -sf --max-time 10 -X DELETE "$_S04_AM/api/v2/silence/$id" >/dev/null; then
      _s04_journal "annulation : silence $id expiré"
    else wb_avert "silence $id à expirer dans Alertmanager"; fi
  fi
  _s04_oublier c7
}

# ---------------------------------------------------------------------------
# Tirage, vérification, annulation
# ---------------------------------------------------------------------------
_s04_effectif() { "_s04_c${1}_effectif"; }

# _s04_defaire_candidat N — défait UN candidat posé mais non constaté (il ne doit pas rester en plus du
# lot annoncé). Candidats 3, 4, 6 : objet créé par l'injection, supprimé.
_s04_defaire_candidat() {
  case "$1" in
    1) _s04_c1_defaire ;;
    2) _s04_c2_defaire ;;
    3) wb_kubectl -n "$_S04_NS_EXC" delete policyexceptions.policies.kyverno.io "$_S04_POLEX" --ignore-not-found >/dev/null; _s04_oublier c3 ;;
    4) wb_kubectl -n "$_S04_NS" delete configmap "$_S04_CM" --ignore-not-found >/dev/null; _s04_oublier c4 ;;
    5) _s04_c5_defaire ;;
    6) wb_kubectl delete clusterrolebinding "$_S04_CRB" --ignore-not-found >/dev/null
       wb_kubectl -n "$_S04_NS" delete serviceaccount "$_S04_SA" --ignore-not-found >/dev/null; _s04_oublier c6 ;;
    7) # posé mais pas encore actif : on l'expire quand même (DELETE expire aussi un silence en attente)
       local id
       id="$(_s04_lire c7)"
       [[ -z "$id" ]] || curl -sf --max-time 10 -X DELETE "$_S04_AM/api/v2/silence/$id" >/dev/null || wb_avert "silence $id à expirer"
       _s04_oublier c7 ;;
  esac
}

_s04_ordre() {
  if [[ -n "${WB_F6_S04_ECARTS:-}" ]]; then
    tr ',' '\n' <<<"$WB_F6_S04_ECARTS" | grep -E '^[1-7]$' | awk '!vu[$0]++'
  else
    printf '%s\n' "${_S04_TOUS[@]}" | shuf
  fi
}

_s04_defaire_tout() {
  _s04_c1_defaire || true
  _s04_c2_defaire || true
  _s04_c5_defaire || true
  _s04_c7_defaire || true
  # Candidats 3, 4, 6 : objets créés (sauvegardés « ABSENT ») → supprimés.
  wb_k8s_restaurer || wb_avert "restauration partielle des objets Kubernetes (voir ~/.local/state/workbook/k8s/F6-S04)"
  _s04_oublier c3
  _s04_oublier c4
  _s04_oublier c6
  _s04_oublier lot
}

panne_S04_v1() {
  local c rc lot=() objectif
  _s04_sain || return 1
  objectif="$_S04_NB"
  [[ -n "${WB_F6_S04_ECARTS:-}" ]] && objectif=7
  while IFS= read -r c; do
    ((${#lot[@]} < objectif)) || break
    rc=0
    "_s04_c$c" || rc=$?
    case "$rc" in
      0)
        if _s04_effectif "$c"; then
          lot+=("$c")
        else
          wb_avert "candidat $c posé mais non constaté : défait et écarté"
          _s04_defaire_candidat "$c" || wb_avert "candidat $c : retrait à vérifier"
        fi
        ;;
      10) ;;
      *)
        wb_avert "candidat $c : échec de l'injection"
        _s04_poser lot "${lot[*]}"
        return 1
        ;;
    esac
    _s04_poser lot "${lot[*]}"
  done < <(_s04_ordre)
  if ((${#lot[@]} < 3)); then
    wb_avert "moins de trois écarts injectables sur ce lab (F2-S12 et M26 faits ? passerelles joignables ?)"
    return 1
  fi
  _s04_journal "lot injecté : ${lot[*]}"
}

verifier_S04() {
  local c
  for c in $(_s04_lire lot); do
    _s04_effectif "$c" || return 1
  done
  [[ -n "$(_s04_lire lot)" ]]
}

annuler_S04() {
  _s04_defaire_tout
  _s04_journal "annulation terminée"
}

resume_S04() {
  echo "L'auditrice a relevé $(wc -w <<<"$(_s04_lire lot)") écarts qu'elle ne nomme pas, entre la revue des accès et aujourd'hui."
}

symptome_S04() {
  local n
  n="$(wc -w <<<"$(_s04_lire lot)")"
  wb_symptome "Ticket SEC-3604 — De : Hélène Mercier (Auditia Santé), relayé par Sophie Laurent" \
    "Bonjour. Hier soir, avec le compte de lecture que vous m'avez ouvert, j'ai refait un tour de ce" \
    "que vous m'aviez montré la semaine dernière : revue des accès, catalogue des preuves, dérogations," \
    "sauvegardes, bordure, supervision. J'ai noté $n choses qui ne collent plus avec ce que vous m'avez" \
    "présenté. Je ne vous dis pas lesquelles : un auditeur interne doit les trouver avant moi." \
    "Je reviens vendredi ; je veux, pour chacune, l'écart formalisé (ECA-3611 et suivants), sa cause," \
    "qui l'a introduit et quand, la correction et ce qui l'empêchera de revenir." \
    "" \
    "Temps cible : 3 h. Contrôle : lab/bin/check F6 4"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main F6 S04 1 "$@"; }
fi
