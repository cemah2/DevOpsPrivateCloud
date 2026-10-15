# shellcheck shell=bash
# _m15-operationnel.sh — fonctions partagées par les checks M15-E10 à M15-E23 (lecture seule).
# Sourcé par les check-EXX.sh concernés (lab/bin/check ne lance que les check-EXX.sh).
# Préfixe _m15o_ : pas de collision avec les fonctions des autres paliers.
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui
# peut échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction).
#
# Accès : kubectl en LECTURE par « kube » (compte de service wb-checks, M14-E06 ; ClusterRole en
# lecture sur les objets du cluster, CRD de Cilium, Gateway API et cert-manager comprises, jamais
# les Secrets) ; GitLab par « gitlab_api » (jeton en lecture) ; SSH vers les passerelles, dns01 et
# les répartiteurs (commandes show/get/list/cat seulement) ; DNS et HTTPS depuis adm01.

_M15O_TRAVAIL="$HOME/m15"
_M15O_K8S="projects/plateforme%2Fk8s"
_M15O_ANSIBLE="projects/plateforme%2Fansible"
_M15O_INFRA="projects/plateforme%2Finfra"
_M15O_DOC="projects/plateforme%2Fmedisphere"
_M15O_APPS="apps.par1.medisphere.internal"
_M15O_GW="10.10.41.10"
_M15O_NOM_MA="mediagenda-recette.${_M15O_APPS}"

# _m15o_kjson ARGS… — sortie JSON de « kube get … -o json » ; « {} » si l'objet est absent ou en erreur.
_m15o_kjson() {
  local out
  out="$(kube get "$@" -o json 2>/dev/null)" || out=""
  [[ -n "$out" ]] && printf '%s\n' "$out" || echo '{}'
}

# _m15o_jq JSON FILTRE [ARGS jq…] — jq -e sur un JSON (code 0 si le filtre est vrai).
_m15o_jq() {
  local json="$1" filtre="$2"; shift 2
  jq -e "$@" "$filtre" <<<"$json" >/dev/null 2>&1
}

# _m15o_condition JSON TYPE — statut (« True »/« False »/vide) de la condition TYPE de .status.conditions.
_m15o_condition() {
  jq -r --arg t "$2" '[.status.conditions[]? | select(.type == $t) | .status][0] // ""' <<<"$1" 2>/dev/null || true
}

# _m15o_code URL [options curl…] — code HTTP (000 si pas de réponse). TLS vérifié par le magasin système.
_m15o_code() {
  local url="$1"; shift
  curl -s -o /dev/null -w '%{http_code}' --max-time "$WB_TIMEOUT" "$@" "$url" 2>/dev/null || true
}

# _m15o_corps URL [options curl…] — corps de la réponse (vide si erreur).
_m15o_corps() {
  local url="$1"; shift
  curl -fsS --max-time "$WB_TIMEOUT" "$@" "$url" 2>/dev/null || true
}

# _m15o_resolve NOM PORT IP — option --resolve de curl (essais avant la publication DNS).
_m15o_resolve() { printf -- '--resolve=%s:%s:%s' "$1" "$2" "$3"; }

# _m15o_cert IP PORT NOM_SNI — émetteur, sujet, dates et SAN du certificat présenté (vide si échec).
_m15o_cert() {
  timeout "$WB_TIMEOUT" openssl s_client -connect "$1:$2" -servername "$3" </dev/null 2>/dev/null \
    | openssl x509 -noout -issuer -subject -dates -ext subjectAltName 2>/dev/null || true
}

# _m15o_duree_jours TEXTE_X509 — durée de validité en jours (arrondie) ; 9999 si illisible.
_m15o_duree_jours() {
  local debut fin
  debut="$(sed -n 's/^notBefore=//p' <<<"$1")"
  fin="$(sed -n 's/^notAfter=//p' <<<"$1")"
  [[ -n "$debut" && -n "$fin" ]] || { echo 9999; return 0; }
  echo $(( ($(date -d "$fin" +%s) - $(date -d "$debut" +%s) + 43200) / 86400 ))
}

# _m15o_dig SERVEUR PORT NOM TYPE [options dig…] — réponse courte (vide si rien).
_m15o_dig() {
  local s="$1" p="$2" n="$3" t="$4"; shift 4
  dig +short +time="$WB_TIMEOUT" +tries=1 -p "$p" "@$s" "$n" "$t" "$@" 2>/dev/null || true
}

# _m15o_vtysh HÔTE "commande show" — sortie de vtysh sur une passerelle (vide si échec).
_m15o_vtysh() { remote "$1" "sudo -n vtysh -c '$2'" 2>/dev/null || true; }

# _m15o_fichier_main PROJET CHEMIN / _m15o_contenu_main PROJET CHEMIN — fichier sur main (GitLab).
_m15o_fichier_main() {
  local chemin
  chemin="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "$1/repository/files/$chemin?ref=main" >/dev/null 2>&1
}
_m15o_contenu_main() {
  local chemin
  chemin="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "$1/repository/files/$chemin/raw?ref=main" 2>/dev/null || true
}

