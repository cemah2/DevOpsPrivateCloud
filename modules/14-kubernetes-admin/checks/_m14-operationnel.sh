# shellcheck shell=bash
# _m14-operationnel.sh — fonctions partagées par les checks M14-E10 à M14-E23 (lecture seule).
# Sourcé par les check-EXX.sh du palier 2 (lab/bin/check ne lance que les check-EXX.sh).
# Préfixe _m14o_ : pas de collision avec les fonctions des autres paliers.
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui
# peut échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction).
#
# Accès :
#   - cluster : « kube » (check-lib.sh), compte de service wb-checks (M14-E06), lecture SANS les
#     Secrets ; droits à vérifier par SubjectAccessReview (create autorisé à wb-checks, rien n'est
#     écrit dans etcd) ;
#   - GitLab : gitlab_api (jeton des checks) pour les fichiers sur main ;
#   - nœuds : SSH « admin » (WB_K8S_CP, WB_K8S_WORKERS), lecture de fichiers ;
#   - Harbor : harbor_api (robot de lecture des checks, M13) ;
#   - Proxmox : root sur pve01 (WB_PVE_HOST), pvesh en lecture.

read -r -a _M14O_CP <<<"${WB_K8S_CP:-k8s-cp01 k8s-cp02 k8s-cp03}"
read -r -a _M14O_W <<<"${WB_K8S_WORKERS:-k8s-w01 k8s-w02 k8s-w03}"
_M14O_NOEUDS=("${_M14O_CP[@]}" "${_M14O_W[@]}")
_M14O_REGISTRE="registry.par1.medisphere.internal/"
_M14O_P_K8S="projects/plateforme%2Fk8s"
_M14O_P_APP="projects/mediagenda%2Fapi"
_M14O_P_DOC="projects/plateforme%2Fmedisphere"
_M14O_TRAVAIL="$HOME/m14"
# Zones attendues (M14-E14), cohérentes avec les baies CRUSH du M08.
declare -A _M14O_ZONE=(
  [k8s-cp01]=par1-baie-a [k8s-cp02]=par1-baie-b [k8s-cp03]=par1-baie-c
  [k8s-w01]=par1-baie-a [k8s-w02]=par1-baie-b [k8s-w03]=par1-baie-c
)

# _m14o_k ARGS… — kubectl en lecture avec wb-checks ; sortie standard seule, vide si erreur.
_m14o_k() { kube "$@" 2>/dev/null || true; }

# _m14o_json JSON FILTRE [ARGS jq…] — OK si le filtre jq (-e) est vrai sur le JSON donné.
_m14o_json() {
  local donnees="$1" filtre="$2"
  shift 2
  [[ -n "$donnees" ]] && jq -e "$@" "$filtre" <<<"$donnees" >/dev/null 2>&1
}

# _m14o_fichier_main PROJET CHEMIN — le fichier existe sur main du projet GitLab.
_m14o_fichier_main() {
  local chemin
  chemin="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "$1/repository/files/$chemin?ref=main" >/dev/null 2>&1
}

# _m14o_contenu_main PROJET CHEMIN — contenu brut du fichier sur main (vide si absent).
_m14o_contenu_main() {
  local chemin
  chemin="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "$1/repository/files/$chemin/raw?ref=main" 2>/dev/null || true
}

# _m14o_arbre PROJET CHEMIN — chemins des fichiers sous CHEMIN sur main (récursif, un par ligne).
_m14o_arbre() {
  local chemin
  chemin="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "$1/repository/tree?ref=main&recursive=true&per_page=100&path=$chemin" 2>/dev/null \
    | jq -r '.[] | select(.type == "blob") | .path' 2>/dev/null || true
}

# _m14o_pipeline_ok PROJET — le dernier pipeline de main a réussi.
_m14o_pipeline_ok() {
  gitlab_api "$1/pipelines?ref=main&per_page=1" 2>/dev/null | jq -e '.[0].status == "success"' >/dev/null 2>&1
}

# _m14o_peut UTILISATEUR GROUPES(virgules) VERBE RESSOURCE [ESPACE] [SOUS-RESSOURCE] [GROUPE_API]
#   Réponse de l'autorisation (SubjectAccessReview) : « yes » ou « no » sur la sortie standard.
_m14o_peut() {
  local u="$1" g="$2" verbe="$3" res="$4" ns="${5:-}" sous="${6:-}" api="${7:-}"
  jq -n --arg u "$u" --arg g "$g" --arg v "$verbe" --arg r "$res" --arg ns "$ns" --arg s "$sous" --arg a "$api" '
    {apiVersion: "authorization.k8s.io/v1", kind: "SubjectAccessReview",
     spec: {user: $u, groups: ($g | split(",") + ["system:authenticated"]),
            resourceAttributes: ({verb: $v, resource: $r, group: $a}
              + (if $ns != "" then {namespace: $ns} else {} end)
              + (if $s != "" then {subresource: $s} else {} end))}}' \
    | kube create -f - -o json 2>/dev/null \
    | jq -r 'if .status.allowed == true then "yes" else "no" end' 2>/dev/null || echo "?"
}

# _m14o_restricted — filtre jq : le pod (entrée) respecte les points principaux du profil
#   Pod Security « restricted » (non-root, pas d'escalade, capacités retirées, seccomp, pas d'hôte).
# shellcheck disable=SC2016
_M14O_RESTRICTED='
  . as $p
  | ($p.spec.securityContext // {}) as $ps
  | ([$p.spec.containers[], ($p.spec.initContainers // [])[]]) as $cs
  | ($p.spec.hostNetwork != true) and ($p.spec.hostPID != true) and ($p.spec.hostIPC != true)
  and ([$p.spec.volumes[]? | select(has("hostPath"))] | length == 0)
  and ($cs | all(
        (.securityContext // {}) as $c
        | (($c.runAsNonRoot // $ps.runAsNonRoot) == true)
        and ($c.allowPrivilegeEscalation == false)
        and (($c.capabilities.drop // []) | index("ALL") != null)
        and ((($c.seccompProfile.type // $ps.seccompProfile.type) // "") | test("RuntimeDefault|Localhost"))
        and ($c.privileged != true)
        and ([.ports[]? | select(.hostPort != null and .hostPort != 0)] | length == 0)))'

# _m14o_image_ok — filtre jq (entrée : chaîne d'image) : registre MédiSphère et version explicite.
# shellcheck disable=SC2016
_M14O_IMAGE_OK='
  startswith("registry.par1.medisphere.internal/")
  and (contains("@sha256:") or ((split("/") | last | contains(":")) and (endswith(":latest") | not)))'

# _m14o_local600 FICHIER — fichier local (adm01) non vide en mode 600.
_m14o_local600() { [[ -s "$1" && "$(stat -c %a "$1" 2>/dev/null)" == 600 ]]; }
