# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # scripts de conteneur et filtres jq entre apostrophes
# break-S12.sh — F3-S12 « Vendredi : alerte Falco en production » (INC-5912)
#
# ⚠️ La « compromission » est STRICTEMENT INOFFENSIVE (règles du bloc F, M26-E42) : aucun binaire,
# aucun code malveillant, aucune donnée lue ni envoyée. Ce que fait l'injection, et rien d'autre :
#   - un shell INTERACTIF (avec terminal : « script » fournit le pseudo-terminal) est ouvert dans un
#     conteneur applicatif par « kubectl exec -it » (ou « kubectl debug -it » pour une image sans
#     shell) avec le kubeconfig d'administration du lab : règle Falco « MédiSphère — shell interactif
#     dans un conteneur applicatif » ;
#   - ce shell laisse derrière lui une boucle qui TENTE, toutes les 60 s et pendant 6 h au plus, une
#     connexion TCP vers une destination interdite par la matrice des flux (le refus réseau par défaut
#     de l'espace la jette : rien ne sort) : règle « connexion sortante vers un port non prévu ». Elle
#     n'envoie aucun octet. Elle s'arrête seule au bout de 6 h, ou à l'annulation ;
#   - un fichier texte (le script de la boucle) dans le /tmp du conteneur.
# Variantes :
#   1. mediagenda-recette, API (python) : boucle Python vers 203.0.113.50:4444 (RFC 5737) ;
#   2. medidoc-dev, MédiDoc (image distroless, sans shell) : conteneur ÉPHÉMÈRE busybox « diag » ciblant
#      le conteneur de MédiDoc (kubectl debug, profil restricted), boucle « nc » vers 198.51.100.23:6667 ;
#   3. mediagenda-recette, API : boucle vers des services INTERNES hors matrice — le coffre
#      (10.10.20.200:8200) et l'API de Kubernetes (10.10.40.200:8443) — : reconnaissance latérale.
# Le pod visé n'est JAMAIS supprimé, ni par l'injection ni par l'annulation tant qu'il n'est pas en
# quarantaine : c'est la preuve. Rien ne touche Falco, falcosidekick, Loki ni le compartiment preuves.
# État local (lisible par le check) : ~/.local/state/workbook/F3-S12/{espace,pod,conteneur,cibles}.
# Annulation : arrêt de la boucle (fichier d'arrêt ou signal au seul processus marqué), retrait du
# fichier de /tmp ; un pod suspect sorti de son contrôleur ET en quarantaine est supprimé (fin de
# l'incident, après ta collecte) ; sinon il est laissé tel quel.

# shellcheck source=../../../../lab/lib/pannes-lib.sh disable=SC1091
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_f3-fin-pannes.sh
source "$WB_ROOT/finaux/F3-astreinte/corrige/pannes/_f3-fin-pannes.sh"

_S12_IMAGE_DEBUG="${WB_F3_S12_IMAGE_DEBUG:-registry.par1.medisphere.internal/dockerhub/library/busybox:1.37}"
_S12_SEL_AGENDA='app.kubernetes.io/name=mediagenda,app.kubernetes.io/component=api'
_S12_SEL_DOC="${WB_F3_S12_SELECTEUR_MEDIDOC:-app.kubernetes.io/name=medidoc}"
_S12_MARQUE=wb-f3-s12
_S12_KCFG="${WB_K8S_ADMIN_KUBECONFIG:-$HOME/.kube/config}"

# Boucle Python (variantes 1 et 3) : CIBLES remplacé à l'injection. Aucun octet envoyé.
read -r -d '' _S12_PY <<'PY' || true
# wb-f3-s12
import os, socket, time
CIBLES = __CIBLES__
if os.fork():
    os._exit(0)
os.setsid()
fin = time.time() + 6 * 3600
while time.time() < fin and not os.path.exists("/tmp/.arret-maj"):
    for hote, port in CIBLES:
        s = socket.socket()
        s.settimeout(3)
        try:
            s.connect((hote, port))
        except OSError:
            pass
        finally:
            s.close()
    time.sleep(60)
PY

_s12_sain() {
  local ds
  f3fp_preparer S12 script timeout base64 || return 1
  ds="$(wb_kubectl -n falco get daemonsets -o json 2>/dev/null || true)"
  jq -e '(.items | length) > 0 and all(.items[]; (.status.numberReady // 0) == (.status.desiredNumberScheduled // -1) and .status.desiredNumberScheduled > 0)' \
    >/dev/null 2>&1 <<<"$ds" || { f3fp_refus "Falco n'est pas prêt sur tous les nœuds (espace falco)"; return 1; }
  wb_kubectl get ciliumclusterwidenetworkpolicies.cilium.io quarantaine >/dev/null 2>&1 ||
    { f3fp_refus "politique de quarantaine absente (M26-E33)"; return 1; }
}

