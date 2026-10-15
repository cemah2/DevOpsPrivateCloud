# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E40.sh — M14-E40 « Panne : un membre etcd est en détresse »
#
# Un seul membre etcd est touché (k8s-cpX tiré au hasard) : le quorum (2 sur 3) reste garanti. Variantes :
#   1. base du membre corrompue : etcd arrêté (manifeste retiré du dossier des pods statiques),
#      dossier member/ d'origine mis de côté dans /var/lib/workbook/, copie dont les deux pages de
#      méta de bbolt (snap/db) sont écrasées, manifeste remis : le membre redémarre en boucle ;
#   2. horloge du nœud reculée de 400 jours (service de temps arrêté) : les certificats des pairs ne
#      sont « pas encore valides » pour ce membre, qui se retrouve isolé. Injection et annulation par
#      l'agent QEMU (les certificats SSH d'utilisateur peuvent être refusés par le nœud décalé) ;
#   3. quota d'espace du membre réduit (--quota-backend-bytes = taille actuelle + 24 Mio) puis des clés
#      « /infoger/test-charge/… » d'environ 1 Mio écrites jusqu'au dépassement : alarme NOSPACE, tout
#      le cluster refuse les écritures (lectures et suppressions permises).
# Un instantané etcd de sécurité est pris avant chaque injection (sur le nœud relais, dans
# /var/lib/workbook/), puis effacé à l'annulation. Annulation : seulement ce qui est encore cassé.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m14-commun.sh
source "$WB_ROOT/modules/14-kubernetes-admin/corrige/pannes/_m14-commun.sh"

# m14_instantane_etcd RELAIS — instantané etcd vérifié (snapshot status) sur RELAIS, dans
# /var/lib/workbook/<WB_EX>.instantane.db (600).
m14_instantane_etcd() {
  m14_wb_exec "$1" >/dev/null <<'EOF'
dst="$WB_DIR/$WB_EX.instantane.db"
rm -f "$dst"
if command -v etcdctl >/dev/null 2>&1; then
  etcdctl_ snapshot save "$dst" >/dev/null 2>&1 || exit 1
else
  etcdctl_ snapshot save /var/lib/etcd/wb-instantane.db >/dev/null 2>&1 || exit 1
  mv /var/lib/etcd/wb-instantane.db "$dst"
fi
chmod 600 "$dst"
ok=0
if command -v etcdutl >/dev/null 2>&1; then
  etcdutl snapshot status "$dst" -w json 2>/dev/null | grep -q '"totalKey":[1-9]' && ok=1
else
  id="$(crictl_ ps -q --name '^etcd$' --state Running 2>/dev/null | head -n 1)"
  cp "$dst" /var/lib/etcd/wb-verif.db
  crictl_ exec "$id" etcdutl snapshot status /var/lib/etcd/wb-verif.db -w json 2>/dev/null </dev/null | grep -q '"totalKey":[1-9]' && ok=1
  rm -f /var/lib/etcd/wb-verif.db
fi
[ "$ok" = 1 ] || { rm -f "$dst"; exit 1; }
journal "instantané etcd de sécurité vérifié : $dst"
EOF
}

_e40_nospace() {
  local r
  r="$(m14_etcd_relais)" || return 1
  m14_wb_exec "$r" >/dev/null 2>&1 <<'EOF'
etcdctl_ alarm list 2>/dev/null | grep -q NOSPACE
EOF
}
_e40_membre_ko() { ! m14_etcd_membre_sain "$1"; }
_e40_membre_ko_stable() { _e40_membre_ko "$1" && sleep 30 && _e40_membre_ko "$1"; }

_m14E40_une() {
  local n="$1" h r rc=0 id
  h="$(m14_hasard "${_M14_CP[@]}")"
  r="$(m14_etcd_relais "$h")" || return 1
  m14_instantane_etcd "$r" || { wb_avert "instantané etcd de sécurité impossible : rien n'est cassé"; return 1; }
  m14_ecrire E40 relais "$r"
  case "$n" in
    1)
      id="$(m14_wb_exec "$h" <<'EOF'
