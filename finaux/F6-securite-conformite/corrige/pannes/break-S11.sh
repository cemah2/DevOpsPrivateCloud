# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # scripts distants, filtres jq et manifestes entre apostrophes
# break-S11.sh — F6-S11 « Panne : un conteneur compromis » (INC-6211)
#
# ⚠️ La « compromission » est STRICTEMENT INOFFENSIVE (règles du bloc F, M26-E42, PLAN §4.15) : AUCUN
# code malveillant, AUCUN binaire d'attaque, AUCUNE donnée lue ni envoyée. Le script ne fait que rejouer
# des commandes ORDINAIRES dans l'espace mediagenda-recette (jamais la production) et créer lui-même un
# faux « C2 » qui ne fait que JOURNALISER ce qu'il reçoit. Ce que fait l'injection, et rien d'autre :
#   - crée la VM « C2 » c2-simule01 (VMID WB_F6_C2_VMID=3601) sur VLAN 99 (SANDBOX), 10.10.99.66, pool
#     « lab », étiquette « env-f6 » : un simple écouteur TCP qui écrit « horodatage adresse_source » dans
#     /var/log/c2-simule.log. Il ne répond rien, n'exécute rien, ne stocke rien d'autre ;
#   - ouvre un shell INTERACTIF dans un conteneur de l'API de recette (règle Falco « shell interactif »)
#     qui LIT le jeton de compte de service monté (règle « lecture du jeton ») — un simple « cat » ;
#   - laisse une boucle qui TENTE, toutes les 60 s pendant 6 h au plus, une connexion TCP vers
#     c2-simule01:4444 (règle « connexion sortante vers un port non prévu »). Elle n'envoie aucun octet.
# Deux VECTEURS (variantes), qui changent la PORTÉE, pas les gestes de confinement :
#   1. jeton de compte de service fuité : le script fabrique un kubeconfig depuis un jeton du compte de
#      service de recette et s'en sert pour DEUX appels de reconnaissance en LECTURE sur l'API
#      (« auth can-i --list », « get pods ») — tracés dans le journal d'audit SOUS L'IDENTITÉ DU COMPTE
#      DE SERVICE. Le refus réseau par défaut tient : la boucle vers le C2 est JETÉE (Hubble DROPPED,
#      le C2 ne journalise rien). Enquête : le vecteur est le jeton, la connexion n'a pas abouti ;
#   2. politique réseau trop large : le script ajoute dans mediagenda-recette une NetworkPolicy
#      « legacy-sortie-large » (comme une vieille MR oubliée) qui autorise la sortie vers 10.10.99.0/24 ;
#      la boucle vers le C2 ABOUTIT alors (Hubble FORWARDED, le C2 journalise les connexions). Enquête :
#      le vecteur est la politique trop large, la connexion a abouti (mais rien n'a été envoyé).
# Le pod visé n'est JAMAIS supprimé (ni par l'injection ni par l'annulation) : c'est la preuve. Rien ne
# touche Falco, Tetragon, Loki ni le compartiment preuves-conformite. L'annulation détruit c2-simule01,
# retire la NetworkPolicy ajoutée (variante 2) et arrête la boucle ; elle ne supprime pas le pod suspect
# (l'éradication est le geste de l'apprenant, après collecte et accord de la RSSI, F6-S12).
# État local (lisible par le check) : ~/.local/state/workbook/F6-S11/{espace,pod,conteneur,cible,vecteur,c2}.

# shellcheck source=../../../../lab/lib/pannes-lib.sh disable=SC1091
source "$WB_ROOT/lab/lib/pannes-lib.sh"

_S11_NS="${WB_F6_RECETTE_NS:-mediagenda-recette}"
_S11_SEL_API='app.kubernetes.io/name=mediagenda,app.kubernetes.io/component=api'
_S11_C2_VMID="${WB_F6_C2_VMID:-3601}"
_S11_C2_IP="${WB_F6_C2_IP:-10.10.99.66}"
_S11_C2_GW="${WB_F6_C2_GW:-10.10.99.1}"
_S11_C2_PORT="${WB_F6_C2_PORT:-4444}"
_S11_C2_BRIDGE="${WB_F6_C2_BRIDGE:-vmbr1}"
_S11_C2_VLAN=99
_S11_TPL="${WB_F6_TPL:-9000}"
_S11_KCFG="${WB_K8S_ADMIN_KUBECONFIG:-$HOME/.kube/config}"
_S11_MARQUE=wb-f6-s11