# _s12_retenir ESPACE POD CONTENEUR CIBLES
_s12_retenir() {
  f3fp_ecrire S12 espace "$1"
  f3fp_ecrire S12 pod "$2"
  f3fp_ecrire S12 conteneur "$3"
  f3fp_ecrire S12 cibles "$4"
}

# _s12_python ESPACE SÉLECTEUR 'CIBLES_PYTHON' 'cibles lisibles'
_s12_python() {
  local ns="$1" sel="$2" cibles="$3" lisible="$4" pod c code
  pod="$(f3fp_pod "$ns" "$sel")"
  [[ -n "$pod" ]] || { f3fp_refus "aucun pod prêt ($sel) dans $ns"; return 1; }
  c="$(wb_kubectl -n "$ns" get pod "$pod" -o jsonpath='{.spec.containers[0].name}' 2>/dev/null || true)"
  [[ -n "$c" ]] || return 1
  _s12_retenir "$ns" "$pod" "$c" "$lisible"
  code="${_S12_PY/__CIBLES__/$cibles}"
  # Le code arrive en base64 dans la ligne de commande du shell : le fichier de /tmp est ce que la
  # collecte retrouvera. Repli sans fichier si /tmp n'est pas inscriptible.
  timeout 60 script -qec "kubectl --kubeconfig $(printf '%q' "$_S12_KCFG") -n $ns exec -it $pod -c $c -- sh -c \
'echo $(printf '%s' "$code" | base64 -w0) | base64 -d > /tmp/.cache-maj.py 2>/dev/null && python3 /tmp/.cache-maj.py \
|| python3 -c \"\$(echo $(printf '%s' "$code" | base64 -w0) | base64 -d)\" cache-maj; exit 0'" /dev/null >/dev/null 2>&1 || return 1
  f3fp_journal S12 "shell interactif ouvert dans $ns/$pod ($c), boucle vers $lisible"
}

panne_S12_v1() {
  _s12_sain || return 1
  _s12_python mediagenda-recette "$_S12_SEL_AGENDA" '[("203.0.113.50", 4444)]' "203.0.113.50:4444"
}

panne_S12_v2() {
  local ns=medidoc-dev pod c perso
  _s12_sain || return 1
  pod="$(f3fp_pod "$ns" "$_S12_SEL_DOC")"
  [[ -n "$pod" ]] || { f3fp_refus "aucun pod MédiDoc prêt dans $ns"; return 1; }
  c="$(wb_kubectl -n "$ns" get pod "$pod" -o jsonpath='{.spec.containers[0].name}' 2>/dev/null || true)"
  [[ -n "$c" ]] || return 1
  _s12_retenir "$ns" "$pod" diag "198.51.100.23:6667"
  perso="$(f3fp_etat S12)/debug.json"
  # PSA restricted : utilisateur non root explicite (busybox tourne en root par défaut).
  jq -n '{securityContext: {runAsUser: 65532, runAsGroup: 65532, runAsNonRoot: true,
          allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}, seccompProfile: {type: "RuntimeDefault"}}}' >"$perso"
  # Le conteneur éphémère vit tant que sa boucle tourne ; « timeout » ne coupe que l'attachement.
  timeout 30 script -qec "kubectl --kubeconfig $(printf '%q' "$_S12_KCFG") -n $ns debug -it $pod --image=$_S12_IMAGE_DEBUG \
--target=$c --container=diag --profile=restricted --custom=$perso -- sh -c \
'i=0; while [ \$i -lt 360 ] && [ ! -e /tmp/.arret-maj ]; do nc -w 3 198.51.100.23 6667 </dev/null >/dev/null 2>&1; i=\$((i+1)); sleep 60; done'" \
    /dev/null >/dev/null 2>&1 || true
  f3fp_journal S12 "conteneur éphémère diag (busybox) dans $ns/$pod, boucle vers 198.51.100.23:6667"
}

panne_S12_v3() {
  _s12_sain || return 1
  _s12_python mediagenda-recette "$_S12_SEL_AGENDA" '[("10.10.20.200", 8200), ("10.10.40.200", 8443)]' \
    "10.10.20.200:8200, 10.10.40.200:8443"
}

