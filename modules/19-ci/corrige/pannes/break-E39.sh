# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E39.sh — M19-E39 « Panne : le déploiement en dev est refusé »
#
# Cible : l'agent GitLab k8s-par1 (projet plateforme/k8s, espace gitlab-agent) et le job deployer-dev
# du pipeline de main de mediagenda/deploiement. Variantes :
#   1. Lucas « fait tourner » le jeton de l'agent : un nouveau jeton est créé par l'API, placé dans le
#      Secret de l'agent… puis révoqué par erreur (il croyait révoquer l'ancien) ; l'agent ne
#      s'authentifie plus auprès de KAS. Le bon jeton est toujours dans Vault (secrets/gitlab-agent.yml) ;
#   2. RoleBinding qui donne ses droits au compte de service de l'agent dans mediagenda-dev supprimé ;
#   3. ci_access : l'autorisation du groupe mediagenda retirée de .gitlab/agents/k8s-par1/config.yaml
#      par une MR de Lucas fusionnée (commit identifiable, défait par une MR de retour arrière) ;
#   4. argument --kas-address du Deployment de l'agent modifié à chaud : nom d'hôte inexistant
#      (gitlab.par1.medisphere.internal).
# Vérification : le dernier job deployer-dev réussi de main est relancé et doit échouer (même commit :
# il réapplique l'overlay dev déjà en place, sans rien changer).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m19-commun.sh
source "$WB_ROOT/modules/19-ci/corrige/pannes/_m19-commun.sh"

_E39_JOB=deployer-dev
_E39_FAUX_HOTE=gitlab.par1.medisphere.internal
_E39_CONFIG=.gitlab/agents/k8s-par1/config.yaml
_E39_BRANCHE=lucas/agent-ci-access

_e39_dep() { wb_kubectl -n "$_M19_NS_AGENT" get deploy -o json 2>/dev/null | jq -r '[.items[] | select(any(.spec.template.spec.containers[].args[]?; startswith("--kas-address=")))][0].metadata.name // empty'; }

