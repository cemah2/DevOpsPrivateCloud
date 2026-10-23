# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et expressions yq entre apostrophes
# break-S09.sh — F3-S09 « Mercredi : la livraison est bloquée » (chaîne de livraison, RECETTE)
#
# L'application va bien ; c'est l'outillage qui bloque. Le témoin de trafic de recette du M27
# (wb-pannes/trafic-recette, créé s'il manque) donne du trafic au canary. Dans les variantes 1 et 2, une
# « livraison » de Julien est ensuite fusionnée : commit dans mediagenda/deploiement, overlay de recette,
# qui ajoute au gabarit des pods l'annotation medisphere.internal/livraison: DEV-3309 (nouvelle révision
# du Rollout).
#   1. Analyse : commit de Lucas dans plateforme/gitops, ClusterAnalysisTemplate taux-erreur-mediagenda :
#      l'étiquette rollouts_pod_template_hash devient pod_template_hash dans les requêtes (« comme le reste
#      du cluster ») ; les requêtes ne renvoient plus rien, la mesure est en erreur, le canary de recette
#      est abandonné (Rollout Degraded) alors que la nouvelle version va très bien.
#   2. Dépôt : nouvelle version du secret kv/plateforme/argocd/depot-mediagenda dans OpenBao, avec un mot
#      de passe (jeton de déploiement) invalide (« rotation » ratée) ; ESO resynchronisé : Argo CD ne
#      peut plus lire les dépôts du groupe mediagenda (ComparisonError), la livraison n'est jamais vue.
#      Jeton d'administration OpenBao requis (BAO_TOKEN ou ~/.vault-token, comme les pannes du M25).
#      Annulation : retour à la version d'origine (kv rollback) si la version injectée est la courante.
#   3. Runner protégé : le gestionnaire du runner k8s-par1-protege (espace gitlab-runner) mis à 0
#      réplica (« maintenance » oubliée) ; le job de signature de la dernière étiquette de mediagenda/api
#      est relancé (« Julien relance la livraison ») et reste en attente : rien n'est signé ni promu.
#      Annulation : réplicas d'origine.
# Annulation commune : commits inverses s'ils sont intacts (la livraison de Julien reste : c'est une
# vraie livraison ; si la panne est annulée, elle arrive normalement) ; Rollout relancé s'il est abandonné.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_f3-commun.sh
source "$WB_ROOT/finaux/F3-astreinte/corrige/pannes/_f3-commun.sh"
# Témoin de trafic de la recette (M27) : m27_trafic.
# shellcheck source=../../../../modules/27-donnees-messaging/corrige/pannes/_m27-commun.sh
source "$WB_ROOT/modules/27-donnees-messaging/corrige/pannes/_m27-commun.sh"

_S09_GITOPS="${WB_F3_PROJET_GITOPS:-plateforme/gitops}"
_S09_DEPLOIEMENT="${WB_F3_PROJET_DEPLOIEMENT:-mediagenda/deploiement}"
_S09_OVERLAY="${WB_F3_FICHIER_OVERLAY_RECETTE:-overlays/recette/kustomization.yaml}"
_S09_API="${WB_F3_PROJET_API:-mediagenda/api}"
_S09_APP="${WB_F3_APP_RECETTE:-mediagenda-recette}"
_S09_CAT=taux-erreur-mediagenda
_S09_KV=plateforme/argocd/depot-mediagenda
_S09_ES=repo-creds-mediagenda

_s09_rollout() { wb_kubectl -n "$_F3P_RECETTE" get rollouts.argoproj.io mediagenda -o json 2>/dev/null; }
_s09_rollout_sain() { _s09_rollout | jq -e '.status.phase == "Healthy" and (.status.abort // false) == false' >/dev/null 2>&1; }

# --- Livraison de Julien -------------------------------------------------------------------------------

