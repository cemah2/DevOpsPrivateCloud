# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E04.sh — M17-E04 « Kustomize : une base et des overlays » : dépôt mediagenda/deploiement,
# recette gérée par Kustomize. Lecture seule.

# shellcheck source=_m17-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m17-decouverte.sh"

title "M17-E04 — Kustomize : une base et des overlays"
require_cmd jq kubectl curl

for _e04_f in base/kustomization.yaml overlays/dev/kustomization.yaml overlays/recette/kustomization.yaml overlays/essai/kustomization.yaml; do
  check_cmd "mediagenda/deploiement (main) : $_e04_f" _m17d_gl_existe mediagenda/deploiement "$_e04_f"
done
if command -v kustomize >/dev/null 2>&1; then
  _e04_k="$(_m17d_extraire "$_m17d_deploiement_clone" .)" || _e04_k=""
  if [[ -n "$_e04_k" ]]; then
    for _e04_o in dev recette; do
      check_cmd "kustomize build overlays/$_e04_o (origin/main)" kustomize build "$_e04_k/overlays/$_e04_o"
    done
  else
    skip "kustomize build des overlays" "clone $_m17d_deploiement_clone absent"
  fi
fi

_e04_d="$(_m17d_obj mediagenda-recette deploy mediagenda)"
check_cmd "recette : Deployment mediagenda hors de toute release Helm" _m17d_hors_helm "$_e04_d"
check_cmd "recette : étiquette medisphere.internal/environnement=recette (objet et pods)" _m17d_jq "$_e04_d" \
  '.metadata.labels["medisphere.internal/environnement"] == "recette" and .spec.template.metadata.labels["medisphere.internal/environnement"] == "recette"'
check_cmd "recette : l'étiquette d'environnement n'est pas dans le sélecteur" _m17d_jq "$_e04_d" \
  '.spec.selector.matchLabels | has("medisphere.internal/environnement") | not'
check_cmd "recette : au moins deux réplicas prêts" _m17d_pret "$_e04_d" 2
_e04_cm="$(jq -r '[.spec.template.spec.containers[] | select(.name == "api") | .envFrom[]?.configMapRef.name // empty
          | select(test("^mediagenda-parametres-[a-z0-9]{6,}$"))][0] // ""' <<<"$_e04_d" 2>/dev/null)" || _e04_cm=""
check_output "recette : l'API lit une ConfigMap générée mediagenda-parametres-<empreinte>" '^mediagenda-parametres-' echo "$_e04_cm"
_e04_cmj=""
[[ -n "$_e04_cm" ]] && _e04_cmj="$(_m17d_obj mediagenda-recette configmap "$_e04_cm")"
check_cmd "recette : la ConfigMap $_e04_cm existe" test -n "$_e04_cmj"
_e04_r="$(_m17d_obj mediagenda-recette httproute mediagenda)"
check_cmd "recette : la route publie mediagenda-recette.$_m17d_domaine" _m17d_jq "$_e04_r" \
  ".spec.hostnames | index(\"mediagenda-recette.$_m17d_domaine\") != null"
check_cmd "recette : la route vise le Service mediagenda, port 80" _m17d_jq "$_e04_r" \
  '[.spec.rules[]?.backendRefs[]? | select(.name == "mediagenda" and .port == 80)] | length > 0'
check_cmd "https://mediagenda-recette.$_m17d_domaine/sante répond 200" _m17d_sante "https://mediagenda-recette.$_m17d_domaine/sante"
# En-têtes de sécurité de l'entrée (M15-E33) : exigés si l'entrée a été durcie au M15, ce que signale
# la Gateway des partenaires du même exercice.
_e04_hsts() {
  curl -sI --max-time "$WB_TIMEOUT" "https://mediagenda-recette.$_m17d_domaine/sante" 2>/dev/null \
    | grep -qi '^strict-transport-security:'
}
if [[ -n "$(_m17d_obj passerelles gateway gw-partenaires)" ]]; then
  check_cmd "recette : la réponse porte toujours Strict-Transport-Security (en-têtes du M15-E33)" _e04_hsts