# _s12_boucle_active — la boucle tourne dans le pod visé (lecture de /proc par un exec non interactif).
_s12_boucle_active() {
  local ns pod c
  ns="$(f3fp_lire S12 espace)"; pod="$(f3fp_lire S12 pod)"; c="$(f3fp_lire S12 conteneur)"
  [[ -n "$pod" ]] || return 1
  if [[ "$c" == diag ]]; then
    wb_kubectl -n "$ns" get pod "$pod" -o json 2>/dev/null |
      jq -e '[.status.ephemeralContainerStatuses[]? | select(.name == "diag" and .state.running != null)] | length == 1' >/dev/null 2>&1
  else
    wb_kubectl -n "$ns" exec "$pod" -c "$c" -- python3 -c \
      "import os,sys
def lire(p):
    try:
        return open('/proc/%s/cmdline' % p, 'rb').read()
    except OSError:
        return b''
moi = str(os.getpid())
sys.exit(0 if any(b'cache-maj' in lire(p) or b'$_S12_MARQUE' in lire(p) for p in os.listdir('/proc') if p.isdigit() and p != moi) else 1)" \
      >/dev/null 2>&1
  fi
}

verifier_S12() { f3fp_attendre 30 _s12_boucle_active; }

annuler_S12() {
  local ns pod c proprio quarantaine
  ns="$(f3fp_lire S12 espace)"; pod="$(f3fp_lire S12 pod)"; c="$(f3fp_lire S12 conteneur)"
  if [[ -n "$pod" ]] && wb_kubectl -n "$ns" get pod "$pod" >/dev/null 2>&1; then
    if [[ "$c" == diag ]]; then
      wb_kubectl -n "$ns" exec "$pod" -c diag -- touch /tmp/.arret-maj >/dev/null 2>&1 || true
    else
      wb_kubectl -n "$ns" exec "$pod" -c "$c" -- sh -c ': > /tmp/.arret-maj 2>/dev/null; rm -f /tmp/.cache-maj.py' >/dev/null 2>&1 || true
      # Signal au seul processus de la boucle (marqué), si le fichier d'arrêt n'a pas pu être posé.
      wb_kubectl -n "$ns" exec "$pod" -c "$c" -- python3 -c \
        "import os,signal
for p in [x for x in os.listdir('/proc') if x.isdigit()]:
    try:
        l = open('/proc/%s/cmdline' % p, 'rb').read()
    except OSError:
        continue
    if (b'cache-maj' in l or b'$_S12_MARQUE' in l) and int(p) != os.getpid():
        os.kill(int(p), signal.SIGTERM)" >/dev/null 2>&1 || true
    fi
    # Pod suspect sorti de son contrôleur ET en quarantaine : fin d'incident, il est supprimé (après ta
    # collecte : c'est toi qui lances --annuler). Sinon il est laissé tel quel.
    proprio="$(wb_kubectl -n "$ns" get pod "$pod" -o jsonpath='{.metadata.ownerReferences[0].kind}' 2>/dev/null || true)"
    quarantaine="$(wb_kubectl -n "$ns" get pod "$pod" -o jsonpath='{.metadata.labels.medisphere\.internal/quarantaine}' 2>/dev/null || true)"
    if [[ -z "$proprio" && "$quarantaine" == oui ]]; then
      wb_kubectl -n "$ns" delete pod "$pod" --wait=false >/dev/null 2>&1 || wb_avert "pod $ns/$pod non supprimé"
      f3fp_journal S12 "annulation : pod suspect $ns/$pod (orphelin, en quarantaine) supprimé"
    elif [[ "$c" == diag ]]; then
      wb_avert "le conteneur éphémère « diag » reste décrit dans $ns/$pod (arrêté) jusqu'au remplacement du pod"
    fi
  fi
  f3fp_oublier S12 espace
  f3fp_oublier S12 pod
  f3fp_oublier S12 conteneur
  f3fp_oublier S12 cibles
  rm -f -- "$(f3fp_etat S12)/debug.json"
  f3fp_journal S12 "annulation"
}

symptome_S12() {
  _f3p_symptome S12 INC-5912 "INC-5912 — Vendredi 7 h 52 — Alerte reçue sur astreinte@ (Falco)" \
    "Courriels d'Alertmanager « AlerteFalco » : shell interactif dans un conteneur applicatif, puis" \
    "connexions sortantes vers un port non prévu, répétées chaque minute, depuis l'espace $(f3fp_lire S12 espace)." \
    "Personne n'a annoncé d'intervention. Qualifie, confine, préserve les preuves, préviens Sophie." \
    "" \
    "⚠️ Ne supprime pas le pod avant la collecte." \
    "Temps cible : 60 min."
}

resume_S12() { echo "Alerte Falco : shell interactif et connexions sortantes interdites depuis un conteneur applicatif"; }

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main F3 S12 3 "$@"; }
fi