# _e39_secret — Secret qui porte le jeton de l'agent (volume monté sur /etc/agentk/secrets).
_e39_secret() {
  wb_kubectl -n "$_M19_NS_AGENT" get deploy "$(_e39_dep)" -o json 2>/dev/null | jq -r '
    (.spec.template.spec.containers[0].volumeMounts[]? | select(.mountPath | startswith("/etc/agentk/secrets")) | .name) as $v
    | [.spec.template.spec.volumes[]? | select(.name == $v) | (.secret.secretName // .projected.sources[0].secret.name)][0] // empty'
}

_e39_agent_id() { m19_api GET "projects/$(m19_enc "$_M19_PROJET_K8S")/cluster_agents" | jq -r --arg n "$_M19_AGENT" '[.[] | select(.name == $n)][0].id // empty'; }

# _e39_dernier_deploiement — id du dernier job deployer-dev réussi sur main.
_e39_dernier_deploiement() {
  m19_api GET "projects/$(m19_enc "$_M19_PROJET_DEPLOIEMENT")/jobs?scope[]=success&per_page=100" |
    jq -r --arg n "$_E39_JOB" '[.[] | select(.name == $n and .ref == "main")] | max_by(.id) | .id // empty'
}

# _e39_deploiement_echoue — relance le dernier deployer-dev réussi : il doit échouer.
_e39_deploiement_echoue() {
  local id nid t=0 st=""
  id="$(m19_lire E39 job-reference)"
  [[ -n "$id" ]] || return 1
  nid="$(m19_api POST "projects/$(m19_enc "$_M19_PROJET_DEPLOIEMENT")/jobs/$id/retry" | jq -r '.id // empty')" || return 1
  [[ -n "$nid" ]] || return 1
  m19_ecraser E39 job-reference "$nid"
  while ((t < 420)); do
    st="$(m19_api GET "projects/$(m19_enc "$_M19_PROJET_DEPLOIEMENT")/jobs/$nid" | jq -r '.status // empty')"
    case "$st" in success | failed | canceled) break ;; esac
    sleep 10
    t=$((t + 10))
  done
  if [[ "$st" == success ]]; then return 2; fi
  [[ "$st" == failed ]]
}

# _e39_redemarrer_agent — supprime tous les pods de l'agent (le jeton n'est lu qu'au démarrage).
_e39_redemarrer_agent() {
  local sel
  sel="$(wb_kubectl -n "$_M19_NS_AGENT" get deploy "$(_e39_dep)" -o json | jq -r '.spec.selector.matchLabels | to_entries | map("\(.key)=\(.value)") | join(",")')"
  [[ -n "$sel" ]] || return 1
  wb_kubectl -n "$_M19_NS_AGENT" delete pods -l "$sel" --wait=false >/dev/null 2>&1 || return 1
  sleep 30
}

# _e39_mr_fusionner BRANCHE TITRE — MR vers main de plateforme/k8s, fusionnée par l'API.
_e39_mr_fusionner() {
  local br="$1" titre="$2" iid t=0 st
  iid="$(m19_api POST "projects/$(m19_enc "$_M19_PROJET_K8S")/merge_requests" --data-urlencode "source_branch=$br" \
    --data-urlencode "target_branch=main" --data-urlencode "title=$titre" --data-urlencode "remove_source_branch=true" |
    jq -r '.iid // empty')" || return 1
  [[ -n "$iid" ]] || return 1
  while ((t < 60)); do
    st="$(m19_api GET "projects/$(m19_enc "$_M19_PROJET_K8S")/merge_requests/$iid" | jq -r '.detailed_merge_status // empty')"
    [[ "$st" == checking || "$st" == unchecked || "$st" == preparing || -z "$st" ]] || break
    sleep 5
    t=$((t + 5))
  done
  # « Pipelines must succeed » sur plateforme/k8s : le pipeline de la MR tourne encore (ou doit
  # passer) ; on demande la fusion automatique (auto_merge, 17.11+) et on attend qu'elle ait lieu.
  if [[ "$st" == ci_still_running || "$st" == ci_must_pass ]] &&
    m19_api PUT "projects/$(m19_enc "$_M19_PROJET_K8S")/merge_requests/$iid/merge" \
      --data-urlencode "auto_merge=true" --data-urlencode "should_remove_source_branch=true" >/dev/null 2>&1; then
    t=0
    while ((t < 900)); do
      [[ "$(m19_api GET "projects/$(m19_enc "$_M19_PROJET_K8S")/merge_requests/$iid" | jq -r '.state // empty')" == merged ]] && st=fusionnee && break
      sleep 15
      t=$((t + 15))
    done
  fi
  if [[ "$st" == fusionnee ]]; then
    :
  elif [[ "$st" != mergeable ]] || ! m19_api PUT "projects/$(m19_enc "$_M19_PROJET_K8S")/merge_requests/$iid/merge" \
    --data-urlencode "should_remove_source_branch=true" >/dev/null; then
    m19_api PUT "projects/$(m19_enc "$_M19_PROJET_K8S")/merge_requests/$iid" --data-urlencode "state_event=close" >/dev/null 2>&1 || true
    m19_api DELETE "projects/$(m19_enc "$_M19_PROJET_K8S")/repository/branches/$(m19_enc "$br")" >/dev/null 2>&1 || true
    wb_avert "MR « $titre » non fusionnable ($st) dans $_M19_PROJET_K8S"
    return 10
  fi
  m19_api GET "projects/$(m19_enc "$_M19_PROJET_K8S")/merge_requests/$iid" | jq -r '.merge_commit_sha // .sha // empty'
}