_s11_etat_dir="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/F6-S11"
_s11_ecrire() { mkdir -p "$_s11_etat_dir" && chmod 700 "$_s11_etat_dir" && printf '%s\n' "$2" >"$_s11_etat_dir/$1"; }
_s11_lire()   { [[ -r "$_s11_etat_dir/$1" ]] && cat "$_s11_etat_dir/$1"; }
_s11_oublier(){ rm -f -- "$_s11_etat_dir/$1"; }

# Boucle de connexion sortante, posée dans le pod (aucun octet envoyé). __CIBLE__ et __PORT__ remplacés.
read -r -d '' _S11_BOUCLE <<'PY' || true
# wb-f6-s11
import os, socket, time
CIBLE = "__CIBLE__"
PORT = __PORT__
if os.fork():
    os._exit(0)
os.setsid()
fin = time.time() + 6 * 3600
while time.time() < fin and not os.path.exists("/tmp/.arret-maj"):
    s = socket.socket()
    s.settimeout(3)
    try:
        s.connect((CIBLE, PORT))
    except OSError:
        pass
    finally:
        s.close()
    time.sleep(60)
PY

# ---------------------------------------------------------------------------
# Contrôle de santé préalable (le lab doit être sain)
# ---------------------------------------------------------------------------
_s11_refus() { echo "Injection refusée : $*." >&2; return 1; }

_s11_sain() {
  command -v jq >/dev/null 2>&1 || { _s11_refus "jq manquant sur ce poste"; return 1; }
  local ds
  # Falco et Tetragon prêts sur tous les nœuds.
  for esp in falco tetragon; do
    ds="$(wb_kubectl -n "$esp" get daemonsets -o json 2>/dev/null || true)"
    jq -e '(.items | length) > 0 and all(.items[]; (.status.numberReady // 0) == (.status.desiredNumberScheduled // -1) and .status.desiredNumberScheduled > 0)' \
      >/dev/null 2>&1 <<<"$ds" || { _s11_refus "$esp n'est pas prêt sur tous les nœuds"; return 1; }
  done
  wb_kubectl get ciliumclusterwidenetworkpolicies.cilium.io quarantaine >/dev/null 2>&1 \
    || { _s11_refus "politique de quarantaine absente (M26-E33)"; return 1; }
  # Un pod d'API prêt en recette.
  [[ -n "$(_s11_pod)" ]] || { _s11_refus "aucun pod d'API prêt dans $_S11_NS"; return 1; }
  # VMID du C2 libre et template présent (création sur pve01).
  if remote "$WB_PVE_HOST" "qm status $_S11_C2_VMID" >/dev/null 2>&1; then
    _s11_refus "la VM $_S11_C2_VMID existe déjà (c2-simule01 non nettoyé ?)"; return 1
  fi
  remote "$WB_PVE_HOST" "qm status $_S11_TPL" >/dev/null 2>&1 \
    || { _s11_refus "template $_S11_TPL introuvable sur $WB_PVE_HOST"; return 1; }
}

_s11_pod() {
  wb_kubectl -n "$_S11_NS" get pods -l "$_S11_SEL_API" -o json 2>/dev/null |
    jq -r '[.items[] | select(.status.phase == "Running" and .metadata.deletionTimestamp == null
            and all(.status.containerStatuses[]?; .ready))] | .[0].metadata.name // empty' 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Le « C2 » simulé : une VM qui ne fait que journaliser les connexions reçues