_s09_livraison() {
  local d
  d="$(_f3p_etat S09)/livraison"
  mkdir -p "$d"
  _f3p_gl_fichier "$_S09_DEPLOIEMENT" "$_S09_OVERLAY" >"$d/orig.yaml" || return 10
  PATCH="$(printf '%s\n' 'apiVersion: apps/v1' 'kind: Deployment' 'metadata:' '  name: mediagenda' 'spec:' '  template:' \
    '    metadata:' '      annotations:' "        medisphere.internal/livraison: \"DEV-3309 $(date +%F)\"")" \
    yq '.patches += [{"target": {"kind": "Deployment", "name": "mediagenda"}, "patch": strenv(PATCH)}]' "$d/orig.yaml" >"$d/neuf.yaml" || return 1
  _f3p_commit S09 livraison "$_S09_DEPLOIEMENT" "feat(recette): créneaux du samedi matin (DEV-3309)

MR !3309 approuvée par l'équipe. -- Julien" julien "$_S09_OVERLAY" "$d/neuf.yaml" || return $?
  _f3p_rafraichir "$_S09_APP"
}

# --- Variante 1 : requête d'analyse qui ne renvoie plus rien ----------------------------------------------

_s09_cat_casse() {
  wb_kubectl get clusteranalysistemplates.argoproj.io "$_S09_CAT" -o json 2>/dev/null |
    jq -e '[.spec.metrics[].provider.prometheus.query // ""] | any(test("[^_]pod_template_hash=")) and (any(test("rollouts_pod_template_hash")) | not)' >/dev/null 2>&1
}
_s09_v1_poser() {
  local d chemin
  d="$(_f3p_etat S09)/v1"
  mkdir -p "$d"
  chemin="$(_f3p_gl_chercher "$_S09_GITOPS" "name: $_S09_CAT" | grep -E '\.ya?ml$' | head -n 1)"
  [[ -n "$chemin" ]] || return 10
  _f3p_gl_fichier "$_S09_GITOPS" "$chemin" >"$d/orig.yaml" || return 1
  grep -q 'rollouts_pod_template_hash' "$d/orig.yaml" || return 10
  sed 's/rollouts_pod_template_hash=/pod_template_hash=/g' "$d/orig.yaml" >"$d/neuf.yaml"
  _f3p_commit S09 v1 "$_S09_GITOPS" "refactor(analyses): étiquette pod_template_hash, comme le reste du cluster

Harmonisation des noms d'étiquettes dans les requêtes d'analyse. -- Lucas" lucas "$chemin" "$d/neuf.yaml" || return $?
  # shellcheck disable=SC2046
  _f3p_rafraichir $(_f3p_apps_du_depot "$_S09_GITOPS")
  _f3p_attendre 600 _s09_cat_casse || return 10
  _s09_livraison || return $?
  _f3p_attendre 1200 _s09_v1_constat || return 10
}
_s09_v1_constat() {
  _s09_rollout | jq -e '(.status.abort // false) == true or .status.phase == "Degraded"' >/dev/null 2>&1
}

# --- Variante 2 : identifiants de dépôt invalides ----------------------------------------------------------

