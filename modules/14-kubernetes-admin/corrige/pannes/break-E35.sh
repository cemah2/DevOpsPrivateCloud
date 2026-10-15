# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E35.sh — M14-E35 « Panne : un nœud est NotReady »
#
# Cible : un travailleur tiré au hasard parmi les nœuds Ready (mémorisé dans
# ~/.local/state/workbook/M14-E35/cible). Jamais un nœud de contrôle.
# Variantes :
#   1. kubelet arrêté ET désactivé (« systemctl disable --now ») ;
#   2. option retirée en 1.35 (--pod-infra-container-image) ajoutée dans /etc/default/kubelet :
#      le kubelet ne démarre plus ;
#   3. /etc/containerd/config.toml rendu invalide (table TOML non fermée) puis containerd relancé :
#      le runtime ne démarre plus (les conteneurs déjà lancés survivent par leurs shims) ;
#   4. swap réactivé (fichier /swap-infoger.img + /etc/fstab) puis kubelet relancé (failSwapOn) ;
#   5. certificat client du kubelet remplacé par un certificat signé par une autre autorité (« restauré
#      depuis la sauvegarde d'un autre cluster ») : l'API répond Unauthorized ;
#   6. /var/lib/containerd rempli à 96 % par un gros fichier (fallocate) : DiskPressure, évictions.
# Rien n'est détruit : les fichiers modifiés sont sauvegardés dans /var/lib/workbook/ du nœud.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m14-commun.sh
source "$WB_ROOT/modules/14-kubernetes-admin/corrige/pannes/_m14-commun.sh"

_e35_pression_disque() {
  wb_kubectl get node "$1" -o json 2>/dev/null |
    jq -e '[.status.conditions[] | select(.type == "DiskPressure" and .status == "True")] | length == 1' >/dev/null 2>&1
}

_m14E35_une() {
  local n="$1" h rc=0
  local -a prets=()
  for h in "${_M14_W[@]}"; do m14_noeud_pret "$h" && prets+=("$h"); done
  ((${#prets[@]} >= 2)) || return 1
  h="$(m14_hasard "${prets[@]}")"
  case "$n" in
    1)
      m14_wb_exec "$h" >/dev/null <<'EOF' || rc=$?
systemctl is-active -q kubelet || exit 10
if systemctl is-enabled -q kubelet; then echo enabled > "$WB_DIR/$WB_EX.kubelet-etat"; fi
systemctl disable --now kubelet >/dev/null 2>&1
journal "kubelet arrêté et désactivé"
EOF
      ;;
    2)
      m14_wb_exec "$h" >/dev/null <<'EOF' || rc=$?
f=/etc/default/kubelet
grep -qs -- '--pod-infra-container-image' "$f" /var/lib/kubelet/kubeadm-flags.env && exit 10
sauver "$f"
ancien="$( [ -f "$f" ] && . "$f" 2>/dev/null; printf '%s' "${KUBELET_EXTRA_ARGS:-}")"
touch "$f"
sed -i '/^KUBELET_EXTRA_ARGS=/d' "$f"
printf '# IG-2231 (InfoGér) : image sandbox explicite, comme sur l ancien cluster\nKUBELET_EXTRA_ARGS="%s--pod-infra-container-image=registry.par1.medisphere.internal/k8s/pause:3.10.2"\n' \
  "${ancien:+$ancien }" >> "$f"
systemctl restart kubelet >/dev/null 2>&1 || true
journal "option --pod-infra-container-image ajoutée dans $f, kubelet relancé"
EOF
      ;;
    3)
      m14_wb_exec "$h" >/dev/null <<'EOF' || rc=$?
f=/etc/containerd/config.toml
[ -f "$f" ] || exit 10
grep -q 'IG-2232' "$f" && exit 10
sauver "$f"
cat >> "$f" <<'TOML'

# IG-2232 (InfoGér) : miroir docker.io « comme avant »
[plugins."io.containerd.cri.v1.images".registry.mirrors."docker.io"
  endpoint = ["https://registry.par1.medisphere.internal/v2/dockerhub"]
TOML
systemctl restart containerd >/dev/null 2>&1 || true
sleep 3
if systemctl is-active -q containerd; then restaurer_fichiers; systemctl restart containerd; exit 10; fi
journal "config.toml de containerd rendu invalide, containerd relancé (en échec)"
EOF
      ;;
    4)
      m14_wb_exec "$h" >/dev/null <<'EOF' || rc=$?
s=/swap-infoger.img
[ -n "$(swapon --show --noheadings 2>/dev/null)" ] && exit 10
[ -e "$s" ] && exit 10
sauver /etc/fstab
sauver "$s"
fallocate -l 1G "$s" && chmod 600 "$s" && mkswap "$s" >/dev/null && swapon "$s" || { restaurer_fichiers; exit 1; }
printf '%s none swap sw 0 0  # IG-2233 : mémoire de secours\n' "$s" >> /etc/fstab
systemctl restart kubelet >/dev/null 2>&1 || true
sleep 8
if systemctl is-active -q kubelet && ! journalctl -u kubelet --since -20s --no-pager 2>/dev/null | grep -qi swap; then
  swapoff "$s"; restaurer_fichiers; systemctl restart kubelet; exit 10
fi
journal "swap $s activé et ajouté à fstab, kubelet relancé"
EOF
      ;;
    5)
      m14_wb_exec "$h" >/dev/null <<'EOF' || rc=$?