# _m15o_arbre_main PROJET DOSSIER — chemins des fichiers sous DOSSIER (vide = tout le dépôt) sur main,
# récursif (jusqu'à 1 000 fichiers : 10 pages de 100).
_m15o_arbre_main() {
  local chemin page lot
  chemin="$(jq -rn --arg v "$2" '$v | @uri')"
  for page in 1 2 3 4 5 6 7 8 9 10; do
    lot="$(gitlab_api "$1/repository/tree?ref=main&recursive=true&per_page=100&page=$page&path=$chemin" 2>/dev/null \
      | jq -r '.[] | select(.type == "blob") | .path' 2>/dev/null || true)"
    [[ -n "$lot" ]] || break
    printf '%s\n' "$lot"
    (( $(wc -l <<<"$lot") == 100 )) || break
  done
}

# _m15o_journal FICHIER MIN_LIGNES — fichier de travail présent avec au moins MIN_LIGNES non vides.
_m15o_journal() {
  local n
  [[ -s "$1" ]] || return 1
  n="$(grep -cv '^[[:space:]]*$' "$1" 2>/dev/null || true)"
  (( ${n:-0} >= $2 ))
}

# _m15o_cert_pki_joker TEXTE_X509 — émis par la PKI MédiSphère (émetteur « …Sph… ») et SAN joker apps.
_m15o_cert_pki_joker() {
  grep -qE '^issuer=.*Sph' <<<"$1" && grep -q 'DNS:\*\.apps\.par1\.medisphere\.internal' <<<"$1"
}

# _m15o_nom_netbox IP — dns_name de l'adresse IP (/32 ou autre masque) dans NetBox (vide si absente).
_m15o_nom_netbox() {
  netbox_api "ipam/ip-addresses/?address=$1" 2>/dev/null | jq -r '.results[0].dns_name // empty' 2>/dev/null || true
}

# _m15o_cabundle_medisphere BASE64 — le caBundle (base64 de PEM) contient un seul certificat, une
# autorité dont le sujet contient « Sph » (MédiSphère Root CA).
_m15o_cabundle_medisphere() {
  local pem n
  pem="$(base64 -d <<<"$1" 2>/dev/null)" || return 1
  n="$(grep -c 'BEGIN CERTIFICATE' <<<"$pem" || true)"
  [[ "$n" == 1 ]] && openssl x509 -noout -subject <<<"$pem" 2>/dev/null | grep -q 'Sph'
}

# _m15o_versions_servies CRD — versions servies d'une CRD, séparées par des espaces (vide si absente).
_m15o_versions_servies() {
  kube get crd "$1" -o json 2>/dev/null | jq -r '[.spec.versions[] | select(.served) | .name] | join(" ")' 2>/dev/null || true
}

# _m15o_politiques_fermees JSON_NETPOL JSON_CNP — aucune autorisation « tout » : règle sans source ou
# destination, élément vide, bloc 0.0.0.0/0, entités world/all, sélecteur d'endpoints vide.
_m15o_politiques_fermees() {
  jq -e '[.items[]?.spec | (.ingress[]? | select((.from // []) | length == 0 or any(.[]; . == {} or .ipBlock.cidr == "0.0.0.0/0"))),
                           (.egress[]?  | select((.to // [])   | length == 0 or any(.[]; . == {} or .ipBlock.cidr == "0.0.0.0/0")))]
         | length == 0' <<<"$1" >/dev/null 2>&1 || return 1
  jq -e '[.items[]?.spec | (.ingress[]?, .egress[]?)
          | select(((.fromEntities // []) + (.toEntities // [])) as $e | ($e | index("world")) or ($e | index("all"))
                   or any((.fromEndpoints // [])[], (.toEndpoints // [])[]; . == {})
                   or any((.fromCIDR // [])[], (.toCIDR // [])[]; . == "0.0.0.0/0"))]
         | length == 0' <<<"$2" >/dev/null 2>&1
}

# _m15o_depot_sans_secret — (E23, après _m15o_arbre="…") aucun fichier de clé ou de Secret dans
# composants/, espaces/, cluster/ (le dossier secrets/ du M14, chiffré par Ansible Vault, est hors champ).
_m15o_depot_sans_secret() {
  ! grep -E '^(composants|espaces|cluster)/' <<<"${_m15o_arbre:-}" | grep -qiE '\.(key|p12|pfx)$|secret[^/]*\.ya?ml$'
}

# _m15o_politiques_lucas JSON_TABLEAU — (E21) les politiques d'un tableau d'objets n'ouvrent rien :
# fermées au sens de _m15o_politiques_fermees, sans toFQDNs « * » ni entité cluster.
_m15o_politiques_lucas() {
  local np cnp
  np="$(jq '{items: [.[] | select(.kind == "NetworkPolicy")]}' <<<"$1" 2>/dev/null)" || return 1
  cnp="$(jq '{items: [.[] | select(.kind == "CiliumNetworkPolicy")]}' <<<"$1" 2>/dev/null)" || return 1
  _m15o_politiques_fermees "$np" "$cnp" || return 1
  jq -e '[.items[]?.spec | (.ingress[]?, .egress[]?)
          | select(any(.toFQDNs[]?; (.matchPattern // "") == "*") or ((.fromEntities // []) | index("cluster")))]
         | length == 0' <<<"$cnp" >/dev/null 2>&1
}
