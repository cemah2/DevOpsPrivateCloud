# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
# shellcheck source-path=SCRIPTDIR
#
# check-E46.sh — M20-E46 « Mini-projet : MédiSphère en GitOps v1 »
# Contrôle global de la livraison gitops-v1 (depuis adm01). Lecture seule : « kube » (compte
# wb-checks), API d'Argo CD et de GitLab en GET, pvesh en lecture sur pve01, nft list sur les
# passerelles (sudo -n), OpenTofu en lecture seule (state list), dig. Rejoue les contrôles clés des
# paliers précédents (E06, E08, E10, E16, E18, E24, E25, E30), puis vérifie l'intégration.
# Les contrôles détaillés restent dans leurs exercices (lab/bin/check 20 XX). 3 à 5 minutes.

# shellcheck source=_m20-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m20-expert.sh"

title "M20-E46 — MédiSphère en GitOps v1 : contrôle global"
require_cmd jq kubectl curl ssh dig

_m20_e46_dir="$(dirname "${BASH_SOURCE[0]}")"

# --- 1. Contrôles clés des paliers 1 à 3 -----------------------------------------------------------
for _m20_e46_c in E06 E08 E10 E16 E18 E24 E25 E30; do
  if [[ -f "$_m20_e46_dir/check-$_m20_e46_c.sh" ]]; then
    # shellcheck source=/dev/null
    source "$_m20_e46_dir/check-$_m20_e46_c.sh"
  else
    skip "contrôle M20-$_m20_e46_c" "script check-$_m20_e46_c.sh absent"
  fi
done

title "M20-E46 — intégration gitops-v1"

