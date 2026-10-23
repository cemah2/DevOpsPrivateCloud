# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# _f3-debut.sh — fonctions des vérifications du début de semaine du final F3 (check-S01 à check-S09).
# Sourcé, jamais lancé seul. Charge _f3-sante.sh (préfixe _f3s_). Préfixe : _f3d_.
# Lecture seule : « kube » (wb-checks), GET sur GitLab, Alertmanager, Prometheus, Mailpit ; SSH + sudo -n
# de commandes de CONSULTATION (systemctl is-active, df, pdnsutil metadata get, qm config, ceph … -f json) ;
# requêtes GET de créneaux sur MédiAgenda (praticien fictif « sonde-f3-… » : rien n'est écrit en base).
#
# Variables (lab/lab.env, toutes facultatives) :
#   WB_F3_PROD_URL, WB_F3_RECETTE_URL       MédiAgenda publié (prod, recette)
#   WB_F3_LATENCE_MAX                       médiane acceptable d'une consultation « cache manqué » (1.0 s)
#   WB_F3_VALKEY_MAXMEMORY_MIN              plancher de maxmemory de Valkey en prod (16777216 octets)
#   WB_F3_ACME_URL                          répertoire ACME attendu de step-ca-acme
#   WB_F3_PROJET_OBSERVABILITE, WB_F3_FICHIER_ROUTES_TESTS
#   WB_F3_PROJET_DEPLOIEMENT, WB_F3_PROJET_API, WB_F3_APP_RECETTE
#   WB_F3_S08_POOL, WB_F3_S08_CEPH_VMS      pool RBD du cluster, VMs Ceph (« nom:vmid »)
#   WB_F3_DNS_PRIMAIRE                      autoritaire primaire (dns01)

# shellcheck source=_f3-sante.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f3-sante.sh"

_f3d_prod="mediagenda-prod"
_f3d_recette="mediagenda-recette"
_f3d_url_prod="${WB_F3_PROD_URL:-https://mediagenda.apps.par1.medisphere.internal}"
_f3d_racine="${WB_RACINE_PKI:-/usr/local/share/ca-certificates/medisphere-root-ca.crt}"

# _f3d_prom 'PromQL' — première valeur du résultat (vide si aucune série).
_f3d_prom() { prom_requete "$1" 2>/dev/null | jq -r '.data.result[0].value[1] // empty' 2>/dev/null || true; }

# _f3d_inferieur A B — vrai si A < B (décimaux).
_f3d_inferieur() { awk -v a="$1" -v b="$2" 'BEGIN {exit !(a < b)}'; }

# _f3d_latence URL N [PARALLÈLES] — médiane (s) de N consultations de créneaux qui manquent le cache.
_f3d_latence() {
  local url="$1" n="$2" par="${3:-1}" jour tmp i
  jour="$(date -d '+30 days' +%F)"
  tmp="$(mktemp)"
  for ((i = 0; i < n; i++)); do
    (
      r="$(curl -s -o /dev/null -w '%{http_code} %{time_total}' --max-time 20 --cacert "$_f3d_racine" \
        "$url/api/v1/creneaux?date=$jour&praticien=sonde-f3-$RANDOM$RANDOM" 2>/dev/null)" || r="000 99"
      read -r code duree <<<"$r"
      if [[ "$code" == 200 ]]; then echo "$duree"; else echo 99; fi
    ) >>"$tmp" &
    if (((i + 1) % par == 0)); then wait; fi
  done
  wait
  sort -n "$tmp" | awk '{v[NR] = $1} END {if (NR == 0) print 99; else print v[int((NR + 1) / 2)]}'
  rm -f "$tmp"
}

# _f3d_latence_ok URL — la médiane est sous WB_F3_LATENCE_MAX (et la note dans _f3d_derniere_latence).
_f3d_derniere_latence=""
_f3d_latence_ok() {
  _f3d_derniere_latence="$(_f3d_latence "$1" 9 3)"
  _f3d_inferieur "$_f3d_derniere_latence" "${WB_F3_LATENCE_MAX:-1.0}"
}

# --- Alertmanager (S01, S04) ------------------------------------------------------------------------

# _f3d_routes ÉTIQUETTES… — récepteurs (séparés par des virgules) que la configuration CHARGÉE de
# l'Alertmanager du cluster donne à une alerte portant ces étiquettes (amtool, sur une copie locale).
_f3d_routes() {
  local tmp r
  command -v amtool >/dev/null 2>&1 || { echo "amtool-absent"; return 0; }
  tmp="$(mktemp)"
  am_api status 2>/dev/null | jq -r '.config.original // empty' >"$tmp" 2>/dev/null || true
  if [[ ! -s "$tmp" ]]; then rm -f "$tmp"; echo "config-illisible"; return 0; fi
  r="$(amtool config routes test --config.file="$tmp" "$@" 2>/dev/null | tail -n 1)" || r="erreur"
  rm -f "$tmp"
  echo "${r:-aucun}"
}

