# shellcheck shell=bash
# _m10-commun.sh — fonctions partagées par les scripts de panne du module 10 (M10-E35 à M10-E43).
#
# Sourcé par break-EXX.sh APRÈS lab/lib/pannes-lib.sh (wb_exec, wb_avert, wb_symptome, WB_EX…).
# Rappel : lab/bin/break tourne avec « set -euo pipefail » ; les fonctions d'annulation sont appelées
# hors de tout « if » : aucune commande ne doit y échouer sans « || true ».
#
# Cibles : osctl01 (contrôle + réseau), oscmp01/oscmp02 (calcul), joints en SSH (admin + sudo -n,
# alias de ~/.ssh/config posés en M10-E02) ; ceph01 pour les gestes sur ceph-par1 (cephadm) ; l'API
# OpenStack par la CLI de adm01 (clouds.yaml de M10-E05 : medisphere-admin, medisphere-plateforme).
# Jamais pve01, son réseau, pbs01, ni une VM hors du pool lab.
#
# 1. Hôtes distants : _M10_AIDE_DISTANTE est préfixée aux scripts envoyés par m10_exec. Elle fournit :
#      subst FICHIER REGEX REMPLACEMENT   modification « chirurgicale » d'un fichier de configuration
#                     Kolla (/etc/kolla/<service>/…), première correspondance (regex Python, re.M) ;
#                     texte d'origine et texte posé mémorisés (code 10 si rien ne correspond) ;
#      defaire_subst  remet le texte d'origine là où le texte posé est ENCORE présent, laisse le reste
#                     (réparation) ; affiche les fichiers rétablis (pour relancer les conteneurs) ;
#      remplacer / retablir_remplacements   remplacement d'un fichier entier (certificat…), rétabli
#                     seulement si le fichier est toujours celui posé par la panne ;
#      ctr_arreter / ctr_relancer_arretes   arrêt d'un conteneur Kolla, relancé à l'annulation s'il
#                     est toujours arrêté ;
#      ovs, ceph, cle_cephx_bidon, ctr_actif, ctr_redemarrer.
#    IMPORTANT : le script distant est lu sur l'entrée standard (bash -s). Toute commande qui lit
#    l'entrée standard (docker exec -i, cephadm shell, ssh…) doit recevoir </dev/null ou un tube,
#    sinon elle avale la suite du script.
# 2. API OpenStack (adm01) : m10_os (cloud d'administration), m10_osp (projet plateforme).
# 3. Sondes : piles jetables m10-eXX-* dans le projet plateforme (réseau, routeur, groupe de
#    sécurité, port, IP flottante, instance) pour E36 et E37, instance et volume pour E38.
# 4. m10_essayer : variantes sans effet sur un lab donné (on passe à la suivante).

# Variables de lab/lab.env : WB_OS_CLOUD (défaut medisphere-admin), WB_OS_CLOUD_PLATEFORME
# (défaut medisphere-plateforme), WB_CEPH_ADMIN (défaut ceph01, M08).
_M10_CLOUD_ADMIN="${WB_OS_CLOUD:-medisphere-admin}"
_M10_CLOUD_PROJET="${WB_OS_CLOUD_PLATEFORME:-medisphere-plateforme}"
_M10_CTL=osctl01
_M10_CMP=(oscmp01 oscmp02)
_M10_CEPH="${WB_CEPH_ADMIN:-ceph01}"
_M10_FQDN="openstack.par1.medisphere.internal"
_M10_VIP_EXT=10.10.50.201
_M10_GABARIT="m1.petit"
_M10_CLE_NOM="m10-sonde"
_M10_ETAT_BASE="${XDG_STATE_HOME:-$HOME/.local/state}/workbook"

# ---------------------------------------------------------------------------
# État local et journal (adm01)
# ---------------------------------------------------------------------------

# m10_etat EXX — affiche (et crée, en 700) le dossier d'état local de la panne.
m10_etat() {
  local d="$_M10_ETAT_BASE/M10-$1"
  mkdir -p "$d" && chmod 700 "$d"
  printf '%s\n' "$d"
}

# m10_journal EXX "message" — journal local de la panne.
m10_journal() {
  local ex="$1" d
  shift
  d="$(m10_etat "$ex")"
  printf '%s %s [M10-%s variante %s] %s\n' "$(date -Is)" "$(hostname -s)" "$ex" "${WB_VAR:-?}" "$*" >>"$d/journal"
}

