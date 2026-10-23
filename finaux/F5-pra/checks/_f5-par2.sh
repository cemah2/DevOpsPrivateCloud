# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
# _f5-par2.sh — fonctions de BASE partagées par toutes les vérifications du final F5 (PRA multi-site),
# check-S01 à check-S14, et par les pannes (via _f5-exercice.sh, qui le source). Sourcé, jamais lancé
# seul. Préfixe _f5p_. Une seule implémentation par fonction : _f5-exercice.sh (préfixe _f5e_) n'ajoute
# que ce qui est propre à l'exercice (T0, sonde, main courante, état « PAR2 prêt »).
#
# LECTURE SEULE : GitLab en GET (jeton des checks), miroirs Git de adm02 en lecture (git show), SSH en
# lecture vers hp01 (root : qm, pvesh, pvesm, ip, nft, proxmox-backup-manager en consultation) et vers
# les VMs de PAR2 (admin), « kubectl » de k8s-par2 avec le compte wb-checks (jamais les Secrets),
# API S3 de s3-02 avec l'identité wb-checks (lecture et liste), API v2 de reg02 en GET.
#
# Les checks se lancent depuis adm01 (phases 1, 2 et 4) ou depuis adm02 (phase 3, PAR1 isolé : S09 à
# S11). Rien ici ne suppose que PAR1 répond, sauf _f5p_fichier en mode « gitlab » et les fonctions de
# check-lib.sh qui visent PAR1 (kube, gitlab_api…).
#
# ---------------------------------------------------------------------------------------------------
# VARIABLES (lab/lab.env, toutes facultatives)
# ---------------------------------------------------------------------------------------------------
#   WB_F5_DOC                dossier de la documentation du PRA (défaut docs/pra)
#   WB_F5_PROJET_DOC         projet de la documentation (défaut plateforme/medisphere)
#   WB_F5_SOURCE_DOC         gitlab (défaut) | miroir : où lire les fichiers des dépôts (miroir = dépôts
#                            nus de adm02, quand GitLab est injoignable)
#   WB_F5_MIROIRS            dossier des miroirs sur adm02 (défaut /srv/miroirs)
#   WB_F5_HP01               hôte SSH de hp01, compte root (défaut : WB_PBS_HOST, sinon pbs01)
#   WB_F5_ADM02              hôte SSH de adm02, compte admin (défaut adm02.par2.medisphere.internal)
#   WB_F5_S3_02_HOTE         hôte SSH de s3-02, compte admin (défaut s3-02.par2.medisphere.internal)
#   WB_F5_DNS03_HOTE         hôte SSH de dns03, compte admin (défaut dns03.par2.medisphere.internal)
#   WB_F5_DNS01, WB_F5_DNS03 adresses de dns01 et dns03 (défaut 10.10.20.10 et 10.20.20.11) ; les checks
#                            interrogent leurs RÉCURSEURS (port 53) : les autoritaires (5300) ne sont pas
#                            ouverts à MGMT
#   WB_F5_S3_URL             API S3 de s3-02 (défaut https://s3-02.par2.medisphere.internal:8333)
#   WB_F5_S3_CHECKS_FILE     identité wb-checks de s3-02 : AWS_ACCESS_KEY_ID=… AWS_SECRET_ACCESS_KEY=…
#                            (défaut ~/.config/workbook/s3-02-checks.env)
#   WB_F5_REG02_URL          registre de PAR2 (défaut https://reg02.par2.medisphere.internal)
#   WB_F5_REG02_CHECKS_FILE  REG02_USER=… REG02_PASSWORD=… (défaut ~/.config/workbook/reg02-checks.env)
#   WB_F5_KUBECONFIG_PAR2    kubeconfig du compte wb-checks de k8s-par2
#                            (défaut ~/.config/workbook/k8s-par2-checks.kubeconfig)
#   WB_F5_SERVEUR_PROD       nom d'archivage (serverName) de la base de prod (défaut mediagenda-db-prod-day0)
#   WB_F5_RETARD_MAX_S       âge maximal du dernier WAL copié à PAR2 (défaut 900)
#   WB_F5_MIROIR_RETARD_MAX_S retard maximal d'un miroir Git (défaut 3600)
#   WB_F5_PROJETS_MIROIRS    projets dont un miroir est exigé (liste séparée par des espaces, défaut :
#                            _F5P_PROJETS_MIROIRS ci-dessous)
#   WB_F5_URL_PAR1           URL de MédiAgenda prod à PAR1 (défaut https://mediagenda.apps.par1.medisphere.internal)
#   WB_F5_KMS01_URL          API de kms01 de PAR1 (défaut https://kms01.par1.medisphere.internal:8200)
# et celles de lab/lib/check-lib.sh (WB_GITLAB_*, WB_PBS_HOST, WB_SSH_OPTS, WB_TIMEOUT, WB_K8S_KUBECONFIG).
#
# ---------------------------------------------------------------------------------------------------
# FONCTIONS (codes de retour : 0 = vrai/succès ; les fonctions « afficher » écrivent sur stdout)
# ---------------------------------------------------------------------------------------------------
# Dépôts et documentation
#   _f5p_fichier PROJET CHEMIN [RÉF=main]   affiche le contenu du fichier (GitLab ou miroir de adm02
#                                            selon WB_F5_SOURCE_DOC) ; code ≠ 0 s'il n'existe pas
#   _f5p_contient PROJET CHEMIN REGEX…      le fichier existe et contient chaque motif (casse ignorée)
#   _f5p_doc CHEMIN_RELATIF REGEX…          idem pour un fichier sous WB_F5_DOC du projet de doc
#   _f5p_doc_motif DOSSIER MOTIF_NOM REGEX… un fichier sous WB_F5_DOC/DOSSIER dont le NOM correspond à
#                                            MOTIF_NOM (regex bash) contient chaque motif ; affiche son chemin
#   _f5p_sans_secret TEXTE                  vrai si TEXTE ne contient aucune forme de secret reconnaissable
#                                            (clé privée PEM, clé age, jeton OpenBao, jeton GitLab, jeton PVE)
#   _f5p_sections TEXTE REGEX…              chaque motif apparaît dans un titre Markdown (#…) de TEXTE
# Hôtes de PAR2
#   _f5p_hp01 COMMANDE                      exécute COMMANDE sur hp01 (root) ; renvoie son code
#   _f5p_vm VMID CHAMP                      affiche un champ de « qm config VMID » sur hp01 (ex. tags, pool
#                                            n'est pas un champ : voir _f5p_vm_pool)
#   _f5p_vm_etat VMID                       affiche running | stopped | absente | injoignable (hp01 muet)
#   _f5p_vm_pool VMID                       affiche le pool Proxmox de la VM (vide si aucun)
#   _f5p_sur HÔTE COMMANDE                  comme « remote », mais exécution LOCALE si le nom court de HÔTE
#                                            (sans « compte@ » ni domaine) est la machine courante (checks
#                                            lancés sur adm02 pendant le PRA)
#   _f5p_ssh HÔTE COMMANDE                  _f5p_sur vers une VM de PAR2 en admin (ou HÔTE complet
#                                            user@hôte) ; renvoie son code
#   _f5p_adm02 COMMANDE                     raccourci de _f5p_ssh vers WB_F5_ADM02
#   _f5p_unite_active HÔTE MOTIF            une unité systemd (service ou timer) dont le nom contient MOTIF
#                                            est active sur HÔTE
#   _f5p_filersync_unites                   unités de s3-02 qui lancent « weed filer.sync » (unités simples,
#                                            et instances activées ou chargées d'une unité modèle « @ »)
#   _f5p_filersync_ok                       au moins une telle unité, et toutes actives (message sinon)
# DNS
#   _f5p_soa ZONE SERVEUR [PORT=53]         affiche le numéro de série SOA de ZONE servi par SERVEUR
#   _f5p_dig NOM TYPE SERVEUR [PORT=53]     affiche la réponse courte (+noall +answer) sans les commentaires
# Stockage objet de PAR2 (identité wb-checks)
#   _f5p_s3 ARGS…                           « aws s3api ARGS » contre s3-02 (sortie JSON)
#   _f5p_s3_compartiments                   affiche les noms des compartiments de s3-02, un par ligne
#   _f5p_s3_age_dernier COMPARTIMENT PRÉFIXE affiche l'âge en secondes de l'objet le plus récent sous le
#                                            préfixe (parcourt au plus 10 pages de 1000) ; code ≠ 0 si aucun
# Registre de PAR2
#   _f5p_reg02 CHEMIN [OPTIONS curl…]       GET sur l'API v2 de reg02 (ex. "medisphere/mediagenda-api/tags/list")
#   _f5p_reg02_digest_existe DÉPÔT DIGEST   le manifeste DÉPÔT@DIGEST existe sur reg02
# Kubernetes de PAR2
#   _f5p_kube ARGS…                         kubectl en lecture sur k8s-par2 (compte wb-checks)
# Divers
#   _f5p_epoch DATE_ISO                     affiche la date en secondes depuis l'époque (GNU date)
#   _f5p_age DATE_ISO                       affiche l'âge en secondes d'une date ISO 8601
# ---------------------------------------------------------------------------------------------------
# Exemple (check de phase 3, depuis adm02) :
#   source "$(dirname "${BASH_SOURCE[0]}")/_f5-par2.sh"
#   check_cmd "mediagenda-db-par2 est primaire" \
#     test "$(_f5p_kube -n mediagenda-prod get cluster mediagenda-db-par2 -o jsonpath='{.spec.replica.primary}' 2>/dev/null)" = mediagenda-db-par2
#   check_cmd "journal du jour : ouverture d'INC-6109" _f5p_doc_motif journal '^[0-9-]+\.md$' 'INC-6109 \[ouverture\]'
# ---------------------------------------------------------------------------------------------------