# _f3d_route_contient RÉCEPTEUR ÉTIQUETTES… — le récepteur fait partie de ceux de l'alerte.
_f3d_route_contient() {
  local rec="$1"
  shift
  [[ ",$(_f3d_routes "$@" | tr -d ' ')," == *",$rec,"* ]]
}

# _f3d_silences_larges 'JSON des étiquettes' — nombre de silences ACTIFS de plus de 24 h qui couvriraient
# une alerte portant ces étiquettes (évaluation des matchers : égalité, regex ancrée, négations).
_f3d_silences_larges() {
  am_api "silences" 2>/dev/null | jq -r --argjson l "$1" '
    [.[] | select(.status.state == "active")
     | select(((.endsAt | sub("\\.[0-9]+"; "") | fromdateiso8601) - (.startsAt | sub("\\.[0-9]+"; "") | fromdateiso8601)) > 86400)
     | select(all(.matchers[];
         (($l[.name] // "") as $v | .value as $val
          | (if .isRegex then ($v | test("^(?:" + $val + ")$")) else ($v == $val) end) as $m
          | if .isEqual == false then ($m | not) else $m end)))]
    | length' 2>/dev/null || echo "?"
}

# _f3d_regle_duree NOM 'regex sur la requête' — « for » (s) de la règle d'alerte chargée dans Prometheus.
_f3d_regle_duree() {
  prom_api "rules?type=alert" 2>/dev/null | jq -r --arg a "$1" --arg q "${2:-.}" \
    '[.data.groups[].rules[] | select(.name == $a) | select(.query | test($q))][0].duration // empty' 2>/dev/null || true
}

# --- Kubernetes ---------------------------------------------------------------------------------------

# _f3d_kq 'filtre jq' ARGS… — « kube get ARGS -o json » satisfait le filtre.
_f3d_kq() {
  local f="$1" j
  shift
  j="$(kube get "$@" -o json 2>/dev/null)" || return 1
  jq -e "$f" <<<"$j" >/dev/null 2>&1
}

# _f3d_api_ressources_conformes — chaque pod de l'API de prod a les ressources CPU du gabarit
# (Deployment « mediagenda », référencé par le Rollout).
_f3d_api_ressources_conformes() {
  local gab pods
  gab="$(kube -n "$_f3d_prod" get deployment mediagenda -o json 2>/dev/null |
    jq -c '([.spec.template.spec.containers[] | select(.name == "api")][0] // .spec.template.spec.containers[0]).resources // {} | {r: .requests.cpu, l: .limits.cpu}')" || return 1
  pods="$(kube -n "$_f3d_prod" get pods -l 'app.kubernetes.io/name=mediagenda,app.kubernetes.io/component=api' -o json 2>/dev/null)" || return 1
  jq -e --argjson g "$gab" '[.items[] | select(.metadata.deletionTimestamp == null)] as $p
    | ($p | length) > 0 and all($p[]; (([.spec.containers[] | select(.name == "api")][0] // .spec.containers[0]).resources // {}) as $r
        | {r: $r.requests.cpu, l: $r.limits.cpu} == $g)' <<<"$pods" >/dev/null 2>&1
}

# --- Livrables de l'exploitation ---------------------------------------------------------------------

# _f3d_rb_present RB-NNN — un runbook docs/exploitation/runbooks/RB-NNN-*.md existe sur main.
_f3d_rb_present() { _f3s_arbre "$_f3s_doc/runbooks" | grep -Eq "/$1([-_.].*)?\.md$"; }
# _f3d_ticket_present PLAT-NNNN — un ticket de plateforme/medisphere cite l'identifiant.
_f3d_ticket_present() { (($(_f3s_ticket_inc "$1") >= 1)); }

# --- Main courante : nombre d'états exigé selon la durée (S07) -----------------------------------------

_f3d_etats_attendus() {
  local d="${1:-0}"
  [[ "$d" =~ ^-?[0-9]+$ ]] || { echo 1; return; }
  ((d < 15)) && { echo 1; return; }
  echo $((d / 15))
}

# --- S07 : état de réparation de la panne tirée -----------------------------------------------------

_f3d_s07_tirage() { cat "${XDG_STATE_HOME:-$HOME/.local/state}/workbook/F3-S07/tirage" 2>/dev/null || true; }

_f3d_s07_m15_40() {
  _f3d_kq '.status.conditions[]? | select(.type == "Ready" and .status == "True")' clusterissuer step-ca-acme || return 1
  if kube -n wb-essais get certificate joker-repetition >/dev/null 2>&1; then
    _f3d_kq '.status.conditions[]? | select(.type == "Ready" and .status == "True")' -n wb-essais certificate joker-repetition
  fi
}
_f3d_s07_m16_41() {
  _f3d_kq '.status.conditions[]? | select(.type == "ContinuousArchiving" and .status == "True")' \
    -n "$_f3d_recette" clusters.postgresql.cnpg.io mediagenda-db
}
_f3d_s07_m27_20() {
  rabbitmq_api "queues/medinotif-recette/notifications" 2>/dev/null |
    jq -e '(.consumers // 0) >= 1 and (.messages_ready // 0) < 100' >/dev/null 2>&1
}
_f3d_s07_m27_22() {
  local e
  check_http_silencieux() { [[ "$(curl -s -o /dev/null -w '%{http_code}' --max-time "$WB_TIMEOUT" --cacert "$_f3d_racine" "$1")" == 200 ]]; }
  check_http_silencieux "${WB_F3_RECETTE_URL:-https://mediagenda-recette.apps.par1.medisphere.internal}/pret" || return 1
  e="$(_f3d_prom "sum(rate(mediagenda_cache_total{namespace=\"$_f3d_recette\", resultat=\"erreur\"}[5m]))")"
  [[ -z "$e" ]] || _f3d_inferieur "$e" 0.01
}
_f3d_s07_m28_19() {
  _f3d_kq '(.metadata.annotations["autoscaling.keda.sh/paused"] // "false") != "true"
    and any(.status.conditions[]?; .type == "Ready" and .status == "True")
    and all(.spec.triggers[]?; (.metadata.vhostName // "medinotif-recette") == "medinotif-recette")' \
    -n medinotif-recette scaledobjects.keda.sh medinotif
}

# _f3d_s07_repare — prédicat de réparation de la panne tirée (code 2 : tirage inconnu).
_f3d_s07_repare() {
  case "$(_f3d_s07_tirage)" in
    15:40) _f3d_s07_m15_40 ;;
    16:41) _f3d_s07_m16_41 ;;
    27:20) _f3d_s07_m27_20 ;;
    27:22) _f3d_s07_m27_22 ;;
    28:19) _f3d_s07_m28_19 ;;
    *) return 2 ;;
  esac
}

