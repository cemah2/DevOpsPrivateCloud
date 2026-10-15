# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et commandes distantes ou bash -c entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E37.sh — M14-E37 « Panne : ImagePullBackOff » : plus aucun pod en échec de tirage, agenda tiré
# de Harbor avec le bon Secret, outil public tiré par le cache Harbor, hosts.toml de docker.io sains,
# RB-145 (section images), panne close. Lecture seule.

# shellcheck source=_m14-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m14-expert.sh"

title "M14-E37 — Les images se tirent à nouveau"
require_cmd jq kubectl ssh

if ! _m14x_api_repond; then
  skip "pods et images" "l'API ne répond pas au compte des checks (lab/bin/check 14 39)"
else
  # shellcheck disable=SC2046  # liste d'espaces voulue
  check_cmd "aucun conteneur en ErrImagePull ou ImagePullBackOff (wb-*, mediagenda-*, kube-system)" \
    _m14x_pods_sans '(.state.waiting.reason // "") | test("ErrImagePull|ImagePullBackOff|InvalidImageName")' \
    kube-system $(_m14x_espaces_workbook)
  if _m14x_temoins; then
    check_cmd "déploiement agenda (wb-pannes) entièrement à jour et disponible" _m14x_deploy_pret "$_m14x_ns" agenda
    check_cmd "agenda : image du projet medisphere de Harbor, référence par étiquette ou par un digest existant" \
      _m14x_kq '.items | length > 0 and all(.[]; .status.containerStatuses[]? | select(.name == "agenda")
                | (.image | startswith("registry.par1.medisphere.internal/medisphere/mediagenda-api")) and .ready == true)' \
      -n "$_m14x_ns" pods -l app.kubernetes.io/name=agenda
    check_cmd "agenda : Secret de tirage « harbor-pull » référencé" \
      _m14x_kq '[.spec.template.spec.imagePullSecrets[]?.name] == ["harbor-pull"]' -n "$_m14x_ns" deploy agenda
    if kube -n "$_m14x_ns" get deploy outil-rapport >/dev/null 2>&1; then
      check_cmd "outil-rapport (image publique par son nom docker.io) disponible" _m14x_deploy_pret "$_m14x_ns" outil-rapport
    fi
  else
    skip "témoins de wb-pannes" "absents : ils sont créés à la première injection (lab/bin/break 14 37)"
  fi
fi
for _m14_e37_h in "${_m14x_w[@]}"; do
  check_cmd "$_m14_e37_h : hosts.toml de docker.io vers le cache Harbor (/v2/dockerhub)" \
    _m14x_noeud "$_m14_e37_h" 'grep -q "registry.par1.medisphere.internal/v2/dockerhub\"" /etc/containerd/certs.d/docker.io/hosts.toml'
done
check_cmd "RB-145 : section sur les échecs de tirage d'image" \
  _m14x_doc_contient 'docs/kubernetes/runbooks/RB-145-*.md' '^#+ .*(ImagePull|image)'
check_cmd "panne M14-E37 close (lab/bin/break 14 37 --annuler après réparation)" _m14x_aucune_panne_active E37
