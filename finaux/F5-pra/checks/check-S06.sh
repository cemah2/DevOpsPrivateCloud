# shellcheck shell=bash
# shellcheck disable=SC2016  # commandes distantes et filtres jq entre apostrophes (développés à distance)
# shellcheck source-path=SCRIPTDIR
# check-S06.sh — F5-S06 « Le cluster de secours k8s-par2 » : nœud, L2 et LB IPAM, gw-par2 et son
# certificat, topologie distribuée CloudNativePG (PAR2 et PAR1), repère de site, veille à zéro réplica,
# ExternalSecrets, témoin de RPO, sources d'Argo CD de PAR2, RB-356. Lecture seule (kubectl wb-checks des
# deux clusters, openssl s_client, curl, GitLab ou miroir).

# shellcheck source=_f5-par2.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f5-par2.sh"

title "F5-S06 — Le cluster de secours k8s-par2"
require_cmd kubectl jq openssl curl

_f5_s06_racine="${WB_RACINE_PKI:-/usr/local/share/ca-certificates/medisphere-root-ca.crt}"
_f5_s06_vip="${WB_F5_GW_PAR2_IP:-10.20.20.200}"
_f5_s06_vide="{}"

# --- Cluster et réseau -----------------------------------------------------------------------------------
_f5_s06_noeuds="$(_f5p_kube get nodes -o json 2>/dev/null || true)"
check_cmd "k8s-par2 : exactement un nœud, Ready, en 1.36" \
  jq -e '(.items | length == 1) and (.items[0].status.conditions[] | select(.type == "Ready") | .status == "True")
         and (.items[0].status.nodeInfo.kubeletVersion | startswith("v1.36"))' <<<"${_f5_s06_noeuds:-$_f5_s06_vide}"
check_cmd "k8s-par2 : le nœud n'a pas de taint NoSchedule (plan de contrôle qui porte les charges)" \
  jq -e '(.items | length == 1) and ([.items[0].spec.taints // [] | .[] | select(.effect == "NoSchedule")] | length == 0)' <<<"${_f5_s06_noeuds:-$_f5_s06_vide}"
_f5_s06_l2() {
  _f5p_kube get ciliuml2announcementpolicies -o json 2>/dev/null \
    | jq -e '[.items[] | select(.spec.loadBalancerIPs == true)] | length >= 1' >/dev/null
}
check_cmd "k8s-par2 : au moins une CiliumL2AnnouncementPolicy qui annonce les adresses de LoadBalancer" _f5_s06_l2
_f5_s06_pool() {
  _f5p_kube get ciliumloadbalancerippools lb-par2 -o json 2>/dev/null \
    | jq -e '[.spec.blocks[]? | select((.start == "10.20.20.200" and .stop == "10.20.20.239"))] | length == 1' >/dev/null
}
check_cmd "k8s-par2 : pool LB IPAM lb-par2 = 10.20.20.200 à 10.20.20.239" _f5_s06_pool
_f5_s06_gw() {
  _f5p_kube -n passerelles get gateway gw-par2 -o json 2>/dev/null | jq -e --arg ip "$_f5_s06_vip" \
    '(.status.addresses // [] | any(.value == $ip)) and (.status.conditions // [] | any(.type == "Programmed" and .status == "True"))' >/dev/null
}
check_cmd "gw-par2 (passerelles) programmée en $_f5_s06_vip" _f5_s06_gw

_f5_s06_cert="$(timeout "$WB_TIMEOUT" openssl s_client -connect "$_f5_s06_vip:443" -servername mediagenda.medisphere.internal </dev/null 2>/dev/null \
  | openssl x509 2>/dev/null || true)"
_f5_s06_emetteur() { openssl x509 -noout -issuer -nameopt utf8,sep_comma_plus <<<"$_f5_s06_cert" 2>/dev/null | grep -q 'MédiSphère PAR2 Intermediate CA'; }
check_cmd "gw-par2 présente un certificat émis par « MédiSphère PAR2 Intermediate CA »" _f5_s06_emetteur
_f5_s06_san() { openssl x509 -noout -ext subjectAltName <<<"$_f5_s06_cert" 2>/dev/null | grep -q 'DNS:mediagenda.medisphere.internal'; }
check_cmd "ce certificat couvre mediagenda.medisphere.internal (nom global)" _f5_s06_san