# ---------------------------------------------------------------------------
_s11_creer_c2() {
  # Clone du template, réseau VLAN 99, adresse fixe, pool lab, étiquette env-f6, démarrage.
  remote "$WB_PVE_HOST" "qm clone $_S11_TPL $_S11_C2_VMID --name c2-simule01 --full 1 --pool lab" >/dev/null 2>&1 \
    || { echo "échec du clone de c2-simule01" >&2; return 1; }
  remote "$WB_PVE_HOST" "qm set $_S11_C2_VMID \
      --net0 virtio,bridge=$_S11_C2_BRIDGE,tag=$_S11_C2_VLAN \
      --ipconfig0 ip=$_S11_C2_IP/24,gw=$_S11_C2_GW \
      --tags env-f6 \
      --onboot 0" >/dev/null 2>&1 \
    || { echo "échec de la configuration réseau de c2-simule01" >&2; return 1; }
  remote "$WB_PVE_HOST" "qm start $_S11_C2_VMID" >/dev/null 2>&1 \
    || { echo "échec du démarrage de c2-simule01" >&2; return 1; }
  # Attente de l'agent QEMU puis pose de l'écouteur (journalise seulement).
  local i
  for ((i = 0; i < 30; i++)); do
    remote "$WB_PVE_HOST" "qm guest exec $_S11_C2_VMID -- true" >/dev/null 2>&1 && break
    sleep 5
  done
  # Écouteur TCP minimal : écrit « horodatage adresse:port » et ferme. Aucune réponse, aucune exécution.
  wb_exec_invite "$_S11_C2_VMID" <<EOF >/dev/null 2>&1 || { echo "échec de la pose de l'écouteur du C2" >&2; return 1; }
cat >/usr/local/bin/c2-simule.py <<'SRV'
import socketserver, datetime
class H(socketserver.BaseRequestHandler):
    def handle(self):
        ip, port = self.client_address[:2]
        with open("/var/log/c2-simule.log", "a") as f:
            f.write("%s %s:%s\n" % (datetime.datetime.utcnow().isoformat(), ip, port))
if __name__ == "__main__":
    srv = socketserver.ThreadingTCPServer(("0.0.0.0", $_S11_C2_PORT), H)
    srv.serve_forever()
SRV
touch /var/log/c2-simule.log
systemd-run --unit c2-simule --description "C2 simule (journalise seulement)" \
  /usr/bin/python3 /usr/local/bin/c2-simule.py
EOF
  return 0
}

