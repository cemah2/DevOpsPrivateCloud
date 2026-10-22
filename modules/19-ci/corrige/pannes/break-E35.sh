# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E35.sh — M19-E35 « Panne : les jobs restent en attente »
#
# Cible : le runner d'instance k8s-par1 (API GitLab), l'espace ci-jobs et le projet témoin. Variantes :
#   1. étiquettes du runner « harmonisées » par Lucas (k8s → k8s-par1, note de maintenance laissée) :
#      plus aucun runner ne porte l'étiquette k8s, les jobs restent « pending » ;
#   2. runner mis en pause (« pause pour maintenance ») et oublié ;
#   3. ResourceQuota de ci-jobs « resserré » : unité Gi devenue Mi sur la mémoire ; les pods de job
#      sont refusés par l'API (exceeded quota), le job échoue à la préparation (ou réessaie, selon
#      retry_limits du runner) ;
#   4. Lucas pousse une branche non protégée du témoin dont un job ne vise que l'étiquette « protege » :
#      seul le runner protégé la porte, il ne prend que les références protégées → « pending » sans fin.
# Annulation : seulement si la marque de la panne est encore là.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m19-commun.sh
source "$WB_ROOT/modules/19-ci/corrige/pannes/_m19-commun.sh"

_E35_NOTE_1="Lucas (stage) : étiquettes harmonisées avec le nom du cluster (M19-E35)"
_E35_NOTE_2="Lucas (stage) : pause pendant la maintenance de k8s-w02 (M19-E35)"
_E35_BRANCHE=lucas/essai-signature

_e35_runner() { m19_api GET "runners/$(m19_lire E35 runner)"; }

_e35_quota() { wb_kubectl -n "$_M19_NS_JOBS" get resourcequota -o json 2>/dev/null; }

_m19E35_une() {
  local n="$1" rid r tags d q nom json pl sha st
  m19_debut E35
  case "$n" in
    1 | 2)
      rid="$(m19_runner_id)"
      [[ -n "$rid" ]] || return 1
      m19_ecrire E35 runner "$rid"
      r="$(m19_api GET "runners/$rid")" || return 1
      m19_ecrire E35 runner.orig "$(jq -c '{tag_list, paused, maintenance_note: (.maintenance_note // "")}' <<<"$r")"
      if ((n == 1)); then
        jq -e '.tag_list | index("k8s")' >/dev/null <<<"$r" || return 10
        tags="$(jq -r '[.tag_list[] | if . == "k8s" then "k8s-par1" else . end] | unique | join(",")' <<<"$r")"
        m19_api PUT "runners/$rid" --data-urlencode "tag_list=$tags" --data-urlencode "maintenance_note=$_E35_NOTE_1" >/dev/null || return 1
      else
        m19_api PUT "runners/$rid" --data-urlencode "paused=true" --data-urlencode "maintenance_note=$_E35_NOTE_2" >/dev/null || return 1
      fi
      m19_journal E35 "variante $n : runner $rid modifié"
      pl="$(m19_temoin_lancer)" || pl=""
      [[ -n "$pl" ]] || { _e35_defaire "$n"; return 1; }
      m19_ecrire E35 pipeline "$pl"
      m19_job_reste pending "$_M19_TEMOIN" "$pl" canari 90 || { _e35_defaire "$n"; return 10; }
      ;;
    3)
      q="$(_e35_quota)" || return 1
      nom="$(jq -r '[.items[] | select((.spec.hard // {}) | to_entries | any(.key | test("^(requests|limits)\\.memory$|^memory$")) and any(.value | test("Gi$")))][0].metadata.name // empty' <<<"$q")"
      [[ -n "$nom" ]] || return 10
      m19_sauver_objet E35 resourcequota "$nom" "$_M19_NS_JOBS"
      m19_ecrire E35 quota "$nom"
      json="$(jq -c --arg n "$nom" '[.items[] | select(.metadata.name == $n)][0].spec.hard
        | with_entries(select(.key | test("^(requests|limits)\\.memory$|^memory$")) | .value |= sub("Gi$"; "Mi"))
        | {metadata: {annotations: {"medisphere.internal/modifie-par": "lucas.martin"}}, spec: {hard: .}}' <<<"$q")"
      wb_kubectl -n "$_M19_NS_JOBS" patch resourcequota "$nom" --type merge -p "$json" >/dev/null || return 1
      m19_journal E35 "variante 3 : quota $nom en Mi"
      read -r st _ < <(m19_temoin_cycle 300)
      if [[ "$st" == success ]]; then _e35_defaire 3; return 10; fi
      ;;
    4)
      if m19_api GET "projects/$(m19_enc "$_M19_TEMOIN")/repository/branches/$(m19_enc "$_E35_BRANCHE")" >/dev/null 2>&1; then
        wb_avert "la branche $_E35_BRANCHE existe déjà dans $_M19_TEMOIN : supprime-la puis relance"
        return 1
      fi
      m19_api POST "projects/$(m19_enc "$_M19_TEMOIN")/repository/branches" \
        --data-urlencode "branch=$_E35_BRANCHE" --data-urlencode "ref=main" >/dev/null || return 1
      m19_ecrire E35 branche "$_E35_BRANCHE"
      d="$(m19_etat E35)"
      m19_brut "$_M19_TEMOIN" .gitlab-ci.yml "$_E35_BRANCHE" >"$d/ci.yml" || return 1
      cat >>"$d/ci.yml" <<'EOF'

