# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # scripts conteneur entre apostrophes
# break-E42.sh — M26-E42 « Incident : un conteneur compromis »
#
# ⚠️ La « compromission » est STRICTEMENT INOFFENSIVE (PLAN §4.12) : aucun vrai code malveillant, aucun
# calcul, aucune sortie réelle. Un pod témoin de l'espace wb-pannes imite les SIGNES qu'un conteneur
# compromis laisse, pour que l'apprenant les détecte (Falco/Tetragon), isole, collecte, éradique et
# rétablisse. Ce que fait le témoin, et rien d'autre :
#   - un processus au nom trompeur (« kdevtmpfsi », nom de mineur connu) : une copie de busybox lancée
#     comme « sleep », qui ne fait que DORMIR en boucle : zéro calcul, zéro charge CPU ;
#   - il lit son propre jeton de compte de service (cat … > /dev/null) : « lecture inattendue du jeton » ;
#   - il tente une connexion TCP vers un « puits » qui NE RÉPOND PAS (192.0.2.10, réseau de documentation
#     RFC 5737, jamais routé ; le refus réseau par défaut de wb-pannes la jette de toute façon) :
#     la tentative échoue toujours, rien n'est exfiltré ;
#   - il copie /bin/sleep dans /tmp et l'exécute de là : « binaire exécuté depuis /tmp ».
# Variantes : 1) le mineur factice ; 2) + exfiltration factice (la boucle écrit dans /tmp et « tente »
# d'envoyer) ; 3) + persistance par un CronJob de wb-pannes qui relance le pod chaque minute.
# Tout vit dans wb-pannes (PSA restricted), en non-root, sans privilège. Jamais ailleurs.
#
# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m26-commun.sh
source "$WB_ROOT/modules/26-durcissement/corrige/pannes/_m26-commun.sh"

_E42_NS=wb-pannes
_E42_IMG="${WB_M26_IMAGE_BB:-registry.par1.medisphere.internal/dockerhub/library/busybox:1.37}"

# Script du conteneur témoin : inoffensif (voir l'en-tête). $1 = 1 si « exfiltration factice ».
read -r -d '' _E42_SCRIPT <<'SH' || true
set +e
cp /bin/sleep /tmp/kdevtmpfsi 2>/dev/null
: > /tmp/.wb-depot-incident
TOKEN=/var/run/secrets/kubernetes.io/serviceaccount/token
while true; do
  # Signe 1 : lecture inattendue du jeton de compte de service (jeté).
  cat "$TOKEN" >/dev/null 2>&1
  # Signe 2 : tentative de connexion vers un puits qui ne répond pas (192.0.2.10, RFC 5737 : jamais
  # routé ; échoue toujours). Une adresse plutôt qu'un nom : l'appel connect() a bien lieu (Falco, Tetragon).
  nc -w 2 -z 192.0.2.10 9999 >/dev/null 2>&1
  if [ "${WB_EXFIL:-0}" = 1 ]; then
    date >> /tmp/.wb-depot-incident 2>/dev/null   # « collecte » factice locale, jamais envoyée
  fi
  # Signe 3 : exécution d'un binaire depuis /tmp, qui ne fait que dormir (zéro calcul).
  # Le fichier s'appelle kdevtmpfsi (c'est ce nom que voient ps, Falco et Tetragon) ; argv[0] = « sleep »
  # pour que busybox lance son applet sleep. Sous-shell : la boucle continue quoi qu'il arrive.
  ( exec -a sleep /tmp/kdevtmpfsi 30 ) 2>/dev/null || sleep 30
done
SH

_e42_manifeste() {
  local exfil="$1"
  cat <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wb-mineur
  namespace: $_E42_NS
  labels: {app.kubernetes.io/name: wb-mineur, medisphere.internal/panne: M26-E42}
spec:
  replicas: 1
  selector: {matchLabels: {app.kubernetes.io/name: wb-mineur}}
  template:
    metadata: {labels: {app.kubernetes.io/name: wb-mineur, medisphere.internal/equipe: plateforme, medisphere.internal/panne: M26-E42}}
    spec:
      securityContext: {runAsNonRoot: true, runAsUser: 65534, runAsGroup: 65534, seccompProfile: {type: RuntimeDefault}}
      containers:
        - name: app
          image: $_E42_IMG
          command: ["sh", "-c", $(printf '%s' "$_E42_SCRIPT" | jq -Rs .)]
          env: [{name: WB_EXFIL, value: "$exfil"}]
          resources: {requests: {cpu: 10m, memory: 16Mi}, limits: {cpu: 50m, memory: 64Mi}}
          securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: ["ALL"]}}
          volumeMounts: [{name: tmp, mountPath: /tmp}]
      volumes: [{name: tmp, emptyDir: {}}]
