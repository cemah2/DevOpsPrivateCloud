# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et scripts distants entre apostrophes
# break-E41.sh — M26-E41 « Panne : kubectl logs et exec refusés »
#
# Depuis la sécurisation des kubelets (serverTLSBootstrap, kubelet-csr-approver), « kubectl logs/exec »
# échoue en x509 ou en timeout. Variantes (jamais plus d'un nœud de contrôle, annulation sûre) :
#   1. la regex de l'approbateur (kubelet-csr-approver) ne correspond plus à un travailleur ET sa demande
#      de certificat de service (CSR) est effacée : la nouvelle CSR reste « Pending », l'apiserver ne
#      peut plus vérifier ce kubelet (x509 sur les pods de ce nœud) ;
#   2. l'horloge d'un travailleur est décalée (chrony arrêté + date avancée) : la poignée de main TLS du
#      kubelet échoue, le nœud finit NotReady ;
#   3. la CA de vérification des kubelets est fausse sur UN nœud de contrôle (--kubelet-certificate-
#      authority dans son manifeste statique) : ~1 requête logs/exec sur 3 échoue (celle servie par ce
#      nœud).
#
# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m26-commun.sh
source "$WB_ROOT/modules/26-durcissement/corrige/pannes/_m26-commun.sh"

_E41_NOEUD="${WB_M26_NOEUD:-k8s-w03}"
_E41_CP="${WB_M26_CP:-k8s-cp03}"
_E41_VALEURS=kubelet-csr-approver/values.yaml

# v1 : la regex de l'approbateur exclut le nœud (plateforme/politiques).
_e41_t1() {
  yq '(.kubelet-csr-approver.providerRegex) = "^k8s-(cp|w)0[1-2]$"
      | (.kubelet-csr-approver.providerRegex) line_comment = "PLAT-2741 (Lucas) : restreindre l approbation"'
}
_e41_i1() { yq '(.kubelet-csr-approver.providerRegex) = "^k8s-(cp|w)0[1-9]$"'; }

panne_E41_v1() { _e41_injecter 1; }
panne_E41_v2() { _e41_injecter 2; }
panne_E41_v3() { _e41_injecter 3; }

_e41_injecter() {
  local n="$1"
  m26_kube_sain || return 1
  m26_ecrire E41 variante "$n"
  case "$n" in
    1)
      wb_kubectl get node "$_E41_NOEUD" >/dev/null 2>&1 || { wb_avert "nœud $_E41_NOEUD introuvable"; return 1; }
      m26_git_transformer E41 reg "$_M26_PROJ_POL" "$_E41_VALEURS" \
        "chore(kubelet-csr-approver): restreindre la regex (M26-E41)" _e41_t1 || return
      # Force le kubelet à redemander un certificat de service : retire le certificat et redémarre.
      m26_hote_sain "$_E41_NOEUD" || return 10
      m26_ecrire E41 cible "$_E41_NOEUD"
      m26_wb_exec "$_E41_NOEUD" >/dev/null <<'EOF' || return 1
d=/var/lib/kubelet/pki
for f in "$d"/kubelet-server-current.pem; do
  [ -e "$f" ] && { sauver "$f"; rm -f "$f"; }
done
u="$(unite_de kubelet)" || u=kubelet.service
systemctl restart "$u" 2>/dev/null || true
journal "certificat de service du kubelet retiré et kubelet redémarré (nouvelle CSR)"
EOF
      m26_attendre 180 _e41_effet 1 || { _e41_defaire 1; return 10; }
      ;;
    2)
      m26_hote_sain "$_E41_NOEUD" || return 10
      m26_ecrire E41 cible "$_E41_NOEUD"
      m26_wb_exec "$_E41_NOEUD" >/dev/null <<'EOF' || return 1
u="$(unite_de chrony 2>/dev/null)" || u=chrony.service
systemctl stop "$u" 2>/dev/null || true
date -s '+2 hours' >/dev/null
journal "chrony arrêté et horloge avancée de 2 h (décalage TLS)"
EOF
      ;;
    3)
      m26_hote_sain "$_E41_CP" || return 10
      m26_ecrire E41 cp "$_E41_CP"
      m26_wb_exec "$_E41_CP" >/dev/null <<'EOF' || return 1
m=/etc/kubernetes/manifests/kube-apiserver.yaml
[ -f "$m" ] || { echo "manifeste kube-apiserver absent" >&2; exit 10; }
sauver "$m"
# Pointe la CA de vérification des kubelets vers un fichier existant mais faux (la CA du front-proxy).
faux=/etc/kubernetes/pki/front-proxy-ca.crt
if grep -q -- '--kubelet-certificate-authority=' "$m"; then
  sed -i "s#--kubelet-certificate-authority=[^[:space:]\"]*#--kubelet-certificate-authority=$faux#" "$m"