# Lucas : essai du job de signature avant de le proposer pour mediagenda/api.
signer-essai:
  stage: test
  image: registry.par1.medisphere.internal/dockerhub/library/python:3.13-slim-trixie
  tags: [protege]
  script:
    - echo "signature d'essai"
EOF
      sha="$(m19_commit --lucas "$_M19_TEMOIN" "$_E35_BRANCHE" "ci: essai du job de signature sur le runner protégé (M19-E35)" \
        "$(jq -s '.' <(m19_action update .gitlab-ci.yml "$d/ci.yml"))")" || sha=""
      rm -f -- "$d/ci.yml"
      [[ -n "$sha" ]] || { _e35_defaire 4; return 1; }
      pl="$(m19_attendre_pipeline "$_M19_TEMOIN" "$sha" 90)"
      [[ -n "$pl" ]] || { _e35_defaire 4; return 1; }
      m19_ecrire E35 pipeline "$pl"
      m19_job_reste pending "$_M19_TEMOIN" "$pl" signer-essai 90 || { _e35_defaire 4; return 10; }
      ;;
  esac
  m19_journal E35 "variante $n posée et constatée"
}

_e35_defaire() {
  local n="$1" rid r o nom cur pl
  case "$n" in
    1 | 2)
      rid="$(m19_lire E35 runner)"
      o="$(m19_lire E35 runner.orig)"
      if [[ -n "$rid" && -n "$o" ]]; then
        r="$(m19_api GET "runners/$rid" 2>/dev/null)" || r=""
        if [[ "$n" == 1 ]] && jq -e --arg note "$_E35_NOTE_1" '(.maintenance_note // "") == $note and (.tag_list | index("k8s") | not)' >/dev/null 2>&1 <<<"$r"; then
          m19_api PUT "runners/$rid" --data-urlencode "tag_list=$(jq -r '.tag_list | join(",")' <<<"$o")" \
            --data-urlencode "maintenance_note=$(jq -r '.maintenance_note' <<<"$o")" >/dev/null || wb_avert "étiquettes du runner non rétablies"
        elif [[ "$n" == 2 ]] && jq -e --arg note "$_E35_NOTE_2" '(.maintenance_note // "") == $note and .paused' >/dev/null 2>&1 <<<"$r"; then
          m19_api PUT "runners/$rid" --data-urlencode "paused=false" \
            --data-urlencode "maintenance_note=$(jq -r '.maintenance_note' <<<"$o")" >/dev/null || wb_avert "runner non réactivé"
        fi
      fi
      m19_oublier E35 runner
      m19_oublier E35 runner.orig
      ;;
    3)
      nom="$(m19_lire E35 quota)"
      if [[ -n "$nom" ]]; then
        cur="$(wb_kubectl -n "$_M19_NS_JOBS" get resourcequota "$nom" -o json 2>/dev/null)" || cur=""
        if jq -e '(.metadata.annotations["medisphere.internal/modifie-par"] // "") == "lucas.martin"
                  and ([.spec.hard | to_entries[] | select(.key | test("memory")) | .value | test("Mi$")] | any)' >/dev/null 2>&1 <<<"$cur"; then
          m19_restaurer_objet E35 resourcequota "$nom" "$_M19_NS_JOBS"
        else
          m19_oublier_objet E35 resourcequota "$nom" "$_M19_NS_JOBS"
        fi
      fi
      m19_oublier E35 quota
      ;;
    4)
      if [[ -n "$(m19_lire E35 branche)" ]]; then
        pl="$(m19_lire E35 pipeline)"
        [[ -z "$pl" ]] || m19_api POST "projects/$(m19_enc "$_M19_TEMOIN")/pipelines/$pl/cancel" >/dev/null 2>&1 || true
        m19_api DELETE "projects/$(m19_enc "$_M19_TEMOIN")/repository/branches/$(m19_enc "$_E35_BRANCHE")" >/dev/null 2>&1 || true
      fi
      m19_oublier E35 branche
      ;;
  esac
  m19_oublier E35 pipeline
}