p=/var/lib/kubelet/pki
[ -L "$p/kubelet-client-current.pem" ] || exit 10
grep -q "client-certificate: $p/kubelet-client-current.pem" /etc/kubernetes/kubelet.conf || exit 10
[ -e "$WB_DIR/$WB_EX.pki.tar" ] && exit 10
tar -C /var/lib/kubelet -cpf "$WB_DIR/$WB_EX.pki.tar" pki && chmod 600 "$WB_DIR/$WB_EX.pki.tar"
d="$(mktemp -d)"
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$d/ca.key" -out "$d/ca.crt" -days 3650 -subj /CN=kubernetes >/dev/null 2>&1
openssl req -new -newkey rsa:2048 -nodes -keyout "$d/k.pem" -out "$d/r.csr" \
  -subj "/O=system:nodes/CN=system:node:$(hostname -s)" >/dev/null 2>&1
printf 'keyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=clientAuth\n' > "$d/ext"
openssl x509 -req -in "$d/r.csr" -CA "$d/ca.crt" -CAkey "$d/ca.key" -CAcreateserial -CAserial "$d/srl" \
  -days 365 -sha256 -extfile "$d/ext" -out "$d/c.pem" >/dev/null 2>&1 || { rm -rf "$d"; exit 1; }
n="$p/kubelet-client-$(date -d '-3 days' +%Y-%m-%d-%H-%M-%S).pem"
cat "$d/c.pem" "$d/k.pem" > "$n" && chmod 600 "$n"
rm -rf "$d"
ln -sfn "$n" "$p/kubelet-client-current.pem"
printf '%s\n' "$n" > "$WB_DIR/$WB_EX.faux-certificat"
systemctl restart kubelet >/dev/null 2>&1 || true
journal "certificat client du kubelet remplacé par $n (autre autorité), kubelet relancé"
EOF
      ;;
    6)
      m14_wb_exec "$h" >/dev/null <<'EOF' || rc=$?
f=/var/lib/containerd/export-images-infoger.tar
[ -e "$f" ] && exit 10
read -r taille dispo < <(df -B1 --output=size,avail /var/lib/containerd | tail -n 1)
a=$((dispo - taille * 4 / 100))
[ "$a" -gt 1073741824 ] || exit 10
sauver "$f"
fallocate -l "$a" "$f" || { restaurer_fichiers; exit 1; }
journal "fichier $f de $a octets créé (disque à 96 %)"
EOF
      ;;
  esac
  ((rc == 0)) || return "$rc"
  m14_ecrire E35 cible "$h"
  m14_journal E35 "variante $n posée sur $h"
  if [[ "$n" == 6 ]]; then
    m14_attendre 150 _e35_pression_disque "$h" || { _e35_defaire 6 "$h"; m14_oublier E35 cible; return 10; }
  else
    m14_attendre 150 m14_noeud_pas_pret "$h" || { _e35_defaire "$n" "$h"; m14_oublier E35 cible; return 10; }
  fi
}

# _e35_defaire N NŒUD — retire la variante N si elle est encore en place (et seulement dans ce cas).
_e35_defaire() {
  local n="$1" h="$2"
  case "$n" in
    1)
      m14_wb_exec "$h" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur $h (kubelet)"
if [ -f "$WB_DIR/$WB_EX.kubelet-etat" ] && ! systemctl is-enabled -q kubelet; then systemctl enable kubelet >/dev/null 2>&1; fi
systemctl is-active -q kubelet || { systemctl start kubelet; journal "annulation : kubelet relancé"; }
rm -f "$WB_DIR/$WB_EX.kubelet-etat"
EOF
      ;;
    2 | 3 | 4 | 6)
      m14_wb_exec "$h" N="$n" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur $h"