else
  skip "recette : en-têtes de sécurité du M15-E33" "Gateway gw-partenaires absente (M15-E33 non fait)"
fi

# Plus aucune politique réseau ne vise ni n'admet les pods mediagenda-api du M14, en dev comme en
# recette (les politiques du M15-E17 sont communes aux deux espaces). Liste illisible = échec.
_e04_politiques() {
  local e t l
  for e in mediagenda-dev mediagenda-recette; do
    for t in networkpolicies ciliumnetworkpolicies.cilium.io; do
      l="$(_m17d_liste "$e" "$t")"
      [[ -n "$l" ]] || return 1
      jq -e '[.items[] | select(.spec | tojson | contains("\"mediagenda-api\""))] | length == 0' >/dev/null 2>&1 <<<"$l" || return 1
    done
  done
}
check_cmd "dev et recette : aucune politique réseau ne vise ni n'admet encore les pods mediagenda-api" _e04_politiques

# Relais mTLS des partenaires (M15-E33), s'il existe : il relaie vers le Service du chart et répond.
_e04_relais="$(_m17d_obj mediagenda-recette deploy relais-mtls)"
if [[ -n "$_e04_relais" ]]; then
  _e04_conf="$(_m17d_obj mediagenda-recette configmap relais-mtls-conf)"
  check_cmd "relais mTLS : relais-mtls-conf relaie vers le Service mediagenda (port 80), plus vers mediagenda-api" \
    _m17d_jq "$_e04_conf" '[.data[]?] | join("\n")
      | test("proxy_pass +https?://mediagenda(\\.mediagenda-recette(\\.svc(\\.cluster\\.local)?)?)?:80;")
        and (test("proxy_pass[^;]*mediagenda-api") | not)'
  check_cmd "relais mTLS : pods prêts" _m17d_pret "$_e04_relais"
  _e04_crt="$HOME/.config/workbook/partenaire-centre-test-01.crt"
  _e04_cle="$HOME/.config/workbook/partenaire-centre-test-01.key"
  _e04_partenaire() {
    curl -fsS -o /dev/null --max-time "$WB_TIMEOUT" --cert "$_e04_crt" --key "$_e04_cle" \
      "https://mediagenda-partenaires.$_m17d_domaine/sante" 2>/dev/null
  }
  if [[ -s "$_e04_crt" && -r "$_e04_cle" ]]; then
    check_cmd "https://mediagenda-partenaires.$_m17d_domaine/sante répond 200 avec le certificat de test" _e04_partenaire
  else
    skip "appel du relais avec le certificat de test" "$_e04_crt absent (M15-E33)"
  fi
else
  skip "relais mTLS des partenaires" "Deployment relais-mtls absent de mediagenda-recette (M15-E33 non fait)"
fi
_e04_ancien() {
  # L'ancienne version (M14) est retirée : plus de Deployment mediagenda-api. Une lecture impossible
  # n'est pas une absence : on exige une liste lisible.
  local l
  l="$(_m17d_liste mediagenda-recette deploy)"
  [[ -n "$l" ]] && jq -e '[.items[] | select(.metadata.name == "mediagenda-api")] | length == 0' >/dev/null 2>&1 <<<"$l"
}
check_cmd "recette : l'ancien Deployment mediagenda-api du M14 est retiré" _e04_ancien
_e04_db="$(_m17d_obj mediagenda-recette cluster.postgresql.cnpg.io mediagenda-db)"
_e04_base_ancienne() {
  local tb tc
  tb="$(jq -r '.metadata.creationTimestamp // ""' <<<"$_e04_db")" || return 1
  tc="$(jq -r '.metadata.creationTimestamp // ""' <<<"$_e04_cmj")" || return 1
  [[ -n "$tb" && -n "$tc" && "$tb" < "$tc" ]]
}
check_cmd "recette : la base mediagenda-db est antérieure à la reprise (non recréée)" _e04_base_ancienne
