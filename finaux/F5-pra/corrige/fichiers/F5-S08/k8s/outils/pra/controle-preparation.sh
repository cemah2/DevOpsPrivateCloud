#!/usr/bin/env bash
# shellcheck disable=SC2016  # commandes distantes entre apostrophes (évaluées sur l'hôte distant)
# plateforme/k8s — outils/pra/controle-preparation.sh (F5-S08, INC-6108, PLAT-3508)
#
# « PAR2 est-il prêt ? » — contrôle de préparation du site de repli, en LECTURE SEULE.
# Lancé chaque nuit par une minuterie de adm02 (indicateur pour la supervision) et au début de RB-350.
# Chaque contrôle regarde un EFFET (âge de la dernière donnée arrivée, capacité à planifier, capacité à
# démarrer), pas seulement l'état d'un processus : les trois pannes de la répétition (filer.sync arrêté,
# nœud cordonné, VM verrouillée) passaient tous les voyants « processus ».
#
# Usage :
#   controle-preparation.sh [--textfile FICHIER.prom]
#     --textfile : écrit aussi les résultats au format du textfile collector de node_exporter
#                  (pra_preparation_ok{controle="…"} 0|1 et pra_par2_pret 0|1), par renommage atomique.
# Code de sortie : 0 si tout est prêt, 1 sinon, 2 si un outil manque.
#
# Variables (défauts entre parenthèses) :
#   KUBECONFIG_PAR2   kubeconfig de k8s-par2 avec droit d'exec dans mediagenda-prod (~/.kube/k8s-par2.config)
#   HP01              hôte SSH de hp01, compte root (root@pbs01)
#   S3_02             hôte SSH de s3-02, compte admin (admin@s3-02.par2.medisphere.internal)
#   DNS01, DNS03      récurseurs de PAR1 et PAR2 (10.10.20.10, 10.20.20.11)
#   RPO_MAX_S         âge maximal du dernier témoin vu à PAR2 (900)
#   MEMOIRE_MIN_GIO   mémoire disponible minimale sur hp01 pour une reprise (3)
set -euo pipefail

KUBECONFIG_PAR2="${KUBECONFIG_PAR2:-$HOME/.kube/k8s-par2.config}"
HP01="${HP01:-root@pbs01}"
S3_02="${S3_02:-admin@s3-02.par2.medisphere.internal}"
DNS01="${DNS01:-10.10.20.10}"
DNS03="${DNS03:-10.20.20.11}"
RPO_MAX_S="${RPO_MAX_S:-900}"
MEMOIRE_MIN_GIO="${MEMOIRE_MIN_GIO:-3}"
NS=mediagenda-prod
CLUSTER=mediagenda-db-par2
NOEUD=k8s-par2-n01
VMID_BAO=1055

textfile=""
if [[ "${1:-}" == "--textfile" ]]; then
  textfile="${2:?--textfile attend un chemin}"
fi

for outil in kubectl jq dig ssh; do
  command -v "$outil" >/dev/null 2>&1 || { echo "outil manquant : $outil" >&2; exit 2; }
done

k2() { kubectl --kubeconfig "$KUBECONFIG_PAR2" --request-timeout=15s "$@"; }
ssh_() { ssh -o BatchMode=yes -o ConnectTimeout=5 "$@"; }

declare -A resultat=()
ko=0
noter() { # noter NOM 0|1 "message"
  resultat[$1]=$2
  if (($2 == 1)); then printf '[OK] %-22s %s\n' "$1" "$3"; else printf '[KO] %-22s %s\n' "$1" "$3"; ko=1; fi
}

# 1. RPO de bout en bout : âge du dernier témoin lu sur la réplique de PAR2.
temoin() {
  local pod age
  pod="$(k2 -n "$NS" get cluster "$CLUSTER" -o jsonpath='{.status.currentPrimary}' 2>/dev/null)" || pod=""
  [[ -n "$pod" ]] || { noter temoin 0 "réplique $CLUSTER sans instance désignée"; return; }
  age="$(k2 -n "$NS" exec "$pod" -c postgres -- psql -d mediagenda -Atc \
    "SELECT COALESCE(EXTRACT(EPOCH FROM now() - max(cree_le))::int, 999999) FROM rendez_vous WHERE praticien = 'PRA-TEMOIN'" 2>/dev/null)" || age=""
  if [[ "$age" =~ ^[0-9]+$ ]] && ((age <= RPO_MAX_S)); then
    noter temoin 1 "dernier témoin vu à PAR2 il y a ${age} s"
  else
    noter temoin 0 "dernier témoin vu à PAR2 il y a ${age:-?} s (maximum ${RPO_MAX_S} s)"
  fi
}

