# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et scripts distants entre apostrophes
# break-E41.sh — M26-E41 « Panne : kubectl logs et exec refusés »
#
# Depuis la sécurisation des kubelets (serverTLSBootstrap, kubelet-csr-approver), « kubectl logs/exec »
# échoue en x509 ou en timeout. Variantes (jamais plus d'un nœud de contrôle, annulation sûre) :
#   1. la regex de l'approbateur (kubelet-csr-approver, valeurs dans plateforme/gitops) ne correspond plus
#      à un travailleur ET son certificat de service est retiré : la nouvelle CSR est REFUSÉE (Denied) par
#      l'approbateur, le kubelet n'a plus de certificat de service et ne termine plus la poignée de main
#      TLS (« remote error: tls: internal error » sur les pods de ce nœud) ;
#   2. l'approbateur est mis à 0 réplica (« en pause », plateforme/gitops) ET le certificat de service d'un
#      travailleur est retiré : la nouvelle CSR reste « Pending », même symptôme sur ce nœud.
#      (L'ancienne variante « horloge avancée de 2 h » n'avait AUCUN effet sur logs/exec : le serveur
#      d'API ne vérifie pas les kubelets dans ce lab et 2 h ne périment aucun certificat ; un décalage
#      assez grand pour périmer un certificat rendrait le nœud NotReady et ferait évincer ses pods, et le
#      retour de l'horloge en arrière ferait refuser par les pairs les poignées de main WireGuard du nœud.)
#   3. une CA de vérification des kubelets FAUSSE est posée sur UN nœud de contrôle
#      (--kubelet-certificate-authority dans son manifeste statique ; kubeadm ne pose pas cette option) :
#      ~1 requête logs/exec sur 3 échoue en x509 (celles servies par ce serveur d'API).
#
# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m26-commun.sh
source "$WB_ROOT/modules/26-durcissement/corrige/pannes/_m26-commun.sh"

_E41_NOEUD="${WB_M26_NOEUD:-k8s-w03}"
_E41_CP="${WB_M26_CP:-k8s-cp03}"
# Valeurs de l'Application Argo CD kubelet-csr-approver (M26-E25) : plateforme/gitops.
_E41_VALEURS=valeurs/kubelet-csr-approver/values.yaml

# v1 : la regex de l'approbateur exclut le nœud. Inverses : seulement si la marque est encore là.
_e41_t1() {
  yq '.providerRegex = "^k8s-(cp|w)0[1-2]$"
      | .providerRegex line_comment = "PLAT-2741 (Lucas) : restreindre l approbation"'
}
_e41_i1() {
  yq 'with(select((.providerRegex | line_comment) | test("PLAT-2741"));
         .providerRegex = "^k8s-(cp|w)0[1-9]$" | .providerRegex line_comment = "")'
}
# v2 : l'approbateur « mis en pause » (0 réplica).
_e41_t2() {
  yq '.replicas = 0 | .replicas line_comment = "PLAT-2741 (Lucas) : approbateur en pause pendant l essai"'
}
_e41_i2() {
  yq 'with(select((.replicas | line_comment) | test("PLAT-2741")); .replicas = 2 | .replicas line_comment = "")'
}

# Retire le certificat de service du kubelet du nœud (sauvegardé) et redémarre le kubelet : il
# redemande un certificat (nouvelle CSR kubelet-serving).
_e41_retirer_certificat() {
  m26_wb_exec "$_E41_NOEUD" >/dev/null <<'EOF'
d=/var/lib/kubelet/pki
for f in "$d"/kubelet-server-current.pem; do
  [ -e "$f" ] && { sauver "$f"; rm -f "$f"; }
done
u="$(unite_de kubelet)" || u=kubelet.service
systemctl restart "$u" 2>/dev/null || true
journal "certificat de service du kubelet retiré et kubelet redémarré (nouvelle CSR)"
EOF
}

panne_E41_v1() { _e41_injecter 1; }
panne_E41_v2() { _e41_injecter 2; }
panne_E41_v3() { _e41_injecter 3; }

