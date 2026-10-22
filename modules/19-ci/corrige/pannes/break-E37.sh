# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E37.sh — M19-E37 « Panne : la construction d'image échoue »
#
# Cible : le démon buildkitd partagé (espace buildkit), ses certificats (cert-manager), le cache de
# construction dans Harbor. Variantes :
#   1. le certificat CLIENT de buildkitd (Certificate cert-manager émis par buildkit-ca, Secret monté
#      dans les pods de job) est réémis par une autre autorité : Lucas a « remplacé l'Issuer »
#      (Issuer CA buildkit-ca-2026 créé à côté) ; buildkitd refuse la poignée de main TLS ;
#   2. CiliumNetworkPolicy « buildkitd-durcissement » ajoutée dans buildkit : refus (ingressDeny) du
#      port 1234 depuis ci-jobs ;
#   3. robot Harbor du cache de construction (projet plateforme, nom contenant « cache ») désactivé ;
#   4. volume de données de buildkitd (PVC uniquement : jamais un emptyDir, qui remplirait le disque
#      du nœud) rempli par un fichier réservé (fallocate) jusqu'à saturation.
# Vérification des variantes 1 et 2 par une sonde : un pod buildctl dans ci-jobs, avec le Secret
# client, qui interroge le démon (debug workers). La sonde doit réussir AVANT l'injection, sinon la
# variante est sautée (configuration différente de celle du corrigé).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m19-commun.sh
source "$WB_ROOT/modules/19-ci/corrige/pannes/_m19-commun.sh"

_E37_ISSUER=buildkit-ca-2026
_E37_CNP=buildkitd-durcissement
_E37_FICHIER=wb-remplissage-M19-E37
_E37_SONDE=sonde-buildkit-m19

# _e37_cert_client — « espace nom secret » du Certificate client (issuerRef buildkit-ca, hors de
# l'espace buildkit, de préférence dans ci-jobs).
_e37_cert_client() {
  wb_kubectl get certificates.cert-manager.io -A -o json 2>/dev/null | jq -r --arg bk "$_M19_NS_BK" '
    [.items[] | select(.spec.issuerRef.name == "buildkit-ca" and .metadata.namespace != $bk)]
    | (map(select(.metadata.namespace == "ci-jobs")) + .) | .[0]
    | select(. != null) | "\(.metadata.namespace) \(.metadata.name) \(.spec.secretName)"'
}

# _e37_sonde — 0 si un pod de ci-jobs, avec le Secret client, obtient la liste des workers du démon.
_e37_sonde() {
  local ns nom secret ph t=0
  read -r ns nom secret < <(_e37_cert_client) || return 2
  [[ -n "$secret" ]] || return 2
  wb_kubectl -n "$_M19_NS_JOBS" delete pod "$_E37_SONDE" --ignore-not-found --wait=true >/dev/null 2>&1 || true
  wb_kubectl apply -f - >/dev/null 2>&1 <<EOF || return 2
apiVersion: v1
kind: Pod
metadata:
  name: $_E37_SONDE
  namespace: $_M19_NS_JOBS
  # medisphere.internal/ci=job : seule étiquette admise en entrée par la politique de buildkitd (M19-E08).
  labels: {app.kubernetes.io/name: $_E37_SONDE, medisphere.internal/ci: job, medisphere.internal/role: sonde-workbook}
spec:
  restartPolicy: Never
  activeDeadlineSeconds: 60
  automountServiceAccountToken: false
  securityContext: {runAsNonRoot: true, runAsUser: 1000, runAsGroup: 1000, seccompProfile: {type: RuntimeDefault}}
  containers:
    - name: buildctl
      image: $_M19_IMAGE_BUILDKIT
      command: ["buildctl", "--addr", "tcp://buildkitd.$_M19_NS_BK.svc.cluster.local:1234",
                "--tlscacert", "/certs/ca.crt", "--tlscert", "/certs/tls.crt", "--tlskey", "/certs/tls.key",
                "--timeout", "20", "debug", "workers"]
      resources: {requests: {cpu: 50m, memory: 64Mi}, limits: {cpu: 200m, memory: 128Mi}}
      securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}}
      volumeMounts: [{name: certs, mountPath: /certs, readOnly: true}]
  volumes:
    - name: certs
      secret: {secretName: $secret}
