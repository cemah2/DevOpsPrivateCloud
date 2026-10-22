# shellcheck shell=bash
# _m19-commun.sh — fonctions partagées par les scripts de panne du module 19 (M19-E35 à M19-E43).
#
# Sourcé par break-EXX.sh APRÈS lab/lib/pannes-lib.sh (wb_exec, wb_kubectl, wb_avert, WB_EX…).
# Rappel : lab/bin/break tourne avec « set -euo pipefail » ; les fonctions d'annulation sont appelées
# hors de tout « if » : aucune commande ne doit y échouer sans « || true ».
#
# Principes (CONVENTIONS §8, PLAN §4.10 et §4.11 « Pannes des blocs D et E ») :
#   - GitLab est modifié par l'API avec le jeton d'ADMINISTRATION de l'apprenant
#     (WB_GITLAB_ADMIN_TOKEN_FILE, jeton « workbook-admin » de M01-E05, portée api + admin_mode) ;
#     le jeton ne passe jamais sur la ligne de commande (en-tête lu par curl dans un descripteur) ;
#   - toute modification d'un dépôt est un COMMIT IDENTIFIABLE : auteur Lucas Martin
#     (author_name / author_email de l'API des commits), marqueur « M19-EXX » dans le message ; elle
#     est défaite par un commit inverse, jamais par réécriture d'historique. Sur une branche protégée
#     en « No one » (plateforme/k8s), le commit passe par une MR fusionnée par l'API ;
#   - les objets Kubernetes sont sauvegardés (JSON nettoyé) avant modification dans
#     ~/.local/state/workbook/M19-EXX/ et ne sont remis que s'ils portent encore la marque de la panne
#     (une réparation de l'apprenant n'est jamais défaite) ;
#   - aucune donnée n'est supprimée : ni volume, ni compartiment, ni base, ni projet ; seuls les objets
#     créés par une panne (branche, MR, Deployment de démonstration, politique) sont retirés ;
#   - jamais de conteneur privilégié, jamais d'image hors de Harbor.
#
# Témoin : projet GitLab formation/ci-pannes (WB_M19_TEMOIN), créé à la première injection à partir
# de _m19-temoin/ et jamais supprimé par les pannes. Il consomme son propre composant « canari ».

_M19_DIR="$(dirname "${BASH_SOURCE[0]}")"
_M19_GITLAB="${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}"
_M19_TEMOIN="${WB_M19_TEMOIN:-formation/ci-pannes}"
_M19_RUNNER="${WB_M19_RUNNER:-k8s-par1}"
_M19_S3="${WB_M19_S3:-s3-01}"
_M19_REGISTRE=registry.par1.medisphere.internal
_M19_IMAGE_BUILDKIT="${WB_M19_IMAGE_BUILDKIT:-$_M19_REGISTRE/dockerhub/moby/buildkit:v0.34.1-rootless}"
# shellcheck disable=SC2034  # utilisées par les scripts qui sourcent ce fichier
{
  _M19_NS_JOBS=ci-jobs
  _M19_NS_RUNNER=gitlab-runner
  _M19_NS_BK=buildkit
  _M19_NS_AGENT=gitlab-agent
  _M19_NS_DEMO=wb-pannes-ci
  _M19_PROJET_K8S=plateforme/k8s
  _M19_PROJET_DEPLOIEMENT=mediagenda/deploiement
  _M19_AGENT=k8s-par1
}
_M19_LUCAS=lucas.martin
_M19_LUCAS_NOM=""
_M19_LUCAS_MEL=""

# ---------------------------------------------------------------------------
# État local et journal (adm01)
# ---------------------------------------------------------------------------

# m19_etat EXX — affiche (et crée, en 700) le dossier d'état local de la panne.
m19_etat() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/M19-$1"
  mkdir -p "$d" && chmod 700 "$d"
  printf '%s\n' "$d"
}

m19_journal() {
  local ex="$1" d
  shift
  d="$(m19_etat "$ex")"
  printf '%s %s [M19-%s variante %s] %s\n' "$(date -Is)" "$(hostname -s)" "$ex" "${WB_VAR:-?}" "$*" >>"$d/journal"
}

# m19_lire EXX CLÉ / m19_ecrire EXX CLÉ VALEUR (une seule fois) / m19_ecraser / m19_oublier
m19_lire() {
  local f
  f="$(m19_etat "$1")/$2"
  if [[ -f "$f" ]]; then cat "$f"; fi
}
m19_ecrire() {
  local d
  d="$(m19_etat "$1")"
  [[ -f "$d/$2" ]] || (umask 077 && printf '%s\n' "$3" >"$d/$2")
}
m19_ecraser() {
  local d
  d="$(m19_etat "$1")"
  (umask 077 && printf '%s\n' "$3" >"$d/$2")
}
m19_oublier() {
  local d
  d="$(m19_etat "$1")"
  rm -f -- "${d:?}/$2"
}