_f5p_doc_dir="${WB_F5_DOC:-docs/pra}"
_f5p_projet_doc="${WB_F5_PROJET_DOC:-plateforme/medisphere}"
_f5p_source="${WB_F5_SOURCE_DOC:-gitlab}"
_f5p_miroirs="${WB_F5_MIROIRS:-/srv/miroirs}"
_f5p_hp01_hote="${WB_F5_HP01:-${WB_PBS_HOST:-pbs01}}"
_f5p_adm02_hote="${WB_F5_ADM02:-adm02.par2.medisphere.internal}"
_f5p_s302_hote="${WB_F5_S3_02_HOTE:-s3-02.par2.medisphere.internal}"
_f5p_dns03_hote="${WB_F5_DNS03_HOTE:-dns03.par2.medisphere.internal}"
_f5p_dns01="${WB_F5_DNS01:-10.10.20.10}"
_f5p_dns03="${WB_F5_DNS03:-10.20.20.11}"
_f5p_s3_url="${WB_F5_S3_URL:-https://s3-02.par2.medisphere.internal:8333}"
_f5p_s3_env="${WB_F5_S3_CHECKS_FILE:-$HOME/.config/workbook/s3-02-checks.env}"
_f5p_reg02_url="${WB_F5_REG02_URL:-https://reg02.par2.medisphere.internal}"
_f5p_reg02_env="${WB_F5_REG02_CHECKS_FILE:-$HOME/.config/workbook/reg02-checks.env}"
_f5p_kubeconfig="${WB_F5_KUBECONFIG_PAR2:-$HOME/.config/workbook/k8s-par2-checks.kubeconfig}"
_f5p_serveur_prod="${WB_F5_SERVEUR_PROD:-mediagenda-db-prod-day0}"
_f5p_retard_max="${WB_F5_RETARD_MAX_S:-900}"
_f5p_miroir_retard_max="${WB_F5_MIROIR_RETARD_MAX_S:-3600}"
_f5p_url_par1="${WB_F5_URL_PAR1:-https://mediagenda.apps.par1.medisphere.internal}"
_f5p_kms01_url="${WB_F5_KMS01_URL:-https://kms01.par1.medisphere.internal:8200}"
# Projets dont un miroir est exigé à PAR2 (F5-S04) : de quoi reconstruire PAR2, déployer les applications
# du périmètre du PRA et lire la documentation. Liste minimale ; l'apprenant peut en miroiter davantage.
_F5P_PROJETS_MIROIRS_DEFAUT="plateforme/medisphere plateforme/infra plateforme/ansible plateforme/k8s plateforme/gitops plateforme/secrets mediagenda/deploiement medidoc/deploiement legacy/deploiement medinotif/deploiement"
_F5P_PROJETS_MIROIRS="${WB_F5_PROJETS_MIROIRS:-$_F5P_PROJETS_MIROIRS_DEFAUT}"

