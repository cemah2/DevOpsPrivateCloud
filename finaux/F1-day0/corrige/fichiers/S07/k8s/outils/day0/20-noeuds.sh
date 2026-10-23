#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# plateforme/k8s — outils/day0/20-noeuds.sh (F1-S07, CHG-3107)
# Destruction et reconstruction des six nœuds de k8s-par1, depuis le code. Après 10-gel.sh.
#
#   1. point de non-retour (confirmation) ;
#   2. OpenTofu (plateforme/infra, envs/k8s) : REMPLACEMENT ciblé des seules ressources VM des six
#      nœuds (-replace) : NetBox, DNS, adresses ne bougent pas ; k8s-w03 suit le chemin de F1-S06
#      (VM vide en démarrage réseau sur le VLAN 60, installée par pxe01, puis repassée sur le VLAN 40) ;
#   3. clés d'hôte SSH : les anciennes empreintes sont retirées de ~/.ssh/known_hosts (geste noté) ;
#   4. Ansible (plateforme/ansible) : inscription FreeIPA nœud par nœud, puis
#      playbooks/k8s-reconstruction.yml (durcissement, fichiers de l'API, amorçage explicite, etcd) ;
#   5. admin.conf du NOUVEAU cluster récupéré (600) pour la suite de la reconstruction ;
#   6. compte wb-checks et son kubeconfig recréés (pour lab/bin/check).
#
# Variables : DAY0_W03_SANS_USINE=oui pour recréer k8s-w03 comme les autres (repli, noté comme écart) ;
# DAY0_ADMIN_CONF (~/.kube/admin-k8s-par1.conf).

# shellcheck source=commun.sh
source "$(dirname "${BASH_SOURCE[0]}")/commun.sh"

PHASE=noeuds
INFRA="$DAY0_SRC/infra/envs/k8s"
ANSIBLE="$DAY0_SRC/ansible"
K8S="$DAY0_SRC/k8s"
NOEUDS=(k8s-cp01 k8s-cp02 k8s-cp03 k8s-w01 k8s-w02 k8s-w03)
ADRESSES=(10.10.40.51 10.10.40.52 10.10.40.53 10.10.40.61 10.10.40.62 10.10.40.63)
ADMIN_CONF="${DAY0_ADMIN_CONF:-$HOME/.kube/admin-k8s-par1.conf}"

outils_requis tofu uv ssh ssh-keygen kubectl jq

# Variables d'environnement des fournisseurs (Proxmox, NetBox, PowerDNS, état S3) : celles du M05/M14.
charger_env_tofu() {
  local f
  set -a
  for f in pve-tofu.env netbox-tofu.env powerdns-api.env s3-tofu.env; do
    # shellcheck disable=SC1090,SC1091
    source "$HOME/.config/workbook/$f"
  done
  set +a
}

# adresses_vm — adresses d'état des ressources VM des six nœuds (le nom exact dépend du module vm-noeud).
adresses_vm() {
  (cd "$INFRA" && tofu state list) | grep -E '^module\.noeud\["k8s-(cp0[1-3]|w0[1-3])"\]\..*proxmox_virtual_environment_vm\.'
}