# 2. La réplication des objets tourne (unité qui lance « weed filer.sync »).
filersync() {
  # Unités simples ou instances (activées ou chargées) d'une unité modèle « @ » : toutes doivent tourner.
  local etat
  etat="$(ssh_ "$S3_02" 'for f in /etc/systemd/system/*.service; do
      grep -qs "filer.sync" "$f" || continue; b=${f##*/}
      case "$b" in
        *@.service) p=${b%.service}
          find /etc/systemd/system -path "*.wants/*" -name "${p}?*.service" -printf "%f\n" 2>/dev/null
          systemctl list-units --all --type=service --no-legend --plain "${p}*" 2>/dev/null | awk "{ print \$1 }" ;;
        *) echo "$b" ;;
      esac
    done | sort -u | while read -r u; do systemctl is-active --quiet "$u" && echo "ok $u" || echo "ko $u"; done' 2>/dev/null)" || etat=""
  if [[ -n "$etat" ]] && ! grep -q '^ko ' <<<"$etat"; then
    noter filer_sync 1 "unités filer.sync actives sur s3-02"
  else
    noter filer_sync 0 "unité filer.sync absente ou arrêtée sur s3-02 : $(grep '^ko ' <<<"$etat" | cut -d' ' -f2 | paste -sd' ' -)"
  fi
}

# 3. On peut planifier un pod à PAR2.
noeud() {
  local j
  j="$(k2 get node "$NOEUD" -o json 2>/dev/null)" || { noter noeud 0 "API de k8s-par2 injoignable"; return; }
  if jq -e '([.status.conditions[]? | select(.type == "Ready")][0].status == "True") and ((.spec.unschedulable // false) | not)
      and ([.spec.taints[]? | select(.effect == "NoSchedule" or .effect == "NoExecute")] | length == 0)' >/dev/null <<<"$j"; then
    noter noeud 1 "$NOEUD Ready, planifiable, sans taint bloquant"
  else
    noter noeud 0 "$NOEUD non prêt, cordonné ou porteur d'un taint bloquant"
  fi
}

# 4. Le coffre de secours démarrerait (arrêté, sans verrou).
coffre() {
  local c s
  c="$(ssh_ "$HP01" "qm config $VMID_BAO" 2>/dev/null)" || { noter bao_par2 0 "VM $VMID_BAO introuvable"; return; }
  s="$(ssh_ "$HP01" "qm status $VMID_BAO" 2>/dev/null | awk '{print $2}')" || s=""
  if grep -q '^lock:' <<<"$c"; then
    noter bao_par2 0 "VM $VMID_BAO verrouillée ($(grep '^lock:' <<<"$c"))"
  elif [[ "$s" != stopped ]]; then
    noter bao_par2 0 "VM $VMID_BAO dans l'état « ${s:-?} » (veille attendue : stopped)"
  else
    noter bao_par2 1 "VM $VMID_BAO arrêtée, sans verrou"
  fi
}

# 5. Le DNS de PAR2 suit celui de PAR1 (si PAR1 répond).
dns() {
  local s1 s3
  s3="$(dig +short +time=3 +tries=1 "@$DNS03" medisphere.internal SOA | awk '{print $3}')" || s3=""
  s1="$(dig +short +time=3 +tries=1 "@$DNS01" medisphere.internal SOA | awk '{print $3}')" || s1=""
  if [[ -z "$s3" ]]; then
    noter dns03 0 "dns03 ne sert pas medisphere.internal"
  elif [[ -z "$s1" || "$s1" == "$s3" ]]; then
    noter dns03 1 "medisphere.internal servi par dns03 (série $s3${s1:+, identique à dns01})"
  else
    noter dns03 0 "série de medisphere.internal : dns03 $s3, dns01 $s1 (transfert en retard)"
  fi
}

# 6. La livraison à PAR2 fonctionne (Argo CD lit ses miroirs).
argocd() {
  local n
  n="$(k2 -n argocd get applications.argoproj.io -o json 2>/dev/null |
    jq '[.items[] | select(any(.status.conditions[]?; .type | test("ComparisonError|SyncError")))] | length' 2>/dev/null)" || n=""
  if [[ "$n" == 0 ]]; then noter argocd 1 "aucune Application en erreur"; else noter argocd 0 "Applications en erreur : ${n:-API injoignable}"; fi
}

# 7. hp01 a la mémoire d'une reprise (bao-par2 + kms01 restauré + applications).
memoire() {
  local dispo
  dispo="$(ssh_ "$HP01" "awk '/^MemAvailable:/ {print int(\$2 / 1048576)}' /proc/meminfo" 2>/dev/null)" || dispo=""
  if [[ "$dispo" =~ ^[0-9]+$ ]] && ((dispo >= MEMOIRE_MIN_GIO)); then
    noter memoire_hp01 1 "${dispo} Gio disponibles sur hp01"
  else
    noter memoire_hp01 0 "${dispo:-?} Gio disponibles sur hp01 (minimum ${MEMOIRE_MIN_GIO})"
  fi
}

temoin
filersync
noeud
coffre
dns
argocd
memoire

if [[ -n "$textfile" ]]; then
  tmp="$(mktemp "${textfile}.XXXXXX")"
  {
    echo "# HELP pra_preparation_ok Contrôle de préparation de PAR2 (1 = vert)."
    echo "# TYPE pra_preparation_ok gauge"
    for c in "${!resultat[@]}"; do echo "pra_preparation_ok{controle=\"$c\"} ${resultat[$c]}"; done
    echo "# HELP pra_par2_pret Tous les contrôles de préparation de PAR2 sont verts."
    echo "# TYPE pra_par2_pret gauge"
    echo "pra_par2_pret $((1 - ko))"
  } >"$tmp"
  chmod 644 "$tmp"
  mv -f "$tmp" "$textfile"
fi

if ((ko)); then echo "PAR2 N'EST PAS PRÊT."; exit 1; fi
echo "PAR2 prêt."