EOF
  while ((t < 120)); do
    ph="$(wb_kubectl -n "$_M19_NS_JOBS" get pod "$_E37_SONDE" -o jsonpath='{.status.phase}' 2>/dev/null)" || ph=""
    [[ "$ph" == Succeeded || "$ph" == Failed ]] && break
    sleep 5
    t=$((t + 5))
  done
  wb_kubectl -n "$_M19_NS_JOBS" delete pod "$_E37_SONDE" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  [[ "$ph" == Succeeded ]]
}
_e37_sonde_ko() { local rc=0; _e37_sonde || rc=$?; ((rc == 1)); }

# _e37_pod_bk — « pod conteneur chemin_de_données » du démon, si ses données sont sur un PVC.
_e37_pod_bk() {
  wb_kubectl -n "$_M19_NS_BK" get pods -o json 2>/dev/null | jq -r '
    [.items[] | select(.status.phase == "Running") as $p
     | ($p.spec.volumes // [] | map(select(.persistentVolumeClaim)) | map(.name)) as $pvc
     | $p.spec.containers[] as $c
     | $c.volumeMounts[]? | select(.name as $v | $pvc | index($v)) | "\($p.metadata.name) \($c.name) \(.mountPath)"][0] // empty'
}

_e37_exec() {
  local pod="$1" ct="$2"
  shift 2
  wb_kubectl -n "$_M19_NS_BK" exec "$pod" -c "$ct" -- sh -c "$*"
}

_e37_plein() {
  local pod ct ch
  read -r pod ct ch < <(_e37_pod_bk) || return 1
  [[ -n "$ch" ]] || return 1
  _e37_exec "$pod" "$ct" "test -e '$ch/$_E37_FICHIER' && df -P '$ch' | awk 'NR == 2 { exit !(\$4 < 51200) }'" >/dev/null 2>&1
}

_e37_issuer_pret() {
  wb_kubectl -n "$1" get issuer "$_E37_ISSUER" -o json 2>/dev/null |
    jq -e 'any(.status.conditions[]?; .type == "Ready" and .status == "True")' >/dev/null 2>&1
}

_e37_robot() { m19_harbor GET "robots/$(m19_lire E37 robot)" 2>/dev/null; }

_m19E37_une() {
  local n="$1" ns nom secret rc=0 r id pod ct ch libre
  m19_debut E37
  case "$n" in
    1 | 2)
      _e37_sonde || rc=$?
      ((rc == 0)) || return 10
      if ((n == 1)); then
        read -r ns nom secret < <(_e37_cert_client) || return 10
        m19_sauver_objet E37 certificates.cert-manager.io "$nom" "$ns"
        m19_ecrire E37 cert "$ns $nom"
        wb_kubectl apply -f - >/dev/null <<EOF || { _e37_defaire 1; return 1; }
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: $_E37_ISSUER-racine
  namespace: $ns
  labels: {medisphere.internal/auteur: lucas.martin}
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: $_E37_ISSUER
  namespace: $ns
  labels: {medisphere.internal/auteur: lucas.martin}
spec:
  isCA: true
  commonName: buildkit-ca-2026
  secretName: $_E37_ISSUER
  duration: 8760h
  privateKey: {algorithm: ECDSA, size: 256}
  issuerRef: {name: $_E37_ISSUER-racine, kind: Issuer}
---
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: $_E37_ISSUER
  namespace: $ns
  labels: {medisphere.internal/auteur: lucas.martin}
spec:
  ca: {secretName: $_E37_ISSUER}
EOF
        m19_attendre 90 _e37_issuer_pret "$ns" || { _e37_defaire 1; return 1; }
        wb_kubectl -n "$ns" patch certificates.cert-manager.io "$nom" --type merge \
          -p "{\"spec\":{\"issuerRef\":{\"name\":\"$_E37_ISSUER\",\"kind\":\"Issuer\",\"group\":\"cert-manager.io\"}}}" >/dev/null || { _e37_defaire 1; return 1; }
        m19_journal E37 "variante 1 : $ns/$nom réémis par $_E37_ISSUER"
        sleep 20
      else
        wb_kubectl apply -f - >/dev/null <<EOF || return 1
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: $_E37_CNP
  namespace: $_M19_NS_BK
  labels: {medisphere.internal/auteur: lucas.martin}
  annotations: {medisphere.internal/ticket: "SEC-2037 durcissement de buildkitd (Lucas)"}
spec:
  endpointSelector: {}
  enableDefaultDeny: {ingress: false, egress: false}
  ingressDeny:
    - fromEndpoints:
        - matchLabels: {"k8s:io.kubernetes.pod.namespace": $_M19_NS_JOBS}
      toPorts:
        - ports: [{port: "1234", protocol: TCP}]
EOF
        m19_ecrire E37 cnp 1
        m19_journal E37 "variante 2 : politique $_E37_CNP posée"
        sleep 10
      fi
      m19_attendre 90 _e37_sonde_ko || { _e37_defaire "$n"; return 10; }
      ;;
    3)
      r="$(m19_harbor GET "robots?page_size=100")" || return 10
      id="$(jq -r '[.[] | select((.name | test("cache"; "i")) and (.disable | not)
                     and ((.name | startswith("robot$plateforme+")) or any(.permissions[]?; .namespace == "plateforme")))][0].id // empty' <<<"$r")"
      [[ -n "$id" ]] || return 10
      m19_ecrire E37 robot "$id"
      r="$(m19_harbor GET "robots/$id")" || return 1
      m19_harbor PUT "robots/$id" -H 'Content-Type: application/json' \
        --data-binary "$(jq -c '.disable = true | .description = ((.description // "") + " [désactivé par Lucas, M19-E37]")' <<<"$r")" >/dev/null || return 1
      m19_journal E37 "variante 3 : robot Harbor $id désactivé"
      _e37_robot | jq -e '.disable' >/dev/null || { _e37_defaire 3; return 10; }
      ;;
    4)
      read -r pod ct ch < <(_e37_pod_bk) || return 10
      [[ -n "$ch" ]] || return 10
      libre="$(_e37_exec "$pod" "$ct" "df -Pk '$ch' | awk 'NR == 2 { print \$4 }'" 2>/dev/null)" || return 10
      [[ "$libre" =~ ^[0-9]+$ ]] && ((libre > 102400)) || return 10
      _e37_exec "$pod" "$ct" "command -v fallocate >/dev/null && fallocate -l $(((libre - 20480) * 1024)) '$ch/$_E37_FICHIER'" >/dev/null 2>&1 || {
        _e37_exec "$pod" "$ct" "rm -f '$ch/$_E37_FICHIER'" >/dev/null 2>&1 || true
        return 10
      }
      m19_ecrire E37 remplissage "$ch"
      m19_journal E37 "variante 4 : $ch rempli ($pod)"
      _e37_plein || { _e37_defaire 4; return 10; }
      ;;
  esac
  m19_journal E37 "variante $n posée et constatée"
}

