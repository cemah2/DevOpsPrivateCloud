# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E15.sh — M17-E15 « Des paquets sans secrets » : démonstration nettoyée, aucune valeur de release
# qui ressemble à un secret, URL PostgreSQL de MédiAgenda lue dans un Secret, garde-fou de CI, registre.
# Lecture seule. Aucune valeur trouvée n'est jamais affichée : seulement le chemin de la clé.

# shellcheck source=_m17-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m17-production.sh"

title "M17-E15 — Des paquets sans secrets"
require_cmd jq kubectl helm

check_cmd "aucune release « fuite » dans wb-essais" \
  bash -c "! helm --kubeconfig '$(_m17p_kubeconfig_admin)' list -n wb-essais -q 2>/dev/null | grep -qx fuite"
_e15_reste() { [[ -z "$(_m17p_kadmin get secret -n wb-essais -l owner=helm,name=fuite -o name)" ]]; }
check_cmd "aucun Secret de release sh.helm.release.v1.fuite.* dans wb-essais" _e15_reste

# Même logique que plateforme/k8s/outils/audit-valeurs-helm.sh (corrigé), réimplémentée ici :
# le check n'exécute pas le script du dépôt.
# shellcheck disable=SC2016  # programme jq
_e15_filtre='
  [ paths(scalars) as $p | getpath($p) as $v | ($p | map(tostring)) as $s | ($s | last) as $c
    | select(($c | test("^(existingsecret|secretname|secretkey|secretref|existingsecretkey|.*secretkeyref)$"; "i")) | not)
    | select((($c | test("^(password|passwd|pass|motdepasse|mot_de_passe|token|apitoken|apikey|api_key|secretaccesskey|aws_secret_access_key|accesskeysecret|tsigsecret|privatekey|private_key|clientsecret|client_secret|webhooksecret)$"; "i")) and (($v | tostring | length) > 0))
             or (($v | type) == "string" and ($v | test("^[a-z][a-z0-9+.-]*://[^/@:\\s]+:[^/@\\s]+@") or test("-----BEGIN [A-Z ]*PRIVATE KEY-----"))))
    | $s | join(".") ]
  + [ paths(objects) as $p | ($p | map(tostring)) as $s | select(($s | last // "") | test("^secretcontents$"; "i"))
      | select((getpath($p) | length) > 0) | $s | join(".") ]
  | unique | .[]'
_e15_suspects=""
_e15_audit() {
  local ns nom v
  _e15_suspects=""
  while IFS=$'\t' read -r ns nom; do
    [[ -n "$nom" ]] || continue
    v="$(_m17p_helm get values "$nom" -n "$ns" -o json)" || continue
    [[ "$v" == null || -z "$v" ]] && continue
    while IFS= read -r c; do
      [[ -n "$c" ]] && _e15_suspects+=" $ns/$nom:$c"
    done < <(jq -r "$_e15_filtre" <<<"$v" 2>/dev/null)
  done < <(_m17p_helm list -A -o json | jq -r '.[] | [.namespace, .name] | @tsv' 2>/dev/null)
  [[ -z "$_e15_suspects" ]]
}
if _e15_audit; then
  check_cmd "aucune valeur de release Helm ne ressemble à un secret" true
else
  check_cmd "aucune valeur de release Helm ne ressemble à un secret (à revoir :$_e15_suspects)" false
fi

for _e15_ns in mediagenda-dev mediagenda-recette; do
  _e15_d="$(_m17p_deploy "$_e15_ns" mediagenda)" || _e15_d=""
  if [[ -z "$_e15_d" ]]; then
    check_cmd "$_e15_ns : Deployment mediagenda présent" false
    continue
  fi
  check_cmd "$_e15_ns : MEDIAGENDA_DB_URL vient d'une référence de Secret" _m17p_jq "$_e15_d" \
    '[.spec.template.spec | (.containers + (.initContainers // []))[] | .env[]? | select(.name == "MEDIAGENDA_DB_URL")]
     | length > 0 and all(.valueFrom.secretKeyRef.name != null and .value == null)'
  check_cmd "$_e15_ns : aucune variable ne contient d'URL PostgreSQL littérale" _m17p_jq "$_e15_d" \
    '[.spec.template.spec | (.containers + (.initContainers // []))[] | .env[]? | .value // "" | select(test("^postgres(ql)?://"))] | length == 0'
done

check_cmd "plateforme/k8s : outils/audit-valeurs-helm.sh sur main" _m17p_gl_existe plateforme/k8s outils/audit-valeurs-helm.sh
check_cmd "mediagenda/chart : job « sans Secret » réussi dans le dernier pipeline de main" \
  _m17p_gl_jobs_ok mediagenda/chart main 'secret'
check_cmd "plateforme/medisphere : docs/kubernetes/packaging/secrets.md" \
  _m17p_gl_existe plateforme/medisphere docs/kubernetes/packaging/secrets.md