panne_E35_v1() { m19_preparer && m19_essayer E35 4 1; }
panne_E35_v2() { m19_preparer && m19_essayer E35 4 2; }
panne_E35_v3() { m19_preparer && m19_essayer E35 4 3; }
panne_E35_v4() { m19_preparer && m19_essayer E35 4 4; }

verifier_E35() {
  case "${WB_VAR:-}" in
    1) _e35_runner | jq -e '.tag_list | index("k8s") | not' >/dev/null ;;
    2) _e35_runner | jq -e '.paused' >/dev/null ;;
    3) [[ -n "$(m19_lire E35 quota)" ]] && wb_kubectl -n "$_M19_NS_JOBS" get resourcequota "$(m19_lire E35 quota)" -o json |
      jq -e '[.spec.hard | to_entries[] | select(.key | test("memory")) | .value | test("Mi$")] | any' >/dev/null ;;
    4) m19_api GET "projects/$(m19_enc "$_M19_TEMOIN")/repository/branches/$(m19_enc "$_E35_BRANCHE")" >/dev/null ;;
    *) return 1 ;;
  esac
}

annuler_E35() {
  case "${WB_VAR:-}" in
    [1-4]) _e35_defaire "$WB_VAR" ;;
    *) local v; for v in 1 2 3 4; do _e35_defaire "$v"; done ;;
  esac
  m19_oublier E35 debut
  m19_journal E35 "annulation"
}

resume_E35() {
  case "${WB_VAR:-}" in
    3) echo "Les jobs du canari (formation/ci-pannes) échouent avant même de démarrer, ou ne démarrent plus." ;;
    4) echo "Lucas : le pipeline de sa branche $_E35_BRANCHE (formation/ci-pannes) attend depuis le matin." ;;
    *) echo "Plus aucun job étiqueté k8s ne démarre : ils restent tous « en attente »." ;;
  esac
}

symptome_E35() {
  case "${WB_VAR:-}" in
    4)
      wb_symptome "Ticket INC-4635 — De : Lucas Martin" \
        "J'ai poussé la branche $_E35_BRANCHE dans formation/ci-pannes pour essayer le job de" \
        "signature avant de le proposer pour MédiAgenda. Le job « signer-essai » est en attente" \
        "depuis des heures (« pending »), alors que le canari de la même branche, lui, est passé." \
        "Le runner protégé est pourtant en ligne. Qu'est-ce que j'ai raté ?" \
        "" \
        "Temps cible : 30 min. Contrôle : lab/bin/check 19 35"
      ;;
    3)
      wb_symptome "Ticket INC-4635 — De : Julien Petit" \
        "Depuis ce matin, nos jobs sur l'étiquette k8s ne démarrent plus : le canari de la" \
        "plateforme (formation/ci-pannes) aussi. Le runner k8s-par1 est vert dans GitLab." \
        "Je n'ai rien changé à nos pipelines. Relance-les quand c'est réparé." \
        "" \
        "Temps cible : 30 min. Contrôle : lab/bin/check 19 35"
      ;;
    *)
      wb_symptome "Ticket INC-4635 — De : Julien Petit" \
        "Depuis ce matin, tous nos jobs restent « en attente » (pending) : rien ne démarre, ni" \
        "chez nous ni sur le canari de la plateforme (formation/ci-pannes). Les pods du runner" \
        "dans gitlab-runner ont l'air de tourner. Ça bloque toutes nos MR." \
        "" \
        "Temps cible : 30 min. Contrôle : lab/bin/check 19 35"
      ;;
  esac
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 19 E35 4 "$@"; }
fi