# --- Base : topologie distribuée ---------------------------------------------------------------------
_f5_s06_c2="$(_f5p_kube -n mediagenda-prod get cluster mediagenda-db-par2 -o json 2>/dev/null || true)"
check_cmd "mediagenda-db-par2 : sain, au moins une instance prête" \
  jq -e '(.status.phase == "Cluster in healthy state") and ((.status.readyInstances // 0) >= 1)' <<<"${_f5_s06_c2:-$_f5_s06_vide}"
check_cmd "mediagenda-db-par2 : réplica de la topologie (replica.primary = mediagenda-db, source = mediagenda-db)" \
  jq -e '.spec.replica.primary == "mediagenda-db" and .spec.replica.source == "mediagenda-db"' <<<"${_f5_s06_c2:-$_f5_s06_vide}"
check_cmd "mediagenda-db-par2 : lit l'archive de PAR1 sous $_f5p_serveur_prod" \
  jq -e --arg s "$_f5p_serveur_prod" '[.spec.externalClusters[]? | select(.name == "mediagenda-db") | .plugin.parameters.serverName] | any(. == $s)' <<<"${_f5_s06_c2:-$_f5_s06_vide}"
_f5_s06_os_par2() {
  _f5p_kube -n mediagenda-prod get objectstores.barmancloud.cnpg.io -o json 2>/dev/null \
    | jq -e '[.items[].spec.configuration.destinationPath | select(test("^s3://cnpg-k8s-par2/?$"))] | length >= 1' >/dev/null
}
check_cmd "k8s-par2 : un ObjectStore vers s3://cnpg-k8s-par2/ (archive propre à PAR2)" _f5_s06_os_par2
_f5_s06_c1="$(kube -n mediagenda-prod get cluster mediagenda-db -o json 2>/dev/null || true)"
if [[ -n "$_f5_s06_c1" ]]; then
  check_cmd "PAR1 : mediagenda-db déclare la topologie (replica.primary = mediagenda-db, source = mediagenda-db-par2)" \
    jq -e '.spec.replica.primary == "mediagenda-db" and .spec.replica.source == "mediagenda-db-par2"' <<<"$_f5_s06_c1"
  check_cmd "PAR1 : mediagenda-db est toujours le primaire sain" \
    jq -e '.status.phase == "Cluster in healthy state"' <<<"$_f5_s06_c1"
else
  skip "topologie déclarée par mediagenda-db de PAR1" "k8s-par1 injoignable (kube)"
fi