_e41_injecter() {
  local n="$1"
  m26_kube_sain || return 1
  m26_ecrire E41 variante "$n"
  case "$n" in
    1|2)
      wb_kubectl get node "$_E41_NOEUD" >/dev/null 2>&1 || { wb_avert "nœud $_E41_NOEUD introuvable"; return 1; }
      m26_hote_sain "$_E41_NOEUD" || return 10
      if ((n == 1)); then
        m26_git_transformer E41 reg "$_M26_PROJ_GITOPS" "$_E41_VALEURS" \
          "chore(kubelet-csr-approver): restreindre la regex (M26-E41)" _e41_t1 || return
      else
        m26_git_transformer E41 rep "$_M26_PROJ_GITOPS" "$_E41_VALEURS" \
          "chore(kubelet-csr-approver): mettre l'approbateur en pause (M26-E41)" _e41_t2 || return
        m26_attendre 180 _e41_approbateur_arrete || { _e41_defaire 2; return 10; }
      fi
      # Force le kubelet à redemander un certificat de service : retire le certificat et redémarre.
      m26_ecrire E41 cible "$_E41_NOEUD"
      _e41_retirer_certificat || return 1
      m26_attendre 180 _e41_effet "$n" || { _e41_defaire "$n"; return 10; }
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

_e41_approbateur_arrete() {
  wb_kubectl get deploy -A -l app.kubernetes.io/name=kubelet-csr-approver -o name 2>/dev/null | grep -q . \
    && [[ "$(wb_kubectl get pods -A -l app.kubernetes.io/name=kubelet-csr-approver --no-headers 2>/dev/null | grep -c Running)" == 0 ]]
}
# Le kubelet du nœud ne présente plus de certificat de service : la poignée de main TLS vers 10250
# échoue (essai fait depuis le nœud lui-même, indépendant du pare-feu d'hôte).
_e41_sans_certificat() {
  m26_ssh "$_E41_NOEUD" '! timeout 5 openssl s_client -connect 127.0.0.1:10250 </dev/null >/dev/null 2>&1' >/dev/null 2>&1
}
# Effet constaté : une CSR kubelet-serving du nœud sans approbation ET plus de certificat servi.
_e41_effet() {
  case "$1" in
    1|2) wb_kubectl get csr -o json 2>/dev/null | jq -e --arg h "system:node:$_E41_NOEUD" '[.items[] | select(.spec.signerName == "kubernetes.io/kubelet-serving") | select(.spec.username == $h) | select((.status.conditions // []) | any(.type == "Approved") | not)] | length > 0' >/dev/null 2>&1 \
           && _e41_sans_certificat ;;
    3) m26_ssh "$_E41_CP" 'grep -q "kubelet-certificate-authority=/etc/kubernetes/pki/front-proxy-ca.crt" /etc/kubernetes/manifests/kube-apiserver.yaml' >/dev/null 2>&1 ;;
  esac
}

verifier_E41() { _e41_effet "$WB_VAR"; }

_e41_defaire() {
  case "$1" in
    1|2)
      if [[ "$1" == 1 ]]; then
        m26_git_defaire E41 reg _e41_i1 "revert(kubelet-csr-approver): regex rétablie (M26-E41, annulation)"
      else
        m26_git_defaire E41 rep _e41_i2 "revert(kubelet-csr-approver): approbateur relancé (M26-E41, annulation)"
      fi
      local c; c="$(m26_lire E41 cible)"
      if [[ -n "$c" ]]; then
        # Remet le certificat de service sauvegardé (repris par le kubelet au redémarrage) ; si
        # l'apprenant a déjà réparé (nouveau certificat approuvé), le fichier restauré n'est qu'un lien
        # vers un certificat encore valide. Aucune CSR n'est approuvée à l'aveugle.
        WB_EX=M26-E41 m26_wb_exec_invite "$c" >/dev/null <<'EOF' || wb_avert "restauration kubelet incomplète"
restaurer_fichiers
u="$(unite_de kubelet 2>/dev/null)" || u=kubelet.service
systemctl restart "$u" 2>/dev/null || true
journal "annulation : certificat de service restauré, kubelet redémarré (agent QEMU)"
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

resume_E41() { echo "« kubectl logs » et « kubectl exec » échouent (erreur TLS) sur une partie des pods."; }

symptome_E41() {
  wb_symptome "Ticket INC-5341 — De : Julien Petit" \
    "Je n'arrive plus à voir les journaux d'un pod : « kubectl logs » renvoie une erreur TLS (tls, x509)" \
    "ou reste bloqué ; « kubectl exec » aussi. Parfois ça marche, parfois non. C'est arrivé après la" \
    "sécurisation des kubelets (certificats de service, approbation des CSR)." \
    "Un seul nœud de contrôle à la fois si tu touches au plan de contrôle ; garde admin.conf de côté." \
    "" \
    "Temps cible : 40 min. Contrôle : lab/bin/check 26 41"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 26 E41 3 "$@"; }
fi