_s09_bao() {
  BAO_ADDR="${WB_OPENBAO_URL:-https://openbao.par1.medisphere.internal:8200}" BAO_CACERT="$_F3P_RACINE" \
    BAO_TOKEN="${BAO_TOKEN:-$(cat "$HOME/.vault-token" 2>/dev/null)}" bao "$@"
}
_s09_kv_version() { _s09_bao kv metadata get -format=json -mount=kv "$_S09_KV" 2>/dev/null | jq -r '.data.current_version // empty'; }
_s09_v2_comparaison_ko() {
  wb_kubectl -n argocd get applications.argoproj.io "$_S09_APP" -o json 2>/dev/null |
    jq -e '[.status.conditions[]? | select(.type == "ComparisonError")] | length > 0' >/dev/null 2>&1
}
_s09_v2_poser() {
  local v faux
  command -v bao >/dev/null || return 10
  v="$(_s09_kv_version)"
  [[ "$v" =~ ^[0-9]+$ ]] || return 10
  _s09_bao kv get -format=json -mount=kv "$_S09_KV" 2>/dev/null | jq -e '.data.data | has("password")' >/dev/null 2>&1 || return 10
  _f3p_ecrire S09 v2-version "$v"
  faux="gldt-$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20)"
  # Valeur par l'entrée standard (« clé=- »), jamais en argument (visible par ps).
  printf '%s' "$faux" | _s09_bao kv patch -mount=kv "$_S09_KV" password=- >/dev/null 2>&1 || return 10
  _f3p_ecrire S09 v2-injectee "$(_s09_kv_version)"
  _f3p_journal S09 "nouvelle version du secret $_S09_KV (mot de passe invalide)"
  wb_kubectl -n argocd annotate externalsecrets.external-secrets.io "$_S09_ES" force-sync="$(date +%s)" --overwrite >/dev/null 2>&1 || return 1
  sleep 20
  wb_kubectl -n argocd delete pods -l app.kubernetes.io/name=argocd-repo-server --wait=false >/dev/null 2>&1 || true
  _f3p_rafraichir "$_S09_APP"
  _f3p_attendre 600 _s09_v2_comparaison_ko || return 10
  _s09_livraison || return $?
}
_s09_v2_defaire() {
  local orig inj
  orig="$(_f3p_lire S09 v2-version)"
  inj="$(_f3p_lire S09 v2-injectee)"
  [[ -n "$orig" ]] || return 0
  if [[ -n "$inj" && "$(_s09_kv_version)" == "$inj" ]]; then
    _s09_bao kv rollback -mount=kv -version="$orig" "$_S09_KV" >/dev/null 2>&1 ||
      wb_avert "secret $_S09_KV à remettre à la version $orig (bao kv rollback -mount=kv -version=$orig $_S09_KV)"
    wb_kubectl -n argocd annotate externalsecrets.external-secrets.io "$_S09_ES" force-sync="$(date +%s)" --overwrite >/dev/null 2>&1 || true
    _f3p_journal S09 "secret $_S09_KV remis à la version $orig"
  fi
  _f3p_oublier S09 v2-version
  _f3p_oublier S09 v2-injectee
}

# --- Variante 3 : runner protégé hors ligne ----------------------------------------------------------------

_s09_runner_deploy() {
  wb_kubectl -n gitlab-runner get deploy -o json 2>/dev/null | jq -r '[.items[] | select(.metadata.name | test("protege"))][0].metadata.name // empty'
}
_s09_v3_poser() {
  local dep rep p tag pipe job nouveau
  dep="$(_s09_runner_deploy)"
  [[ -n "$dep" ]] || return 10
  rep="$(wb_kubectl -n gitlab-runner get deploy "$dep" -o jsonpath='{.spec.replicas}')" || return 1
  [[ "$rep" =~ ^[1-9][0-9]*$ ]] || return 10
  p="$(_f3p_enc "$_S09_API")"
  tag="$(_f3p_gl GET "projects/$p/repository/tags?order_by=updated&per_page=1" | jq -r '.[0].name // empty')" || return 10
  [[ -n "$tag" ]] || return 10
  pipe="$(_f3p_gl GET "projects/$p/pipelines?ref=$(_f3p_enc "$tag")&per_page=1" | jq -r '.[0].id // empty')" || return 10
  [[ -n "$pipe" ]] || return 10
  job="$(_f3p_gl GET "projects/$p/pipelines/$pipe/jobs?per_page=100&include_retried=false" |
    jq -r '[.[] | select((.tag_list // []) | index("protege")) | select(.status == "success")
            | select(.name | test("sign"; "i"))][0].id // empty')" || return 10
  [[ -n "$job" ]] || return 10
  _f3p_ecrire S09 v3-runner "$dep:$rep"
  wb_kubectl -n gitlab-runner scale deploy "$dep" --replicas=0 >/dev/null || return 1
  _f3p_journal S09 "runner protégé $dep mis à 0 (au lieu de $rep)"
  sleep 30
  nouveau="$(_f3p_gl POST "projects/$p/jobs/$job/retry" <<<'{}' | jq -r '.id // empty')" || nouveau=""
  [[ -n "$nouveau" ]] || return 1
  _f3p_ecrire S09 v3-job "$nouveau"
  _f3p_journal S09 "job de signature $job ($tag) relancé : $nouveau"
}
_s09_v3_constat() {
  local j
  j="$(_f3p_lire S09 v3-job)"
  [[ -n "$j" ]] && sleep 90 &&
    _f3p_gl GET "projects/$(_f3p_enc "$_S09_API")/jobs/$j" | jq -e '.status == "pending"' >/dev/null 2>&1
}
_s09_v3_defaire() {
  local dep rep cur
  IFS=: read -r dep rep <<<"$(_f3p_lire S09 v3-runner)"
  [[ -n "$dep" ]] || return 0
  cur="$(wb_kubectl -n gitlab-runner get deploy "$dep" -o jsonpath='{.spec.replicas}' 2>/dev/null)" || cur=""
  if [[ "$cur" == 0 ]]; then
    wb_kubectl -n gitlab-runner scale deploy "$dep" --replicas="$rep" >/dev/null 2>&1 || wb_avert "runner $dep à remettre à $rep réplica(s)"
    _f3p_journal S09 "runner protégé $dep remis à $rep"
  fi
  _f3p_oublier S09 v3-runner
  _f3p_oublier S09 v3-job
}