# m19_debut EXX — date de début de l'injection (epoch), mémorisée une fois.
m19_debut() { m19_ecrire "$1" debut "$(date +%s)"; }

# m19_attendre SECONDES commande… — relance la commande toutes les 5 s jusqu'à succès ou délai.
m19_attendre() {
  local max="$1" t=0
  shift
  while ((t < max)); do
    if "$@"; then return 0; fi
    sleep 5
    t=$((t + 5))
  done
  "$@"
}

# m19_essayer EXX NB DÉPART — essaie les variantes à partir de DÉPART ; une variante qui renvoie 10
# est « sans effet sur ce lab » (configuration différente de celle attendue) : on passe à la suivante.
m19_essayer() {
  local ex="$1" nb="$2" depart="$3" i n rc
  for ((i = 0; i < nb; i++)); do
    n=$(((depart - 1 + i) % nb + 1))
    rc=0
    WB_VAR="$n"
    "_m19${ex}_une" "$n" || rc=$?
    if ((rc == 0)); then
      WB_VAR="$n"
      return 0
    fi
    ((rc == 10)) || return 1
  done
  wb_avert "aucune variante de M19-$ex n'a d'effet sur ce lab (configuration inattendue)"
  return 1
}

m19_sha() { sha256sum | cut -d' ' -f1; }

# ---------------------------------------------------------------------------
# API GitLab (jeton d'administration de l'apprenant)
# ---------------------------------------------------------------------------

# m19_enc CHAÎNE — encodage URL (chemins de projets, de fichiers, noms de branches).
m19_enc() { jq -rn --arg s "$1" '$s|@uri'; }

# m19_api MÉTHODE CHEMIN [options curl…] — corps sur stdout ; code ≠ 0 si HTTP ≥ 400.
m19_api() {
  local m="$1" p="$2" f t
  shift 2
  f="${WB_GITLAB_ADMIN_TOKEN_FILE:-$HOME/.config/workbook/gitlab-admin.token}"
  [[ -r "$f" ]] || { wb_avert "jeton d'administration GitLab illisible : $f"; return 1; }
  t="$(tr -d '[:space:]' <"$f")"
  curl -sf --max-time 60 -X "$m" -H @<(printf 'PRIVATE-TOKEN: %s\n' "$t") "$_M19_GITLAB/api/v4/$p" "$@"
}

# m19_api_json MÉTHODE CHEMIN 'JSON'
m19_api_json() { m19_api "$1" "$2" -H 'Content-Type: application/json' --data-binary "$3"; }

# m19_projet_id CHEMIN — identifiant numérique d'un projet.
m19_projet_id() {
  local id
  id="$(m19_api GET "projects/$(m19_enc "$1")" | jq -r '.id // empty')" || return 1
  [[ -n "$id" ]] || return 1
  printf '%s\n' "$id"
}

# m19_lucas — identité de Lucas Martin (nom affiché et adresse) pour signer les commits des pannes.
m19_lucas() {
  local u
  [[ -n "$_M19_LUCAS_NOM" ]] && return 0
  u="$(m19_api GET "users?username=$_M19_LUCAS" | jq -c '.[0] // empty')" || return 1
  [[ -n "$u" ]] || { wb_avert "compte GitLab $_M19_LUCAS introuvable (M01-E05)"; return 1; }
  _M19_LUCAS_NOM="$(jq -r '.name' <<<"$u")"
  _M19_LUCAS_MEL="$(jq -r '.public_email // empty' <<<"$u")"
  [[ -n "$_M19_LUCAS_MEL" ]] || _M19_LUCAS_MEL="$_M19_LUCAS@medisphere.internal"
}

# m19_lucas_id — identifiant numérique du compte de Lucas.
m19_lucas_id() { m19_api GET "users?username=$_M19_LUCAS" | jq -r '.[0].id // empty'; }

# m19_brut PROJET CHEMIN REF — contenu brut d'un fichier du dépôt (code ≠ 0 s'il n'existe pas).
m19_brut() {
  m19_api GET "projects/$(m19_enc "$1")/repository/files/$(m19_enc "$2")/raw?ref=$(m19_enc "$3")"
}

# m19_action create|update|delete CHEMIN [FICHIER_LOCAL] — objet JSON d'une action de commit.
m19_action() {
  if [[ "$1" == delete ]]; then
    jq -n --arg p "$2" '{action: "delete", file_path: $p}'
  else
    jq -n --arg a "$1" --arg p "$2" --rawfile c "$3" '{action: $a, file_path: $p, content: $c}'
  fi
}