# m10_lire EXX CLÉ / m10_ecrire EXX CLÉ VALEUR — petites valeurs d'état (IP flottante, cible…).
m10_lire() {
  local f
  f="$(m10_etat "$1")/$2"
  if [[ -f "$f" ]]; then cat "$f"; fi
}
m10_ecrire() {
  local d
  d="$(m10_etat "$1")"
  printf '%s\n' "$3" >"$d/$2"
}

# m10_attendre DÉLAI_S COMMANDE [args…] — relance la commande toutes les 5 s jusqu'au succès.
m10_attendre() {
  local delai="$1" t=0
  shift
  until "$@" >/dev/null 2>&1; do
    t=$((t + 5))
    ((t <= delai)) || return 1
    sleep 5
  done
}

# m10_existe HÔTE — l'hôte répond en SSH.
m10_existe() { remote "$1" true >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# API OpenStack (CLI de adm01, clouds.yaml de M10-E05)
# ---------------------------------------------------------------------------

# m10_os ARGS… — openstack avec le cloud d'administration (délai borné).
m10_os() { timeout 300 openstack --os-cloud "$_M10_CLOUD_ADMIN" "$@" </dev/null; }

# m10_osp ARGS… — openstack avec le cloud du projet plateforme (sondes).
m10_osp() { timeout 300 openstack --os-cloud "$_M10_CLOUD_PROJET" "$@" </dev/null; }

# m10_jeton_ok — le cloud d'administration obtient un jeton.
m10_jeton_ok() { m10_os token issue -f value -c id >/dev/null 2>&1; }

# m10_etat_calcul HÔTE — « enabled up », « disabled up », « enabled down »… du nova-compute de HÔTE.
m10_etat_calcul() {
  m10_os compute service list --service nova-compute -f json 2>/dev/null \
    | jq -r --arg h "$1" '.[] | select(.Host == $h) | "\(.Status) \(.State)"' 2>/dev/null
}

# m10_calculs_sains — les deux nova-compute sont « enabled up ».
m10_calculs_sains() {
  local h
  for h in "${_M10_CMP[@]}"; do
    [[ "$(m10_etat_calcul "$h")" == "enabled up" ]] || return 1
  done
}

# m10_image_sonde — identifiant de l'image Debian 13 des sondes : debian-13 (M10-E06), à défaut
# la première image publique active dont le nom évoque Debian 13.
m10_image_sonde() {
  local j id
  id="$(m10_os image show debian-13 -f value -c id 2>/dev/null)" || id=""
  if [[ -n "$id" ]]; then
    printf '%s\n' "$id"
    return 0
  fi
  j="$(m10_os image list --public --status active --long -f json 2>/dev/null)" || return 1
  id="$(jq -r '[.[] | select((.Name | test("debian"; "i")) and (.Name | test("13|trixie"; "i")))][0].ID // empty' <<<"$j")"
  if [[ -z "$id" ]]; then
    id="$(jq -r '[.[] | select(.Name | test("debian"; "i"))][0].ID // empty' <<<"$j")"
  fi
  [[ -n "$id" ]] || return 1
  printf '%s\n' "$id"
}

# m10_cle_sonde — clé SSH des sondes (dans l'état local) et paire de clés « m10-sonde » du projet.
m10_cle_sonde() {
  local d="$_M10_ETAT_BASE/M10-sonde"
  mkdir -p "$d" && chmod 700 "$d"
  if [[ ! -f "$d/id_ed25519" ]]; then
    ssh-keygen -q -t ed25519 -N '' -C "sonde-workbook-m10" -f "$d/id_ed25519" || return 1
  fi
  if ! m10_osp keypair show "$_M10_CLE_NOM" >/dev/null 2>&1; then
    m10_osp keypair create --public-key "$d/id_ed25519.pub" "$_M10_CLE_NOM" >/dev/null || return 1
  fi
}

# m10_ssh_sonde IP — connexion SSH par clé à une instance sonde (utilisateur debian de l'image).
m10_ssh_sonde() {
  local d="$_M10_ETAT_BASE/M10-sonde"
  ssh -o BatchMode=yes -o ConnectTimeout=8 -o ControlPath=none -o IdentitiesOnly=yes \
    -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$d/known_hosts" \
    -i "$d/id_ed25519" "debian@$1" true </dev/null >/dev/null 2>&1
}

# m10_oublier_hote IP — retire l'IP des hôtes connus des sondes (instance recréée = nouvelle clé d'hôte).
m10_oublier_hote() {
  local f="$_M10_ETAT_BASE/M10-sonde/known_hosts"
  if [[ -f "$f" ]]; then ssh-keygen -q -R "$1" -f "$f" >/dev/null 2>&1 || true; fi
}

m10_ping() { ping -c 2 -W 3 "$1" >/dev/null 2>&1; }
m10_port22() { timeout 5 bash -c "exec 3<>/dev/tcp/$1/22" 2>/dev/null; }

# m10_pile_creer EXX — réseau 172.30.<XX>.0/24, routeur vers ext-net, groupe de sécurité (ICMP et
# SSH depuis MGMT), port et IP flottante, dans le projet plateforme. L'IP est gardée dans l'état.
m10_pile_creer() {
  local ex="$1" n="m10-${1,,}" fip
  m10_cle_sonde || return 1
  m10_osp network create "$n-net" >/dev/null || return 1
  m10_osp subnet create "$n-subnet" --network "$n-net" --subnet-range "172.30.${ex#E}.0/24" \
    --dns-nameserver 10.10.20.10 --dns-nameserver 10.10.20.16 >/dev/null || return 1
  m10_osp router create "$n-routeur" >/dev/null || return 1
  m10_osp router set --external-gateway ext-net "$n-routeur" >/dev/null || return 1
  m10_osp router add subnet "$n-routeur" "$n-subnet" >/dev/null || return 1
  m10_osp security group create --description "Sonde du workbook ($ex)" "$n-sg" >/dev/null || return 1
  m10_osp security group rule create --ingress --protocol icmp --remote-ip 10.10.10.0/24 "$n-sg" >/dev/null || return 1
  m10_osp security group rule create --ingress --protocol tcp --dst-port 22 --remote-ip 10.10.10.0/24 "$n-sg" >/dev/null || return 1
  m10_osp port create --network "$n-net" --security-group "$n-sg" "$n-port" >/dev/null || return 1
  fip="$(m10_osp floating ip create --port "$n-port" -f value -c floating_ip_address ext-net)" || return 1
  [[ -n "$fip" ]] || return 1
  m10_ecrire "$ex" fip "$fip"
  m10_journal "$ex" "pile sonde $n créée (IP flottante $fip)"
}

# m10_pile_serveur EXX NOM — instance Debian 13 (m1.petit) sur le port de la pile, clé m10-sonde.
m10_pile_serveur() {
  local ex="$1" nom="$2" n="m10-${1,,}" img
  img="$(m10_image_sonde)" || return 1
  m10_oublier_hote "$(m10_lire "$ex" fip)"
  m10_osp server create --flavor "$_M10_GABARIT" --image "$img" --port "$n-port" \
    --key-name "$_M10_CLE_NOM" --wait "$nom" >/dev/null
}

# m10_pile_detruire EXX — supprime tout ce qui porte le préfixe m10-eXX- (idempotent, sans erreur).
m10_pile_detruire() {
  local ex="$1" n="m10-${1,,}" id
  for id in $(m10_osp server list --name "^$n-" -f value -c ID 2>/dev/null); do
    m10_osp server delete --wait "$id" >/dev/null 2>&1 || true
  done
  for id in $(m10_osp floating ip list --port "$n-port" -f value -c ID 2>/dev/null); do
    m10_osp floating ip delete "$id" >/dev/null 2>&1 || true
  done
  m10_osp port delete "$n-port" >/dev/null 2>&1 || true
  m10_osp router remove subnet "$n-routeur" "$n-subnet" >/dev/null 2>&1 || true
  m10_osp router unset --external-gateway "$n-routeur" >/dev/null 2>&1 || true
  m10_osp router delete "$n-routeur" >/dev/null 2>&1 || true
  m10_osp network delete "$n-net" >/dev/null 2>&1 || true
  m10_osp security group delete "$n-sg" >/dev/null 2>&1 || true
  m10_osp security group delete "$n-durci" >/dev/null 2>&1 || true
  rm -f -- "$(m10_etat "$ex")/fip"
  m10_journal "$ex" "pile sonde $n supprimée"
}

# ---------------------------------------------------------------------------
# Hôtes distants : aide ajoutée au script envoyé (après le prélude de wb_exec)
# ---------------------------------------------------------------------------
read -r -d '' _M10_AIDE_DISTANTE <<'AIDE' || true
# copie_securite FICHIER — copie unique, hors manifeste (consultation en cas de doute).
copie_securite() {
  local c="$WB_DIR/$WB_EX.$(printf '%s' "$1" | tr '/' '_').copie"
  [ -e "$c" ] || cp -a "$1" "$c"
}
# subst FICHIER REGEX REMPLACEMENT — première correspondance (Python, re.M), mémorisée.
subst() {
  [ -f "$1" ] || return 10
  copie_securite "$1"
  python3 - "$1" "$2" "$3" "$WB_DIR/$WB_EX.subst" <<'PY'
import base64, re, sys
f, rx, repl, m = sys.argv[1:5]
t = open(f, encoding="utf-8").read()
mo = re.search(rx, t, re.M)
if not mo:
    sys.exit(10)
avant, apres = mo.group(0), mo.expand(repl)
if avant == apres or not apres:
    sys.exit(10)
open(f, "w", encoding="utf-8").write(t[:mo.start()] + apres + t[mo.end():])
b = lambda s: base64.b64encode(s.encode()).decode()
with open(m, "a", encoding="utf-8") as h:
    h.write("%s\t%s\t%s\n" % (f, b(avant), b(apres)))
PY
}
# defaire_subst — dans l'ordre inverse : remet le texte d'origine là où le texte posé est encore là.
# Affiche les fichiers effectivement rétablis (un par ligne).
defaire_subst() {
  local m="$WB_DIR/$WB_EX.subst"
  [ -f "$m" ] || return 0
  python3 - "$m" <<'PY' | while IFS="$(printf '\t')" read -r etat fichier; do
import base64, sys
d = lambda s: base64.b64decode(s).decode()
lignes = [l.rstrip("\n").split("\t") for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
for f, avant, apres in reversed(lignes):
    avant, apres = d(avant), d(apres)
    try:
        t = open(f, encoding="utf-8").read()
    except OSError:
        print("absent\t" + f)
        continue
    if apres in t:
        open(f, "w", encoding="utf-8").write(t.replace(apres, avant, 1))
        print("retabli\t" + f)
    else:
        print("repare\t" + f)
PY
    case "$etat" in
      retabli) journal "annulation : $fichier rétabli"; printf '%s\n' "$fichier" ;;
      repare) journal "annulation : $fichier modifié depuis l'injection (réparation), laissé tel quel" ;;
      *) journal "annulation : $fichier introuvable" ;;
    esac
  done
  rm -f -- "$m" "$WB_DIR/$WB_EX".*.copie
}
# remplacer FICHIER SOURCE — remplace FICHIER par SOURCE (droits et propriétaire conservés) ;
# l'original est gardé une fois, l'empreinte du fichier posé est notée.
remplacer() {
  local f="$1" src="$2" o
  o="$WB_DIR/$WB_EX.$(printf '%s' "$f" | tr '/' '_').orig"
  [ -f "$f" ] || return 10
  [ -e "$o" ] || cp -a "$f" "$o"
  cat "$src" >"$f"
  printf '%s\t%s\t%s\n' "$f" "$o" "$(sha256sum <"$f" | cut -d' ' -f1)" >>"$WB_DIR/$WB_EX.remplacements"
}
# retablir_remplacements — rétablit l'original si le fichier est encore celui posé par la panne.
# Affiche les fichiers rétablis.
retablir_remplacements() {
  local m="$WB_DIR/$WB_EX.remplacements" f o s
  [ -f "$m" ] || return 0
  while IFS="$(printf '\t')" read -r f o s; do
    if [ -f "$f" ] && [ "$(sha256sum <"$f" | cut -d' ' -f1)" = "$s" ] && [ -f "$o" ]; then
      cat "$o" >"$f"
      journal "annulation : $f rétabli"
      printf '%s\n' "$f"
    else
      journal "annulation : $f modifié depuis l'injection (réparation), laissé tel quel"
    fi
    rm -f -- "$o"
  done <"$m"
  rm -f -- "$m"
}
# Conteneurs Kolla (moteur Docker)
ctr_actif() { [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null </dev/null)" = true ]; }
ctr_existe() { docker inspect "$1" >/dev/null 2>&1 </dev/null; }
ctr_redemarrer() { docker restart "$1" >/dev/null 2>&1 </dev/null; }
# ctr_arreter NOM — arrête le conteneur s'il tourne et le note pour l'annulation (code 10 sinon).
ctr_arreter() {
  ctr_actif "$1" || return 10
  docker stop "$1" >/dev/null 2>&1 </dev/null || return 1
  printf '%s\n' "$1" >>"$WB_DIR/$WB_EX.arrets"
  journal "conteneur $1 arrêté"
}
# ctr_relancer_arretes — relance les conteneurs arrêtés par la panne s'ils le sont encore.
ctr_relancer_arretes() {
  local m="$WB_DIR/$WB_EX.arrets" c
  [ -f "$m" ] || return 0
  while read -r c; do
    [ -n "$c" ] || continue
    if ctr_actif "$c"; then
      journal "annulation : conteneur $c déjà relancé (réparation)"
    else
      docker start "$c" >/dev/null 2>&1 </dev/null || true
      journal "annulation : conteneur $c relancé"
    fi
  done <"$m"
  rm -f -- "$m"
}
# ovs ARGS… — ovs-vsctl dans le conteneur openvswitch_vswitchd.
ovs() { docker exec openvswitch_vswitchd ovs-vsctl "$@" </dev/null; }
# ceph ARGS… — client ceph de l'hôte s'il existe, sinon par « cephadm shell » (ceph01, M08).
ceph() {
  local c
  if [ -x /usr/bin/ceph ]; then
    /usr/bin/ceph "$@" </dev/null
    return
  fi
  for c in /usr/sbin/cephadm /usr/local/sbin/cephadm /usr/local/bin/cephadm /usr/bin/cephadm; do
    if [ -x "$c" ]; then
      "$c" shell -- ceph "$@" </dev/null 2>/dev/null
      return
    fi
  done
  return 127
}
# cle_cephx_bidon — clé cephx au bon format (type 1, 16 octets aléatoires), qui n'est celle de personne.
cle_cephx_bidon() {
  python3 -c 'import base64, os, struct, time; print(base64.b64encode(struct.pack("<hIIh", 1, int(time.time()), 0, 16) + os.urandom(16)).decode())'
}
AIDE

# m10_exec HÔTE [VAR=valeur…] <<'EOF' … EOF — wb_exec (SSH, root par sudo -n) avec l'aide ci-dessus.
m10_exec() {
  { printf '%s\n' "$_M10_AIDE_DISTANTE"; cat; } | wb_exec "$@"
}

# ---------------------------------------------------------------------------
# Variantes sans effet sur un lab donné
# ---------------------------------------------------------------------------

# m10_essayer EXX NB DÉPART — appelle _mEXX_une N (codes : 0 panne posée et constatée, 10 variante
# sans effet sur ce lab, déjà défaite ; autre = erreur) pour N = DÉPART, DÉPART+1… jusqu'à un succès.
# La variante retenue est mise dans WB_VAR (enregistrée par wb_main ou par l'astreinte).
m10_essayer() {
  local ex="$1" nb="$2" depart="$3" i n rc
  for ((i = 0; i < nb; i++)); do
    n=$(((depart - 1 + i) % nb + 1))
    rc=0
    WB_VAR="$n"
    "_m${ex}_une" "$n" || rc=$?
    if ((rc == 0)); then
      WB_VAR="$n"
      return 0
    fi
    ((rc == 10)) || return 1
  done
  wb_avert "aucune variante de M10-$ex n'a d'effet sur ce lab (configuration inattendue)"
  return 1
}

# m10_prerequis — outils de adm01 et accès aux nœuds avant toute injection.
m10_prerequis() {
  local h c
  for c in openstack jq ssh-keygen; do
    if ! command -v "$c" >/dev/null 2>&1; then
      wb_avert "outil manquant sur ce poste : $c"
      return 1
    fi
  done
  for h in "$_M10_CTL" "${_M10_CMP[@]}"; do
    if ! m10_existe "$h"; then
      wb_avert "$h ne répond pas en SSH : démarre le profil openstack (lab/bin/check 10 04)"
      return 1
    fi
  done
  if ! m10_jeton_ok; then
    wb_avert "le cloud $_M10_CLOUD_ADMIN n'obtient pas de jeton : lab/bin/check 10 05"
    return 1
  fi
}