EOF
}

_e42_cronjob() {
  cat <<EOF
apiVersion: batch/v1
kind: CronJob
metadata:
  name: wb-persistance
  namespace: $_E42_NS
  labels: {medisphere.internal/panne: M26-E42}
spec:
  schedule: "*/1 * * * *"
  concurrencyPolicy: Forbid
  jobTemplate:
    metadata: {labels: {medisphere.internal/panne: M26-E42}}
    spec:
      template:
        metadata: {labels: {app.kubernetes.io/name: wb-persistance, medisphere.internal/equipe: plateforme, medisphere.internal/panne: M26-E42}}
        spec:
          restartPolicy: Never
          securityContext: {runAsNonRoot: true, runAsUser: 65534, seccompProfile: {type: RuntimeDefault}}
          containers:
            - name: app
              image: $_E42_IMG
              command: ["sh", "-c", "echo relance factice de persistance ; sleep 5"]
              resources: {requests: {cpu: 10m, memory: 16Mi}, limits: {cpu: 50m, memory: 32Mi}}
              securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: ["ALL"]}}
EOF
}

_m26E42_une() {
  local n="$1" exfil=0
  m26_ecrire E42 variante "$n"
  wb_kubectl get namespace "$_E42_NS" >/dev/null 2>&1 || wb_kubectl create namespace "$_E42_NS" >/dev/null || return 1
  wb_kubectl label namespace "$_E42_NS" pod-security.kubernetes.io/enforce=restricted --overwrite >/dev/null 2>&1 || true
  [[ "$n" -ge 2 ]] && exfil=1
  _e42_manifeste "$exfil" | wb_kubectl apply -f - >/dev/null || return 1
  if ((n == 3)); then _e42_cronjob | wb_kubectl apply -f - >/dev/null || return 1; fi
  m26_journal E42 "témoin inoffensif wb-mineur posé (variante $n)"
  m26_attendre 180 _e42_present || return 1
}

_e42_present() { [[ "$(wb_kubectl -n "$_E42_NS" get deploy wb-mineur -o jsonpath='{.status.availableReplicas}' 2>/dev/null)" -ge 1 ]]; }

panne_E42_v1() { m26_kube_sain && _m26E42_une 1; }
panne_E42_v2() { m26_kube_sain && _m26E42_une 2; }
panne_E42_v3() { m26_kube_sain && _m26E42_une 3; }

verifier_E42() { _e42_present; }

annuler_E42() {
  wb_kubectl -n "$_E42_NS" delete deployment wb-mineur --ignore-not-found >/dev/null 2>&1 || true
  wb_kubectl -n "$_E42_NS" delete cronjob wb-persistance --ignore-not-found >/dev/null 2>&1 || true
  wb_kubectl -n "$_E42_NS" delete job -l medisphere.internal/panne=M26-E42 --ignore-not-found >/dev/null 2>&1 || true
  # Si l'apprenant a mis l'espace en quarantaine (étiquette posée pendant l'incident), on la retire pour
  # revenir à l'état sain ; la politique « quarantaine » posée en E33 reste en place (elle ne nuit pas).
  wb_kubectl -n "$_E42_NS" label pods --all medisphere.internal/quarantaine- >/dev/null 2>&1 || true
  m26_oublier E42 variante
  m26_journal E42 "annulation : témoin retiré"
}

resume_E42() { echo "Un pod de wb-pannes se comporte comme un conteneur compromis (processus suspect, lecture du jeton, sortie vers un puits, binaire dans /tmp)."; }

symptome_E42() {
  wb_symptome "Ticket INC-5342 — De : Sophie Laurent (priorité P1)" \
    "Falco (ou Tetragon) remonte un comportement anormal dans un pod de wb-pannes : un processus" \
    "« kdevtmpfsi », la lecture du jeton de compte de service par un processus inattendu, une tentative" \
    "de sortie vers une adresse inconnue, un binaire exécuté depuis /tmp. Traite-le comme une" \
    "compromission : détecte, ISOLE (quarantaine), collecte les preuves, éradique, rétablis, puis" \
    "complète RB-262 (E33). (Le pod est un témoin strictement inoffensif : il ne mine rien, n'exfiltre rien.)" \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 26 42"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 26 E42 3 "$@"; }
fi
