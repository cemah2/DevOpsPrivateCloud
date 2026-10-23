# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-S04.sh — F1-S04 « Le filet : sauvegardes prouvées, go/no-go et retour arrière ».
# Lecture seule : listage des instantanés du datastore PBS (SSH root sur pbs01, aucun accès au
# contenu), état de l'unité d'instantané etcd sur les nœuds de contrôle (systemctl show), objets
# Velero, CNPG et Jobs par le compte wb-checks, documents sur main.
# Âge maximal : WB_F1_HEURES heures (24 par défaut). À lancer JUSTE AVANT le go de la fenêtre.
#
# Variables : WB_F1_PBS_DATASTORE (ds-lab), WB_F1_PBS_NS (par1/k8s), WB_F1_NOEUDS_VMID
# (« 2141 2142 2143 2144 2145 2146 »), WB_F1_ETCD_UNITE (etcd-instantane.service),
# WB_F1_ETCD_HEURES (2), WB_K8S_CP.

# shellcheck source=_f1-preparer.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f1-preparer.sh"

title "F1-S04 — Le filet : sauvegardes prouvées, go/no-go et retour arrière"
require_cmd curl jq kubectl ssh

_f1_s04_ds="${WB_F1_PBS_DATASTORE:-ds-lab}"
_f1_s04_ns="${WB_F1_PBS_NS:-par1/k8s}"
read -r -a _f1_s04_vmids <<<"${WB_F1_NOEUDS_VMID:-2141 2142 2143 2144 2145 2146}"
read -r -a _f1_s04_cp <<<"${WB_K8S_CP:-k8s-cp01 k8s-cp02 k8s-cp03}"
_f1_s04_unite="${WB_F1_ETCD_UNITE:-etcd-instantane.service}"

# --- PBS : une sauvegarde récente de chacun des six nœuds -----------------------------------------
# Chemin d'un espace de noms PBS dans le datastore : ns/par1/ns/k8s/vm/<VMID>/<horodatage RFC 3339>/
_f1_s04_nsdir="ns/${_f1_s04_ns//\//\/ns\/}"
# Script de lecture exécuté en root sur pbs01 : chemin du datastore, puis, par VMID, l'horodatage
# du plus récent instantané complet (index.json.blob présent), en époque Unix ; 0 si aucun.
# shellcheck disable=SC2016  # variables du script distant
_f1_s04_script='p="$(proxmox-backup-manager datastore show "$1" --output-format json | perl -MJSON::PP -0777 -ne '"'"'print decode_json($_)->{path}'"'"')" || exit 1
ns="$2"; shift 2
for v in "$@"; do
  d="$(ls -1d "$p/$ns/vm/$v"/*/ 2>/dev/null | sort | tail -n 1)"
  if [ -n "$d" ] && [ -f "${d}index.json.blob" ]; then echo "$v $(date -d "$(basename "$d")" +%s)"; else echo "$v 0"; fi
done'
_f1_s04_pbs="$(remote "$WB_PBS_HOST" "bash -c $(printf '%q' "$_f1_s04_script") _ $(printf '%q ' "$_f1_s04_ds" "$_f1_s04_nsdir" "${_f1_s04_vmids[@]}")" </dev/null 2>/dev/null)" || _f1_s04_pbs=""
check_cmd "datastore $_f1_s04_ds de $WB_PBS_HOST lu (espace de noms $_f1_s04_ns)" test -n "$_f1_s04_pbs"
for _f1_s04_v in "${_f1_s04_vmids[@]}"; do
  _f1_s04_t="$(awk -v v="$_f1_s04_v" '$1 == v {print $2}' <<<"$_f1_s04_pbs")"
  check_cmd "PBS ($_f1_s04_ns) : sauvegarde de la VM $_f1_s04_v de moins de $_f1p_heures h (âge : $(_f1p_age_heures "${_f1_s04_t:-0}") h)" \
    _f1p_frais "${_f1_s04_t:-0}"
done

