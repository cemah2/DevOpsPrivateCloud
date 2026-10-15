# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E19.sh — M18-E19 « Panne : le nœud k3s ne rejoint plus le cluster »
#
# Banc de M18-E14 : k3s-ha01 (serveur, etcd), k3s-ha02 (agent). La panne touche l'agent (ou, pour la
# variante 4, le seul pare-feu local du serveur) puis redémarre k3s-agent : l'agent ne se réenregistre
# plus et le nœud passe NotReady. Variantes :
#   1. jeton de l'agent remplacé par un jeton au format sécurisé d'un AUTRE cluster (empreinte de CA
#      différente) : l'agent refuse la CA du serveur avant même de s'authentifier ;
#   2. adresse du serveur sur le port 9345 (superviseur de RKE2) au lieu de 6443 : connexion refusée ;
#   3. horloge de l'agent reculée de 400 jours, service de temps arrêté : certificats « pas encore
#      valides » (injection et annulation par l'agent QEMU : un certificat SSH serait refusé lui aussi) ;
#   4. pare-feu local de k3s-ha01 (table nftables dédiée) qui jette le TCP 6443 venant de l'agent.
# La configuration de l'agent est cherchée dans /etc/rancher/k3s/config.yaml (server:, token:,
# token-file:) puis dans le fichier d'environnement de l'unité (K3S_URL, K3S_TOKEN).
# Annulation : fichiers d'origine remis (sauvegardes du prélude), horloge remise à l'heure de adm01 et
# service de temps relancé, table nftables supprimée, k3s-agent redémarré.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m18-commun.sh
source "$WB_ROOT/modules/18-distributions/corrige/pannes/_m18-commun.sh"

_E19_AGENT=k3s-ha02
_E19_SERVEUR=k3s-ha01

_e19_ip_agent() {
  m18_k "$_M18_KC_K3SHA" get node "$_E19_AGENT" \
    -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null
}

_mE19_une() {
  local v="$1" rc=0 ip faux
  case "$v" in
    1)
      faux="K10$(head -c 32 /dev/urandom | sha256sum | cut -c1-64)::server:$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
      m18_exec "$_E19_AGENT" FAUX="$faux" <<'EOF' || rc=$?
f=/etc/rancher/k3s/config.yaml
env=/etc/systemd/system/k3s-agent.service.env
if [ -f "$f" ] && grep -Eq '^token-file:' "$f"; then
  tf="$(sed -n 's/^token-file:[[:space:]]*//p' "$f" | tr -d "\"'" | head -n 1)"
  [ -f "$tf" ] || exit 10
  sauver "$tf"
  printf '%s\n' "$FAUX" > "$tf"
elif [ -f "$f" ] && grep -Eq '^token:' "$f"; then
  sauver "$f"
  sed -i "s|^token:.*|token: \"$FAUX\"|" "$f"
elif [ -f "$env" ] && grep -Eq '^K3S_TOKEN=' "$env"; then
  sauver "$env"
  sed -i "s|^K3S_TOKEN=.*|K3S_TOKEN='$FAUX'|" "$env"
  systemctl daemon-reload
else
  exit 10
fi
journal "jeton de l'agent remplacé par un jeton d'un autre cluster (empreinte de CA différente)"
systemctl restart --no-block k3s-agent
EOF
      ;;
    2)
      m18_exec "$_E19_AGENT" <<'EOF' || rc=$?
f=/etc/rancher/k3s/config.yaml
env=/etc/systemd/system/k3s-agent.service.env
if [ -f "$f" ] && grep -Eq '^server:[[:space:]]*"?https://[^:/"]+:6443' "$f"; then
  sauver "$f"
  sed -i -E 's#^(server:[[:space:]]*"?https://[^:/"]+):6443#\1:9345#' "$f"
elif [ -f "$env" ] && grep -Eq "^K3S_URL=['\"]?https://[^:/'\"]+:6443" "$env"; then
  sauver "$env"
  sed -i -E "s#^(K3S_URL=['\"]?https://[^:/'\"]+):6443#\1:9345#" "$env"
  systemctl daemon-reload
else
  exit 10
fi
journal "adresse du serveur passée sur le port 9345 (superviseur RKE2)"
systemctl restart --no-block k3s-agent
EOF
      ;;
    3)
      m18_exec_invite "$_E19_AGENT" ADM="$(date +%s)" <<'EOF' || rc=$?
svc=""
for s in chrony chronyd systemd-timesyncd; do
  if systemctl is-active -q "$s"; then svc="$s"; break; fi
done
[ -n "$svc" ] || exit 10
printf '%s\n' "$svc" > "$WB_DIR/$WB_EX.service-temps"
systemctl stop "$svc"
[ "$svc" = systemd-timesyncd ] && timedatectl set-ntp false
date -s "@$((ADM - 400 * 86400))" >/dev/null
journal "horloge reculée de 400 jours, service $svc arrêté"
systemctl restart --no-block k3s-agent
EOF
      # wb_exec_invite ne distingue pas « sans effet » d'un échec : l'effet est vérifié par verifier_E19.
      ((rc == 0)) || return 1
      m18_ecrire E19 horloge 1
      ;;
    4)
      ip="$(_e19_ip_agent)" || ip=""
      [[ "$ip" =~ ^[0-9.]+$ ]] || return 10
      m18_exec "$_E19_SERVEUR" AGENT="$ip" <<'EOF' || rc=$?
