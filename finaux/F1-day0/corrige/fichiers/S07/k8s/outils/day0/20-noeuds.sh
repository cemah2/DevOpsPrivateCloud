#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# plateforme/k8s — outils/day0/20-noeuds.sh (F1-S07, CHG-3107)
# Destruction et reconstruction des six nœuds de k8s-par1, depuis le code. Après 10-gel.sh.
#
#   1. point de non-retour (confirmation) ;
#   2. OpenTofu (plateforme/infra, envs/k8s) :
#      a. REMPLACEMENT ciblé (-replace) des ressources VM des cinq nœuds clonés (k8s-cp01-03,
#         k8s-w01, k8s-w02) : leurs objets NetBox et DNS ne bougent pas ;
#      b. k8s-w03 change de mode de création (clone vm-noeud → usine.tf de F1-S06) : on ne le fait
#         jamais en une passe sur un nœud existant (même VMID, même adresse : « already exists »).
#         D'abord RETRAIT de module.noeud["k8s-w03"] (tofu apply -destroy -target, VM et objets
#         NetBox/DNS du seul k8s-w03), PUIS la procédure de F1-S06 (usine-k8s.md §6) : MR
#         noeuds_usine = { "k8s-w03" = "installation" }, apply, job « provisionner »
#         (EQUIPEMENT=k8s-w03), MR noeuds_usine = { "k8s-w03" = "service" }, apply, puis
#         « uv run outils/provisionner.py k8s-w03 --apres-bascule » (clé d'hôte confirmée) ;
#   3. clés d'hôte SSH : les anciennes empreintes sont retirées de ~/.ssh/known_hosts (geste noté) ;
#      celle de k8s-w03, confirmée par l'agent QEMU, est reprise du cache de provisionner.py ;
#   4. Ansible (plateforme/ansible) : inscription FreeIPA nœud par nœud, puis
#      playbooks/k8s-reconstruction.yml (durcissement, fichiers de l'API, amorçage explicite, etcd) ;
#   5. admin.conf du NOUVEAU cluster récupéré (600) pour la suite de la reconstruction ;
#   6. compte wb-checks et son kubeconfig recréés (pour lab/bin/check).
#
# Relance : les deux étapes OpenTofu (remplacement, retrait de k8s-w03) laissent une marque
# (~/day0/20-noeuds.vms, ~/day0/20-noeuds.retrait-w03) et ne se rejouent pas ; le reste est relançable.
# Variables : DAY0_W03_SANS_USINE=oui pour recréer k8s-w03 par clone comme les autres (repli si
# l'usine est indisponible : noeuds_usine reste vide, écart noté au CHG-3107) ;
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

sans_usine() { [[ "${DAY0_W03_SANS_USINE:-non}" == oui ]]; }

# adresses_vm — adresses d'état des ressources VM des nœuds CLONÉS à remplacer (le nom exact dépend du
#   module vm-noeud) : les six en repli, sinon tous sauf k8s-w03 (qui passe par l'usine).
adresses_vm() {
  local motif='k8s-(cp0[1-3]|w0[12])'
  sans_usine && motif='k8s-(cp0[1-3]|w0[1-3])'
  (cd "$INFRA" && tofu state list) | grep -E "^module\.noeud\[\"$motif\"\]\..*proxmox_virtual_environment_vm\."
}