# --- etcd : dernier instantané réussi et récent ---------------------------------------------------
_f1_s04_etcd_ok=0
for _f1_s04_h in "${_f1_s04_cp[@]}"; do
  _f1_s04_o="$(_f1p_hote_sortie "$_f1_s04_h" "systemctl show $(printf '%q' "$_f1_s04_unite") -p Result -p ExecMainExitTimestamp --timestamp=unix")" || continue
  if grep -q '^Result=success' <<<"$_f1_s04_o"; then
    _f1_s04_e="$(sed -n 's/^ExecMainExitTimestamp=@\([0-9]*\).*/\1/p' <<<"$_f1_s04_o")"
    if _f1p_frais "${_f1_s04_e:-0}" "${WB_F1_ETCD_HEURES:-2}"; then _f1_s04_etcd_ok=$((_f1_s04_etcd_ok + 1)); fi
  fi
done
check_cmd "etcd : instantané réussi de moins de ${WB_F1_ETCD_HEURES:-2} h sur au moins un nœud de contrôle ($_f1_s04_etcd_ok)" \
  test "$_f1_s04_etcd_ok" -ge 1

# --- Cluster : Velero, CNPG, RabbitMQ, Argo CD ------------------------------------------------------
_f1_s04_seuil="$(date -u -d "-$_f1p_heures hours" +%Y-%m-%dT%H:%M:%SZ)"
if _f1p_api_repond; then
  _f1_s04_velero="$(kube -n velero get backups.velero.io -o json 2>/dev/null | jq --arg s "$_f1_s04_seuil" \
    '[.items[] | select(.status.phase == "Completed" and (.status.completionTimestamp // "") > $s
       and ((.spec.includedNamespaces // []) | length == 0 or index("*") != null)
       and ((.spec.excludedNamespaces // []) | length == 0))] | length' 2>/dev/null)" || _f1_s04_velero=0
  check_cmd "Velero : une sauvegarde complète (tous les espaces, aucun exclu) Completed de moins de $_f1p_heures h" \
    test "${_f1_s04_velero:-0}" -ge 1

  for _f1_s04_c in mediagenda-recette/mediagenda-db mediagenda-prod/mediagenda-db portail/portail-db; do
    _f1_s04_n="$(kube -n "${_f1_s04_c%/*}" get backups.postgresql.cnpg.io -o json 2>/dev/null | jq --arg s "$_f1_s04_seuil" --arg c "${_f1_s04_c#*/}" \
      '[.items[] | select(.spec.cluster.name == $c and (.status.phase // "") == "completed" and (.status.stoppedAt // "") > $s)] | length' 2>/dev/null)" || _f1_s04_n=0
    check_cmd "CNPG : sauvegarde « completed » de $_f1_s04_c de moins de $_f1p_heures h" test "${_f1_s04_n:-0}" -ge 1
  done

  # Jobs issus des CronJobs d'export (planifiés ou lancés à la main depuis le CronJob).
  for _f1_s04_j in messagerie/export-definitions argocd/argocd-export; do
    _f1_s04_n="$(kube -n "${_f1_s04_j%/*}" get jobs -o json 2>/dev/null | jq --arg s "$_f1_s04_seuil" --arg a "${_f1_s04_j#*/}" \
      '[.items[] | select(((.spec.template.metadata.labels["app.kubernetes.io/name"] // "") == $a or (.metadata.name | startswith($a)))
         and (.status.succeeded // 0) >= 1 and (.status.completionTime // "") > $s)] | length' 2>/dev/null)" || _f1_s04_n=0
    check_cmd "export $_f1_s04_j réussi il y a moins de $_f1p_heures h" test "${_f1_s04_n:-0}" -ge 1
  done
else
  check_cmd "l'API de k8s-par1 répond au compte des checks" false
fi

# --- Documents -------------------------------------------------------------------------------------
check_cmd "docs/day0/reference-avant.md : inventaire de référence (rendez-vous en prod, messages en file, ExternalSecrets, certificats)" \
  _f1p_doc '^reference-avant\.md$' 'rendez-vous' 'file|messages' 'ExternalSecret' 'certificat'
check_cmd "docs/day0/retour-arriere.md : restauration des six VMs depuis PBS, ordre de démarrage, vérifications" \
  _f1p_doc '^retour-arriere\.md$' 'PBS|pbs01' '2141' '2146' 'ordre|démarr' 'vérifi'
check_cmd "fiche CHG-3104 publiée sous docs/day0 : critères de go/no-go, preuve de restauration ou de vérification PBS" \
  _f1p_doc '^CHG-3104.*\.md$' 'no-go|no go' 'go' 'restaur|verif'
