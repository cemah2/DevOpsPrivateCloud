# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # expressions perl, yq et jq entre apostrophes
# break-E36.sh — M19-E36 « Panne : le job échoue avant le script »
#
# Cible : le runner k8s-par1 (ConfigMap et Secret du chart dans gitlab-runner), l'espace ci-jobs,
# le projet témoin. Variantes :
#   1. image helper : dans le gabarit TOML du runner, le chemin du cache Harbor « gitlab » devient
#      « gitlab-registry » (projet qui n'existe pas) ; gestionnaire redémarré → ErrImagePull du helper ;
#   2. Secret des certificats du gestionnaire (certsSecretName) vidé, pods du gestionnaire supprimés :
#      au redémarrage, l'enregistrement auprès de git01 échoue (x509), le gestionnaire boucle et ne
#      prend plus de jobs ;
#   3. compte de service ci-job supprimé de ci-jobs : l'API refuse les pods de job ;
#   4. Lucas fait consommer au canari une image « officielle » prise directement sur Docker Hub : la
#      ValidatingAdmissionPolicy medisphere-images refuse le pod (sans effet si ci-jobs n'est pas
#      couvert par la politique : variante sautée).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m19-commun.sh
source "$WB_ROOT/modules/19-ci/corrige/pannes/_m19-commun.sh"

_E36_SA=ci-job

# _e36_certs_secret — Secret monté sur custom-certs par le gestionnaire de k8s-par1.
_e36_certs_secret() {
  local dep
  dep="$(m19_runner_deploy "$(m19_runner_cm)")"
  [[ -n "$dep" ]] || return 1
  m19_ecrire E36 deploy "$dep"
  wb_kubectl -n "$_M19_NS_RUNNER" get deploy "$dep" -o json | jq -r '
    [.spec.template.spec.volumes[]? | select(.name == "custom-certs") | .secret.secretName][0] // empty'
}

# _e36_gestionnaire_ko — aucun pod du gestionnaire n'est prêt depuis le redémarrage.
_e36_gestionnaire_ko() {
  wb_kubectl -n "$_M19_NS_RUNNER" get deploy "$(m19_lire E36 deploy)" -o json 2>/dev/null |
    jq -e '(.status.readyReplicas // 0) == 0' >/dev/null 2>&1
}

_e36_pods_gestionnaire_supprimer() {
  local dep sel
  dep="$(m19_lire E36 deploy)"
  sel="$(wb_kubectl -n "$_M19_NS_RUNNER" get deploy "$dep" -o json | jq -r '.spec.selector.matchLabels | to_entries | map("\(.key)=\(.value)") | join(",")')"
  [[ -n "$sel" ]] && wb_kubectl -n "$_M19_NS_RUNNER" delete pods -l "$sel" --wait=false >/dev/null 2>&1
}

_m19E36_une() {
  local n="$1" s json st id d sha
  m19_debut E36
  case "$n" in
    1)
      m19_toml_modifier E36 's{(registry\.par1\.medisphere\.internal/)gitlab/}{${1}gitlab-registry/}g' || return $?
      read -r st id < <(m19_temoin_cycle 420)
      if [[ "$st" == success ]]; then _e36_defaire 1; return 10; fi
      ;;
    2)
      s="$(_e36_certs_secret)" || s=""
      [[ -n "$s" ]] || return 10
      m19_sauver_objet E36 secret "$s" "$_M19_NS_RUNNER"
      m19_ecrire E36 secret "$s"
      json="$(wb_kubectl -n "$_M19_NS_RUNNER" get secret "$s" -o json | jq -c '{
          metadata: {annotations: {"medisphere.internal/restaure-depuis": "sauvegarde-vide-lucas"}},
          data: (.data | map_values(""))}')"
      wb_kubectl -n "$_M19_NS_RUNNER" patch secret "$s" --type merge -p "$json" >/dev/null || return 1
      _e36_pods_gestionnaire_supprimer || return 1
      m19_journal E36 "variante 2 : Secret $s vidé, pods du gestionnaire supprimés"
      sleep 30
      m19_attendre 180 _e36_gestionnaire_ko || { _e36_defaire 2; return 10; }
      ;;
    3)
      wb_kubectl -n "$_M19_NS_JOBS" get serviceaccount "$_E36_SA" >/dev/null 2>&1 || return 10
      m19_sauver_objet E36 serviceaccount "$_E36_SA" "$_M19_NS_JOBS"
      wb_kubectl -n "$_M19_NS_JOBS" delete serviceaccount "$_E36_SA" >/dev/null || return 1
      m19_ecrire E36 sa 1
      m19_journal E36 "variante 3 : compte de service $_E36_SA supprimé"
      read -r st id < <(m19_temoin_cycle 300)
      if [[ "$st" == success ]]; then _e36_defaire 3; return 10; fi
      ;;
    4)
      d="$(m19_etat E36)"
      m19_brut "$_M19_TEMOIN" .gitlab-ci.yml main >"$d/ci.yml" || return 1
      yq -i '.include[0].inputs.image = "docker.io/library/python:3.13-slim-trixie"' "$d/ci.yml" || return 1
      sha="$(m19_temoin_maj E36 main "ci: image Python officielle pour le canari, plus simple (M19-E36)" .gitlab-ci.yml "$d/ci.yml")" || return 1
      rm -f -- "$d/ci.yml"
      id="$(m19_attendre_pipeline "$_M19_TEMOIN" "$sha" 90)"
      [[ -n "$id" ]] || { _e36_defaire 4; return 1; }
      read -r st _ < <(m19_attendre_job "$_M19_TEMOIN" "$id" canari 420)
      if [[ "$st" == success ]]; then _e36_defaire 4; return 10; fi
      ;;
  esac
  m19_journal E36 "variante $n posée et constatée"
}