planifier() {
  local args=() a attendu=5
  sans_usine && attendu=6
  charger_env_tofu
  (cd "$INFRA" && git pull --ff-only && tofu init -input=false >/dev/null)
  # Le code de F1-S06 doit être fusionné et INACTIF : k8s-w03 est encore un clone de vm-noeud.
  (cd "$INFRA" && tofu state list) | grep -q '^module\.noeud\["k8s-w03"\]' ||
    { echo "module.noeud[\"k8s-w03\"] absent de l'état envs/k8s : relis l'état avant de continuer." >&2; return 1; }
  while IFS= read -r a; do
    args+=("-replace=$a")
  done < <(adresses_vm)
  ((${#args[@]} == attendu)) || { echo "Attendu : $attendu ressources VM dans l'état envs/k8s, trouvé ${#args[@]}" >&2; return 1; }
  (cd "$INFRA" && tofu plan -input=false -out=day0.tfplan "${args[@]}")
  # Garde-fou : le plan ne remplace QUE des VMs (aucune suppression d'enregistrement DNS ni d'objet NetBox).
  (cd "$INFRA" && tofu show -json day0.tfplan) | jq -e --argjson n "$attendu" '
    [.resource_changes[] | select(.change.actions | index("delete"))] as $d
    | ($d | length == $n) and all($d[]; .type == "proxmox_virtual_environment_vm")' >/dev/null ||
    { echo "Le plan supprime autre chose que les $attendu VMs clonées : arrêt (relis-le)." >&2; return 1; }
}

appliquer() {
  charger_env_tofu
  (cd "$INFRA" && tofu apply -input=false day0.tfplan)
}

# retirer_w03 — retrait de k8s-w03 de module.noeud (VM 2146 et ses objets NetBox/DNS), AVANT que
#   usine.tf ne le recrée (F1-S06 : jamais les deux dans le même apply).
retirer_w03() {
  charger_env_tofu
  (cd "$INFRA" && tofu plan -input=false -destroy -target='module.noeud["k8s-w03"]' -out=day0-w03.tfplan)
  # Garde-fou : uniquement des suppressions, et uniquement d'objets de k8s-w03.
  (cd "$INFRA" && tofu show -json day0-w03.tfplan) | jq -e '
    [.resource_changes[] | select(.change.actions != ["no-op"])] as $c
    | ($c | length > 0)
      and all($c[]; .change.actions == ["delete"] and (.address | contains("\"k8s-w03\"")))' >/dev/null ||
    { echo "Le plan de retrait touche autre chose que k8s-w03 : arrêt (relis-le)." >&2; return 1; }
  confirmer "Relis le plan ci-dessus : seuls la VM 2146 et les objets de k8s-w03 disparaissent. On applique ?"
  (cd "$INFRA" && tofu apply -input=false day0-w03.tfplan)
}

# w03_en_service — l'usine a fini : état envs/k8s en phase « service » pour k8s-w03, VM sur vk8s.
w03_en_service() {
  charger_env_tofu
  (cd "$INFRA" && git pull --ff-only >/dev/null && tofu output -json noeuds_usine) |
    jq -e '.["k8s-w03"].phase == "service"' >/dev/null
}

installer_w03() {
  if sans_usine; then
    geste "$PHASE" "k8s-w03 recréé par clone (repli, usine non utilisée) : écart au CHG-3107"
    return 0
  fi
  echo "k8s-w03 : suis maintenant usine-k8s.md §6 (F1-S06) :"
  echo "  1. MR plateforme/infra : noeuds_usine = { \"k8s-w03\" = \"installation\" }, plan relu, apply ;"
  echo "  2. plateforme/provisioning : Run pipeline, EQUIPEMENT=k8s-w03, job « provisionner » ;"
  echo "  3. MR plateforme/infra : noeuds_usine = { \"k8s-w03\" = \"service\" }, plan relu (en place), apply ;"
  echo "  4. uv run outils/provisionner.py k8s-w03 --apres-bascule (copie de plateforme/provisioning)."
  echo "Quand provisionner.py a mis k8s-w03 « active » dans NetBox, appuie sur Entrée."
  read -r _
  w03_en_service || { echo "envs/k8s : k8s-w03 n'est pas en phase « service » (noeuds_usine) : reprends la procédure." >&2; return 1; }
}

oublier_cles_hote() {
  local i kh="${XDG_CACHE_HOME:-$HOME/.cache}/provisionner/known_hosts-k8s-w03"
  for i in "${!NOEUDS[@]}"; do
    ssh-keygen -R "${NOEUDS[$i]}" >/dev/null 2>&1 || true
    ssh-keygen -R "${NOEUDS[$i]}.par1.medisphere.internal" >/dev/null 2>&1 || true
    ssh-keygen -R "${ADRESSES[$i]}" >/dev/null 2>&1 || true
  done
  # k8s-w03 (usine) : clé lue DANS la machine par l'agent QEMU (provisionner.py --apres-bascule).
  if ! sans_usine && [[ -s "$kh" ]]; then cat "$kh" >>"$HOME/.ssh/known_hosts"; fi
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

# Relance : les étapes OpenTofu déjà faites sont marquées (un remplacement ne se rejoue JAMAIS par
# accident). Marques dans le dossier du journal ; à supprimer seulement pour une nouvelle fenêtre.
MARQUES="$(dirname "$DAY0_JOURNAL")"
fait() { [[ -e "$MARQUES/20-noeuds.$1" ]]; }
marquer() { touch "$MARQUES/20-noeuds.$1"; }

if ! fait vms; then
  confirmer "POINT DE NON-RETOUR : les six VMs de k8s-par1 (2141-2146) vont être DÉTRUITES puis recréées. Le gel (10-gel.sh) est-il terminé et le retour arrière relu ?"
  etape "$PHASE" "plan OpenTofu (remplacement des VMs clonées)" planifier
  confirmer "Relis le plan ci-dessus : remplacements de VM seulement (cinq, six en repli), rien d'autre. On applique ?"
  etape "$PHASE" "destruction et création des VMs clonées (tofu apply)" appliquer
  marquer vms
fi
if ! sans_usine && ! fait retrait-w03; then
  etape "$PHASE" "retrait de k8s-w03 de module.noeud (VM 2146, NetBox, DNS)" retirer_w03
  marquer retrait-w03
fi
etape "$PHASE" "installation de k8s-w03 par l'usine (F1-S06)" installer_w03
geste "$PHASE" "anciennes clés d'hôte SSH des six nœuds retirées de ~/.ssh/known_hosts"
etape "$PHASE" "clés d'hôte" oublier_cles_hote
etape "$PHASE" "nœuds joignables en SSH" attendre 900 "SSH des six nœuds" ssh_ok
etape "$PHASE" "inscription FreeIPA, nœud par nœud" inscrire_ipa
etape "$PHASE" "Ansible : playbooks/k8s-reconstruction.yml (amorçage compris)" ansible_reconstruction
etape "$PHASE" "admin.conf du nouveau cluster" recuperer_admin_conf
etape "$PHASE" "compte wb-checks et kubeconfig des checks" recreer_wb_checks
jalon "$PHASE" "nœuds reconstruits" "utilise DAY0_KUBECONFIG=$ADMIN_CONF pour 30-couche-base.sh"