_e37_defaire() {
  local n="$1" ns nom cur pod ct ch r
  case "$n" in
    1)
      read -r ns nom < <(m19_lire E37 cert) || true
      if [[ -n "${nom:-}" ]]; then
        cur="$(wb_kubectl -n "$ns" get certificates.cert-manager.io "$nom" -o json 2>/dev/null)" || cur=""
        if jq -e --arg i "$_E37_ISSUER" '.spec.issuerRef.name == $i' >/dev/null 2>&1 <<<"$cur"; then
          m19_restaurer_objet E37 certificates.cert-manager.io "$nom" "$ns"
          m19_journal E37 "annulation : $ns/$nom rendu à buildkit-ca"
        else
          m19_oublier_objet E37 certificates.cert-manager.io "$nom" "$ns"
        fi
        if ! wb_kubectl get certificates.cert-manager.io -A -o json 2>/dev/null | jq -e --arg i "$_E37_ISSUER" \
          'any(.items[]; .spec.issuerRef.name == $i)' >/dev/null 2>&1; then
          wb_kubectl -n "$ns" delete issuer "$_E37_ISSUER" "$_E37_ISSUER-racine" --ignore-not-found >/dev/null 2>&1 || true
          wb_kubectl -n "$ns" delete certificates.cert-manager.io "$_E37_ISSUER" --ignore-not-found >/dev/null 2>&1 || true
          wb_kubectl -n "$ns" delete secret "$_E37_ISSUER" --ignore-not-found >/dev/null 2>&1 || true
        fi
      fi
      m19_oublier E37 cert
      ;;
    2)
      if [[ -n "$(m19_lire E37 cnp)" ]]; then
        wb_kubectl -n "$_M19_NS_BK" delete ciliumnetworkpolicies.cilium.io "$_E37_CNP" --ignore-not-found >/dev/null 2>&1 || true
      fi
      m19_oublier E37 cnp
      ;;
    3)
      if [[ -n "$(m19_lire E37 robot)" ]]; then
        r="$(_e37_robot)" || r=""
        if jq -e '.disable and ((.description // "") | test("M19-E37"))' >/dev/null 2>&1 <<<"$r"; then
          m19_harbor PUT "robots/$(m19_lire E37 robot)" -H 'Content-Type: application/json' \
            --data-binary "$(jq -c '.disable = false | .description = ((.description // "") | sub(" \\[désactivé par Lucas, M19-E37\\]"; ""))' <<<"$r")" >/dev/null ||
            wb_avert "robot Harbor $(m19_lire E37 robot) non réactivé"
        fi
      fi
      m19_oublier E37 robot
      ;;
    4)
      if [[ -n "$(m19_lire E37 remplissage)" ]]; then
        read -r pod ct ch < <(_e37_pod_bk) || true
        [[ -z "${ch:-}" ]] || _e37_exec "$pod" "$ct" "rm -f '$ch/$_E37_FICHIER'" >/dev/null 2>&1 ||
          wb_avert "fichier $_E37_FICHIER à retirer à la main du volume de buildkitd"
      fi
      m19_oublier E37 remplissage
      ;;
  esac
}