# --- Dépôts ------------------------------------------------------------------------------------------

_f5p_enc() { jq -rn --arg s "$1" '$s|@uri'; }

# _f5p_fichier PROJET CHEMIN [RÉF=main]
_f5p_fichier() {
  local projet="$1" chemin="$2" ref="${3:-main}"
  if [[ "$_f5p_source" == "miroir" ]]; then
    # Lecture dans le dépôt nu du miroir : aucune écriture, aucun « fetch ».
    _f5p_adm02 "git --git-dir='$_f5p_miroirs/$projet.git' show '$ref:$chemin'"
  else
    gitlab_api "projects/$(_f5p_enc "$projet")/repository/files/$(_f5p_enc "$chemin")/raw?ref=$(_f5p_enc "$ref")"
  fi
}

# _f5p_arbre PROJET [DOSSIER] — chemins des fichiers sous DOSSIER (tout le dépôt si vide), un par ligne.
_f5p_arbre() {
  local projet="$1" dossier="$2" p page=1 r
  if [[ "$_f5p_source" == "miroir" ]]; then
    _f5p_adm02 "git --git-dir='$_f5p_miroirs/$projet.git' ls-tree -r --name-only main -- ${dossier:+'$dossier'}" 2>/dev/null || true
    return 0
  fi
  p="$(_f5p_enc "$projet")"
  while ((page <= 10)); do
    r="$(gitlab_api "projects/$p/repository/tree?ref=main&recursive=true&per_page=100&page=$page${dossier:+&path=$(_f5p_enc "$dossier")}" 2>/dev/null)" || return 0
    jq -r '.[]? | select(.type == "blob") | .path' <<<"$r"
    (($(jq 'length' <<<"$r" 2>/dev/null || echo 0) < 100)) && return 0
    page=$((page + 1))
  done
}