_m19E39_une() {
  local n="$1" rc=0 aid tk tok s json d sha dep idx arg
  m19_debut E39
  case "$n" in
    1)
      aid="$(_e39_agent_id)"; s="$(_e39_secret)"
      [[ -n "$aid" && -n "$s" ]] || return 10
      m19_sauver_objet E39 secret "$s" "$_M19_NS_AGENT"
      m19_ecrire E39 secret "$s"
      tk="$(m19_api POST "projects/$(m19_enc "$_M19_PROJET_K8S")/cluster_agents/$aid/tokens" \
        --data-urlencode "name=rotation-lucas" --data-urlencode "description=Rotation du jeton (Lucas, M19-E39)")" || return 10
      tok="$(jq -r '.token // empty' <<<"$tk")"
      [[ -n "$tok" ]] || return 1
      m19_api DELETE "projects/$(m19_enc "$_M19_PROJET_K8S")/cluster_agents/$aid/tokens/$(jq -r '.id' <<<"$tk")" >/dev/null || return 1
      m19_ecrire E39 empreinte-jeton "$(printf '%s' "$tok" | m19_sha)"
      json="$(jq -n --arg t "$(printf '%s' "$tok" | base64 | tr -d '\n')" \
        '{metadata: {annotations: {"medisphere.internal/rotation": "lucas.martin"}}, data: {token: $t}}')"
      wb_kubectl -n "$_M19_NS_AGENT" patch secret "$s" --type merge -p "$json" >/dev/null || { _e39_defaire 1; return 1; }
      _e39_redemarrer_agent || true
      ;;
    2)
      json="$(wb_kubectl -n mediagenda-dev get rolebindings -o json 2>/dev/null | jq -r --arg ns "$_M19_NS_AGENT" '
        [.items[] | select(any(.subjects[]?; .kind == "ServiceAccount" and .namespace == $ns)) | .metadata.name] | join(" ")')"
      [[ -n "$json" ]] || return 10
      m19_ecrire E39 rolebindings "$json"
      for s in $json; do
        m19_sauver_objet E39 rolebinding "$s" mediagenda-dev
        wb_kubectl -n mediagenda-dev delete rolebinding "$s" >/dev/null || { _e39_defaire 2; return 1; }
      done
      ;;
    3)
      d="$(m19_etat E39)"
      m19_brut "$_M19_PROJET_K8S" "$_E39_CONFIG" main >"$d/config.yaml" 2>/dev/null || return 10
      yq -e '.ci_access.groups[]? | select(.id == "mediagenda")' "$d/config.yaml" >/dev/null 2>&1 || return 10
      yq -i 'del(.ci_access.groups[] | select(.id == "mediagenda"))' "$d/config.yaml" || return 1
      if m19_api GET "projects/$(m19_enc "$_M19_PROJET_K8S")/repository/branches/$(m19_enc "$_E39_BRANCHE")" >/dev/null 2>&1; then
        wb_avert "la branche $_E39_BRANCHE existe déjà dans $_M19_PROJET_K8S : supprime-la puis relance"
        return 1
      fi
      m19_api POST "projects/$(m19_enc "$_M19_PROJET_K8S")/repository/branches" --data-urlencode "branch=$_E39_BRANCHE" \
        --data-urlencode "ref=main" >/dev/null || return 1
      sha="$(m19_commit --lucas "$_M19_PROJET_K8S" "$_E39_BRANCHE" \
        "fix(agent): ci_access limité aux projets qui en ont besoin (M19-E39)" \
        "$(jq -s '.' <(m19_action update "$_E39_CONFIG" "$d/config.yaml"))")" || sha=""
      [[ -n "$sha" ]] || return 1
      sha="$(_e39_mr_fusionner "$_E39_BRANCHE" "Agent k8s-par1 : ci_access resserré (Lucas)")" || return $?
      m19_ecrire E39 commit-fusion "$sha"
      m19_ecrire E39 config-empreinte "$(m19_sha <"$d/config.yaml")"
      rm -f -- "$d/config.yaml"
      sleep 60
      ;;
    4)
      dep="$(_e39_dep)"
      [[ -n "$dep" ]] || return 10
      m19_sauver_objet E39 deployment "$dep" "$_M19_NS_AGENT"
      m19_ecrire E39 deploy "$dep"
      idx="$(wb_kubectl -n "$_M19_NS_AGENT" get deploy "$dep" -o json | jq -r '.spec.template.spec.containers[0].args | to_entries[] | select(.value | startswith("--kas-address=")) | .key' | head -n 1)"
      arg="$(wb_kubectl -n "$_M19_NS_AGENT" get deploy "$dep" -o json | jq -r ".spec.template.spec.containers[0].args[$idx]")"
      [[ "$arg" == *git01.par1.medisphere.internal* ]] || return 10
      arg="${arg//git01.par1.medisphere.internal/$_E39_FAUX_HOTE}"
      wb_kubectl -n "$_M19_NS_AGENT" patch deploy "$dep" --type json \
        -p "[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/args/$idx\",\"value\":\"$arg\"}]" >/dev/null || return 1
      sleep 30
      ;;
  esac
  m19_journal E39 "variante $n posée"
  _e39_deploiement_echoue || rc=$?
  if ((rc != 0)); then _e39_defaire "$n"; return 10; fi
  m19_journal E39 "variante $n constatée"
}