# m19_commit [--lucas] PROJET BRANCHE MESSAGE 'ACTIONS_JSON' — commit par l'API ; affiche son SHA.
#   --lucas : auteur Lucas Martin (le committeur reste ton compte d'administration, comme toute
#   action faite par une API au nom d'un autre : c'est visible dans « git log --format=fuller »).
m19_commit() {
  local lucas=0 corps
  if [[ "$1" == --lucas ]]; then lucas=1; shift; fi
  if ((lucas)); then
    m19_lucas || return 1
    corps="$(jq -n --arg b "$2" --arg m "$3" --argjson a "$4" --arg n "$_M19_LUCAS_NOM" --arg e "$_M19_LUCAS_MEL" \
      '{branch: $b, commit_message: $m, actions: $a, author_name: $n, author_email: $e}')"
  else
    corps="$(jq -n --arg b "$2" --arg m "$3" --argjson a "$4" '{branch: $b, commit_message: $m, actions: $a}')"
  fi
  m19_api_json POST "projects/$(m19_enc "$1")/repository/commits" "$corps" | jq -r '.id // empty'
}

# m19_tete PROJET BRANCHE — SHA du dernier commit d'une branche.
m19_tete() { m19_api GET "projects/$(m19_enc "$1")/repository/branches/$(m19_enc "$2")" | jq -r '.commit.id // empty'; }

# m19_pipeline_du_commit PROJET SHA — identifiant du pipeline créé pour ce commit (vide sinon).
m19_pipeline_du_commit() {
  m19_api GET "projects/$(m19_enc "$1")/pipelines?sha=$2&per_page=5&order_by=id&sort=desc" | jq -r '.[0].id // empty'
}

# m19_attendre_pipeline PROJET SHA [MAX] — attend la création du pipeline du commit ; affiche son id.
m19_attendre_pipeline() {
  local t=0 pl=""
  while ((t <= ${3:-60})); do
    pl="$(m19_pipeline_du_commit "$1" "$2" 2>/dev/null)" || pl=""
    [[ -n "$pl" ]] && break
    sleep 5
    t=$((t + 5))
  done
  printf '%s\n' "$pl"
}

# m19_job_json PROJET PIPELINE NOM — JSON du job NOM du pipeline (le plus récent s'il a été relancé).
m19_job_json() {
  m19_api GET "projects/$(m19_enc "$1")/pipelines/$2/jobs?per_page=100&include_retried=false" |
    jq -c --arg n "$3" '[.[] | select(.name == $n)] | max_by(.id) // empty'
}

# m19_attendre_job PROJET PIPELINE NOM MAX — attend la fin du job (succès, échec, annulé) ; affiche
# « statut id ». Statut « pending » ou « running » si le délai est dépassé.
m19_attendre_job() {
  local p="$1" pl="$2" n="$3" max="$4" t=0 j="" st=""
  while ((t <= max)); do
    j="$(m19_job_json "$p" "$pl" "$n" 2>/dev/null)" || j=""
    st="$(jq -r '.status // empty' <<<"$j" 2>/dev/null)" || st=""
    case "$st" in success | failed | canceled | skipped) break ;; esac
    sleep 10
    t=$((t + 10))
  done
  printf '%s %s\n' "${st:-absent}" "$(jq -r '.id // empty' <<<"$j" 2>/dev/null)"
}

# m19_job_reste NOM_ÉTAT PROJET PIPELINE NOM SECONDES — le job est encore dans cet état après le délai.
m19_job_reste() {
  local etat="$1" p="$2" pl="$3" n="$4" s="$5"
  sleep "$s"
  [[ "$(m19_job_json "$p" "$pl" "$n" | jq -r '.status // empty')" == "$etat" ]]
}

# m19_trace PROJET JOB — journal brut d'un job.
m19_trace() { m19_api GET "projects/$(m19_enc "$1")/jobs/$2/trace"; }

# m19_runner_id [NOM] — identifiant du runner d'instance dont la description est NOM.
m19_runner_id() {
  local n="${1:-$_M19_RUNNER}"
  m19_api GET "runners/all?type=instance_type&per_page=100" |
    jq -r --arg n "$n" '[.[] | select(.description == $n)][0].id // empty'
}

# ---------------------------------------------------------------------------
# Harbor (compte de l'apprenant, ~/.config/workbook/harbor-moi.env, M13-E03)
# ---------------------------------------------------------------------------

# m19_harbor MÉTHODE CHEMIN [options curl…] — API v2.0, identifiants jamais sur la ligne de commande.
m19_harbor() {
  local m="$1" p="$2" f HARBOR_USER="" HARBOR_PASSWORD=""
  shift 2
  f="${WB_M19_HARBOR_ADMIN_FILE:-$HOME/.config/workbook/harbor-moi.env}"
  [[ -r "$f" ]] || { wb_avert "identifiants Harbor illisibles : $f"; return 1; }
  # shellcheck disable=SC1090
  source "$f"
  curl -sf --max-time 30 -X "$m" -K <(printf 'user = "%s:%s"\n' "$HARBOR_USER" "$HARBOR_PASSWORD") \
    -H 'Accept: application/json' "${WB_HARBOR_URL:-https://$_M19_REGISTRE}/api/v2.0/$p" "$@"
}