# _f5p_contient PROJET CHEMIN REGEX…
_f5p_contient() {
  local c m projet="$1" chemin="$2"
  shift 2
  c="$(_f5p_fichier "$projet" "$chemin" 2>/dev/null)" || return 1
  [[ -n "$c" ]] || return 1
  for m in "$@"; do grep -Eqi -- "$m" <<<"$c" || return 1; done
}

# _f5p_doc CHEMIN_RELATIF REGEX…
_f5p_doc() {
  local chemin="$1"
  shift
  _f5p_contient "$_f5p_projet_doc" "$_f5p_doc_dir/$chemin" "$@"
}

# _f5p_doc_motif DOSSIER MOTIF_NOM REGEX… — DOSSIER relatif à WB_F5_DOC (« . » : WB_F5_DOC lui-même).
_f5p_doc_motif() {
  local d="$_f5p_doc_dir/$1" motif="$2" f
  [[ -z "$1" || "$1" == . ]] && d="$_f5p_doc_dir"
  shift 2
  while IFS= read -r f; do
    [[ -n "$f" && "${f##*/}" =~ $motif ]] || continue
    if _f5p_contient "$_f5p_projet_doc" "$f" "$@"; then
      printf '%s\n' "$f"
      return 0
    fi
  done < <(_f5p_arbre "$_f5p_projet_doc" "$d")
  return 1
}