# --- Repère de site ---------------------------------------------------------------------------------------
_f5_s06_entete_par2() {
  _f5p_kube -n mediagenda-prod get httproutes -o json 2>/dev/null | jq -e '
    [.items[].spec.rules[]?.filters[]? | select(.type == "ResponseHeaderModifier")
     | .responseHeaderModifier | ((.set // []) + (.add // []))[]
     | select((.name | ascii_downcase) == "x-medisphere-site" and .value == "par2")] | length >= 1' >/dev/null
}
check_cmd "k8s-par2 : une HTTPRoute de mediagenda-prod pose X-MediSphere-Site: par2" _f5_s06_entete_par2
_f5_s06_entete_par1() {
  local o=()
  [[ -r "$_f5_s06_racine" ]] && o=(--cacert "$_f5_s06_racine")
  curl -s -o /dev/null -D - --max-time "$WB_TIMEOUT" "${o[@]}" "$_f5p_url_par1/sante" | grep -Eqi '^x-medisphere-site: *par1'
}
check_cmd "PAR1 : $_f5p_url_par1 répond avec X-MediSphere-Site: par1" _f5_s06_entete_par1

# --- Veille ---------------------------------------------------------------------------------------------
_f5_s06_veille() {
  local ns="$1"
  _f5p_kube -n "$ns" get pods -o json 2>/dev/null | jq -e '
    [.items[] | select(.status.phase == "Running" or .status.phase == "Pending")
     | select((.metadata.labels // {}) | (has("cnpg.io/cluster") or has("cnpg.io/poolerName")) | not)
     | select([.metadata.ownerReferences[]?.kind] | index("Job") | not)] | length == 0' >/dev/null
}
for _f5_s06_ns in mediagenda-prod medidoc-recette legacy-rdv-prod medinotif-prod; do
  check_cmd "k8s-par2 : aucun pod applicatif actif dans $_f5_s06_ns (veille)" _f5_s06_veille "$_f5_s06_ns"
done
_f5_s06_es() {
  _f5p_kube -n mediagenda-prod get externalsecrets.external-secrets.io -o json 2>/dev/null | jq -e '
    (.items | length >= 1) and
    ([.items[] | select([.status.conditions[]? | select(.type == "Ready" and .status == "True")] | length == 0)] | length == 0)' >/dev/null
}
check_cmd "k8s-par2 : les ExternalSecrets de mediagenda-prod sont tous Ready" _f5_s06_es

# --- Témoin de RPO --------------------------------------------------------------------------------------
check_output "k8s-par2 : CronJob temoin-rpo suspendu" '^true$' \
  _f5p_kube -n mediagenda-prod get cronjob temoin-rpo -o 'jsonpath={.spec.suspend}'
_f5_s06_temoin_par1() {
  local j age
  j="$(kube -n mediagenda-prod get cronjob temoin-rpo -o json 2>/dev/null)" || return 1
  jq -e '(.spec.suspend // false) == false' >/dev/null <<<"$j" || return 1
  age="$(_f5p_age "$(jq -r '.status.lastSuccessfulTime // empty' <<<"$j")")" || return 1
  ((age <= 300))
}
check_cmd "k8s-par1 : temoin-rpo actif, dernière réussite il y a moins de 5 min" _f5_s06_temoin_par1

# --- Sonde utilisateur (adm02) ----------------------------------------------------------------------------
check_cmd "adm02 : minuterie ms-sonde-pra active" _f5p_unite_active "$_f5p_adm02_hote" 'ms-sonde-pra\.timer'
_f5_s06_sonde() {
  local l age
  l="$(_f5p_adm02 "grep 'mediagenda.medisphere.internal' /var/lib/ms-sonde-pra/mesures.csv | tail -n 1" 2>/dev/null)" || return 1
  [[ -n "$l" ]] || return 1
  age="$(_f5p_age "${l%%,*}")" || return 1
  IFS=, read -r _ _ code _ site <<<"$l"
  ((age <= 120)) && [[ "$code" =~ ^2[0-9][0-9]$ && "$site" == par1 ]]
}
check_cmd "ms-sonde-pra : dernière mesure de mediagenda.medisphere.internal récente (< 2 min), 2xx, servie par par1" _f5_s06_sonde

# --- Argo CD de PAR2 ------------------------------------------------------------------------------------
_f5_s06_argocd() {
  local j
  j="$(_f5p_kube -n argocd get applications.argoproj.io,applicationsets.argoproj.io -o json 2>/dev/null)" || return 1
  jq -e '
    [.. | objects | .repoURL? // empty] as $u
    | ($u | length >= 1)
      and ($u | all(test("par1\\.medisphere\\.internal") | not))
      and ($u | any(startswith("ssh://miroir@adm02.par2.medisphere.internal/")))' >/dev/null <<<"$j"
}
check_cmd "Argo CD de k8s-par2 : sources sur les miroirs de adm02, aucune à PAR1" _f5_s06_argocd

check_cmd "RB-356 publié : différences de site, secrets en veille et en PRA, requête du RPO (PRA-TEMOIN)" \
  _f5p_doc runbooks/RB-356-cluster-de-secours.md 'site' 'externalsecret|ESO|secret' 'PRA-TEMOIN' 'promotionToken|jeton'
