# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E40.sh — M20-E40 « Panne : le canary ne progresse plus »
#
# Cible : le Rollout mediagenda de mediagenda-recette (canary par le plugin Gateway API, M20-E16,
# analyses M20-E18). Chaque variante pose une cause, puis déclenche une nouvelle révision de la
# recette par un changement anodin de Lucas (MEDIAGENDA_CACHE_TTL dans overlays/recette/parametres.env) :
#   1. URL de l'analyse web « pret-mediagenda » modifiée en recette seulement (correctif de
#      l'overlay : /prets au lieu de /pret) : l'analyse de fond échoue, le Rollout s'interrompt et
#      revient à la version stable (Degraded) ;
#   2. emplacement du greffon Gateway API modifié dans les valeurs d'Argo Rollouts (plateforme/gitops,
#      trafficRouterPlugins) puis contrôleur redémarré : le greffon est introuvable, le contrôleur
#      ne démarre plus, plus aucun Rollout n'avance ;
#   3. différence des poids de la HTTPRoute retirée des ignoreDifferences de l'ApplicationSet
#      mediagenda (gabarit ou templatePatch) : Argo CD remet les poids de Git pendant le canary, le
#      greffon les remet à son tour ;
#   4. Rollout mis en pause « à la main » (spec.paused, comme « kubectl argo rollouts pause »)
#      juste avant la livraison : la nouvelle version ne part jamais.
# Jamais la production : seuls overlays/recette, l'ApplicationSet (champ propre à recette et prod,
# sans changement de la version de prod) et la configuration du contrôleur sont touchés ; le Rollout
# de prod n'est pas modifié (la variante 2 suspend aussi ses progrès, sans rien y changer).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m20-commun.sh
source "$WB_ROOT/modules/20-gitops/corrige/pannes/_m20-commun.sh"

_E40_DOSSIER="${WB_M20_OVERLAY_RECETTE:-overlays/recette}"
_E40_KUSTO="$_E40_DOSSIER/kustomization.yaml"
_E40_PARAMS="$_E40_DOSSIER/parametres.env"
_E40_NS_AR="${WB_M20_NS_ROLLOUTS:-argo-rollouts}"
_E40_APP_AR="${WB_M20_APP_ROLLOUTS:-argo-rollouts}"
_E40_SEL_AR="app.kubernetes.io/name=argo-rollouts,app.kubernetes.io/component=rollouts-controller"
# Entrée du greffon Gateway API dans les valeurs du chart argo-rollouts (où qu'elle soit rangée).
_E40_YQ_GREFFON='.. | select(tag == "!!map" and has("trafficRouterPlugins")) | .trafficRouterPlugins[] | select(.name == "argoproj-labs/gatewayAPI")'

_e40_rollout() { wb_kubectl -n "$_M20_NS_RECETTE" get rollouts.argoproj.io mediagenda -o json 2>/dev/null; }

_e40_rollout_sain() {
  _e40_rollout | jq -e '.status.phase == "Healthy" and ((.spec.paused // false) == false) and ((.status.abort // false) == false)' >/dev/null 2>&1
}

_e40_controleur_pret() {
  wb_kubectl -n "$_E40_NS_AR" get pods -l "$_E40_SEL_AR" -o json 2>/dev/null |
    jq -e '[.items[] | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))] | length > 0' >/dev/null 2>&1
}
_e40_controleur_ko() {
  wb_kubectl -n "$_E40_NS_AR" get pods -l "$_E40_SEL_AR" -o json 2>/dev/null |
    jq -e '(.items | length > 0) and ([.items[] | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))] | length == 0)' >/dev/null 2>&1
}

# _e40_declencheur — action de commit qui change MEDIAGENDA_CACHE_TTL dans l'overlay de recette.
_e40_declencheur() {
  local t ttl
  t="$(mktemp)"
  m20_brut "$_M20_DEPLOIEMENT" "$_E40_PARAMS" >"$t" 2>/dev/null || { rm -f "$t"; return 1; }
  ttl="$(sed -n 's/^MEDIAGENDA_CACHE_TTL=//p' "$t" | tail -n 1)"
  if [[ -n "$ttl" ]]; then
    if [[ "$ttl" == 75 ]]; then ttl=90; else ttl=75; fi
    sed -i "s/^MEDIAGENDA_CACHE_TTL=.*/MEDIAGENDA_CACHE_TTL=$ttl/" "$t"
  else
    [[ -z "$(tail -c 1 "$t")" ]] || printf '\n' >>"$t"
    printf 'MEDIAGENDA_CACHE_TTL=75\n' >>"$t"
  fi
  m20_action update "$_E40_PARAMS" "$t"
  rm -f "$t"
}