_e36_defaire() {
  local n="$1" s cur
  case "$n" in
    1) m19_toml_retablir E36 ;;
    2)
      s="$(m19_lire E36 secret)"
      if [[ -n "$s" ]]; then
        cur="$(wb_kubectl -n "$_M19_NS_RUNNER" get secret "$s" -o json 2>/dev/null)" || cur=""
        if jq -e '(.metadata.annotations["medisphere.internal/restaure-depuis"] // "") == "sauvegarde-vide-lucas"
                  and all(.data[]?; . == "")' >/dev/null 2>&1 <<<"$cur"; then
          m19_restaurer_objet E36 secret "$s" "$_M19_NS_RUNNER"
          _e36_pods_gestionnaire_supprimer || true
          m19_journal E36 "annulation : Secret $s rétabli, gestionnaire relancé"
        else
          m19_oublier_objet E36 secret "$s" "$_M19_NS_RUNNER"
        fi
      fi
      m19_oublier E36 secret
      ;;
    3)
      if [[ -n "$(m19_lire E36 sa)" ]] && ! wb_kubectl -n "$_M19_NS_JOBS" get serviceaccount "$_E36_SA" >/dev/null 2>&1; then
        m19_restaurer_objet E36 serviceaccount "$_E36_SA" "$_M19_NS_JOBS"
      else
        m19_oublier_objet E36 serviceaccount "$_E36_SA" "$_M19_NS_JOBS"
      fi
      m19_oublier E36 sa
      ;;
    4) m19_temoin_retablir E36 ;;
  esac
}

panne_E36_v1() { m19_preparer && m19_essayer E36 4 1; }
panne_E36_v2() { m19_preparer && m19_essayer E36 4 2; }
panne_E36_v3() { m19_preparer && m19_essayer E36 4 3; }
panne_E36_v4() { m19_preparer && m19_essayer E36 4 4; }

verifier_E36() {
  case "${WB_VAR:-}" in
    1) m19_toml "$(m19_lire E36 toml-cm)" | grep -q 'medisphere\.internal/gitlab-registry/' ;;
    2) _e36_gestionnaire_ko ;;
    3) ! wb_kubectl -n "$_M19_NS_JOBS" get serviceaccount "$_E36_SA" >/dev/null 2>&1 ;;
    4) m19_brut "$_M19_TEMOIN" .gitlab-ci.yml main | grep -q 'docker.io/library/python' ;;
    *) return 1 ;;
  esac
}

annuler_E36() {
  case "${WB_VAR:-}" in
    [1-4]) _e36_defaire "$WB_VAR" ;;
    *) local v; for v in 1 2 3 4; do _e36_defaire "$v"; done ;;
  esac
  m19_oublier E36 deploy
  m19_oublier E36 debut
  m19_journal E36 "annulation"
}

resume_E36() {
  case "${WB_VAR:-}" in
    2) echo "Depuis le redémarrage de cette nuit, le runner k8s-par1 ne prend plus aucun job." ;;
    *) echo "Les jobs du canari (formation/ci-pannes) échouent avant la première ligne de leur script." ;;
  esac
}

symptome_E36() {
  case "${WB_VAR:-}" in
    2)
      wb_symptome "Ticket INC-4636 — De : Nadia Roussel" \
        "Les nœuds ont été redémarrés cette nuit (correctifs). Depuis, plus aucun job k8s ne" \
        "tourne : le canari (formation/ci-pannes) reste en attente et le runner k8s-par1 n'a plus" \
        "contacté GitLab depuis des heures. Lucas avait « fait du ménage dans les Secrets » de" \
        "gitlab-runner hier. Remets la CI en route ; la cause doit être corrigée dans le code." \
        "" \
        "Temps cible : 30 min. Contrôle : lab/bin/check 19 36"
      ;;
    *)
      wb_symptome "Ticket INC-4636 — De : Julien Petit" \
        "Le job du canari (formation/ci-pannes) échoue en quelques secondes, avant même la" \
        "première ligne de son script : « ERROR: Job failed (system failure) » ou un échec à la" \
        "préparation de l'environnement. Rien n'a changé dans notre code. Lucas a « simplifié »" \
        "deux ou trois choses hier. Remets le canari au vert sans contourner les garde-fous." \
        "" \
        "Temps cible : 30 min. Contrôle : lab/bin/check 19 36"
      ;;
  esac
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 19 E36 4 "$@"; }
fi
