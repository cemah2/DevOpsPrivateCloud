# shellcheck shell=bash
# _m10-expert.sh — fonctions partagées par les vérifications du palier 4 du module 10 (check-E35 à
# check-E44). Sourcé par ces scripts, jamais lancé seul. Lecture seule : CLI OpenStack (list, show,
# token issue), SSH vers les nœuds (docker inspect, lecture de fichiers, ovs-vsctl get/list), ceph en
# lecture par ceph01, curl et openssl vers la VIP externe.
# Préfixe _m10x_ : évite les collisions quand check-E43 charge plusieurs checks.
# Les secrets (mots de passe, clés) ne sont jamais affichés : seules leurs empreintes sont comparées.

_m10x_cloud_admin="${WB_M10_CLOUD_ADMIN:-medisphere-admin}"
_m10x_cloud_projet="${WB_M10_CLOUD_PROJET:-medisphere-plateforme}"
_m10x_ctl="${WB_M10_CTL:-osctl01}"
# shellcheck disable=SC2034  # utilisées par les checks qui sourcent ce fichier
_m10x_cmps=("${WB_M10_CMP1:-oscmp01}" "${WB_M10_CMP2:-oscmp02}")
_m10x_ceph="${WB_M10_CEPH:-ceph01}"
# shellcheck disable=SC2034
_m10x_fqdn="openstack.par1.medisphere.internal"
# shellcheck disable=SC2034
_m10x_vip_ext=10.10.50.201
# shellcheck disable=SC2034
_m10x_vip_int=10.10.50.200
# shellcheck disable=SC2034
_m10x_depot="${WB_DEPOT:-$HOME/medisphere}"
_m10x_sonde_dir="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/M10-sonde"

# _m10x_os ARGS… / _m10x_osp ARGS… — CLI OpenStack (cloud d'administration / projet plateforme).
_m10x_os() { timeout 120 openstack --os-cloud "$_m10x_cloud_admin" "$@" </dev/null; }
_m10x_osp() { timeout 120 openstack --os-cloud "$_m10x_cloud_projet" "$@" </dev/null; }

# _m10x_etat_calcul HÔTE — « enabled up », « disabled down »… du nova-compute de HÔTE.
_m10x_etat_calcul() {
  _m10x_os compute service list --service nova-compute -f json 2>/dev/null \
    | jq -r --arg h "$1" '.[] | select(.Host == $h) | "\(.Status) \(.State)"' 2>/dev/null
}

# _m10x_ctr_sain HÔTE CONTENEUR — le conteneur tourne et n'est pas « unhealthy ».
_m10x_ctr_sain() {
  local s
  s="$(remote "$1" "sudo -n docker inspect -f '{{.State.Running}} {{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' $2" 2>/dev/null)" || return 1
  [[ "$s" == "true healthy" || "$s" == "true none" || "$s" == "true starting" ]]
}

# _m10x_ceph ARGS… — commande ceph en lecture sur ceph01 (client natif, sinon cephadm shell).
_m10x_ceph() {
  local a
  a="$(printf '%q ' "$@")"
  remote "$_m10x_ceph" "if [ -x /usr/bin/ceph ]; then sudo -n /usr/bin/ceph $a; else for c in /usr/sbin/cephadm /usr/local/sbin/cephadm /usr/local/bin/cephadm /usr/bin/cephadm; do if sudo -n test -x \$c; then sudo -n \$c shell -- ceph $a 2>/dev/null; exit; fi; done; exit 127; fi" </dev/null
}

# _m10x_ini HÔTE FICHIER SECTION CLÉ — valeur d'une option d'un fichier INI (dernière occurrence),
# lue en root sur l'hôte. Ne sert qu'à des valeurs non secrètes.
_m10x_ini() {
  remote "$1" "sudo -n python3 - '$2' '$3' '$4'" <<'PY' 2>/dev/null
import configparser, sys
c = configparser.ConfigParser(strict=False, interpolation=None)
c.read(sys.argv[1])
s, k = sys.argv[2], sys.argv[3]
if s == "DEFAULT":
    print(c.defaults().get(k, ""))
elif c.has_option(s, k):
    print(c.get(s, k))
PY
}

# _m10x_ini_empreinte HÔTE FICHIER SECTION CLÉ — empreinte SHA-256 de la valeur (secrets).
_m10x_ini_empreinte() {
  remote "$1" "sudo -n python3 - '$2' '$3' '$4'" <<'PY' 2>/dev/null
import configparser, hashlib, sys
c = configparser.ConfigParser(strict=False, interpolation=None)
c.read(sys.argv[1])
s, k = sys.argv[2], sys.argv[3]
v = c.defaults().get(k, "") if s == "DEFAULT" else (c.get(s, k) if c.has_option(s, k) else "")
print(hashlib.sha256(v.strip().encode()).hexdigest() if v.strip() else "")
PY
}

# _m10x_https_ok [CHEMIN] — la VIP externe répond 200 en HTTPS, certificat vérifié par le magasin
# système de adm01 (sans dépendre du DNS).
_m10x_https_code() {
  curl -sS -o /dev/null -w '%{http_code}' --max-time 10 \
    --resolve "$_m10x_fqdn:443:$_m10x_vip_ext" "https://$_m10x_fqdn${1:-/auth/login/}" 2>/dev/null
}

# _m10x_ssh_sonde IP — connexion par clé à une instance sonde (clé du dossier M10-sonde).
_m10x_ssh_sonde() {
  [[ -f "$_m10x_sonde_dir/id_ed25519" ]] || return 1
  ssh -o BatchMode=yes -o ConnectTimeout=8 -o ControlPath=none -o IdentitiesOnly=yes \
    -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$_m10x_sonde_dir/known_hosts" \
    -i "$_m10x_sonde_dir/id_ed25519" "debian@$1" true </dev/null >/dev/null 2>&1
}

# _m10x_fip_port PORT — IP flottante associée à un port du projet plateforme (vide si aucune).
_m10x_fip_port() {
  _m10x_osp floating ip list --port "$1" -f value -c "Floating IP Address" 2>/dev/null | head -n 1
}

# _m10x_aucune_panne_active [EXX…] — aucune des pannes listées (ou M10-* si aucune) n'est marquée.
_m10x_aucune_panne_active() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives" e
  if (($# == 0)); then
    [[ -z "$(find "$d" -maxdepth 1 -name 'M10-E*' 2>/dev/null)" ]]
    return
  fi
  for e in "$@"; do
    [[ ! -e "$d/M10-$e" ]] || return 1
  done
}

# _m10x_commite FICHIER (relatif au dépôt de documentation) — suivi par git, sans modification.
_m10x_commite() {
  (cd "$_m10x_depot" && git ls-files --error-unmatch "$1" >/dev/null 2>&1 && [[ -z "$(git status --porcelain -- "$1")" ]])
}