# ---------------------------------------------------------------------------
# Objets Kubernetes : sauvegarde nettoyée et restauration (modèle M14)
# ---------------------------------------------------------------------------

_m19_fichier_objet() { printf '%s/%s_%s_%s.json\n' "$(m19_etat "$1")" "${4:-_cluster}" "${2//\//-}" "$3"; }

# m19_sauver_objet EXX TYPE NOM [ESPACE] — une seule fois par panne ; « ABSENT » si l'objet n'existe pas.
m19_sauver_objet() {
  local ex="$1" type="$2" nom="$3" ns="${4:-}" f
  f="$(_m19_fichier_objet "$ex" "$type" "$nom" "$ns")"
  [[ -e "$f" ]] && return 0
  if wb_kubectl get "$type" "$nom" ${ns:+-n "$ns"} -o json 2>/dev/null | jq '
      del(.metadata.resourceVersion, .metadata.uid, .metadata.creationTimestamp, .metadata.generation,
          .metadata.managedFields, .metadata.selfLink, .status)
      | if .metadata.annotations then .metadata.annotations |= del(."kubectl.kubernetes.io/last-applied-configuration") else . end' >"$f.tmp" 2>/dev/null &&
    [[ -s "$f.tmp" ]]; then
    mv "$f.tmp" "$f"
  else
    rm -f "$f.tmp"
    printf 'ABSENT\n' >"$f"
  fi
  chmod 600 "$f"
}

# m19_objet_sauve EXX TYPE NOM [ESPACE] — copie sauvegardée (JSON) ; code 1 si aucune.
m19_objet_sauve() {
  local f
  f="$(_m19_fichier_objet "$@")"
  [[ -s "$f" ]] && [[ "$(head -c 6 "$f")" != ABSENT ]] && cat "$f"
}

# m19_restaurer_objet EXX TYPE NOM [ESPACE] — remet la copie (ou supprime l'objet s'il n'existait pas).
m19_restaurer_objet() {
  local ex="$1" type="$2" nom="$3" ns="${4:-}" f
  f="$(_m19_fichier_objet "$ex" "$type" "$nom" "$ns")"
  [[ -e "$f" ]] || return 0
  if [[ "$(head -c 6 "$f")" == ABSENT ]]; then
    wb_kubectl delete "$type" "$nom" ${ns:+-n "$ns"} --ignore-not-found >/dev/null 2>&1 || wb_avert "suppression de $type/$nom impossible"
  elif wb_kubectl get "$type" "$nom" ${ns:+-n "$ns"} >/dev/null 2>&1; then
    wb_kubectl replace -f "$f" >/dev/null 2>&1 || wb_avert "restauration de $type/$nom impossible (copie : $f)"
  else
    wb_kubectl create -f "$f" >/dev/null 2>&1 || wb_avert "recréation de $type/$nom impossible (copie : $f)"
  fi
  rm -f -- "$f"
}

# m19_oublier_objet EXX TYPE NOM [ESPACE] — efface la copie sans rien restaurer.
m19_oublier_objet() { rm -f -- "$(_m19_fichier_objet "$@")"; }