# --- Ceph et Proxmox (S08) -----------------------------------------------------------------------------

_f3d_ceph_drapeaux_ok() {
  local f
  f="$(_f3s_ceph_json "osd dump" | jq -r '.flags // ""' 2>/dev/null)" || return 1
  ! grep -Eq '(^|,)(noout|norecover|nobackfill|norebalance|pause|noup|nodown|noin)(,|$)' <<<"$f"
}
_f3d_ceph_osds_ok() {
  _f3s_ceph_json "osd stat" | jq -e '(.num_osds // .osdmap.num_osds) as $n | $n > 0
    and (.num_up_osds // .osdmap.num_up_osds) == $n and (.num_in_osds // .osdmap.num_in_osds) == $n' >/dev/null 2>&1
}
_f3d_ceph_latence_max() {
  _f3s_ceph_json "osd perf" | jq -r '[(.osdstats.osd_perf_infos // .osd_perf_infos)[] | .perf_stats.commit_latency_ms] | max // 0' 2>/dev/null || echo 9999
}
_f3d_ceph_quota_ok() {
  local pool="${WB_F3_S08_POOL:-k8s-rbd}" q s
  q="$(_f3s_ceph_json "osd pool get-quota $pool" | jq -r '.quota_max_bytes // empty' 2>/dev/null)" || return 1
  [[ "$q" =~ ^[0-9]+$ ]] || return 1
  ((q == 0)) && return 0
  s="$(_f3s_ceph_json "df" | jq -r --arg p "$pool" '.pools[] | select(.name == $p) | .stats.stored // .stats.bytes_used' 2>/dev/null)" || return 1
  [[ "$s" =~ ^[0-9]+$ ]] && ((q >= s * 3 / 2))
}
# _f3d_vm_sans_limite_es VMID — aucun disque de la VM n'a de limite d'E/S (qm config, en lecture sur pve01).
_f3d_vm_sans_limite_es() {
  local c
  c="$(remote "$WB_PVE_HOST" "qm config $1" 2>/dev/null </dev/null)" || return 1
  # Options de limite de Proxmox : iops, iops_rd, iops_wr, mbps, mbps_rd, mbps_wr (et leurs *_max).
  [[ -n "$c" ]] && ! grep -E '^(scsi|virtio|sata|ide)[0-9]+: ' <<<"$c" | grep -Eq '[:,](iops|mbps)(_rd|_wr)?(_max)?='
}
