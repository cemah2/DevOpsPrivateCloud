# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq/yq et commandes distantes entre apostrophes
# _m26-expert.sh — fonctions partagées par les vérifications du palier 4 et du mini-projet du module 26
# (check-E35 à check-E46). Sourcé par ces scripts, jamais lancé seul. LECTURE SEULE : kubectl avec le
# compte des checks (« kube », ClusterRole agrégée wb-checks-securite), vue globale (prom_requete),
# Loki locataire audit (loki_requete), Mailpit (lecture), API GitLab en lecture (gitlab_api), et
# commandes de consultation sur les VMs (check_ssh, sudo -n en lecture). Préfixe _m26x_.

_m26x_depot="${WB_DEPOT:-$HOME/medisphere}"
_m26x_rb="docs/securite/durcissement/runbooks"
_m26x_ns_falco=falco
_m26x_ns_kyverno=kyverno
_m26x_ns_pannes=wb-pannes

# _m26x_kq 'filtre jq' ARGS… — 0 si « kube get ARGS -o json » satisfait le filtre.
_m26x_kq() { local f="$1"; shift; kube get "$@" -o json 2>/dev/null | jq -e "$f" >/dev/null 2>&1; }
# _m26x_existe TYPE NOM [ESPACE] — 0 si l'objet existe (vu par le compte des checks).
_m26x_existe() { kube get "$1" "$2" ${3:+-n "$3"} >/dev/null 2>&1; }
# _m26x_absent TYPE NOM [ESPACE] — 0 si l'objet n'existe pas.
_m26x_absent() { ! _m26x_existe "$@"; }

# _m26x_app_ok APP — Application Argo CD Synced, Healthy, dernière opération réussie.
_m26x_app_ok() {
  _m26x_kq '.status.sync.status == "Synced" and .status.health.status == "Healthy"
            and ((.status.operationState.phase // "Succeeded") == "Succeeded")' -n argocd applications.argoproj.io "$1"
}

# _m26x_aucune_panne_active [EXX…] — aucune des pannes listées (ou M26-* si aucune) n'est marquée active.
_m26x_aucune_panne_active() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives" e
  if (($# == 0)); then
    [[ -z "$(find "$d" -maxdepth 1 -name 'M26-E*' 2>/dev/null)" ]]
    return
  fi
  for e in "$@"; do [[ ! -e "$d/M26-$e" ]] || return 1; done
}

# _m26x_vp_sans_condition NOM_CONDITION — aucune ValidatingPolicy ne porte une matchCondition de ce nom
# (sert à détecter une garde trop large injectée). 0 = propre.
_m26x_vp_sans_condition() {
  kube get validatingpolicies.policies.kyverno.io -o json 2>/dev/null |
    jq -e --arg n "$1" '[.items[]? | select((.spec.matchConditions // []) | any(.name == $n))] | length == 0' >/dev/null 2>&1
}

# _m26x_vp_sans_exemption_groupe — aucune ValidatingPolicy ne saute un groupe d'administrateurs.
_m26x_vp_sans_exemption_groupe() {
  kube get validatingpolicies.policies.kyverno.io -o json 2>/dev/null |
    jq -e '[.items[]? | select((.spec.matchConditions // []) | any(.expression | test("userInfo.groups")))] | length == 0' >/dev/null 2>&1
}

# _m26x_psa_enforce ESPACE — niveau pod-security.kubernetes.io/enforce de l'espace (vide si aucun).
_m26x_psa_enforce() { kube get namespace "$1" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null; }

# _m26x_regle_falco_active MOTIF — une règle Falco chargée (ConfigMap de l'espace falco) contient le
# motif et n'est pas désactivée (pas de « enabled: false » attaché).
_m26x_regle_falco_active() {
  kube -n "$_m26x_ns_falco" get configmap -o json 2>/dev/null |
    jq -e --arg m "$1" '[.items[].data // {} | to_entries[] | .value | select(test($m; "i"))
      | select(test("enabled: *false") | not)] | length > 0' >/dev/null 2>&1
}

# _m26x_ssh_ok HÔTE — l'hôte répond en SSH + sudo -n (sinon le contrôle qui l'utilise doit skip).
_m26x_ssh_ok() { remote "$1" 'sudo -n true' </dev/null >/dev/null 2>&1; }
# _m26x_ssh HÔTE 'commande' — exécute une commande de consultation en root (sortie standard).
_m26x_ssh() { local h="$1"; shift; remote "$h" "sudo -n bash -c $(printf '%q' "$*")" </dev/null 2>/dev/null; }

# _m26x_doc_commite MOTIF — un fichier du dépôt de documentation correspond au motif, suivi par git et
# sans modification en attente.
_m26x_doc_commite() {
  (
    cd "$_m26x_depot" 2>/dev/null || exit 1
    shopt -s nullglob
    # shellcheck disable=SC2206
    local -a f=($1)
    ((${#f[@]} > 0)) || exit 1
    git ls-files --error-unmatch "${f[0]}" >/dev/null 2>&1 && [[ -z "$(git status --porcelain -- "${f[0]}")" ]]
  )
}
# _m26x_doc_contient MOTIF 'regex' — le premier fichier correspondant contient la regex.
_m26x_doc_contient() {
  (
    cd "$_m26x_depot" 2>/dev/null || exit 1
    shopt -s nullglob
    # shellcheck disable=SC2206
    local -a f=($1)
    ((${#f[@]} > 0)) || exit 1
    grep -Eqi -- "$2" "${f[0]}"
  )
}
# _m26x_doc_existe 'regex de chemin' — un fichier suivi par git correspond.
_m26x_doc_existe() { (cd "$_m26x_depot" 2>/dev/null && git ls-files | grep -Eq -- "$1"); }

# _m26x_git_brut PROJET CHEMIN — contenu d'un fichier sur main (API GitLab, jeton de lecture).
_m26x_git_brut() {
  gitlab_api "projects/$(jq -rn --arg v "$1" '$v|@uri')/repository/files/$(jq -rn --arg v "$2" '$v|@uri')/raw?ref=main"
}
# _m26x_pipeline_main_vert PROJET — le dernier pipeline de main a réussi.
_m26x_pipeline_main_vert() {
  gitlab_api "projects/$(jq -rn --arg v "$1" '$v|@uri')/pipelines?ref=main&per_page=1" 2>/dev/null |
    jq -e '.[0].status == "success"' >/dev/null 2>&1
}

# _m26x_conformite 'PromQL' — valeur du premier résultat (vide si aucun) de la vue globale.
_m26x_conformite_val() { prom_requete "$1" 2>/dev/null | jq -r '.data.result[0].value[1] // empty' 2>/dev/null; }