# m19_deploiement_pret ESPACE NOM — déploiement entièrement à jour et disponible.
m19_deploiement_pret() {
  wb_kubectl -n "$1" get deploy "$2" -o json 2>/dev/null | jq -e '
    (.spec.replicas // 1) as $n
    | (.status.updatedReplicas // 0) == $n and (.status.availableReplicas // 0) == $n
      and (.status.replicas // 0) == $n and (.status.observedGeneration // 0) >= .metadata.generation' >/dev/null 2>&1
}

# m19_evenement_depuis EXX ESPACE 'regex raison' — un événement récent de cette raison existe.
m19_evenement_depuis() {
  local debut
  debut="$(m19_lire "$1" debut)"
  wb_kubectl -n "$2" get events -o json 2>/dev/null | jq -e --arg r "$3" --argjson t "${debut:-0}" '
    [.items[] | select(.reason | test($r))
              | select(((.lastTimestamp // .eventTime // .metadata.creationTimestamp) | sub("\\.[0-9]+"; "") | fromdateiso8601) >= ($t - 5))]
    | length > 0' >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Runner k8s-par1 : ConfigMap du chart gitlab/gitlab-runner (config.template.toml)
# ---------------------------------------------------------------------------

# m19_runner_cm — nom de la ConfigMap dont le gabarit envoie les jobs dans ci-jobs (pas ci-jobs-protege).
m19_runner_cm() {
  wb_kubectl -n "$_M19_NS_RUNNER" get configmaps -o json 2>/dev/null | jq -r '
    [.items[] | select(.data["config.template.toml"] // "" | test("namespace *= *\"ci-jobs\""))][0].metadata.name // empty'
}

# m19_runner_deploy CM — Deployment du gestionnaire qui monte cette ConfigMap.
m19_runner_deploy() {
  wb_kubectl -n "$_M19_NS_RUNNER" get deploy -o json 2>/dev/null | jq -r --arg cm "$1" '
    [.items[] | select(any(.spec.template.spec.volumes[]?; .configMap.name? == $cm))][0].metadata.name // empty'
}

# m19_toml CM — gabarit TOML actuel.
m19_toml() { wb_kubectl -n "$_M19_NS_RUNNER" get configmap "$1" -o json | jq -r '.data["config.template.toml"]'; }

# m19_toml_ecrire CM FICHIER — remplace le gabarit TOML de la ConfigMap par le contenu du fichier.
m19_toml_ecrire() {
  local patch
  patch="$(jq -n --rawfile t "$2" '{data: {"config.template.toml": $t}}')"
  wb_kubectl -n "$_M19_NS_RUNNER" patch configmap "$1" --type merge -p "$patch" >/dev/null
}

# m19_runner_redemarrer DEPLOY — redémarrage progressif du gestionnaire (le gabarit est lu au démarrage).
m19_runner_redemarrer() {
  wb_kubectl -n "$_M19_NS_RUNNER" rollout restart "deploy/$1" >/dev/null || return 1
  wb_kubectl -n "$_M19_NS_RUNNER" rollout status "deploy/$1" --timeout=240s >/dev/null 2>&1
}

# m19_toml_modifier EXX 'programme perl' — applique une substitution au gabarit du runner k8s-par1,
# mémorise l'original (une fois) et l'empreinte injectée, redémarre le gestionnaire.
#   Code 10 : la substitution ne change rien (configuration différente de celle attendue).
m19_toml_modifier() {
  local ex="$1" prog="$2" cm dep d
  cm="$(m19_runner_cm)"
  [[ -n "$cm" ]] || return 10
  dep="$(m19_runner_deploy "$cm")"
  [[ -n "$dep" ]] || return 10
  d="$(m19_etat "$ex")"
  m19_toml "$cm" >"$d/toml.actuel" || return 1
  perl -0pe "$prog" "$d/toml.actuel" >"$d/toml.injecte" || return 1
  if cmp -s "$d/toml.actuel" "$d/toml.injecte"; then
    rm -f "$d/toml.actuel" "$d/toml.injecte"
    return 10
  fi
  [[ -f "$d/toml.orig" ]] || cp "$d/toml.actuel" "$d/toml.orig"
  m19_ecrire "$ex" toml-cm "$cm"
  m19_ecrire "$ex" toml-deploy "$dep"
  m19_ecraser "$ex" toml-empreinte "$(m19_sha <"$d/toml.injecte")"
  m19_toml_ecrire "$cm" "$d/toml.injecte" || return 1
  rm -f "$d/toml.actuel"
  m19_runner_redemarrer "$dep" || wb_avert "le gestionnaire $dep tarde à redémarrer"
  m19_journal "$ex" "gabarit TOML de $cm modifié, $dep redémarré"
}

# m19_toml_retablir EXX — remet le gabarit d'origine s'il porte encore la marque de la panne.
m19_toml_retablir() {
  local ex="$1" cm dep d
  d="$(m19_etat "$ex")"
  cm="$(m19_lire "$ex" toml-cm)"
  dep="$(m19_lire "$ex" toml-deploy)"
  if [[ -n "$cm" && -f "$d/toml.orig" ]]; then
    if [[ "$(m19_toml "$cm" 2>/dev/null | m19_sha)" == "$(m19_lire "$ex" toml-empreinte)" ]]; then
      m19_toml_ecrire "$cm" "$d/toml.orig" || wb_avert "gabarit de $cm non rétabli (copie : $d/toml.orig)"
      [[ -z "$dep" ]] || m19_runner_redemarrer "$dep" || true
      m19_journal "$ex" "annulation : gabarit TOML de $cm rétabli"
    else
      m19_journal "$ex" "annulation : gabarit TOML de $cm modifié depuis l'injection (réparation), laissé tel quel"
    fi
  fi
  rm -f -- "$d/toml.orig" "$d/toml.injecte"
  m19_oublier "$ex" toml-cm
  m19_oublier "$ex" toml-deploy
  m19_oublier "$ex" toml-empreinte
}

# ---------------------------------------------------------------------------
# Témoin formation/ci-pannes
# ---------------------------------------------------------------------------

m19_temoin_id() { m19_projet_id "$_M19_TEMOIN"; }

# m19_temoin_creer — crée le projet témoin (première injection du palier).
m19_temoin_creer() {
  local groupe="${_M19_TEMOIN%/*}" nom="${_M19_TEMOIN##*/}" gid pid t a sha jeton lid lt sid uid
  gid="$(m19_api GET "groups/$(m19_enc "$groupe")" | jq -r '.id // empty')" || gid=""
  [[ -n "$gid" ]] || { wb_avert "groupe GitLab « $groupe » introuvable (M19-E04)"; return 1; }
  echo "Première injection du palier 4 : création du projet témoin $_M19_TEMOIN (2 à 4 min)…"
  pid="$(m19_api POST projects --data-urlencode "name=$nom" --data-urlencode "path=$nom" \
    --data-urlencode "namespace_id=$gid" --data-urlencode "default_branch=main" \
    --data-urlencode "visibility=internal" \
    --data-urlencode "description=Témoin du palier 4 du module 19 (pannes de CI). Ne pas supprimer avant M19-E46." |
    jq -r '.id // empty')" || pid=""
  [[ -n "$pid" ]] || { wb_avert "création du projet $_M19_TEMOIN refusée"; return 1; }
  # main : poussée et fusion par les Maintainers (projet de formation : les pannes y commitent).
  m19_api DELETE "projects/$pid/protected_branches/main" >/dev/null 2>&1 || true
  m19_api POST "projects/$pid/protected_branches" --data-urlencode "name=main" \
    --data-urlencode "push_access_level=40" --data-urlencode "merge_access_level=40" >/dev/null || return 1
  uid="$(m19_lucas_id)"
  [[ -n "$uid" ]] && m19_api POST "projects/$pid/members" --data-urlencode "user_id=$uid" \
    --data-urlencode "access_level=40" >/dev/null 2>&1 || true
  # 1er commit : le composant et l'outil ; étiquette 1.0.0 ; 2e commit : .gitlab-ci.yml qui la consomme.
  t="$(mktemp -d)"
  a="$(jq -s '.' <(m19_action create README.md "$_M19_DIR/_m19-temoin/README.md") \
    <(m19_action create requirements.txt "$_M19_DIR/_m19-temoin/requirements.txt") \
    <(m19_action create outils/canari.py "$_M19_DIR/_m19-temoin/outils/canari.py") \
    <(m19_action create templates/canari/template.yml "$_M19_DIR/_m19-temoin/templates/canari/template.yml"))"
  sha="$(m19_commit "$_M19_TEMOIN" main "feat: composant canari 1.0.0 (témoin du palier 4, M19)" "$a")" || sha=""
  [[ -n "$sha" ]] || { rm -rf -- "$t"; return 1; }
  m19_api POST "projects/$pid/repository/tags" --data-urlencode "tag_name=1.0.0" --data-urlencode "ref=$sha" \
    --data-urlencode "message=canari 1.0.0" >/dev/null || { rm -rf -- "$t"; return 1; }
  a="$(jq -s '.' <(m19_action create .gitlab-ci.yml "$_M19_DIR/_m19-temoin/gitlab-ci.yml"))"
  m19_commit "$_M19_TEMOIN" main "ci: pipeline du canari (composant 1.0.0)" "$a" >/dev/null || { rm -rf -- "$t"; return 1; }
  rm -rf -- "$t"
  # Jeton d'accès de projet en lecture du dépôt, rangé dans la variable masquée et protégée CANARI_JETON.
  lt="$(m19_api POST "projects/$pid/access_tokens" --data-urlencode "name=canari-lecture" \
    --data-urlencode "scopes[]=read_repository" --data-urlencode "access_level=20" \
    --data-urlencode "expires_at=$(date -d '+90 days' +%F)")" || return 1
  jeton="$(jq -r '.token // empty' <<<"$lt")"
  [[ -n "$jeton" ]] || return 1
  m19_api POST "projects/$pid/variables" --data-urlencode "key=CANARI_JETON" --data-urlencode "value=$jeton" \
    --data-urlencode "masked=true" --data-urlencode "protected=true" >/dev/null || return 1
  # Pipeline planifié appartenant à Lucas (pris en charge par lui par l'API d'emprunt d'identité).
  sid="$(m19_api POST "projects/$pid/pipeline_schedules" --data-urlencode "description=canari-quotidien" \
    --data-urlencode "ref=main" --data-urlencode "cron=17 5 * * *" --data-urlencode "cron_timezone=Europe/Paris" \
    --data-urlencode "active=true" | jq -r '.id // empty')" || sid=""
  if [[ -n "$sid" && -n "$uid" ]]; then
    lid="$(m19_api POST "users/$uid/impersonation_tokens" --data-urlencode "name=workbook-M19-temoin" \
      --data-urlencode "scopes[]=api" --data-urlencode "expires_at=$(date -d tomorrow +%F)")" || lid=""
    if [[ -n "$lid" ]]; then
      curl -sf --max-time 30 -X POST -H @<(printf 'PRIVATE-TOKEN: %s\n' "$(jq -r '.token' <<<"$lid")") \
        "$_M19_GITLAB/api/v4/projects/$pid/pipeline_schedules/$sid/take_ownership" >/dev/null 2>&1 ||
        wb_avert "le pipeline planifié du témoin n'a pas pu être confié à Lucas"
      m19_api DELETE "users/$uid/impersonation_tokens/$(jq -r '.id' <<<"$lid")" >/dev/null 2>&1 || true
    fi
  fi
  echo "Projet témoin créé : $_M19_GITLAB/$_M19_TEMOIN"
}

# m19_temoin_lancer — lance un pipeline sur main du témoin ; affiche son identifiant.
m19_temoin_lancer() {
  m19_api POST "projects/$(m19_enc "$_M19_TEMOIN")/pipeline?ref=main" | jq -r '.id // empty'
}

# m19_temoin_cycle [MAX] — lance un pipeline et attend la fin du job canari ; affiche « statut id ».
m19_temoin_cycle() {
  local pl
  pl="$(m19_temoin_lancer)" || pl=""
  [[ -n "$pl" ]] || { printf 'absent \n'; return 0; }
  m19_attendre_job "$_M19_TEMOIN" "$pl" canari "${1:-600}"
}

# m19_temoin_trace_contient JOB 'regex' — le journal du job canari correspond.
m19_temoin_trace_contient() { m19_trace "$_M19_TEMOIN" "$1" 2>/dev/null | grep -Eq -- "$2"; }

# m19_temoin_sain — un pipeline du témoin réussit, sur le runner k8s-par1.
m19_temoin_sain() {
  local st id r
  read -r st id < <(m19_temoin_cycle 600)
  if [[ "$st" != success ]]; then
    echo "Le pipeline du témoin $_M19_TEMOIN ne réussit pas ($st) : répare d'abord la CI (lab/bin/check 19 35, puis le journal du job)." >&2
    return 1
  fi
  r="$(m19_api GET "projects/$(m19_enc "$_M19_TEMOIN")/jobs/$id" | jq -r '.runner.description // empty')"
  if [[ "$r" != "$_M19_RUNNER" ]]; then
    echo "Le job du témoin a tourné sur « $r » et non sur $_M19_RUNNER : seul $_M19_RUNNER doit porter l'étiquette k8s." >&2
    return 1
  fi
}

# m19_temoin — crée le témoin s'il n'existe pas.
m19_temoin() {
  m19_temoin_id >/dev/null 2>&1 && return 0
  m19_temoin_creer
}

# --- Modifications du dépôt témoin (commits de Lucas, défaits par commit inverse) ---

_m19_cle() { printf '%s' "$1" | tr '/.' '__'; }

# m19_temoin_maj EXX BRANCHE MESSAGE CHEMIN FICHIER [CHEMIN FICHIER…] — commit de Lucas sur le témoin ;
#   mémorise le contenu d'origine de chaque chemin (une fois) et son empreinte injectée. Affiche le SHA.
m19_temoin_maj() {
  local ex="$1" br="$2" msg="$3" d c actions="[]" a sha
  shift 3
  d="$(m19_etat "$ex")"
  while (($# >= 2)); do
    c="$(_m19_cle "$1")"
    if [[ ! -e "$d/depot.$c.orig" ]]; then
      if m19_brut "$_M19_TEMOIN" "$1" "$br" >"$d/depot.$c.orig" 2>/dev/null; then :; else printf 'ABSENT' >"$d/depot.$c.orig"; fi
      printf '%s\t%s\n' "$1" "$br" >>"$d/depot.liste"
    fi
    if [[ "$(cat "$d/depot.$c.orig")" == ABSENT ]]; then a=create; else a=update; fi
    actions="$(jq --argjson x "$(m19_action "$a" "$1" "$2")" '. + [$x]' <<<"$actions")"
    m19_ecraser "$ex" "depot.$c.empreinte" "$(m19_sha <"$2")"
    shift 2
  done
  sha="$(m19_commit --lucas "$_M19_TEMOIN" "$br" "$msg" "$actions")" || sha=""
  [[ -n "$sha" ]] || return 1
  m19_journal "$ex" "commit $sha sur $_M19_TEMOIN ($br) : $msg"
  printf '%s\n' "$sha"
}

# m19_temoin_retablir EXX — commit inverse : chaque fichier encore identique à la version injectée
#   reprend son contenu d'origine. Les fichiers modifiés depuis (réparation) sont laissés.
m19_temoin_retablir() {
  local ex="$1" d chemin br c actions="[]" act cur
  d="$(m19_etat "$ex")"
  [[ -f "$d/depot.liste" ]] || return 0
  while IFS="$(printf '\t')" read -r chemin br; do
    c="$(_m19_cle "$chemin")"
    cur="$(m19_brut "$_M19_TEMOIN" "$chemin" "$br" 2>/dev/null | m19_sha)" || cur=""
    if [[ "$cur" == "$(m19_lire "$ex" "depot.$c.empreinte")" ]]; then
      if [[ "$(cat "$d/depot.$c.orig")" == ABSENT ]]; then
        act="$(m19_action delete "$chemin")"
      else
        act="$(m19_action update "$chemin" "$d/depot.$c.orig")"
      fi
      actions="$(jq --argjson x "$act" '. + [$x]' <<<"$actions")"
    else
      m19_journal "$ex" "annulation : $chemin modifié depuis l'injection (réparation), laissé tel quel"
    fi
  done <"$d/depot.liste"
  br="$(head -n 1 "$d/depot.liste" | cut -f2)"
  if [[ "$(jq 'length' <<<"$actions")" -gt 0 ]]; then
    m19_commit "$_M19_TEMOIN" "$br" "Revert des changements de Lucas (M19-$ex, annulation par lab/bin/break)" "$actions" >/dev/null ||
      wb_avert "commit inverse impossible sur $_M19_TEMOIN ($br) : copies dans $d"
  fi
  rm -f -- "$d"/depot.*
}

# m19_canari_publier EXX MESSAGE 'expression yq' — Lucas publie une nouvelle version du composant
#   canari (commit du gabarit, étiquette 1.N.0) puis fait consommer cette version par le témoin.
#   Affiche « version sha_du_commit_de_consommation ».
m19_canari_publier() {
  local ex="$1" msg="$2" expr="$3" d pid sha v ancienne
  d="$(m19_etat "$ex")"
  pid="$(m19_temoin_id)" || return 1
  m19_brut "$_M19_TEMOIN" templates/canari/template.yml main >"$d/canari.yml" || return 1
  m19_brut "$_M19_TEMOIN" .gitlab-ci.yml main >"$d/ci.yml" || return 1
  ancienne="$(sed -n 's|.*/canari@\([0-9][0-9.]*\).*|\1|p' "$d/ci.yml" | head -n 1)"
  [[ -n "$ancienne" ]] || return 10
  yq -i "$expr" "$d/canari.yml" || return 1
  sha="$(m19_temoin_maj "$ex" main "$msg (M19-$ex)" templates/canari/template.yml "$d/canari.yml")" || return 1
  v="$(m19_api GET "projects/$pid/repository/tags?per_page=100" | jq -r '
        [.[].name | select(test("^1\\.[0-9]+\\.0$")) | split(".")[1] | tonumber] | (max // 0) + 1 | "1.\(.).0"')"
  m19_api POST "projects/$pid/repository/tags" --data-urlencode "tag_name=$v" --data-urlencode "ref=$sha" \
    --data-urlencode "message=canari $v" >/dev/null || return 1
  m19_ecrire "$ex" canari-version "$v"
  sed "s|/canari@$ancienne|/canari@$v|" "$d/ci.yml" >"$d/ci.nouveau"
  sha="$(m19_temoin_maj "$ex" main "chore(ci): canari $v (M19-$ex)" .gitlab-ci.yml "$d/ci.nouveau")" || return 1
  rm -f -- "$d/canari.yml" "$d/ci.yml" "$d/ci.nouveau"
  printf '%s %s\n' "$v" "$sha"
}

# m19_pas_de_pipeline SHA [SECONDES] — aucun pipeline n'a été créé pour ce commit du témoin.
m19_pas_de_pipeline() {
  sleep "${2:-60}"
  [[ -z "$(m19_pipeline_du_commit "$_M19_TEMOIN" "$1")" ]]
}

# ---------------------------------------------------------------------------
# Santé avant injection
# ---------------------------------------------------------------------------

# m19_sain — refuse de casser une chaîne de CI qui ne va pas bien.
m19_sain() {
  local c rid st
  for c in curl jq yq perl kubectl; do
    command -v "$c" >/dev/null 2>&1 || { echo "outil manquant sur adm01 : $c" >&2; return 1; }
  done
  m19_api GET version >/dev/null || { echo "API GitLab inaccessible avec le jeton d'administration." >&2; return 1; }
  rid="$(m19_runner_id)"
  [[ -n "$rid" ]] || { echo "Runner d'instance « $_M19_RUNNER » introuvable (M19-E04)." >&2; return 1; }
  st="$(m19_api GET "runners/$rid" | jq -r '"\(.status) \(.paused)"')"
  [[ "$st" == "online false" ]] || { echo "Le runner $_M19_RUNNER n'est pas en ligne et actif ($st) : rien n'est cassé." >&2; return 1; }
  wb_kubectl get --raw /readyz >/dev/null 2>&1 || { echo "L'API de k8s-par1 ne répond pas : rien n'est cassé." >&2; return 1; }
  [[ -n "$(m19_runner_cm)" ]] || { echo "ConfigMap du runner (gabarit vers ci-jobs) introuvable dans $_M19_NS_RUNNER." >&2; return 1; }
}

# m19_preparer — précondition commune : chaîne saine, témoin présent et vert. Pendant l'astreinte
# (_M19_ASTREINTE=1), break-E43 a fait ces contrôles une fois avant la première panne.
m19_preparer() {
  if [[ -n "${_M19_ASTREINTE:-}" ]]; then return 0; fi
  m19_sain || return 1
  m19_temoin || return 1
  m19_temoin_sain
}