panne_E37_v1() { m19_preparer && m19_essayer E37 4 1; }
panne_E37_v2() { m19_preparer && m19_essayer E37 4 2; }
panne_E37_v3() { m19_preparer && m19_essayer E37 4 3; }
panne_E37_v4() { m19_preparer && m19_essayer E37 4 4; }

verifier_E37() {
  local ns nom
  case "${WB_VAR:-}" in
    1) read -r ns nom < <(m19_lire E37 cert) && wb_kubectl -n "$ns" get certificates.cert-manager.io "$nom" -o json |
      jq -e --arg i "$_E37_ISSUER" '.spec.issuerRef.name == $i' >/dev/null ;;
    2) wb_kubectl -n "$_M19_NS_BK" get ciliumnetworkpolicies.cilium.io "$_E37_CNP" >/dev/null 2>&1 ;;
    3) _e37_robot | jq -e '.disable' >/dev/null ;;
    4) _e37_plein ;;
    *) return 1 ;;
  esac
}

annuler_E37() {
  case "${WB_VAR:-}" in
    [1-4]) _e37_defaire "$WB_VAR" ;;
    *) local v; for v in 1 2 3 4; do _e37_defaire "$v"; done ;;
  esac
  wb_kubectl -n "$_M19_NS_JOBS" delete pod "$_E37_SONDE" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  m19_oublier E37 debut
  m19_journal E37 "annulation"
}

resume_E37() { echo "Les constructions d'images par buildkitd (étiquette k8s) échouent toutes, MédiAgenda compris."; }

symptome_E37() {
  wb_symptome "Ticket INC-4637 — De : Julien Petit" \
    "Plus aucune image ne se construit par le démon BuildKit partagé : le job de construction de" \
    "mediagenda/api échoue (relance le pipeline de main pour voir l'erreur), et chez MédiDoc" \
    "pareil. Les tests passent, c'est seulement l'image. Lucas a « durci » et « rangé » deux ou" \
    "trois choses autour de buildkitd cette semaine. Il nous faut une release ce soir." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 19 37"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 19 E37 4 "$@"; }
fi