_e39_defaire() {
  local n="$1" s cur rb sha br
  case "$n" in
    1)
      s="$(m19_lire E39 secret)"
      if [[ -n "$s" ]]; then
        cur="$(wb_kubectl -n "$_M19_NS_AGENT" get secret "$s" -o json 2>/dev/null | jq -r '.data.token // empty' | base64 -d 2>/dev/null | m19_sha)" || cur=""
        if [[ "$cur" == "$(m19_lire E39 empreinte-jeton)" ]]; then
          m19_restaurer_objet E39 secret "$s" "$_M19_NS_AGENT"
          _e39_redemarrer_agent || true
        else
          m19_oublier_objet E39 secret "$s" "$_M19_NS_AGENT"
        fi
      fi
      m19_oublier E39 secret
      m19_oublier E39 empreinte-jeton
      ;;
    2)
      for rb in $(m19_lire E39 rolebindings); do
        if wb_kubectl -n mediagenda-dev get rolebinding "$rb" >/dev/null 2>&1; then
          m19_oublier_objet E39 rolebinding "$rb" mediagenda-dev
        else
          m19_restaurer_objet E39 rolebinding "$rb" mediagenda-dev
        fi
      done
      m19_oublier E39 rolebindings
      ;;
    3)
      sha="$(m19_lire E39 commit-fusion)"
      if [[ -n "$sha" && "$(m19_brut "$_M19_PROJET_K8S" "$_E39_CONFIG" main 2>/dev/null | m19_sha)" == "$(m19_lire E39 config-empreinte)" ]]; then
        br="annulation/m19-e39-$(date +%s)"
        if m19_api POST "projects/$(m19_enc "$_M19_PROJET_K8S")/repository/branches" --data-urlencode "branch=$br" --data-urlencode "ref=main" >/dev/null &&
          m19_api POST "projects/$(m19_enc "$_M19_PROJET_K8S")/repository/commits/$sha/revert" --data-urlencode "branch=$br" >/dev/null; then
          _e39_mr_fusionner "$br" "Revert « ci_access resserré » (M19-E39, annulation par lab/bin/break)" >/dev/null ||
            wb_avert "MR de retour arrière ouverte sur $_M19_PROJET_K8S : fais-la fusionner"
        else
          wb_avert "retour arrière de $sha impossible sur $_M19_PROJET_K8S : rétablis ci_access à la main"
        fi
      fi
      m19_oublier E39 commit-fusion
      m19_oublier E39 config-empreinte
      ;;
    4)
      s="$(m19_lire E39 deploy)"
      if [[ -n "$s" ]] && wb_kubectl -n "$_M19_NS_AGENT" get deploy "$s" -o json 2>/dev/null | grep -q "$_E39_FAUX_HOTE"; then
        m19_restaurer_objet E39 deployment "$s" "$_M19_NS_AGENT"
      else
        m19_oublier_objet E39 deployment "$s" "$_M19_NS_AGENT"
      fi
      m19_oublier E39 deploy
      ;;
  esac
}

_e39_prealable() {
  local id
  id="$(_e39_dernier_deploiement)"
  [[ -n "$id" ]] || { echo "Aucun job $_E39_JOB réussi sur main de $_M19_PROJET_DEPLOIEMENT (M19-E18) : rien n'est cassé." >&2; return 1; }
  m19_ecraser E39 job-reference "$id"
}

panne_E39_v1() { m19_preparer && _e39_prealable && m19_essayer E39 4 1; }
panne_E39_v2() { m19_preparer && _e39_prealable && m19_essayer E39 4 2; }
panne_E39_v3() { m19_preparer && _e39_prealable && m19_essayer E39 4 3; }
panne_E39_v4() { m19_preparer && _e39_prealable && m19_essayer E39 4 4; }

verifier_E39() {
  local rb
  case "${WB_VAR:-}" in
    1) [[ "$(wb_kubectl -n "$_M19_NS_AGENT" get secret "$(m19_lire E39 secret)" -o json | jq -r '.data.token' | base64 -d | m19_sha)" == "$(m19_lire E39 empreinte-jeton)" ]] ;;
    2) for rb in $(m19_lire E39 rolebindings); do ! wb_kubectl -n mediagenda-dev get rolebinding "$rb" >/dev/null 2>&1 || return 1; done ;;
    3) [[ "$(m19_brut "$_M19_PROJET_K8S" "$_E39_CONFIG" main | m19_sha)" == "$(m19_lire E39 config-empreinte)" ]] ;;
    4) wb_kubectl -n "$_M19_NS_AGENT" get deploy "$(m19_lire E39 deploy)" -o json | grep -q "$_E39_FAUX_HOTE" ;;
    *) return 1 ;;
  esac
}

annuler_E39() {
  case "${WB_VAR:-}" in
    [1-4]) _e39_defaire "$WB_VAR" ;;
    *) local v; for v in 1 2 3 4; do _e39_defaire "$v"; done ;;
  esac
  m19_oublier E39 job-reference
  m19_oublier E39 debut
  m19_journal E39 "annulation"
}

resume_E39() { echo "Le job deployer-dev de mediagenda/deploiement échoue : plus rien n'arrive dans mediagenda-dev."; }

symptome_E39() {
  wb_symptome "Ticket INC-4639 — De : Julien Petit" \
    "Notre MR de promotion vient d'être fusionnée dans mediagenda/deploiement, mais le job" \
    "deployer-dev échoue : rien n'est arrivé dans mediagenda-dev. Ça marchait jeudi. Lucas a" \
    "« fait de la sécurité » sur l'agent cette semaine. On ne revient pas aux kubectl depuis" \
    "adm01 : répare la chaîne, puis relance le job." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 19 39"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 19 E39 4 "$@"; }
fi