command -v nft >/dev/null 2>&1 || exit 10
nft list table inet wb_m18_e19 >/dev/null 2>&1 && exit 10
nft -f - <<NFT || exit 1
table inet wb_m18_e19 {
  chain entree {
    type filter hook input priority -10; policy accept;
    ip saddr $AGENT tcp dport 6443 drop
  }
}
NFT
journal "nftables : table inet wb_m18_e19, TCP 6443 jeté depuis $AGENT"
EOF
      ((rc == 0)) || return "$rc"
      m18_ecrire E19 nft 1
      m18_exec "$_E19_AGENT" <<'EOF' || return 1
systemctl restart --no-block k3s-agent
EOF
      ;;
  esac
  ((rc == 0)) || return "$rc"
  m18_journal E19 "variante $v injectée"
}

_e19_sain() {
  m18_noeud_pret "$_M18_KC_K3SHA" "$_E19_AGENT" && m18_noeud_pret "$_M18_KC_K3SHA" "$_E19_SERVEUR"
}

_e19_injecter() {
  m18_outils kubectl || return 1
  if ! _e19_sain; then
    wb_avert "le banc k3s-ha n'est pas sain avant la panne (k3s-ha01 et k3s-ha02 doivent être Ready : M18-E14)"
    return 1
  fi
  m18_essayer E19 4 "$1"
}

panne_E19_v1() { _e19_injecter 1; }
panne_E19_v2() { _e19_injecter 2; }
panne_E19_v3() { _e19_injecter 3; }
panne_E19_v4() { _e19_injecter 4; }

# La panne a pris quand l'agent n'est plus Ready (bail du kubelet non renouvelé : 40 à 60 s).
verifier_E19() { m18_attendre 180 m18_noeud_pas_pret "$_M18_KC_K3SHA" "$_E19_AGENT"; }

annuler_E19() {
  if [[ -n "$(m18_lire E19 horloge)" ]]; then
    m18_exec_invite "$_E19_AGENT" ADM="$(date +%s)" <<'EOF' || wb_avert "annulation incomplète sur k3s-ha02 (horloge) : vérifie « timedatectl » sur le nœud"
svc="$(cat "$WB_DIR/$WB_EX.service-temps" 2>/dev/null)"
ecart=$((ADM - $(date +%s)))
[ "$ecart" -lt 0 ] && ecart=$((-ecart))
if [ "$ecart" -gt 300 ]; then
  date -s "@$ADM" >/dev/null
  journal "annulation : horloge remise à l'heure de adm01"
fi
if [ -n "$svc" ] && ! systemctl is-active -q "$svc"; then
  [ "$svc" = systemd-timesyncd ] && timedatectl set-ntp true
  systemctl start "$svc"
  journal "annulation : service de temps $svc relancé"
fi
rm -f "$WB_DIR/$WB_EX.service-temps"
EOF
    m18_oublier E19 horloge
  fi
  if [[ -n "$(m18_lire E19 nft)" ]]; then
    m18_exec "$_E19_SERVEUR" <<'EOF' || wb_avert "annulation incomplète sur k3s-ha01 (table nftables wb_m18_e19)"
if nft list table inet wb_m18_e19 >/dev/null 2>&1; then
  nft delete table inet wb_m18_e19
  journal "annulation : table nftables wb_m18_e19 supprimée"
fi
EOF
    m18_oublier E19 nft
  fi
  m18_exec "$_E19_AGENT" <<'EOF' || wb_avert "annulation incomplète sur k3s-ha02 (fichiers de configuration)"
if [ -f "$WB_DIR/$WB_EX.manifeste" ]; then
  restaurer_fichiers
  systemctl daemon-reload
  journal "annulation : configuration d'origine de l'agent remise"
fi
systemctl is-active -q k3s-agent || systemctl restart k3s-agent
EOF
  m18_attendre 180 m18_noeud_pret "$_M18_KC_K3SHA" "$_E19_AGENT" || wb_avert "k3s-ha02 n'est pas revenu Ready : regarde « journalctl -u k3s-agent » sur le nœud"
  m18_journal E19 "annulation terminée"
}

resume_E19() { echo "Le nœud k3s-ha02 du banc k3s est NotReady et ne rejoint plus son serveur."; }

symptome_E19() {
  wb_symptome "Ticket INC-4519 — De : Nadia Roussel" \
    "Cette nuit, Lucas et Sophie ont fait chacun une « petite intervention » sur le banc k3s." \
    "Depuis, k3s-ha02 est NotReady et ne revient pas tout seul. Il ne faut pas le réinstaller :" \
    "c'est exactement ce qui arrivera à l'agence de Lyon, et là-bas il n'y aura personne." \
    "Trouve pourquoi l'agent ne rejoint plus k3s-ha01, corrige à la racine, et écris RB-183." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 18 19"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 18 E19 4 "$@"; }
fi
