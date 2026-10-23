# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et scripts distants entre apostrophes
# break-S11.sh — F2-S11 « Panne : le prestataire voit trop de choses »
#
# Élargit le périmètre d'AxiomDev par UN des trois chemins qu'une revue d'accès doit savoir trouver :
#   1. GitLab : les personnes d'AxiomDev (WB_F2_AXIOM_PERSONNES) ajoutées en Developer, sans date
#      d'expiration, au GROUPE GitLab « mediagenda » (au lieu du seul projet mediagenda/api) : par
#      héritage, elles lisent mediagenda/deploiement, le chart, les issues de tous les projets ;
#   2. Kubernetes : ClusterRoleBinding « lecture-prestataires » qui donne le ClusterRole « view » à
#      oidc:ext-axiomdev sur TOUT le cluster (prod comprise ; « view » ne montre pas les Secrets) ;
#   3. annuaire : la seconde personne d'AxiomDev ajoutée au groupe FreeIPA « mediagenda » (sur ipa01,
#      cadre Python de FreeIPA en root, liaison LDAPI) : par le groupe, propriétaire Capsule en lecture
#      sur mediagenda-* (prod comprise), rôle Argo CD de l'équipe, Viewer Grafana, et Maintainer du
#      groupe GitLab mediagenda au prochain passage de synchro-gitlab.
#
# Garde-fous (CONVENTIONS §8, PLAN §4.12-4.14) : refus si le lab n'est pas sain (S10 en place, aucune
# des trois dérives déjà présente) ; jamais le compte de l'apprenant ni un compte de bris de glace ;
# aucune donnée touchée ; état noté dans ~/.local/state/workbook/F2-S11/ ; l'annulation ne défait que
# ce que la panne a posé ET qui est encore dans l'état injecté (une réparation n'est jamais défaite).
#
# Prérequis sur adm01 : jeton d'administration GitLab (WB_GITLAB_ADMIN_TOKEN_FILE, portée api, M01) ;
# SSH admin + sudo vers ipa01 et vers le premier nœud de contrôle (kubectl d'administration avec
# /etc/kubernetes/admin.conf, comme au M24) ou WB_K8S_ADMIN_KUBECONFIG ; jq, curl.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# Fonctions de lecture des checks du final (comptes de lecture : gitlab_api, kube, ipa_ldap).
# shellcheck source=../../checks/_f2-equipes.sh
source "$WB_ROOT/finaux/F2-day1/checks/_f2-equipes.sh"

_S11_GITLAB="${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}"
_S11_IPA="${WB_F2_IPA_HOTE:-ipa01}"
_S11_CP1="${WB_F2_CP1:-k8s-cp01}"
_S11_GROUPE_GITLAB="${WB_F2_S11_GROUPE_GITLAB:-mediagenda}"
_S11_GROUPE_IPA="${WB_F2_S11_GROUPE_IPA:-mediagenda}"
_S11_CRB=lecture-prestataires

# ---------------------------------------------------------------------------
# État local
# ---------------------------------------------------------------------------
_s11_etat() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/F2-S11"
  mkdir -p "$d" && chmod 700 "$d"
  printf '%s\n' "$d"
}
_s11_poser() { printf '%s\n' "$2" >"$(_s11_etat)/$1"; }
_s11_lire() {
  local f
  f="$(_s11_etat)/$1"
  if [[ -f "$f" ]]; then cat "$f"; fi
}
_s11_oublier() { rm -f -- "$(_s11_etat)/$1"; }
_s11_journal() {
  printf '%s [F2-S11 variante %s] %s\n' "$(date -Is)" "${WB_VAR:-?}" "$*" >>"$(_s11_etat)/journal"
}

# ---------------------------------------------------------------------------
# Accès d'administration
# ---------------------------------------------------------------------------

# _s11_gl MÉTHODE CHEMIN [options curl…] — API GitLab avec le jeton d'administration (jamais en argument).
_s11_gl() {
  local m="$1" p="$2" f t
  shift 2
  f="${WB_GITLAB_ADMIN_TOKEN_FILE:-$HOME/.config/workbook/gitlab-admin.token}"
  [[ -r "$f" ]] || { wb_avert "jeton d'administration GitLab illisible : $f"; return 1; }
  t="$(tr -d '[:space:]' <"$f")"
  curl -sf --max-time 30 -X "$m" -H @<(printf 'PRIVATE-TOKEN: %s\n' "$t") "$_S11_GITLAB/api/v4/$p" "$@"
}