# _e40_livrer — commit de Lucas qui déclenche une nouvelle révision de la recette.
_e40_livrer() {
  local a
  a="$(_e40_declencheur)" || { wb_avert "$_E40_PARAMS introuvable dans $_M20_DEPLOIEMENT : impossible de livrer en recette"; return 1; }
  m20_commit_lucas E40 "$_M20_DEPLOIEMENT" "lucas/recette-cache-ttl" \
    "chore(recette): durée de cache des créneaux ajustée" \
    "DEV-2140 : Julien veut mesurer l'effet d'un cache plus long en recette." "[$a]" || return $?
  m20_rafraichir "$_M20_APP_RECETTE"
}

# _e40_fichier PROJET 'regex' 'filtre yq' — premier fichier YAML du projet qui contient la regex
# et dont un document satisfait le filtre.
_e40_fichier() {
  local f
  while read -r f; do
    [[ -n "$f" ]] || continue
    if m20_brut "$1" "$f" 2>/dev/null | yq -e "$3" >/dev/null 2>&1; then printf '%s\n' "$f"; return 0; fi
  done < <(m20_chercher "$1" "$2")
  return 1
}

# _e40_sans_ignore_route — filtre (entrée → sortie) qui retire de la liste ignoreDifferences l'entrée
# de la HTTPRoute (gabarit YAML ou texte du templatePatch), commentaire de tête compris.
_e40_sans_ignore_route() {
  perl -e '
    my @l = <STDIN>; my @o; my $i = 0;
    while ($i < @l) {
      my ($ind) = $l[$i] =~ /^(\s*)- group:\s*gateway\.networking\.k8s\.io\s*$/;
      if (defined $ind && $i + 1 < @l && $l[$i + 1] =~ /^\s+kind:\s*HTTPRoute\s*$/) {
        my $n = length($ind);
        while (@o && $o[-1] =~ /^(\s*)#/ && length($1) == $n) { pop @o; }
        $i++;
        while ($i < @l && $l[$i] !~ /^\s*$/ && length(($l[$i] =~ /^(\s*)/)[0]) > $n) { $i++; }
        next;
      }
      push @o, $l[$i]; $i++;
    }
    print @o;'
}

_e40_analyse_echouee() {
  local debut
  debut="$(m20_lire E40 debut)"
  wb_kubectl -n "$_M20_NS_RECETTE" get analysisruns.argoproj.io -o json 2>/dev/null |
    jq -e --argjson t "${debut:-0}" '[.items[] | select((.metadata.creationTimestamp | fromdateiso8601) >= $t)
      | select((.status.phase // "") | test("Failed|Error"))] | length > 0' >/dev/null 2>&1 ||
    _e40_rollout | jq -e '.status.abort == true or .status.phase == "Degraded"' >/dev/null 2>&1
}

_e40_cm_modifiee() {
  wb_kubectl -n "$_E40_NS_AR" get configmap argo-rollouts-config -o json 2>/dev/null |
    jq -e --arg v "$(m20_lire E40 valeur)" '(.data.trafficRouterPlugins // "") | contains($v)' >/dev/null 2>&1
}

_e40_ignore_retire() {
  m20_app_jq "$_M20_APP_RECETTE" '[.spec.ignoreDifferences[]? | select(.kind == "HTTPRoute")] | length == 0'
}

_e40_bataille() {
  local debut
  debut="$(m20_lire E40 debut)"
  (($(m20_sync_auto_depuis "$_M20_APP_RECETTE" "${debut:-0}") >= 3))
}

_e40_en_pause() {
  _e40_rollout | jq -e '(.spec.paused // false) == true' >/dev/null 2>&1 &&
    m20_app_jq "$_M20_APP_RECETTE" '.status.sync.status == "Synced"'
}

_m20E40_une() {
  local n="$1" f t actions a idx url p loc
  m20_debut E40
  case "$n" in
    1)
      idx="$(wb_kubectl -n "$_M20_NS_RECETTE" get analysistemplates.argoproj.io pret-mediagenda -o json 2>/dev/null |
        jq -r '[.spec.metrics | to_entries[] | select((.value.provider.web.url // "") | test("/pret$")) | .key][0] // empty')"
      [[ -n "$idx" ]] || return 10
      url="$(wb_kubectl -n "$_M20_NS_RECETTE" get analysistemplates.argoproj.io pret-mediagenda -o json | jq -r ".spec.metrics[$idx].provider.web.url")"
      # Valeur reprise du gabarit : on garde {{args.espace}} tel quel, seul le chemin change.
      p="$(printf -- '- op: replace\n  path: /spec/metrics/%s/provider/web/url\n  value: "%s"\n' "$idx" "${url%/pret}/prets")"
      t="$(mktemp)"
      m20_brut "$_M20_DEPLOIEMENT" "$_E40_KUSTO" >"$t" || { rm -f "$t"; return 1; }
      P="$p" yq -i '.patches += [{"target": {"group": "argoproj.io", "kind": "AnalysisTemplate", "name": "pret-mediagenda"}, "patch": strenv(P)}]
        | .patches[-1].patch style="literal"' "$t" || { rm -f "$t"; return 10; }
      a="$(_e40_declencheur)" || { rm -f "$t"; return 1; }
      actions="[$(m20_action update "$_E40_KUSTO" "$t"),$a]"
      rm -f "$t"
      m20_commit_lucas E40 "$_M20_DEPLOIEMENT" "lucas/recette-analyse-pret" \
        "chore(recette): chemin de l'analyse de disponibilité et cache ajustés" \
        "DEV-2140 : chemin de disponibilité de la future version de l'API ; cache des créneaux plus long." "$actions" || return $?
      m20_rafraichir "$_M20_APP_RECETTE"
      m20_attendre 600 _e40_analyse_echouee || { _e40_defaire 1; return 10; }
      ;;
    2)
      f="$(_e40_fichier "$_M20_GITOPS" 'trafficRouterPlugins' "$_E40_YQ_GREFFON")" || return 10
      t="$(mktemp)"
      m20_brut "$_M20_GITOPS" "$f" >"$t" || { rm -f "$t"; return 1; }
      loc="$(yq -r "[$_E40_YQ_GREFFON | .location][0] // \"\"" "$t")"
      case "$loc" in
        file://*)
          # Greffon copié par un conteneur d'initialisation (M20-E15) : Lucas « versionne » le nom
          # dans la configuration… sans changer la copie.
          L="$loc" perl -pi -e 's/^(\s*location:\s*"?)\Q$ENV{L}\E("?\s*)$/$1$ENV{L}-0.17.0$2/' "$t"
          m20_ecrire E40 valeur "${loc}-0.17.0"
          ;;
        http*)
          if grep -Eq 'sha256:[[:space:]]*"?[0-9a-f]{64}' "$t"; then
            a="$(grep -Eo 'sha256:[[:space:]]*"?[0-9a-f]{64}' "$t" | grep -Eo '[0-9a-f]{64}' | head -n 1)"
            p="${a:0:63}$([[ "${a:63:1}" == 0 ]] && echo 1 || echo 0)"
            sed -i "s/${a}/${p}/" "$t"
            m20_ecrire E40 valeur "$p"
          else
            sed -i 's#/v0\.17\.0/#/v0.17.9/#' "$t"
            m20_ecrire E40 valeur "/v0.17.9/"
          fi
          ;;
        *) rm -f "$t"; return 10 ;;
      esac
      actions="[$(m20_action update "$f" "$t")]"
      rm -f "$t"
      m20_commit_lucas E40 "$_M20_GITOPS" "lucas/rollouts-greffon-versionne" \
        "chore(rollouts): greffon Gateway API désigné avec sa version" \
        "DEV-2140 : nommer le binaire du greffon avec sa version, pour préparer les montées." "$actions" || return $?
      m20_rafraichir racine applications "$_E40_APP_AR"
      m20_attendre 300 _e40_cm_modifiee || { _e40_defaire 2; return 10; }
      # Le greffon n'est chargé qu'au démarrage du contrôleur : on simule le redémarrage qu'aurait
      # provoqué n'importe quelle maintenance de nœud.
      wb_kubectl -n "$_E40_NS_AR" delete pods -l "$_E40_SEL_AR" --wait=false >/dev/null 2>&1 || true
      _e40_livrer || { _e40_defaire 2; return 1; }
      m20_attendre 300 _e40_controleur_ko || { _e40_defaire 2; return 10; }
      ;;
    3)
      m20_app_jq "$_M20_APP_RECETTE" '[.spec.ignoreDifferences[]? | select(.kind == "HTTPRoute")] | length > 0' || return 10
      f="$(_e40_fichier "$_M20_GITOPS" 'kind:[[:space:]]*HTTPRoute' 'select(.kind == "ApplicationSet" and .metadata.name == "mediagenda")')" || return 10
      t="$(mktemp)"
      m20_brut "$_M20_GITOPS" "$f" | _e40_sans_ignore_route >"$t" || { rm -f "$t"; return 1; }
      if ! yq -e 'select(.kind == "ApplicationSet" and .metadata.name == "mediagenda")' "$t" >/dev/null 2>&1 ||
        grep -Eq '^[[:space:]]+kind:[[:space:]]*HTTPRoute[[:space:]]*$' "$t"; then
        rm -f "$t"
        return 10
      fi
      actions="[$(m20_action update "$f" "$t")]"
      rm -f "$t"
      m20_commit_lucas E40 "$_M20_GITOPS" "lucas/mediagenda-ignore-minimal" \
        "refactor(mediagenda): ignoreDifferences réduit au strict nécessaire" \
        "DEV-2140 : on ne masque plus les différences des routes, Argo CD doit tout voir." "$actions" || return $?
      m20_rafraichir racine applications
      m20_attendre 300 _e40_ignore_retire || { _e40_defaire 3; return 10; }
      _e40_livrer || { _e40_defaire 3; return 1; }
      m20_attendre 600 _e40_bataille || { _e40_defaire 3; return 10; }
      ;;
    4)
      wb_kubectl -n "$_M20_NS_RECETTE" patch rollouts.argoproj.io mediagenda --type merge \
        --field-manager=kubectl-argo-rollouts -p '{"spec":{"paused":true}}' >/dev/null || return 1
      m20_ecrire E40 pause posee
      _e40_livrer || { _e40_defaire 4; return 1; }
      m20_attendre 300 _e40_en_pause || { _e40_defaire 4; return 10; }
      ;;
  esac
  m20_journal E40 "variante $n posée"
}