else
  sed -i "s#\(- kube-apiserver\)#\1\n    - --kubelet-certificate-authority=$faux#" "$m"
fi
journal "kube-apiserver : --kubelet-certificate-authority pointé vers $faux (pod statique redémarré)"
EOF
      ;;
  esac
  m26_journal E41 "variante $n posée"
}

_e41_effet() {
  case "$1" in
    1) wb_kubectl get csr -o json 2>/dev/null | jq -e --arg h "$_E41_NOEUD" '[.items[] | select(.spec.signerName == "kubernetes.io/kubelet-serving") | select(.status.conditions == null or ([.status.conditions[].type] | index("Approved") | not)) | select(.spec.username | test($h))] | length > 0' >/dev/null 2>&1 ;;
    2) ! m26_ssh "$_E41_NOEUD" 'systemctl is-active chrony chronyd 2>/dev/null | grep -q "^active"' >/dev/null 2>&1 ;;
    3) m26_ssh "$_E41_CP" 'grep -q "kubelet-certificate-authority=/etc/kubernetes/pki/front-proxy-ca.crt" /etc/kubernetes/manifests/kube-apiserver.yaml' >/dev/null 2>&1 ;;
  esac
}

verifier_E41() { _e41_effet "$WB_VAR"; }

_e41_defaire() {
  case "$1" in
    1)
      m26_git_defaire E41 reg _e41_i1 "revert(kubelet-csr-approver): regex rétablie (M26-E41, annulation)"
      local c; c="$(m26_lire E41 cible)"
      if [[ -n "$c" ]]; then
        # Approuve une éventuelle CSR encore en attente puis restaure.
        wb_kubectl get csr -o json 2>/dev/null | jq -r --arg h "$c" '.items[] | select(.spec.signerName == "kubernetes.io/kubelet-serving") | select(.spec.username | test($h)) | select(.status.conditions == null) | .metadata.name' |
          while read -r csr; do [[ -n "$csr" ]] && wb_kubectl certificate approve "$csr" >/dev/null 2>&1 || true; done
        WB_EX=M26-E41 m26_wb_exec_invite "$c" >/dev/null <<'EOF' || wb_avert "restauration kubelet incomplète"
restaurer_fichiers
u="$(unite_de kubelet 2>/dev/null)" || u=kubelet.service
systemctl restart "$u" 2>/dev/null || true
journal "annulation : certificat de service restauré, kubelet redémarré (agent QEMU)"
EOF
      fi
      ;;
    2)
      local c; c="$(m26_lire E41 cible)"
      if [[ -n "$c" ]]; then
        WB_EX=M26-E41 m26_wb_exec_invite "$c" >/dev/null <<'EOF' || wb_avert "annulation horloge incomplète"
u="$(unite_de chrony 2>/dev/null)" || u=chrony.service
systemctl start "$u" 2>/dev/null || true
chronyc -a makestep 2>/dev/null || chronyc makestep 2>/dev/null || true
journal "annulation : chrony redémarré, horloge resynchronisée (agent QEMU)"
EOF
      fi
      ;;
    3)
      local c; c="$(m26_lire E41 cp)"
      if [[ -n "$c" ]]; then
        WB_EX=M26-E41 m26_wb_exec_invite "$c" >/dev/null <<'EOF' || wb_avert "restauration kube-apiserver incomplète"
restaurer_fichiers
journal "annulation : manifeste kube-apiserver restauré (pod statique redémarré, agent QEMU)"
EOF
      fi
      ;;
  esac
}

annuler_E41() {
  local v="${WB_VAR:-}"
  [[ "$v" =~ ^[1-3]$ ]] || v="$(m26_lire E41 variante)"
  [[ -n "$v" ]] && _e41_defaire "$v"
  m26_oublier E41 variante
  m26_oublier E41 cible
  m26_oublier E41 cp
  m26_journal E41 "annulation"
}

resume_E41() { echo "« kubectl logs » et « kubectl exec » échouent (x509 ou timeout) sur une partie des pods."; }

symptome_E41() {
  wb_symptome "Ticket INC-5341 — De : Julien Petit" \
    "Je n'arrive plus à voir les journaux d'un pod : « kubectl logs » renvoie une erreur TLS (x509)" \
    "ou reste bloqué ; « kubectl exec » aussi. Parfois ça marche, parfois non. C'est arrivé après la" \
    "sécurisation des kubelets (certificats de service, approbation des CSR)." \
    "Un seul nœud de contrôle à la fois si tu touches au plan de contrôle ; garde admin.conf de côté." \
    "" \
    "Temps cible : 40 min. Contrôle : lab/bin/check 26 41"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 26 E41 3 "$@"; }
fi
