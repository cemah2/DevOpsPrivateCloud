# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées par bash -c
# check-E44.sh — M14-E44 « Sous le capot : du kubectl apply au conteneur » : compte rendu présent,
# structuré et commité ; pod « capot » lié à la main (ordonnanceur inexistant) et en marche ; aucune
# clé privée laissée dans le dossier de travail ni dans le compte rendu. Lecture seule.

# shellcheck source=_m14-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m14-expert.sh"

title "M14-E44 — Sous le capot : du kubectl apply au conteneur"
require_cmd git jq kubectl

_m14_e44_cr="$_m14x_depot/docs/kubernetes/analyses/du-apply-au-conteneur.md"
check_cmd "compte rendu docs/kubernetes/analyses/du-apply-au-conteneur.md présent" test -s "$_m14_e44_cr"
check_output "section sur l'API (list, watch, resourceVersion)" '^## .*(API|watch)' cat "$_m14_e44_cr"
check_output "section sur l'ordonnanceur" '^## .*[Oo]rdonnanceur' cat "$_m14_e44_cr"
check_output "section sur le kubelet et le CRI" '^## .*(kubelet|CRI)' cat "$_m14_e44_cr"
check_output "section sur les cgroups et les espaces de noms" '^## .*cgroup' cat "$_m14_e44_cr"
check_output "section « Réponses aux questions »" '^## Réponses aux questions' cat "$_m14_e44_cr"
check_cmd "notions citées : resourceVersion, watch, binding, crictl, pause, cgroup" \
  bash -c 'for m in resourceVersion watch binding crictl pause cgroup; do grep -qi -- "$m" "$1" || exit 1; done' _ "$_m14_e44_cr"
check_cmd "compte rendu commité, sans modification en attente" \
  bash -c 'cd "$1" && git ls-files --error-unmatch docs/kubernetes/analyses/du-apply-au-conteneur.md >/dev/null 2>&1 && [ -z "$(git status --porcelain -- docs/kubernetes/analyses)" ]' _ "$_m14x_depot"
check_cmd "aucune clé privée ni jeton dans le compte rendu" \
  bash -c 'test -s "$1" && ! grep -Eq "PRIVATE KEY|client-key-data|eyJhbGciOi" "$1"' _ "$_m14_e44_cr"

if _m14x_api_repond; then
  check_cmd "pod capot (wb-essais) : ordonnanceur « ordonnanceur-manuel », lié à un travailleur, en marche" \
    _m14x_kq '.spec.schedulerName == "ordonnanceur-manuel" and ((.spec.nodeName // "") | test("^k8s-w"))
              and .status.phase == "Running"' -n wb-essais pod capot
  check_cmd "pod capot : limites de ressources posées (cgroups observables)" \
    _m14x_kq '.spec.containers[0].resources.limits.cpu != null and .spec.containers[0].resources.limits.memory != null' \
    -n wb-essais pod capot
  check_cmd "le nœud réel du pod capot figure dans le compte rendu" \
    bash -c 'n="$(kubectl --kubeconfig "$2" get pod capot -n wb-essais -o jsonpath="{.spec.nodeName}" 2>/dev/null)"; [ -n "$n" ] && grep -qF -- "$n" "$1"' \
    _ "$_m14_e44_cr" "${WB_K8S_KUBECONFIG:-$HOME/.config/workbook/k8s-checks.kubeconfig}"
else
  skip "pod capot" "l'API ne répond pas au compte des checks (lab/bin/check 14 39)"
fi
check_cmd "dossier de travail ~/capot sans clé privée (supprimé ou nettoyé)" \
  bash -c '! grep -rqs "PRIVATE KEY" "$HOME/capot"'