_e40_defaire() {
  local n="$1"
  m20_defaire_commits E40
  m20_rafraichir racine applications "$_M20_APP_RECETTE"
  case "$n" in
    2)
      if [[ -n "$(m20_lire E40 valeur)" ]]; then
        m20_oublier E40 valeur
        m20_rafraichir hard "$_E40_APP_AR"
        # La configuration revenue, on relance le contrôleur s'il ne démarre toujours pas.
        sleep 60
        if ! _e40_controleur_pret; then
          wb_kubectl -n "$_E40_NS_AR" delete pods -l "$_E40_SEL_AR" --wait=false >/dev/null 2>&1 || true
        fi
      fi
      ;;
    4)
      if [[ -n "$(m20_lire E40 pause)" ]]; then
        if _e40_rollout | jq -e '(.spec.paused // false) == true' >/dev/null 2>&1; then
          wb_kubectl -n "$_M20_NS_RECETTE" patch rollouts.argoproj.io mediagenda --type merge \
            --field-manager=kubectl-argo-rollouts -p '{"spec":{"paused":false}}' >/dev/null 2>&1 || wb_avert "Rollout mediagenda (recette) toujours en pause"
        fi
        m20_oublier E40 pause
      fi
      ;;
  esac
}

_e40_preparer() {
  if [[ -z "${_M20_ASTREINTE:-}" ]]; then
    m20_sain "$_M20_APP_RECETTE" || return 1
  fi
  _e40_rollout_sain || { echo "Le Rollout mediagenda de recette n'est pas Healthy (kubectl argo rollouts get rollout mediagenda -n $_M20_NS_RECETTE) : rien n'est cassé." >&2; return 1; }
  _e40_controleur_pret || { echo "Le contrôleur Argo Rollouts n'est pas prêt : rien n'est cassé." >&2; return 1; }
}