# _f5p_sans_secret TEXTE
_f5p_sans_secret() {
  ! grep -Eq -- '-----BEGIN ([A-Z]+ )?PRIVATE KEY-----|AGE-SECRET-KEY-1|\b(hvs|hvb|s)\.[A-Za-z0-9]{20,}|glpat-[A-Za-z0-9_-]{20}|![a-z0-9-]+=[0-9a-f]{8}-[0-9a-f]{4}-|PVEAPIToken=' <<<"$1"
}

# _f5p_sections TEXTE REGEX…
_f5p_sections() {
  local t="$1" s
  shift
  for s in "$@"; do
    grep -Eqi -- "^#+ .*($s)" <<<"$t" || return 1
  done
}

# --- Hôtes ------------------------------------------------------------------------------------------

_f5p_hp01() { remote "root@$_f5p_hp01_hote" "$@"; }

_f5p_vm() { _f5p_hp01 "qm config $1 2>/dev/null" | awk -F': ' -v c="$2" '$1 == c { print $2; exit }'; }

_f5p_vm_etat() {
  local s
  # « absente » seulement si hp01 a RÉPONDU que la VM n'existe pas ; « injoignable » si hp01 ne répond pas.
  s="$(_f5p_hp01 "if qm status $1 >/dev/null 2>&1; then qm status $1; else echo 'status: absente'; fi" 2>/dev/null \
    | awk '/^status:/ { print $2 }')" || true
  printf '%s\n' "${s:-injoignable}"
}

_f5p_vm_pool() {
  _f5p_hp01 "pvesh get /cluster/resources --type vm --output-format json 2>/dev/null" \
    | jq -r --argjson id "$1" '.[] | select(.vmid == $id) | .pool // empty'
}

_f5p_sur() {
  local court="${1#*@}"
  court="${court%%.*}"
  if [[ "$court" == "$(hostname -s)" || "$court" == localhost ]]; then
    bash -c "$2"
    return
  fi
  remote "$1" "$2"
}

_f5p_ssh() {
  local h="$1"
  shift
  [[ "$h" == *@* ]] || h="admin@$h"
  _f5p_sur "$h" "$*"
}

_f5p_adm02() { _f5p_ssh "$_f5p_adm02_hote" "$@"; }

_f5p_unite_active() {
  _f5p_ssh "$1" "systemctl list-units --type=service,timer --state=active --no-legend --plain 2>/dev/null" \
    | awk '{ print $1 }' | grep -q -- "$2"
}

# Unités de s3-02 qui lancent « weed filer.sync ». Une unité modèle (S04 : seaweedfs-filer-sync@.service,
# une instance par compartiment) n'est pas lançable elle-même : on liste ses INSTANCES activées (liens
# *.wants) ou chargées. Une instance arrêtée mais toujours activée reste listée (et donc vue inactive).
_f5p_filersync_unites() {
  _f5p_ssh "$_f5p_s302_hote" 'for f in /etc/systemd/system/*.service; do
      grep -qs "filer.sync" "$f" || continue
      b=${f##*/}
      case "$b" in
        *@.service)
          p=${b%.service}
          find /etc/systemd/system -path "*.wants/*" -name "${p}?*.service" -printf "%f\n" 2>/dev/null
          systemctl list-units --all --type=service --no-legend --plain "${p}*" 2>/dev/null | awk "{ print \$1 }" ;;
        *) echo "$b" ;;
      esac
    done | sort -u' 2>/dev/null
}

_f5p_filersync_ok() {
  local u l ko=0
  l="$(_f5p_filersync_unites)" || l=""
  [[ -n "$l" ]] || { echo "aucune unité systemd de s3-02 ne lance weed filer.sync"; return 1; }
  while IFS= read -r u; do
    [[ -n "$u" ]] || continue
    _f5p_ssh "$_f5p_s302_hote" "systemctl is-active --quiet '$u'" 2>/dev/null || { echo "s3-02 : $u n'est pas actif"; ko=1; }
  done <<<"$l"
  return "$ko"
}