# _s11_kubectl ARGS… — kubectl d'administration sans OIDC (WB_K8S_ADMIN_KUBECONFIG, sinon admin.conf
# lu en root sur le premier nœud de contrôle : après M24, le kubeconfig personnel exige un navigateur).
_s11_kubectl() {
  if [[ -n "${WB_K8S_ADMIN_KUBECONFIG:-}" ]]; then
    wb_kubectl "$@"
    return
  fi
  local a args=""
  for a in "$@"; do args+=" $(printf '%q' "$a")"; done
  remote "$_S11_CP1" "sudo -n kubectl --kubeconfig /etc/kubernetes/admin.conf --request-timeout=20s$args" </dev/null
}

# Prélude Python de l'annuaire : cadre FreeIPA côté serveur, liaison LDAPI en root (autobind, sans le
# mot de passe d'admin). Paramètres en JSON (sys.argv[1]), sortie JSON.
read -r -d '' _S11_IPA_PRELUDE <<'PY' || true
import json, sys
from ipalib import api, errors
api.bootstrap(in_server=True, confdir='/etc/ipa')
api.finalize()
api.Backend.ldap2.connect()
P = json.loads(sys.argv[1]) if len(sys.argv) > 1 else {}
def sortie(o):
    print(json.dumps(o, default=str))
PY

# _s11_ipa_py 'code' 'paramètres JSON' — exécute le code sur ipa01 (root), sortie JSON.
_s11_ipa_py() {
  local code="$_S11_IPA_PRELUDE"$'\n'"$1" params="${2:-}"
  [[ -n "$params" ]] || params='{}'
  wb_exec "$_S11_IPA" "PY=$code" "PARAMS=$params" <<'EOF'
journal "annuaire (cadre FreeIPA) : ${PARAMS:0:200}"
python3 -I -c "$PY" "$PARAMS"
EOF
}