case "$N" in
  2) if grep -qs -- 'IG-2231' /etc/default/kubelet; then restaurer_fichiers; systemctl restart kubelet; journal "annulation : /etc/default/kubelet rétabli"; else oublier_fichiers; fi ;;
  3) if grep -qs -- 'IG-2232' /etc/containerd/config.toml; then restaurer_fichiers; systemctl restart containerd; systemctl restart kubelet; journal "annulation : config.toml rétabli"; else oublier_fichiers; fi ;;
  4) if swapon --show=NAME --noheadings 2>/dev/null | grep -qx /swap-infoger.img; then swapoff /swap-infoger.img; fi
     if [ -e /swap-infoger.img ] || grep -qs 'IG-2233' /etc/fstab; then restaurer_fichiers; rm -f /swap-infoger.img; systemctl restart kubelet; journal "annulation : swap retiré"; else oublier_fichiers; fi ;;
  6) restaurer_fichiers; journal "annulation : fichier de remplissage supprimé" ;;
esac
EOF
      ;;
    5)
      m14_wb_exec "$h" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur $h (certificat du kubelet)"
p=/var/lib/kubelet/pki
faux="$(cat "$WB_DIR/$WB_EX.faux-certificat" 2>/dev/null)"
if [ -n "$faux" ] && [ "$(readlink "$p/kubelet-client-current.pem")" = "$faux" ] && [ -f "$WB_DIR/$WB_EX.pki.tar" ]; then
  rm -rf "$p" && tar -C /var/lib/kubelet -xpf "$WB_DIR/$WB_EX.pki.tar"
  systemctl restart kubelet
  journal "annulation : dossier pki du kubelet rétabli"
elif [ -n "$faux" ]; then
  rm -f -- "$faux"
fi
rm -f "$WB_DIR/$WB_EX.pki.tar" "$WB_DIR/$WB_EX.faux-certificat"
EOF
      ;;
  esac
}

panne_E35_v1() { m14_preparer && m14_essayer E35 6 1; }
panne_E35_v2() { m14_preparer && m14_essayer E35 6 2; }
panne_E35_v3() { m14_preparer && m14_essayer E35 6 3; }
panne_E35_v4() { m14_preparer && m14_essayer E35 6 4; }
panne_E35_v5() { m14_preparer && m14_essayer E35 6 5; }
panne_E35_v6() { m14_preparer && m14_essayer E35 6 6; }

verifier_E35() {
  local h
  h="$(m14_lire E35 cible)"
  [[ -n "$h" ]] || return 1
  case "$WB_VAR" in
    6) _e35_pression_disque "$h" ;;
    *) m14_noeud_pas_pret "$h" ;;
  esac
}

annuler_E35() {
  local h
  h="$(m14_lire E35 cible)"
  if [[ -n "$h" ]]; then
    case "${WB_VAR:-}" in
      [1-6]) _e35_defaire "$WB_VAR" "$h" ;;
      *) local v; for v in 1 2 3 4 5 6; do _e35_defaire "$v" "$h"; done ;;
    esac
    m14_journal E35 "annulation ($h)"
  fi
  m14_oublier E35 cible
}

resume_E35() {
  local h
  h="$(m14_lire E35 cible)"
  case "${WB_VAR:-}" in
    6) echo "Le nœud ${h:-?} signale une pression disque et des pods en sont évincés." ;;
    *) echo "Le nœud ${h:-?} est NotReady : ses pods ne sont plus suivis." ;;
  esac
}

symptome_E35() {
  local h
  h="$(m14_lire E35 cible)"
  case "${WB_VAR:-}" in
    6)
      wb_symptome "Ticket INC-4135 — De : Nadia Roussel" \
        "Depuis une heure, des pods de plusieurs équipes sont « Evicted » puis recréés ailleurs," \
        "toujours depuis le nœud $h. Le nœud est encore Ready, mais il refuse les nouveaux pods." \
        "InfoGér est intervenu dessus hier (« ménage et export des images pour l'audit »)." \
        "Rends le nœud pleinement utilisable et dis-moi pourquoi personne n'a été alerté avant." \
        "" \
        "Temps cible : 30 min. Contrôle : lab/bin/check 14 35"
      ;;
    *)
      wb_symptome "Ticket INC-4135 — De : Nadia Roussel" \
        "Alerte de 6 h 40 : le nœud $h est NotReady depuis plusieurs minutes." \
        "InfoGér y est intervenu cette nuit (« maintenance de routine »). Les pods qui y tournaient" \
        "semblent encore répondre, mais Kubernetes ne sait plus rien d'eux. Lucas propose de" \
        "« supprimer le nœud et de le rejoindre » : n'en fais rien avant d'avoir trouvé la cause." \
        "" \
        "Temps cible : 30 min. Contrôle : lab/bin/check 14 35"
      ;;
  esac
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 14 E35 6 "$@"; }
fi