panne_E40_v1() { _e40_preparer && m20_essayer E40 4 1; }
panne_E40_v2() { _e40_preparer && m20_essayer E40 4 2; }
panne_E40_v3() { _e40_preparer && m20_essayer E40 4 3; }
panne_E40_v4() { _e40_preparer && m20_essayer E40 4 4; }

verifier_E40() {
  case "${WB_VAR:-}" in
    1) _e40_analyse_echouee ;;
    2) _e40_controleur_ko ;;
    3) _e40_bataille ;;
    4) _e40_en_pause ;;
    *) return 1 ;;
  esac
}

annuler_E40() {
  case "${WB_VAR:-}" in
    [1-4]) _e40_defaire "$WB_VAR" ;;
    *) _e40_defaire 4; _e40_defaire 2 ;;
  esac
  m20_oublier E40 debut
  m20_journal E40 "annulation"
}

resume_E40() {
  case "${WB_VAR:-}" in
    1) echo "Le canary de MédiAgenda en recette s'est interrompu tout seul et la recette est revenue à l'ancienne version." ;;
    2) echo "La nouvelle version de MédiAgenda n'avance plus en recette et le contrôleur d'Argo Rollouts redémarre en boucle." ;;
    3) echo "Pendant le canary de recette, Argo CD resynchronise sans cesse la recette et le trafic ne suit pas les poids annoncés." ;;
    *) echo "La nouvelle version de MédiAgenda est livrée en recette mais n'y démarre jamais." ;;
  esac
}

symptome_E40() {
  wb_symptome "Ticket INC-4740 — De : Julien Petit" \
    "$(resume_E40)" \
    "Lucas a livré un petit réglage en recette (MR fusionnée, pipeline vert). On voulait le" \
    "promouvoir en prod cet après-midi : c'est bloqué. Trouve ce qui empêche le canary d'aller au" \
    "bout, répare-le à la source, et vérifie qu'un canary complet repasse en recette." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 20 40"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 20 E40 4 "$@"; }
fi