planifier() {
  local args=() a
  charger_env_tofu
  (cd "$INFRA" && tofu init -input=false >/dev/null)
  # k8s-w03 est remplacée comme les autres : la variable de F1-S06 la décrit déjà vide, en démarrage
  # réseau sur le VLAN 60 (sauf DAY0_W03_SANS_USINE=oui, qui doit alors avoir été remise à false).
  while IFS= read -r a; do
    args+=("-replace=$a")
  done < <(adresses_vm)
  ((${#args[@]} == 6)) || { echo "Attendu : 6 ressources VM dans l'état envs/k8s, trouvé ${#args[@]}" >&2; return 1; }
  (cd "$INFRA" && tofu plan -input=false -out=day0.tfplan "${args[@]}")
  # Garde-fou : le plan ne remplace QUE des VMs (aucune suppression d'enregistrement DNS ni d'objet NetBox).
  (cd "$INFRA" && tofu show -json day0.tfplan) | jq -e '
    [.resource_changes[] | select(.change.actions | index("delete"))] as $d
    | ($d | length == 6) and all($d[]; .type == "proxmox_virtual_environment_vm")' >/dev/null ||
    { echo "Le plan supprime autre chose que les six VMs : arrêt (relis-le)." >&2; return 1; }
}

appliquer() {
  charger_env_tofu
  (cd "$INFRA" && tofu apply -input=false day0.tfplan)
}

installer_w03() {
  if [[ "${DAY0_W03_SANS_USINE:-non}" == oui ]]; then
    geste "$PHASE" "k8s-w03 recréé par clone (repli, usine non utilisée) : écart au CHG-3107"
    return 0
  fi
  # L'installation par pxe01 se déroule seule (preseed du profil k8s-noeud) ; la bascule sur le
  # VLAN 40 est la seconde application de la variable de F1-S06 (voir son corrigé).
  echo "k8s-w03 : suis la procédure de F1-S06 (installation par l'usine puis passage sur le VLAN 40)."
  echo "Quand k8s-w03 répond en SSH sur 10.10.40.63, appuie sur Entrée."
  read -r _
}

oublier_cles_hote() {
  local i
  for i in "${!NOEUDS[@]}"; do
    ssh-keygen -R "${NOEUDS[$i]}" >/dev/null 2>&1 || true
    ssh-keygen -R "${NOEUDS[$i]}.par1.medisphere.internal" >/dev/null 2>&1 || true
    ssh-keygen -R "${ADRESSES[$i]}" >/dev/null 2>&1 || true
  done
}

ssh_ok() {
  local n
  for n in "${NOEUDS[@]}"; do
    ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "$n" true || return 1
  done
}

# inscrire_ipa — un nœud à la fois (garde-fou du playbook) ; l'hôte existe déjà dans l'annuaire avec
#   la clé de l'ancienne VM : ton rôle freeipa_client doit forcer la ré-inscription (corrigé F1-S07).
inscrire_ipa() {
  local n
  for n in "${NOEUDS[@]}"; do
    (cd "$ANSIBLE" && uv run ansible-playbook playbooks/inscription-ipa.yml --limit "$n")
  done
}

ansible_reconstruction() {
  (cd "$ANSIBLE" && uv run ansible-playbook playbooks/k8s-reconstruction.yml --limit k8s_par1 \
    -e k8s_plan_controle_amorcage_auto=true \
    -e "k8s_plan_controle_fichier_cluster=$K8S/cluster/kubeadm-config.yaml")
}

recuperer_admin_conf() {
  (umask 077 && ssh k8s-cp01 'sudo cat /etc/kubernetes/admin.conf' >"$ADMIN_CONF.tmp")
  # Le contexte s'appelle « kubernetes-admin@k8s-par1 » dans admin.conf : on le renomme en k8s-par1.
  KUBECONFIG="$ADMIN_CONF.tmp" kubectl config rename-context "$(KUBECONFIG="$ADMIN_CONF.tmp" kubectl config current-context)" "$DAY0_CONTEXTE" >/dev/null
  mv "$ADMIN_CONF.tmp" "$ADMIN_CONF"
  KUBECONFIG="$ADMIN_CONF" kubectl --context "$DAY0_CONTEXTE" get --raw /readyz >/dev/null
}

recreer_wb_checks() {
  local f fichiers=()
  # Seulement l'espace wb-system et les ClusterRoles/liaisons du compte des checks : PAS « task
  # appliquer » (il créerait aussi les bases CNPG de espaces/, dont la CRD n'existe pas encore et qui
  # ne doivent naître que par récupération, F1-S11).
  while IFS= read -r f; do fichiers+=(-f "$f"); done < <(cd "$K8S" && grep -rlE 'wb-checks|name: wb-system' espaces rbac 2>/dev/null | sort)
  ((${#fichiers[@]} > 0)) || { echo "aucun fichier wb-checks trouvé dans espaces/ et rbac/" >&2; return 1; }
  (cd "$K8S" && KUBECONFIG="$ADMIN_CONF" kubectl --context "$DAY0_CONTEXTE" apply --server-side --field-manager=plateforme-k8s "${fichiers[@]}")
  (cd "$K8S" && KUBECONFIG="$ADMIN_CONF" outils/kubeconfig-checks.sh)
}

confirmer "POINT DE NON-RETOUR : les six VMs de k8s-par1 (2141-2146) vont être DÉTRUITES puis recréées. Le gel (10-gel.sh) est-il terminé et le retour arrière relu ?"
etape "$PHASE" "plan OpenTofu (remplacement des six VMs)" planifier
confirmer "Relis le plan ci-dessus : six remplacements de VM, rien d'autre. On applique ?"
etape "$PHASE" "destruction et création des VMs (tofu apply)" appliquer
etape "$PHASE" "installation de k8s-w03 par l'usine" installer_w03
geste "$PHASE" "anciennes clés d'hôte SSH des six nœuds retirées de ~/.ssh/known_hosts"
etape "$PHASE" "clés d'hôte" oublier_cles_hote
etape "$PHASE" "nœuds joignables en SSH" attendre 900 "SSH des six nœuds" ssh_ok
etape "$PHASE" "inscription FreeIPA, nœud par nœud" inscrire_ipa
etape "$PHASE" "Ansible : playbooks/k8s-reconstruction.yml (amorçage compris)" ansible_reconstruction
etape "$PHASE" "admin.conf du nouveau cluster" recuperer_admin_conf
etape "$PHASE" "compte wb-checks et kubeconfig des checks" recreer_wb_checks
jalon "$PHASE" "nœuds reconstruits" "utilise DAY0_KUBECONFIG=$ADMIN_CONF pour 30-couche-base.sh"