# --- 2. Toutes les applications sous ApplicationSets, racine propriétaire -------------------------
if _m20x_argo_lisible; then
  check_cmd "racine : Synced, Healthy" _m20x_app_saine racine
  _m20_e46_hors_appset() {
    kube -n "$_m20x_ns" get applications.argoproj.io -o json 2>/dev/null | jq -e '
      [.items[] | select((.spec.destination.namespace // "") | test("^(mediagenda|medidoc)-"))
       | select(any(.metadata.ownerReferences[]?; .kind == "ApplicationSet") | not)] | length == 0' >/dev/null 2>&1
  }
  check_cmd "toutes les Applications de mediagenda-* et medidoc-* générées par un ApplicationSet" _m20_e46_hors_appset
  for _m20_e46_as in mediagenda medidoc; do
    check_cmd "ApplicationSet $_m20_e46_as présent et géré depuis plateforme/gitops (racine ou applications)" \
      _m20x_kq '(.metadata.annotations["argocd.argoproj.io/tracking-id"] // "") | test("^(racine|applications):")' \
      -n "$_m20x_ns" applicationsets.argoproj.io "$_m20_e46_as"
  done
  check_cmd "aucune Application en erreur (comparaison, spécification, synchronisation)" _m20x_apps_sans 'Error$'
  _m20_e46_toutes_saines() {
    kube -n "$_m20x_ns" get applications.argoproj.io -o json 2>/dev/null | jq -e '
      [.items[] | select(.status.health.status != "Healthy" or (.status.sync.status != "Synced"))] | length == 0' >/dev/null 2>&1
  }
  check_cmd "toutes les Applications Synced et Healthy" _m20_e46_toutes_saines

  # --- 3. Canary et analyses en recette et en production -------------------------------------------
  for _m20_e46_ns in "$_m20x_ns_recette" "$_m20x_ns_prod"; do
    check_cmd "$_m20_e46_ns : Rollout piloté par argoproj-labs/gatewayAPI" \
      _m20x_kq '.spec.strategy.canary.trafficRouting.plugins["argoproj-labs/gatewayAPI"] != null' \
      -n "$_m20_e46_ns" rollouts.argoproj.io mediagenda
    check_cmd "$_m20_e46_ns : Rollout Healthy, ni en pause ni interrompu" _m20x_rollout_sain "$_m20_e46_ns" mediagenda
    check_cmd "$_m20_e46_ns : analyses branchées sur le canary (étape analysis ou analyse d'arrière-plan)" \
      _m20x_kq '(.spec.strategy.canary.analysis != null) or ([.spec.strategy.canary.steps[]? | select(.analysis != null)] | length > 0)' \
      -n "$_m20_e46_ns" rollouts.argoproj.io mediagenda
  done
  check_cmd "$_m20x_app_prod : synchronisation manuelle (aucune synchronisation automatique)" \
    _m20x_app_jq "$_m20x_app_prod" '.spec.syncPolicy.automated == null or ((.spec.syncPolicy.automated.enabled // true) == false)'

  # --- 4. Notifications, fenêtres, RBAC ------------------------------------------------------------
  check_cmd "notifications : service email et déclencheurs on-sync-failed, on-health-degraded, on-deployed" \
    _m20x_kq '(.data | keys | any(test("^service\\.email"))) and .data["trigger.on-sync-failed"] != null
      and .data["trigger.on-health-degraded"] != null and .data["trigger.on-deployed"] != null' \
    -n "$_m20x_ns" configmap argocd-notifications-cm
  check_cmd "AppProject mediagenda : fenêtre de refus en production avec synchronisation manuelle d'urgence" \
    _m20x_kq '[.spec.syncWindows[]? | select(.kind == "deny" and (.manualSync // false) == true)] | length > 0' \
    -n "$_m20x_ns" appprojects.argoproj.io mediagenda
  check_cmd "RBAC d'Argo CD : politique par défaut vide et rôle de l'équipe MédiAgenda" \
    _m20x_kq '((.data["policy.default"] // "") == "") and ((.data["policy.csv"] // "") | test("role:mediagenda-equipe"))' \
    -n "$_m20x_ns" configmap argocd-rbac-cm
  check_cmd "compte admin d'Argo CD désactivé" \
    _m20x_kq '(.data["admin.enabled"] // "true") == "false"' -n "$_m20x_ns" configmap argocd-cm

  # --- 5. Plus aucun cluster de l'agence ni de Flux ------------------------------------------------
  _m20_e46_aucune_app_lyo() {
    kube -n "$_m20x_ns" get applications.argoproj.io -o json 2>/dev/null | jq -e '
      [.items[] | select(((.spec.destination.server // "") | test("10\\.10\\.99\\.6[12]|lyo|flux")) or ((.spec.destination.name // "") | test("lyo")))] | length == 0' >/dev/null 2>&1
  }
  check_cmd "aucune Application ne vise encore lyo-k3s01 ou flux01" _m20_e46_aucune_app_lyo
  if _m20x_argocd_api clusters >/dev/null 2>&1; then
    check_cmd "API d'Argo CD : plus aucun cluster enregistré hors k8s-par1" \
      bash -c 'jq -e "[.items[]? | select(.server != \"https://kubernetes.default.svc\")] | length == 0" >/dev/null <<<"$1"' _ "$(_m20x_argocd_api clusters)"
  else
    skip "clusters enregistrés" "API d'Argo CD illisible avec ~/.config/workbook/argocd-checks.token"
  fi
else
  skip "objets d'Argo CD" "le compte des checks ne lit pas les Applications (wb-checks-livraison)"
fi

check_cmd "VM 2201 (lyo-k3s01) détruite" _m20x_vm_absente 2201
check_cmd "VM 2202 (flux01) détruite" _m20x_vm_absente 2202

# État OpenTofu envs/m20 : vide (lecture seule, sans verrou).
_m20_e46_etat_vide() {
  local d="${WB_SRC:-$HOME/src}/infra/envs/m20" n
  (
    cd "$d" 2>/dev/null || exit 2
    set -a
    for f in "$HOME/.config/workbook/pve-tofu.env" "$HOME/.config/workbook/s3-tofu.env"; do
      # shellcheck source=/dev/null
      [[ -r "$f" ]] && source "$f"
    done
    set +a
    if [[ -r ../../outils/charger-acces.sh ]]; then
      # shellcheck source=/dev/null
      . ../../outils/charger-acces.sh >/dev/null 2>&1 || true
    fi
    export AWS_CA_BUNDLE="${AWS_CA_BUNDLE:-/etc/ssl/certs/ca-certificates.crt}" TF_IN_AUTOMATION=1 TF_INPUT=0
    n="$(tofu state list 2>/dev/null </dev/null | grep -c .)" || n=""
    [[ "$n" == 0 ]]
  )
}
if command -v tofu >/dev/null 2>&1 && [[ -d "${WB_SRC:-$HOME/src}/infra/envs/m20" ]]; then
  check_cmd "état OpenTofu envs/m20 vide (tofu state list)" _m20_e46_etat_vide
else
  skip "état OpenTofu envs/m20" "copie ~/src/infra/envs/m20 ou tofu absents sur adm01"
fi

_m20_e46_gw_propre() {
  local o
  o="$(remote "$1" "sudo -n nft list ruleset" </dev/null 2>/dev/null)" || return 1
  [[ -n "$o" ]] && ! grep -Eq '10\.10\.99\.6[12]([^0-9]|$)' <<<"$o"
}
for _m20_e46_gw in gw01 gw02; do
  check_cmd "$_m20_e46_gw : plus aucune règle vers 10.10.99.61 ou 10.10.99.62 (flux de M20 retirés)" \
    _m20_e46_gw_propre "$_m20_e46_gw"
done
check_cmd "plateforme/ansible (main) : matrice de la bordure sans flux vers lyo-k3s01 ni flux01" \
  bash -c '! grep -Eq "10\.10\.99\.6[12]([^0-9]|$)|lyo-k3s01|flux01" <<<"$1" && [ -n "$1" ]' _ \
  "$(_m20x_gitlab_brut plateforme/ansible inventories/lab/group_vars/role_routeur/pare_feu.yml 2>/dev/null || _m20x_gitlab_brut plateforme/ansible group_vars/role_routeur/pare_feu.yml 2>/dev/null)"
for _m20_e46_h in lyo-k3s01 flux01; do
  check_cmd "DNS : $_m20_e46_h.par1.medisphere.internal n'est plus publié" \
    bash -c 'r="$(dig +time=3 +tries=1 @10.10.20.10 "$1" A 2>/dev/null)" && { grep -q "status: NXDOMAIN" <<<"$r" || ! grep -q "ANSWER SECTION" <<<"$r"; }' _ "$_m20_e46_h.par1.medisphere.internal"
done
check_cmd "matrice des flux (docs/socle/matrice-flux.md) sans flux actif vers lyo-k3s01 ni flux01" \
  bash -c '[ -f "$1" ] && ! grep -E "10\.10\.99\.6[12]|lyo-k3s01|flux01" "$1" | grep -viq "retir"' _ "$_m20x_depot/docs/socle/matrice-flux.md"

# --- 6. Documentation et étiquette ---------------------------------------------------------------
for _m20_e46_d in "docs/livraison/gitops/adr/ADR-0200*.md" "$_m20x_rb200" \
  "docs/livraison/gitops/promotion.md" "docs/livraison/gitops/politique-changements.md" \
  "docs/livraison/gitops/comparatif-flux.md" "docs/livraison/gitops/sous-le-capot.md" \
  "docs/livraison/gitops/recette-gitops-v1.md"; do
  check_cmd "documentation : ${_m20_e46_d%% *} commité" _m20x_doc_commite "$_m20_e46_d"
done
# Chaque ligne d'exigence (| n | exigence | preuve | …) doit avoir une preuve non vide.
_m20_e46_preuves() {
  local f="$_m20x_depot/docs/livraison/gitops/recette-gitops-v1.md"
  [[ -f "$f" ]] || return 1
  awk -F'|' '/^\|[[:space:]]*[0-9]+[[:space:]]*\|/ { n++; p = $4; gsub(/[[:space:]]/, "", p); if (p == "") vide++ }
    END { exit !(n >= 13 && vide == 0) }' "$f"
}
check_cmd "recette gitops-v1 : les 13 exigences ont chacune une preuve" _m20_e46_preuves
check_cmd "étiquette gitops-v1 sur plateforme/medisphere" \
  bash -c 'jq -e ".name == \"gitops-v1\"" >/dev/null <<<"$1"' _ "$(gitlab_api 'projects/plateforme%2Fmedisphere/repository/tags/gitops-v1' 2>/dev/null)"
check_cmd "aucune MR de panne restée ouverte (mediagenda/deploiement, plateforme/gitops)" \
  bash -c '(( $1 + $2 == 0 ))' _ "$(_m20x_mr_lucas_ouvertes mediagenda/deploiement)" "$(_m20x_mr_lucas_ouvertes plateforme/gitops)"
check_cmd "aucune panne M20 encore marquée active" _m20x_aucune_panne_active
