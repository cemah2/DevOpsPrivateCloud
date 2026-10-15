# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et commandes distantes ou bash -c entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E41.sh — M14-E41 « Panne : accès refusé » : ton identité personnelle fonctionne (certificat
# valable, pas system:masters), l'équipe MédiAgenda a son RoleBinding, aucune politique d'admission ne
# refuse les volumes emptyDir des bases jetables, les témoins (postgres, sonde-api) sont prêts avec
# leurs droits exacts, RB-147, panne close.
# Lecture seule : « auth whoami » et un « apply --dry-run=server » (rien n'est créé) avec TON
# kubeconfig (WB_K8S_ADMIN_KUBECONFIG, défaut ~/.kube/config), le reste avec le compte des checks.

# shellcheck source=_m14-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m14-expert.sh"

title "M14-E41 — Les accès sont rétablis, sans droit de trop"
require_cmd jq kubectl openssl

_m14_e41_kc="${WB_K8S_ADMIN_KUBECONFIG:-$HOME/.kube/config}"
_m14_e41_moi() { kubectl --kubeconfig "$_m14_e41_kc" --request-timeout=15s auth whoami -o json 2>/dev/null; }
check_cmd "ton kubeconfig personnel est accepté par l'API (auth whoami)" _m14_e41_moi
check_cmd "ton identité n'est pas dans system:masters (pas de super-admin.conf au quotidien)" \
  bash -c '[ -n "$1" ] && ! jq -e ".status.userInfo.groups | index(\"system:masters\")" >/dev/null <<<"$1"' _ "$(_m14_e41_moi)"
check_cmd "ton certificat client est encore valable au moins 24 h" \
  bash -c 'kubectl --kubeconfig "$1" config view --raw --minify -o jsonpath="{.users[0].user.client-certificate-data}" | base64 -d | openssl x509 -noout -checkend 86400 >/dev/null' _ "$_m14_e41_kc"

if _m14x_api_repond; then
  check_cmd "mediagenda-dev : un RoleBinding donne des droits au groupe medisphere:mediagenda-devs" \
    _m14x_kq '[.items[] | select(any(.subjects[]?; .kind == "Group" and .name == "medisphere:mediagenda-devs"))] | length > 0' \
    -n mediagenda-dev rolebindings
  check_cmd "aucune politique d'admission « sec-volumes-locaux » qui refuse emptyDir" \
    _m14x_kq '[.items[] | select(any(.spec.validations[]?; .expression | test("emptyDir")))] | length == 0' validatingadmissionpolicies
  if _m14x_temoins; then
    _m14_e41_essai() {
      kubectl --kubeconfig "$_m14_e41_kc" --request-timeout=20s apply --dry-run=server -f - >/dev/null 2>&1 <<EOF
apiVersion: v1
kind: Pod
metadata: {name: essai-check-e41, namespace: $_m14x_ns}
spec:
  securityContext: {runAsNonRoot: true, runAsUser: 65534, seccompProfile: {type: RuntimeDefault}}
  containers:
    - name: c
      image: registry.par1.medisphere.internal/dockerhub/library/busybox:1.37
      command: ["true"]
      securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}}
      volumeMounts: [{name: t, mountPath: /tmp}]
  volumes: [{name: t, emptyDir: {}}]
EOF
    }
    check_cmd "un pod avec un volume emptyDir est admis dans wb-pannes (essai à blanc)" _m14_e41_essai
    check_cmd "témoin postgres (wb-pannes) disponible" _m14x_deploy_pret "$_m14x_ns" postgres
    check_cmd "témoin sonde-api disponible (il lit l'API avec son compte de service)" _m14x_deploy_pret "$_m14x_ns" sonde-api
    check_cmd "RoleBinding sonde-api : le compte sonde-api de wb-pannes, rôle sonde-api (rien de plus)" \
      _m14x_kq '.roleRef.kind == "Role" and .roleRef.name == "sonde-api"
                and .subjects == [{"kind": "ServiceAccount", "name": "sonde-api", "namespace": "wb-pannes"}]' \
      -n "$_m14x_ns" rolebinding sonde-api
  else
    skip "témoins de wb-pannes" "absents : ils sont créés à la première injection (lab/bin/break 14 41)"
  fi
else
  skip "objets RBAC et admission" "l'API ne répond pas au compte des checks (lab/bin/check 14 39)"
fi
check_cmd "RB-147 (accès refusé) publié et commité" _m14x_doc_commite 'docs/kubernetes/runbooks/RB-147-*.md'
check_cmd "panne M14-E41 close (lab/bin/break 14 41 --annuler après réparation)" _m14x_aucune_panne_active E41