# ---------------------------------------------------------------------------
# Lab sain avant injection
# ---------------------------------------------------------------------------
_s11_sain() {
  local c u gu
  for c in jq curl ssh kubectl ldapsearch; do
    command -v "$c" >/dev/null 2>&1 || { echo "outil manquant sur adm01 : $c" >&2; return 1; }
  done
  _s11_gl GET "groups/$(_f2b_enc "$_S11_GROUPE_GITLAB")" >/dev/null ||
    { echo "Groupe GitLab $_S11_GROUPE_GITLAB introuvable avec le jeton d'administration." >&2; return 1; }
  for u in "${_f2b_axiom_personnes[@]}"; do
    [[ -n "$(_f2b_ldap_personne "$u" uid)" ]] || { echo "Personne $u absente de l'annuaire : fais d'abord F2-S10." >&2; return 1; }
    ! _f2b_desactivee "$u" || { echo "$u est désactivée (départ fait, S12) : cette panne n'a plus de sens." >&2; return 1; }
    _f2b_groupes_ipa "$u" | grep -qx "$_f2b_groupe_axiom" ||
      { echo "$u n'est pas dans $_f2b_groupe_axiom : fais d'abord F2-S10." >&2; return 1; }
    ! _f2b_groupes_ipa "$u" | grep -Evx "ipausers|$_f2b_groupe_axiom" | grep -q . ||
      { echo "$u appartient déjà à un autre groupe de l'annuaire : corrige d'abord (lab/bin/check F2 11)." >&2; return 1; }
    gu="$(_f2b_gitlab_utilisateur "$u")"
    [[ -n "$gu" ]] || { echo "Utilisateur GitLab $u absent : fais d'abord F2-S10." >&2; return 1; }
    [[ "$(_f2b_gitlab_groupes_etrangers "$(jq -r .id <<<"$gu")")" == 0 ]] ||
      { echo "$u est déjà membre d'un groupe GitLab : corrige d'abord (lab/bin/check F2 11)." >&2; return 1; }
  done
  _s11_kubectl get namespace "$_f2b_ns_axiom" -o name >/dev/null 2>&1 ||
    { echo "Espace $_f2b_ns_axiom absent ou kubectl d'administration indisponible : fais d'abord F2-S10." >&2; return 1; }
  if _s11_kubectl get clusterrolebinding "$_S11_CRB" -o name >/dev/null 2>&1; then
    echo "Un ClusterRoleBinding $_S11_CRB existe déjà : rien n'est cassé, vérifie ton lab." >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Variante 1 : groupe GitLab parent
# ---------------------------------------------------------------------------
_s11_gitlab_gid() { _s11_gl GET "groups/$(_f2b_enc "$_S11_GROUPE_GITLAB")" | jq -r '.id // empty'; }

panne_S11_v1() {
  _s11_sain || return 1
  local gid u uid ajoutes=""
  gid="$(_s11_gitlab_gid)" || return 1
  [[ -n "$gid" ]] || return 1
  _s11_poser gitlab-groupe "$gid"
  for u in "${_f2b_axiom_personnes[@]}"; do
    uid="$(_f2b_gitlab_utilisateur "$u" | jq -r '.id // empty')"
    [[ -n "$uid" ]] || return 1
    _s11_gl POST "groups/$gid/members" --data-urlencode "user_id=$uid" --data-urlencode "access_level=30" >/dev/null || return 1
    ajoutes+="$uid"$'\n'
    _s11_poser gitlab-membres "${ajoutes%$'\n'}"
    _s11_journal "GitLab : $u (id $uid) ajouté au groupe $_S11_GROUPE_GITLAB en Developer"
  done
}

_s11_v1_actif() {
  local gid uid
  gid="$(_s11_lire gitlab-groupe)"
  [[ -n "$gid" ]] || return 1
  while IFS= read -r uid; do
    [[ -n "$uid" ]] || continue
    _s11_gl GET "groups/$gid/members/$uid" | jq -e '.access_level == 30' >/dev/null 2>&1 || return 1
  done < <(_s11_lire gitlab-membres)
}

_s11_v1_annuler() {
  local gid uid m
  gid="$(_s11_lire gitlab-groupe)"
  [[ -n "$gid" ]] || return 0
  while IFS= read -r uid; do
    [[ -n "$uid" ]] || continue
    m="$(_s11_gl GET "groups/$gid/members/$uid" 2>/dev/null)" || continue
    # Retiré seulement s'il est encore exactement comme la panne l'a posé (Developer, sans échéance).
    if jq -e '.access_level == 30 and (.expires_at == null)' <<<"$m" >/dev/null 2>&1; then
      _s11_gl DELETE "groups/$gid/members/$uid" >/dev/null 2>&1 && _s11_journal "annulation : id $uid retiré du groupe GitLab"
    else
      _s11_journal "annulation : id $uid modifié depuis la panne, laissé tel quel"
    fi
  done < <(_s11_lire gitlab-membres)
  _s11_oublier gitlab-membres
  _s11_oublier gitlab-groupe
}

# ---------------------------------------------------------------------------
# Variante 2 : ClusterRoleBinding « view » sur tout le cluster
# ---------------------------------------------------------------------------
panne_S11_v2() {
  _s11_sain || return 1
  _s11_poser crb "$_S11_CRB"
  if ! _s11_kubectl create clusterrolebinding "$_S11_CRB" --clusterrole=view --group="oidc:$_f2b_groupe_axiom" >/dev/null 2>&1; then
    # Refus probable par la politique d'admission rbac-prestataires (prévention de S11 déjà en place) :
    # on bascule sur la variante GitLab, que l'admission ne voit pas.
    _s11_oublier crb
    _s11_journal "ClusterRoleBinding refusé (politique d'admission ?) : bascule sur la variante 1"
    WB_VAR=1
    panne_S11_v1
    return
  fi
  _s11_kubectl annotate clusterrolebinding "$_S11_CRB" \
    "medisphere.internal/ticket=DEV-3210" "medisphere.internal/motif=lecture des journaux pour AxiomDev" \
    "workbook.medisphere.internal/panne=F2-S11" >/dev/null || return 1
  _s11_journal "ClusterRoleBinding $_S11_CRB (view → oidc:$_f2b_groupe_axiom) créé"
}

_s11_v2_actif() {
  _s11_kubectl get clusterrolebinding "$_S11_CRB" -o json 2>/dev/null |
    jq -e --arg g "oidc:$_f2b_groupe_axiom" 'any(.subjects[]?; .kind == "Group" and .name == $g)' >/dev/null 2>&1
}

_s11_v2_annuler() {
  [[ -n "$(_s11_lire crb)" ]] || return 0
  # Supprimé seulement s'il porte encore la marque de la panne.
  if _s11_kubectl get clusterrolebinding "$_S11_CRB" -o json 2>/dev/null |
    jq -e '.metadata.annotations["workbook.medisphere.internal/panne"] == "F2-S11"' >/dev/null 2>&1; then
    _s11_kubectl delete clusterrolebinding "$_S11_CRB" --ignore-not-found >/dev/null 2>&1 &&
      _s11_journal "annulation : ClusterRoleBinding $_S11_CRB supprimé"
  fi
  _s11_oublier crb
}

# ---------------------------------------------------------------------------
# Variante 3 : appartenance au groupe « mediagenda » de l'annuaire
# ---------------------------------------------------------------------------
_s11_v3_personne() { printf '%s\n' "${_f2b_axiom_personnes[-1]}"; }

panne_S11_v3() {
  _s11_sain || return 1
  local u r
  u="$(_s11_v3_personne)"
  _s11_poser ipa "$u"
  r="$(_s11_ipa_py '
uid, g = P["uid"], P["groupe"]
membres = api.Command.group_show(g)["result"].get("member_user", [])
if uid in membres:
    sortie({"ajoute": False})
else:
    api.Command.group_add_member(g, user=[uid])
    sortie({"ajoute": True})
' "$(jq -nc --arg u "$u" --arg g "$_S11_GROUPE_IPA" '{uid: $u, groupe: $g}')")" || return 1
  jq -e '.ajoute == true' <<<"$r" >/dev/null 2>&1 || return 1
  _s11_journal "annuaire : $u ajoutée au groupe $_S11_GROUPE_IPA"
}

_s11_v3_actif() {
  local u
  u="$(_s11_lire ipa)"
  [[ -n "$u" ]] || return 1
  _f2b_groupes_ipa "$u" | grep -qx "$_S11_GROUPE_IPA"
}

_s11_v3_annuler() {
  local u
  u="$(_s11_lire ipa)"
  [[ -n "$u" ]] || return 0
  _s11_ipa_py '
uid, g = P["uid"], P["groupe"]
if uid in api.Command.group_show(g)["result"].get("member_user", []):
    api.Command.group_remove_member(g, user=[uid])
    sortie({"retire": True})
else:
    sortie({"retire": False})
' "$(jq -nc --arg u "$u" --arg g "$_S11_GROUPE_IPA" '{uid: $u, groupe: $g}')" >/dev/null 2>&1 &&
    _s11_journal "annulation : $u retirée de $_S11_GROUPE_IPA (si elle y était encore)"
  _s11_oublier ipa
}

# ---------------------------------------------------------------------------
# Interface de pannes-lib
# ---------------------------------------------------------------------------
verifier_S11() {
  case "${WB_VAR:-}" in
    1) _s11_v1_actif ;;
    2) _s11_v2_actif ;;
    3) _s11_v3_actif ;;
    *) return 1 ;;
  esac
}

annuler_S11() {
  _s11_v1_annuler || true
  _s11_v2_annuler || true
  _s11_v3_annuler || true
  _s11_journal "annulation terminée"
}

resume_S11() {
  echo "La revue d'accès mensuelle montre qu'un compte d'AxiomDev voit des projets ou des espaces hors de son périmètre."
}

symptome_S11() {
  wb_symptome "Ticket SEC-3211 — De : Sophie Laurent" \
    "Revue d'accès du mois, ligne AxiomDev : au moins un de leurs comptes voit des choses qu'il ne devrait" \
    "pas voir (Marc m'a même envoyé, très content, une capture d'un écran qui n'est pas dans son périmètre)." \
    "Le contrat est clair : mediagenda/api et leur espace de développement, rien d'autre, et surtout rien" \
    "de la production. Trouve ce qui leur donne cet accès, retire-le proprement, dis-moi depuis quand" \
    "et par où c'est arrivé, et fais en sorte que ça ne puisse pas revenir sans que je le voie." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check F2 11"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main F2 S11 3 "$@"; }
fi
