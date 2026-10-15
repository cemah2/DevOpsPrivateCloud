#!/usr/bin/env bash
# shellcheck disable=SC2029  # chemins et options expansés côté adm01, volontairement
# outils/kube-bench.sh — passage de kube-bench en APERÇU sur un nœud (M18-E15). Ne corrige rien.
# Usage (depuis adm01) : outils/kube-bench.sh HÔTE RÉFÉRENTIEL [CIBLES]
#   ex. outils/kube-bench.sh rke2-01 rke2-cis-1.9 master,node,etcd,policies
#       outils/kube-bench.sh rke2-01 cis-1.12     master,node,etcd,policies
#       outils/kube-bench.sh k3s01   k3s-cis-1.9  master,node,etcd,policies
# Le binaire est téléchargé une fois sur adm01 (empreinte vérifiée sur checksums.txt de la publication),
# copié sur le nœud dans un dossier temporaire avec son dossier cfg/, lancé en root, puis effacé.
# Rapport JSON écrit dans docs/kubernetes/distributions/durcissement/ de ~/medisphere.
set -euo pipefail

hote="$1"; ref="$2"; cibles="${3:-master,node,etcd,policies}"
version=0.16.0
cache="$HOME/.cache/kube-bench/$version"
archive="kube-bench_${version}_linux_amd64.tar.gz"
url="https://github.com/aquasecurity/kube-bench/releases/download/v${version}"
sortie="${WB_DEPOT:-$HOME/medisphere}/docs/kubernetes/distributions/durcissement/kube-bench-${hote}-${ref}-$(date +%F).json"

mkdir -p "$cache" "$(dirname "$sortie")"
if [[ ! -x "$cache/kube-bench" ]]; then
  curl -fsSL -o "$cache/$archive" "$url/$archive"
  curl -fsSL -o "$cache/checksums.txt" "$url/kube-bench_${version}_checksums.txt"   # nom vérifié sur la publication 0.16.0
  (cd "$cache" && grep " $archive\$" checksums.txt | sha256sum -c -)
  tar -C "$cache" -xzf "$cache/$archive"
fi
[[ -d "$cache/cfg/$ref" ]] || { echo "référentiel $ref absent de cfg/ (ls $cache/cfg)" >&2; exit 1; }

dist="/tmp/kube-bench.$$"
ssh "$hote" "mkdir -m 700 $dist"
tar -C "$cache" -czf - kube-bench cfg | ssh "$hote" "tar -C $dist -xzf -"
# --benchmark force le référentiel : aucun ne correspond à Kubernetes 1.36, kube-bench ne devine pas.
ssh "$hote" "sudo -n $dist/kube-bench run --config-dir $dist/cfg --benchmark $ref --targets $cibles --json" > "$sortie" || true
ssh "$hote" "rm -rf $dist"

jq -r '.Totals | "PASS \(.total_pass)  FAIL \(.total_fail)  WARN \(.total_warn)  INFO \(.total_info)"' "$sortie"
echo "rapport : $sortie"
