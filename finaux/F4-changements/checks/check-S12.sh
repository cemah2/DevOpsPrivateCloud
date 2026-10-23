# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-S12.sh — F4-S12 « Legacy-RDV sur Kubernetes ». Lecture seule : objets Kubernetes par le compte
# wb-checks (jamais les Secrets ; objets k8s.mariadb.com par la ClusterRole wb-checks-donnees-mariadb),
# HTTP en GET (le test de session ne fait que recharger le formulaire), témoins lus sur pve01.

# shellcheck source=_f4-migrations.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f4-migrations.sh"

title "F4-S12 — Legacy-RDV sur Kubernetes"
require_cmd kubectl jq curl ssh

if ! _f4g_api; then
  check_cmd "l'API de k8s-par1 répond au compte des vérifications" false
else
  for _f4_s12_app in mariadb-operator-crds mariadb-operator legacy-rdv-recette; do
    check_cmd "Application Argo CD $_f4_s12_app : Synced et Healthy" _f4g_app_saine "$_f4_s12_app"
  done
  check_cmd "les charts de mariadb-operator viennent de registry.par1.medisphere.internal/charts" _f4g_kq \
    '[.items[] | select(.metadata.name | test("^mariadb-operator"))
      | [(.spec.source // empty), (.spec.sources // [])[]] | .[] | select(.chart != null) | .repoURL]
     | length >= 2 and all(test("^(oci://)?registry\\.par1\\.medisphere\\.internal/charts"))' -n argocd applications.argoproj.io
  check_cmd "CRD mariadbs.k8s.mariadb.com servie en v1alpha1" _f4g_kq \
    'any(.spec.versions[]; .name == "v1alpha1" and .served)' crd mariadbs.k8s.mariadb.com

  _f4_s12_ns=legacy-rdv-recette
  if kube get mariadbs.k8s.mariadb.com -n "$_f4_s12_ns" -o name >/dev/null 2>&1; then
    check_cmd "$_f4_s12_ns : une MariaDB 11.8 prête" _f4g_mariadb_prete "$_f4_s12_ns"
    check_cmd "$_f4_s12_ns : base legacy_rdv déclarée et prête (Database)" _f4g_kq \
      'any(.items[]; (.spec.name // .metadata.name) == "legacy_rdv" and any(.status.conditions[]?; .type == "Ready" and .status == "True"))' \
      -n "$_f4_s12_ns" databases.k8s.mariadb.com
    check_cmd "$_f4_s12_ns : au moins deux comptes (User) prêts" _f4g_kq \
      '[.items[] | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))] | length >= 2' \
      -n "$_f4_s12_ns" users.k8s.mariadb.com
    check_cmd "$_f4_s12_ns : droits déclarés (Grant) prêts, sans ALL PRIVILEGES pour le compte applicatif legacy_rdv" _f4g_kq \
      '(.items | length >= 1) and all(.items[]; any(.status.conditions[]?; .type == "Ready" and .status == "True"))
       and ([.items[] | select(.spec.username == "legacy_rdv") | .spec.privileges[] | ascii_upcase | select(test("ALL"))] | length == 0)' \
      -n "$_f4_s12_ns" grants.k8s.mariadb.com
    check_cmd "$_f4_s12_ns : sauvegarde planifiée vers s3-01 (Backup)" _f4g_kq \
      'any(.items[]; (.spec.schedule.cron // "") != "" and ((.spec.storage.s3.endpoint // "") | test("s3-01")))' \
      -n "$_f4_s12_ns" backups.k8s.mariadb.com
  else
    check_cmd "le compte des vérifications lit les objets k8s.mariadb.com de $_f4_s12_ns (ClusterRole wb-checks-donnees-mariadb)" false
  fi
  # Les Jobs d'une Backup planifiée portent le nom de la Backup en préfixe (CronJob de l'opérateur).
  _f4_s12_sauvegarde_ok() {
    local b j
    b="$(kube get backups.k8s.mariadb.com -n "$1" -o json 2>/dev/null | jq -c '[.items[].metadata.name]')" || return 1
    j="$(kube get jobs -n "$1" -o json 2>/dev/null)" || return 1
    jq -e --argjson b "$b" 'any(.items[]; (.status.succeeded // 0) >= 1 and (.metadata.name as $n | any($b[]; . as $p | $n | startswith($p))))' >/dev/null 2>&1 <<<"$j"
  }
  check_cmd "$_f4_s12_ns : au moins une sauvegarde de la base a réussi (Job terminé)" _f4_s12_sauvegarde_ok "$_f4_s12_ns"
  check_cmd "$_f4_s12_ns : deux pods Legacy-RDV prêts (image par empreinte) sur deux nœuds différents" _f4g_pods_legacy "$_f4_s12_ns" 2 2
  check_cmd "$_f4_s12_ns : un PVC cephfs en ReadWriteMany lié" _f4g_kq \
    'any(.items[]; .spec.storageClassName == "cephfs" and (.spec.accessModes | index("ReadWriteMany")) and .status.phase == "Bound")' \
    -n "$_f4_s12_ns" pvc
  check_cmd "$_f4_s12_ns : un PodDisruptionBudget" _f4g_kq '.items | length >= 1' -n "$_f4_s12_ns" pdb
  check_cmd "$_f4_s12_ns : un CronJob de purge qui utilise l'image de Legacy-RDV" _f4g_kq \
    'any(.items[]; any(.spec.jobTemplate.spec.template.spec.containers[]; .image | test("/medisphere/legacy-rdv")))' \
    -n "$_f4_s12_ns" cronjobs
  check_cmd "$_f4_s12_ns : ExternalSecret présents et synchronisés" _f4g_kq \
    '(.items | length >= 1) and all(.items[]; any(.status.conditions[]?; .type == "Ready" and .status == "True"))' \
    -n "$_f4_s12_ns" externalsecrets.external-secrets.io
  check_cmd "politique de signature de Kyverno : legacy-rdv-recette et legacy-rdv-prod couverts" _f4g_kq \
    'any(.items[]; [.spec.matchConstraints.namespaceSelector.matchExpressions[]? | select(.key == "kubernetes.io/metadata.name" and .operator == "In") | .values[]]
       | (index("legacy-rdv-recette") != null) and (index("legacy-rdv-prod") != null))' imagevalidatingpolicies.policies.kyverno.io

  _f4_s12_ns=legacy-rdv-prod
  if kube get mariadbs.k8s.mariadb.com -n "$_f4_s12_ns" -o name >/dev/null 2>&1; then
    check_cmd "$_f4_s12_ns : une MariaDB 11.8 prête" _f4g_mariadb_prete "$_f4_s12_ns"
  else
    check_cmd "le compte des vérifications lit les objets k8s.mariadb.com de $_f4_s12_ns" false
  fi
  check_cmd "$_f4_s12_ns : Legacy-RDV déployé (au moins un pod prêt, image par empreinte)" _f4g_pods_legacy "$_f4_s12_ns" 1
fi

# --- Par la Gateway (recette) -------------------------------------------------------------------------
check_http "recette : $_f4g_recette/sante.php répond 200" "$_f4g_recette/sante.php"
check_output "recette : la page d'accueil liste les rendez-vous" 'Rendez-vous à venir' _f4g_get "$_f4g_recette/index.php"
check_cmd "recette : la pièce jointe témoin (rendez-vous 9003) se télécharge à l'identique" _f4g_piece_temoin "$_f4g_recette"
check_cmd "recette : six chargements du formulaire avec la même session gardent le même jeton (sessions partagées)" \
  _f4g_session_partagee "$_f4g_recette"