# --- Mécanique commune ------------------------------------------------------------------------------------

_f3p_S09_une() {
  case "$1" in
    1) _s09_v1_poser ;;
    2) _s09_v2_poser ;;
    3) _s09_v3_poser || return $?; _s09_v3_constat || return 10 ;;
  esac
}
_f3p_S09_defaire() {
  case "$1" in
    1) _f3p_retablir S09 v1 ;;
    2) _s09_v2_defaire ;;
    3) _s09_v3_defaire ;;
  esac
}

_s09_injecter() {
  _f3p_preparer S09 || return 1
  _s09_rollout_sain || { echo "Le Rollout mediagenda de $_F3P_RECETTE n'est pas Healthy : $_F3P_REFUS" >&2; return 1; }
  echo "Témoin de trafic de la recette (wb-pannes/trafic-recette, M27)…"
  m27_trafic || return 1
  echo "Injection et constat : jusqu'à 30 min (commits, synchronisation, analyse du canary)…"
  _f3p_essayer S09 3 "$1"
}

panne_S09_v1() { _s09_injecter 1; }
panne_S09_v2() { _s09_injecter 2; }
panne_S09_v3() { _s09_injecter 3; }

verifier_S09() {
  case "$(_f3p_lire S09 variante)" in
    1) _s09_v1_constat ;;
    2) _s09_v2_comparaison_ko ;;
    3) local j; j="$(_f3p_lire S09 v3-job)"; _f3p_gl GET "projects/$(_f3p_enc "$_S09_API")/jobs/$j" | jq -e '.status == "pending"' >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

annuler_S09() {
  local v
  for v in 3 2 1; do _f3p_S09_defaire "$v" || true; done
  # La livraison de Julien reste (vraie livraison) : le journal de l'état local suffit.
  rm -rf -- "$(_f3p_etat S09)/git-livraison"
  # shellcheck disable=SC2046
  _f3p_rafraichir "$_S09_APP" $(_f3p_apps_du_depot "$_S09_GITOPS" 2>/dev/null || true)
  if _s09_rollout | jq -e '(.status.abort // false) == true' >/dev/null 2>&1; then
    sleep 60
    wb_kubectl -n "$_F3P_RECETTE" patch rollouts.argoproj.io mediagenda --subresource=status --type=merge \
      -p '{"status":{"abort":false}}' >/dev/null 2>&1 || wb_avert "Rollout de recette à relancer : kubectl argo rollouts retry rollout mediagenda -n $_F3P_RECETTE"
  fi
  _f3p_oublier S09 variante
}

resume_S09() { echo "la livraison de MédiAgenda n'arrive pas en recette"; }

symptome_S09() {
  local l
  if [[ "$(_f3p_lire S09 variante)" == 3 ]]; then
    l="« J'ai relancé la livraison de la dernière version ce matin : elle n'a toujours pas atteint la recette. »"
  else
    l="« Ma MR DEV-3309 est fusionnée depuis une heure : rien n'est arrivé en recette. »"
  fi
  _f3p_symptome S09 INC-5909 "Ticket INC-5909 — De : Julien Petit — mercredi 15 h 10" \
    "$l" \
    "« On a une démo client demain à 10 h sur la recette. L'appli, elle, va bien : on l'a testée en dev." \
    "Je n'ai touché à rien d'autre. »" \
    "Contraintes : aucune livraison à la main (pas de kubectl apply ni d'image poussée à la main en recette)." \
    "Temps cible : 1 h."
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main F3 S09 3 "$@"; }
fi