m=/etc/kubernetes/manifests/etcd.yaml
[ -f "$m" ] && [ -d /var/lib/etcd/member/snap ] || exit 10
[ -e "$WB_DIR/$WB_EX.member.orig" ] && exit 10
etcdctl_ member list -w simple 2>/dev/null | awk -F', ' -v n="$(hostname -s)" '$3 == n {print $1}' > "$WB_DIR/$WB_EX.id"
[ -s "$WB_DIR/$WB_EX.id" ] || exit 1
cp -a "$m" "$WB_DIR/$WB_EX.etcd.yaml" && rm -f "$m"
t=0; while [ -n "$(crictl_ ps -q --name '^etcd$' 2>/dev/null)" ] && [ "$t" -lt 90 ]; do sleep 3; t=$((t + 3)); done
[ -z "$(crictl_ ps -q --name '^etcd$' 2>/dev/null)" ] || { cp -a "$WB_DIR/$WB_EX.etcd.yaml" "$m"; exit 1; }
mv /var/lib/etcd/member "$WB_DIR/$WB_EX.member.orig"
cp -a "$WB_DIR/$WB_EX.member.orig" /var/lib/etcd/member
dd if=/dev/urandom of=/var/lib/etcd/member/snap/db bs=4096 count=2 conv=notrunc status=none
cp -a "$WB_DIR/$WB_EX.etcd.yaml" "$m"
journal "membre etcd : base bbolt corrompue (copie), originale dans $WB_DIR/$WB_EX.member.orig"
cat "$WB_DIR/$WB_EX.id"
EOF
)" || rc=$?
      ((rc == 0)) || return "$rc"
      m14_ecrire E40 cible "$h"
      m14_ecrire E40 id "$(tail -n 1 <<<"$id")"
      if ! m14_attendre 120 _e40_membre_ko_stable "$h"; then
        _e40_defaire 1 "$h"
        m14_oublier E40 cible
        return 10
      fi
      ;;
    2)
      m14_wb_exec_invite "$h" ADM="$(date +%s)" <<'EOF' || rc=$?
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
EOF
      # wb_exec_invite ne distingue pas « sans effet » d'un échec : l'effet est vérifié ci-dessous.
      ((rc == 0)) || return 1
      m14_ecrire E40 cible "$h"
      if ! m14_attendre 120 _e40_membre_ko "$h"; then
        _e40_defaire 2 "$h"
        m14_oublier E40 cible
        return 10
      fi
      ;;
    3)
      m14_wb_exec "$h" >/dev/null <<'EOF' || rc=$?
m=/etc/kubernetes/manifests/etcd.yaml
grep -q -- '--quota-backend-bytes' "$m" && exit 10
taille="$(etcdctl_ endpoint status -w json 2>/dev/null | sed -n 's/.*"dbSize":\([0-9]*\).*/\1/p' | head -n 1)"
[ -n "$taille" ] || exit 1
q=$((taille + 25165824))
printf '%s\n' "$q" > "$WB_DIR/$WB_EX.quota"
sauver "$m"
avant="$(crictl_ ps -q --name '^etcd$' 2>/dev/null | head -n 1)"
sed -i "0,/^\([[:space:]]*\)- etcd\$/s//&\n\1- --quota-backend-bytes=$q/" "$m"
grep -q -- "--quota-backend-bytes=$q" "$m" || { restaurer_fichiers; exit 1; }
# Attendre que le membre redémarre avec son nouveau quota.
t=0
while [ "$t" -lt 150 ]; do
  apres="$(crictl_ ps -q --name '^etcd$' --state Running 2>/dev/null | head -n 1)"
  if [ -n "$apres" ] && [ "$apres" != "$avant" ] && etcdctl_ endpoint health >/dev/null 2>&1; then break; fi
  sleep 5; t=$((t + 5))