# --- DNS --------------------------------------------------------------------------------------------

_f5p_soa() {
  dig +short +time="$WB_TIMEOUT" +tries=1 -p "${3:-53}" "@$2" "$1" SOA 2>/dev/null | awk 'NF >= 7 { print $3; exit }'
}

_f5p_dig() {
  dig +noall +answer +time="$WB_TIMEOUT" +tries=1 -p "${4:-53}" "@$3" "$1" "$2" 2>/dev/null | grep -v '^;'
}

# --- S3 de PAR2 ---------------------------------------------------------------------------------------

_f5p_s3() {
  [[ -r "$_f5p_s3_env" ]] || { echo "identité S3 des checks illisible : $_f5p_s3_env" >&2; return 1; }
  (
    set -a
    # shellcheck disable=SC1090
    . "$_f5p_s3_env"
    set +a
    exec aws --endpoint-url "$_f5p_s3_url" --region us-east-1 --output json \
      --cli-read-timeout "$WB_TIMEOUT" --cli-connect-timeout "$WB_TIMEOUT" s3api "$@" </dev/null
  )
}

_f5p_s3_compartiments() { _f5p_s3 list-buckets 2>/dev/null | jq -r '.Buckets[]?.Name'; }

# _f5p_s3_age_dernier COMPARTIMENT PRÉFIXE
_f5p_s3_age_dernier() {
  local b="$1" pfx="$2" jeton="" page=0 r dernier="" d
  while ((page < 10)); do
    if [[ -n "$jeton" ]]; then
      r="$(_f5p_s3 list-objects-v2 --bucket "$b" --prefix "$pfx" --continuation-token "$jeton" 2>/dev/null)" || return 1
    else
      r="$(_f5p_s3 list-objects-v2 --bucket "$b" --prefix "$pfx" 2>/dev/null)" || return 1
    fi
    d="$(jq -r '[.Contents[]?.LastModified] | max // empty' <<<"$r")"
    [[ -n "$d" && ( -z "$dernier" || "$d" > "$dernier" ) ]] && dernier="$d"
    jeton="$(jq -r '.NextContinuationToken // empty' <<<"$r")"
    [[ -n "$jeton" ]] || break
    page=$((page + 1))
  done
  [[ -n "$dernier" ]] || return 1
  _f5p_age "$dernier"
}

# --- Registre de PAR2 ---------------------------------------------------------------------------------

_f5p_reg02() {
  local chemin="$1" REG02_USER="" REG02_PASSWORD=""
  shift
  [[ -r "$_f5p_reg02_env" ]] || { echo "identifiants de reg02 illisibles : $_f5p_reg02_env" >&2; return 1; }
  # shellcheck disable=SC1090
  source "$_f5p_reg02_env"
  # Identifiants par un fichier de configuration curl : jamais sur la ligne de commande (ps).
  curl -sf --max-time "$WB_TIMEOUT" -K <(printf 'user = "%s:%s"\n' "$REG02_USER" "$REG02_PASSWORD") \
    "$@" "$_f5p_reg02_url/v2/$chemin"
}

_f5p_reg02_digest_existe() {
  _f5p_reg02 "$1/manifests/$2" -o /dev/null -I \
    -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json'
}

# --- Kubernetes de PAR2 ------------------------------------------------------------------------------

_f5p_kube() {
  [[ -r "$_f5p_kubeconfig" ]] || { echo "kubeconfig de k8s-par2 illisible : $_f5p_kubeconfig" >&2; return 1; }
  kubectl --kubeconfig "$_f5p_kubeconfig" --request-timeout="${WB_TIMEOUT}s" "$@"
}

# --- Dates --------------------------------------------------------------------------------------------

_f5p_epoch() { date -d "$1" +%s 2>/dev/null; }

_f5p_age() {
  local e
  e="$(_f5p_epoch "$1")" || return 1
  [[ -n "$e" ]] || return 1
  echo $(($(date +%s) - e))
}