_s11_detruire_c2() {
  remote "$WB_PVE_HOST" "qm status $_S11_C2_VMID" >/dev/null 2>&1 || return 0
  remote "$WB_PVE_HOST" "qm stop $_S11_C2_VMID" >/dev/null 2>&1 || true
  sleep 2
  remote "$WB_PVE_HOST" "qm destroy $_S11_C2_VMID --purge 1" >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------------------
# Compromission dans le pod (commandes ordinaires, aucune donnée touchée)
# ---------------------------------------------------------------------------
# _s11_shell POD CONTENEUR — shell interactif, lecture du jeton, boucle vers le C2.
_s11_shell() {
  local pod="$1" c="$2" code
  code="${_S11_BOUCLE/__CIBLE__/$_S11_C2_IP}"
  code="${code/__PORT__/$_S11_C2_PORT}"
  # Le shell interactif (pseudo-terminal fourni par « script ») lit le jeton puis lance la boucle.
  timeout 60 script -qec "kubectl --kubeconfig $(printf '%q' "$_S11_KCFG") -n $_S11_NS exec -it $pod -c $c -- sh -c \
'cat /var/run/secrets/kubernetes.io/serviceaccount/token >/dev/null 2>&1; \
echo $(printf '%s' "$code" | base64 -w0) | base64 -d > /tmp/.sonde-maj.py 2>/dev/null \
&& python3 /tmp/.sonde-maj.py || python3 -c \"\$(echo $(printf '%s' "$code" | base64 -w0) | base64 -d)\" sonde-maj; exit 0'" \
    /dev/null >/dev/null 2>&1 || return 1
}

# Variante 1 : jeton de compte de service fuité, utilisé contre l'API (reconnaissance en lecture).
panne_S11_v1() {
  _s11_sain || return 1
  local pod c sa kube
  pod="$(_s11_pod)"; [[ -n "$pod" ]] || { _s11_refus "aucun pod d'API prêt"; return 1; }
  c="$(wb_kubectl -n "$_S11_NS" get pod "$pod" -o jsonpath='{.spec.containers[0].name}' 2>/dev/null || true)"
  [[ -n "$c" ]] || return 1
  sa="$(wb_kubectl -n "$_S11_NS" get pod "$pod" -o jsonpath='{.spec.serviceAccountName}' 2>/dev/null || true)"
  sa="${sa:-default}"
  _s11_creer_c2 || { _s11_detruire_c2; return 1; }
  # Shell + lecture du jeton + boucle (jetée par le refus réseau par défaut : Hubble DROPPED).
  _s11_shell "$pod" "$c" || { _s11_detruire_c2; return 1; }
  # Usage du jeton fuité contre l'API : kubeconfig éphémère -> tracé sous l'identité du compte de service.
  kube="$(mktemp)"
  if wb_kubectl -n "$_S11_NS" create token "$sa" --duration=1h >"$kube.tok" 2>/dev/null; then
    wb_kubectl config view --raw -o json >/dev/null 2>&1 || true
    KUBECONFIG="" kubectl --server "$(wb_kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')" \
      --token "$(cat "$kube.tok")" --insecure-skip-tls-verify \
      -n "$_S11_NS" auth can-i --list >/dev/null 2>&1 || true
    KUBECONFIG="" kubectl --server "$(wb_kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')" \
      --token "$(cat "$kube.tok")" --insecure-skip-tls-verify \
      -n "$_S11_NS" get pods >/dev/null 2>&1 || true
  fi
  rm -f -- "$kube" "$kube.tok"
  _s11_ecrire espace "$_S11_NS"
  _s11_ecrire pod "$pod"
  _s11_ecrire conteneur "$c"
  _s11_ecrire cible "$_S11_C2_IP:$_S11_C2_PORT"
  _s11_ecrire vecteur "jeton-compte-service ($sa)"
  _s11_ecrire c2 "$_S11_C2_VMID"
}

# Variante 2 : politique réseau trop large (vieille MR) qui laisse sortir vers le C2.
panne_S11_v2() {
  _s11_sain || return 1
  local pod c
  pod="$(_s11_pod)"; [[ -n "$pod" ]] || { _s11_refus "aucun pod d'API prêt"; return 1; }
  c="$(wb_kubectl -n "$_S11_NS" get pod "$pod" -o jsonpath='{.spec.containers[0].name}' 2>/dev/null || true)"
  [[ -n "$c" ]] || return 1
  _s11_creer_c2 || { _s11_detruire_c2; return 1; }
  # NetworkPolicy trop large (étiquetée comme une vieille MR) : sortie autorisée vers 10.10.99.0/24.
  wb_kubectl apply -f - >/dev/null 2>&1 <<EOF || { _s11_detruire_c2; return 1; }
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: legacy-sortie-large
  namespace: $_S11_NS
  labels:
    wb-f6-s11: "injection"
  annotations:
    medisphere.internal/origine: "MR !218 (2026-03) — sortie temporaire, jamais retirée"
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
    - to:
        - ipBlock:
            cidr: 10.10.99.0/24
EOF
  _s11_shell "$pod" "$c" || { wb_kubectl -n "$_S11_NS" delete networkpolicy legacy-sortie-large >/dev/null 2>&1 || true; _s11_detruire_c2; return 1; }
  _s11_ecrire espace "$_S11_NS"
  _s11_ecrire pod "$pod"
  _s11_ecrire conteneur "$c"
  _s11_ecrire cible "$_S11_C2_IP:$_S11_C2_PORT"
  _s11_ecrire vecteur "politique-reseau-trop-large (legacy-sortie-large)"
  _s11_ecrire c2 "$_S11_C2_VMID"
}

# ---------------------------------------------------------------------------
# Vérification sur place (la panne est effective) et annulation
# ---------------------------------------------------------------------------
_s11_boucle_active() {
  local ns pod c
  ns="$(_s11_lire espace)"; pod="$(_s11_lire pod)"; c="$(_s11_lire conteneur)"
  [[ -n "$pod" ]] || return 1
  wb_kubectl -n "$ns" exec "$pod" -c "$c" -- python3 -c \
    "import os,sys
moi=str(os.getpid())
def lire(p):
    try: return open('/proc/%s/cmdline'%p,'rb').read()
    except OSError: return b''
sys.exit(0 if any(b'sonde-maj' in lire(p) or b'$_S11_MARQUE' in lire(p) for p in os.listdir('/proc') if p.isdigit() and p!=moi) else 1)" \
    >/dev/null 2>&1
}

_s11_c2_actif() { remote "$WB_PVE_HOST" "qm status $_S11_C2_VMID" 2>/dev/null | grep -q running; }

verifier_S11() {
  local i
  for ((i = 0; i < 6; i++)); do
    if _s11_boucle_active && _s11_c2_actif; then return 0; fi
    sleep 5
  done
  _s11_boucle_active && _s11_c2_actif
}

annuler_S11() {
  local ns pod c
  ns="$(_s11_lire espace)"; pod="$(_s11_lire pod)"; c="$(_s11_lire conteneur)"
  # Arrêt de la boucle dans le pod (si le pod existe encore), sans le supprimer.
  if [[ -n "$pod" ]] && wb_kubectl -n "$ns" get pod "$pod" >/dev/null 2>&1; then
    wb_kubectl -n "$ns" exec "$pod" -c "$c" -- sh -c ': > /tmp/.arret-maj 2>/dev/null; rm -f /tmp/.sonde-maj.py' >/dev/null 2>&1 || true
    wb_kubectl -n "$ns" exec "$pod" -c "$c" -- python3 -c \
      "import os,signal
for p in [x for x in os.listdir('/proc') if x.isdigit()]:
    try: l=open('/proc/%s/cmdline'%p,'rb').read()
    except OSError: continue
    if (b'sonde-maj' in l or b'$_S11_MARQUE' in l) and int(p)!=os.getpid():
        os.kill(int(p), signal.SIGTERM)" >/dev/null 2>&1 || true
    local proprio quarantaine
    proprio="$(wb_kubectl -n "$ns" get pod "$pod" -o jsonpath='{.metadata.ownerReferences[0].kind}' 2>/dev/null || true)"
    quarantaine="$(wb_kubectl -n "$ns" get pod "$pod" -o jsonpath='{.metadata.labels.medisphere\.internal/quarantaine}' 2>/dev/null || true)"
    if [[ -z "$proprio" && "$quarantaine" == oui ]]; then
      wb_avert "pod suspect $ns/$pod laissé en quarantaine : supprime-le toi-même APRÈS le dépôt des preuves (RB-361)"
    fi
  fi
  # Retrait de la politique réseau trop large (variante 2 seulement).
  wb_kubectl -n "$ns" delete networkpolicy legacy-sortie-large >/dev/null 2>&1 || true
  # Destruction du C2.
  _s11_detruire_c2
  _s11_oublier espace; _s11_oublier pod; _s11_oublier conteneur
  _s11_oublier cible; _s11_oublier vecteur; _s11_oublier c2
}

symptome_S11() {
  wb_symptome "INC-6211 — Alerte Falco : activité anormale dans $_S11_NS" \
    "Courriels d'Alertmanager (source falco) pour l'espace $_S11_NS :" \
    "shell interactif dans un conteneur de l'API, lecture du jeton de compte de service," \
    "puis connexions sortantes répétées vers $(_s11_lire cible), chaque minute." \
    "Personne n'a annoncé d'intervention." \
    "" \
    "Qualifie (vrai/faux positif), confine SANS détruire les preuves, préviens la RSSI et le DPO." \
    "⚠️ Ne supprime pas le pod avant la collecte (F6-S12)." \
    "Temps cible : 60 min."
}

resume_S11() { echo "Alerte Falco : shell, lecture du jeton et connexions sortantes depuis un conteneur de mediagenda-recette"; }

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main F6 S11 2 "$@"; }
fi