done
[ "$t" -lt 150 ] || { restaurer_fichiers; exit 1; }
journal "quota d'espace du membre réduit à $q octets"
i=0
while [ "$i" -lt 64 ]; do
  if head -c 786432 /dev/urandom | base64 -w 0 | etcdctl_entree put "/infoger/test-charge/$(printf '%03d' "$i")" >/dev/null 2>&1; then
    i=$((i + 1))
  else
    break
  fi
done
journal "$i clés /infoger/test-charge/* écrites (~1 Mio chacune)"
etcdctl_ alarm list 2>/dev/null | grep -q NOSPACE || exit 10
EOF
      m14_ecrire E40 cible "$h"
      if ((rc != 0)); then
        _e40_defaire 3 "$h"
        m14_oublier E40 cible
        return "$rc"
      fi
      ;;
  esac
  m14_journal E40 "variante $n posée sur $h"
}

_e40_defaire() {
  local n="$1" h="$2" r id present=0
  case "$n" in
    1)
      # Le membre d'origine est-il encore déclaré (pas remplacé par l'apprenant) et muet ? Vu d'un relais.
      id="$(m14_lire E40 id)"
      r="$(m14_etcd_relais "$h")" || r=""
      if [[ -n "$id" && -n "$r" ]] && ! m14_etcd_membre_sain "$h" "$r" &&
        m14_wb_exec "$r" ID="$id" >/dev/null 2>&1 <<'EOF'; then
etcdctl_ member list 2>/dev/null | grep -q "^$ID,"
EOF
        present=1
      fi
      m14_wb_exec "$h" PRESENT="$present" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur $h (etcd)"
m=/etc/kubernetes/manifests/etcd.yaml
o="$WB_DIR/$WB_EX.member.orig"
if [ -d "$o" ] && [ "$PRESENT" = 1 ]; then
  [ -f "$m" ] && cp -a "$m" "$WB_DIR/$WB_EX.etcd.yaml" && rm -f "$m"
  t=0; while [ -n "$(crictl_ ps -q --name '^etcd$' 2>/dev/null)" ] && [ "$t" -lt 90 ]; do sleep 3; t=$((t + 3)); done
  rm -rf /var/lib/etcd/member && mv "$o" /var/lib/etcd/member
  cp -a "$WB_DIR/$WB_EX.etcd.yaml" "$m"
  journal "annulation : données d'origine du membre etcd remises"
fi
rm -rf "$o"
rm -f "$WB_DIR/$WB_EX.id" "$WB_DIR/$WB_EX.etcd.yaml"
EOF
      m14_oublier E40 id
      ;;
    2)
      m14_wb_exec_invite "$h" ADM="$(date +%s)" <<'EOF' || wb_avert "annulation incomplète sur $h (horloge) : vérifie « timedatectl » sur le nœud"
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
      ;;
    3)
      m14_wb_exec "$h" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur $h (quota etcd)"
m=/etc/kubernetes/manifests/etcd.yaml
q="$(cat "$WB_DIR/$WB_EX.quota" 2>/dev/null)"
if [ -n "$q" ] && grep -q -- "--quota-backend-bytes=$q" "$m"; then
  restaurer_fichiers
  sleep 20
  attendre_etcd_local 150 || true
  journal "annulation : manifeste etcd rétabli (quota par défaut)"
else
  oublier_fichiers
fi
if etcdctl_ get /infoger/ --prefix --keys-only 2>/dev/null | grep -q .; then
  etcdctl_ del /infoger/ --prefix >/dev/null 2>&1
  journal "annulation : clés /infoger/ supprimées"
fi
if etcdctl_ alarm list 2>/dev/null | grep -q NOSPACE; then
  rev="$(etcdctl_ endpoint status -w json 2>/dev/null | sed -n 's/.*"revision":\([0-9]*\).*/\1/p' | head -n 1)"
  [ -n "$rev" ] && etcdctl_ compact "$rev" >/dev/null 2>&1
  for ep in https://10.10.40.51:2379 https://10.10.40.52:2379 https://10.10.40.53:2379; do
    etcdctl_ --endpoints="$ep" defrag >/dev/null 2>&1
  done
  etcdctl_ alarm disarm >/dev/null 2>&1
  journal "annulation : compactage, défragmentation des trois membres, alarme levée"
fi
rm -f "$WB_DIR/$WB_EX.quota"
EOF
      ;;
  esac
}

_e40_preparer() {
  if [[ -n "${_M14_ASTREINTE:-}" ]]; then return 0; fi
  m14_sain
}

panne_E40_v1() { _e40_preparer && m14_essayer E40 3 1; }
panne_E40_v2() { _e40_preparer && m14_essayer E40 3 2; }
panne_E40_v3() { _e40_preparer && m14_essayer E40 3 3; }

verifier_E40() {
  local h
  h="$(m14_lire E40 cible)"
  [[ -n "$h" ]] || return 1
  case "$WB_VAR" in
    3) _e40_nospace ;;
    *) _e40_membre_ko "$h" ;;
  esac
}

annuler_E40() {
  local h r v
  h="$(m14_lire E40 cible)"
  if [[ -n "$h" ]]; then
    case "${WB_VAR:-}" in
      [1-3]) _e40_defaire "$WB_VAR" "$h" ;;
      *) for v in 2 1 3; do _e40_defaire "$v" "$h"; done ;;
    esac
    m14_journal E40 "annulation ($h)"
  fi
  r="$(m14_lire E40 relais)"
  if [[ -n "$r" ]]; then
    m14_wb_exec "$r" >/dev/null <<'EOF' || true
rm -f "$WB_DIR/$WB_EX.instantane.db"
EOF
  fi
  m14_oublier E40 cible
  m14_oublier E40 relais
}

resume_E40() {
  local h
  h="$(m14_lire E40 cible)"
  case "${WB_VAR:-}" in
    3) echo "Plus aucune écriture dans le cluster : « etcdserver: mvcc: database space exceeded »." ;;
    *) echo "Le membre etcd de ${h:-?} est signalé en échec ; le cluster tourne sur deux membres." ;;
  esac
}

symptome_E40() {
  local h
  h="$(m14_lire E40 cible)"
  case "${WB_VAR:-}" in
    3)
      wb_symptome "Ticket INC-4140 — De : Nadia Roussel — priorité P1" \
        "Plus rien ne se déploie : chaque « kubectl apply », chaque création de pod échoue avec" \
        "« etcdserver: mvcc: database space exceeded ». La lecture fonctionne encore. InfoGér dit" \
        "avoir « testé les performances d'etcd » sur un nœud de contrôle hier. Rends le cluster" \
        "inscriptible sans perdre un seul objet, et fais en sorte que ça ne revienne pas." \
        "" \
        "Un instantané etcd de sécurité a été pris avant l'incident (RB-141 si tout tourne mal)." \
        "Temps cible : 45 min. Contrôle : lab/bin/check 14 40"
      ;;
    *)
      wb_symptome "Ticket INC-4140 — De : Karim Benali" \
        "La vérification d'etcd signale le membre de $h en échec (« endpoint health » en erreur)." \
        "Le cluster fonctionne sur deux membres sur trois : la moindre panne d'un autre nœud de" \
        "contrôle nous coûterait le quorum. InfoGér est intervenu sur ce nœud cette nuit." \
        "Remets les trois membres en bonne santé, sans jamais toucher à deux membres à la fois." \
        "" \
        "Un instantané etcd de sécurité a été pris avant l'incident (RB-141 si tout tourne mal)." \
        "Temps cible : 45 min. Contrôle : lab/bin/check 14 40"
      ;;
  esac
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 14 E40 3 "$@"; }
fi
