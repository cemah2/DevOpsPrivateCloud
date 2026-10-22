# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E37.sh — M20-E37 « Panne : Argo CD ne lit plus le dépôt »
#
# Variantes :
#   1. Secret d'identifiants (repo-creds) du groupe mediagenda « restauré d'une ancienne copie » :
#      le mot de passe est un ancien jeton de déploiement, révoqué (refus d'authentification) ;
#   2. racine MédiSphère retirée de argocd-tls-certs-cm (entrée git01.par1.medisphere.internal) :
#      le repo-server ne fait plus confiance au certificat de la forge ;
#   3. adresse du dépôt de labo modifiée dans plateforme/gitops (commit de Lucas : la forge
#      « déménage » sous gitlab.par1…, nom qui n'existe pas) ;
#   4. CiliumNetworkPolicy de refus ajoutée dans l'espace argocd : le repo-server ne joint plus
#      git01 en 443 (« durcissement » de Lucas).
# Les objets modifiés sont sauvegardés (~/.local/state/workbook/M20-E37/, 600 : la copie du Secret
# contient le vrai jeton) et ne sont restaurés que s'ils portent encore la marque de la panne.
# Aucune application n'est modifiée dans le cluster : Argo CD cesse seulement de voir Git.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m20-commun.sh
source "$WB_ROOT/modules/20-gitops/corrige/pannes/_m20-commun.sh"

_E37_APP_LABO="${WB_M20_APP_LABO:-labo}"
_E37_MARQUE="sauvegarde-2026-09"
_E37_CNP=argocd-sortie-restreinte

# _e37_secret_creds — Secret repo-creds à altérer : celui du groupe mediagenda s'il existe, sinon
# celui qui couvre toute la forge.
_e37_secret_creds() {
  wb_kubectl -n "$_M20_NS" get secrets -l argocd.argoproj.io/secret-type=repo-creds -o json 2>/dev/null | jq -r --arg f "$_M20_FQDN_GIT" '
    [.items[] | {n: .metadata.name, u: ((.data.url // "") | @base64d)}
     | select(.u | startswith("https://" + $f))] as $l
    | ([$l[] | select(.u | test("/mediagenda/?$"))][0] // [$l[] | select(.u | test("^https://[^/]+/?$"))][0] // empty) | .n'
}

# _e37_erreur_depot APP 'regex' — l'Application signale une erreur de comparaison qui correspond.
_e37_erreur_depot() {
  m20_rafraichir hard "$1"
  m20_app "$1" | jq -e --arg r "$2" '[.status.conditions[]? | select(.type | test("ComparisonError|InvalidSpecError"))
    | select((.message // "") | test($r; "i"))] | length > 0' >/dev/null 2>&1
}

_m20E37_une() {
  local n="$1" s jeton cle f fichiers t actions
  m20_debut E37
  case "$n" in
    1)
      s="$(_e37_secret_creds)"
      [[ -n "$s" ]] || return 10
      m20_sauver_objet E37 secret "$s" "$_M20_NS" || return 1
      m20_ecrire E37 secret "$s"
      jeton="gldt-$(openssl rand -hex 10)"
      wb_kubectl -n "$_M20_NS" get secret "$s" -o json | jq --arg p "$(printf '%s' "$jeton" | base64 -w0)" --arg m "$_E37_MARQUE" '
        .data.password = $p | .metadata.annotations["medisphere.internal/restaure-depuis"] = $m
        | del(.metadata.managedFields)' | wb_kubectl replace -f - >/dev/null || return 1
      m20_journal E37 "Secret $s : mot de passe remplacé par un ancien jeton"
      m20_attendre 300 _e37_erreur_depot "$_M20_APP_DEV" 'auth|denied|403|401|credentials' || { _e37_defaire 1; return 10; }
      ;;
    2)
      cle="$_M20_FQDN_GIT"
      wb_kubectl -n "$_M20_NS" get configmap argocd-tls-certs-cm -o json 2>/dev/null |
        jq -e --arg k "$cle" '.data[$k] // "" | test("BEGIN CERTIFICATE")' >/dev/null 2>&1 || return 10
      m20_sauver_objet E37 configmap argocd-tls-certs-cm "$_M20_NS" || return 1
      wb_kubectl -n "$_M20_NS" patch configmap argocd-tls-certs-cm --type json \
        -p "[{\"op\":\"remove\",\"path\":\"/data/${cle}\"}]" >/dev/null || return 1
      m20_journal E37 "argocd-tls-certs-cm : entrée $cle retirée"
      m20_attendre 300 _e37_erreur_depot "$_M20_APP_DEV" 'x509|certificate|tls' || { _e37_defaire 2; return 10; }
      ;;
    3)
      m20_app "$_E37_APP_LABO" >/dev/null || return 10
      mapfile -t fichiers < <(m20_chercher "$_M20_GITOPS" "https://${_M20_FQDN_GIT//./\\.}/formation/gitops-labo")
      ((${#fichiers[@]} > 0)) || return 10
      actions=""
      for f in "${fichiers[@]}"; do
        # Seules les Applications et ApplicationSets « déménagent » : l'AppProject labo garde
        # l'ancienne adresse dans sourceRepos (c'est lui qui refuse la nouvelle, avant toute connexion).
        m20_brut "$_M20_GITOPS" "$f" | yq -e 'select(.kind == "Application" or .kind == "ApplicationSet")' >/dev/null 2>&1 || continue
        m20_brut "$_M20_GITOPS" "$f" | yq -e 'select(.kind == "AppProject")' >/dev/null 2>&1 && continue
        t="$(mktemp)"
        m20_brut "$_M20_GITOPS" "$f" | perl -pe 's{https://git01\.par1\.medisphere\.internal/formation/gitops-labo}{https://gitlab.par1.medisphere.internal/formation/gitops-labo}g' >"$t"
        actions+="${actions:+,}$(m20_action update "$f" "$t")"
        rm -f "$t"
      done
      [[ -n "$actions" ]] || return 10
      m20_commit_lucas E37 "$_M20_GITOPS" "lucas/labo-nouvelle-adresse-forge" \
        "chore(labo): nouvelle adresse de la forge" \
        "PLAT-2137 : InfoGér annonce que la forge sera publiée sous gitlab.par1.medisphere.internal ; on anticipe sur labo." \
        "[$actions]" || return $?
      m20_rafraichir hard racine applications "$_E37_APP_LABO"
      m20_attendre 300 _e37_erreur_depot "$_E37_APP_LABO" 'gitlab\.par1|not permitted|no such host|resolve' || { _e37_defaire 3; return 10; }
      ;;
    4)
      wb_kubectl get crd ciliumnetworkpolicies.cilium.io >/dev/null 2>&1 || return 10
      if wb_kubectl -n "$_M20_NS" get ciliumnetworkpolicies.cilium.io "$_E37_CNP" >/dev/null 2>&1; then return 10; fi
      f="$(mktemp)"
      cat >"$f" <<EOF
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: $_E37_CNP
  namespace: $_M20_NS
  labels:
    medisphere.internal/ticket: SEC-2137
  annotations:
    medisphere.internal/motif: "Durcissement : le repo-server ne sort plus que vers les adresses publiées (Lucas)"
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: argocd-repo-server
  egressDeny:
    - toCIDR:
        - 10.10.20.12/32
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
EOF
      wb_kubectl apply --dry-run=server -f "$f" >/dev/null 2>&1 || { rm -f "$f"; return 10; }
      wb_kubectl apply -f "$f" >/dev/null || { rm -f "$f"; return 1; }
      rm -f "$f"
      m20_ecrire E37 cnp posee
      m20_journal E37 "CiliumNetworkPolicy $_E37_CNP posée (refus de 10.10.20.12:443 au repo-server)"
      m20_attendre 300 _e37_erreur_depot "$_M20_APP_DEV" 'timeout|timed out|deadline|connect|i/o' || { _e37_defaire 4; return 10; }
      ;;
  esac
  m20_journal E37 "variante $n posée"
}

_e37_defaire() {
  local n="$1" s v cm
  case "$n" in
    1)
      s="$(m20_lire E37 secret)"
      [[ -n "$s" ]] || return 0
      if wb_kubectl -n "$_M20_NS" get secret "$s" -o json 2>/dev/null |
        jq -e --arg m "$_E37_MARQUE" '.metadata.annotations["medisphere.internal/restaure-depuis"] == $m' >/dev/null 2>&1; then
        m20_restaurer_objet E37 secret "$s" "$_M20_NS"
      else
        m20_oublier_objet E37 secret "$s" "$_M20_NS"
      fi
      m20_oublier E37 secret
      ;;
    2)
      cm="$(wb_kubectl -n "$_M20_NS" get configmap argocd-tls-certs-cm -o json 2>/dev/null)" || cm=""
      if [[ -n "$cm" ]] && ! jq -e --arg k "$_M20_FQDN_GIT" '.data[$k] != null' >/dev/null 2>&1 <<<"$cm"; then
        v="$(m20_objet_sauve E37 configmap argocd-tls-certs-cm "$_M20_NS" | jq -c --arg k "$_M20_FQDN_GIT" '.data[$k] // empty')" || v=""
        if [[ -n "$v" ]]; then
          # Ajout de la seule entrée retirée : une autre modification faite entre-temps est conservée.
          wb_kubectl -n "$_M20_NS" patch configmap argocd-tls-certs-cm --type merge \
            -p "{\"data\":{\"$_M20_FQDN_GIT\":$v}}" >/dev/null 2>&1 || wb_avert "entrée $_M20_FQDN_GIT non rétablie dans argocd-tls-certs-cm"
        fi
      fi
      m20_oublier_objet E37 configmap argocd-tls-certs-cm "$_M20_NS"
      ;;
    3)
      m20_defaire_commits E37
      m20_rafraichir hard racine applications "$_E37_APP_LABO"
      ;;
    4)
      if [[ -n "$(m20_lire E37 cnp)" ]]; then
        if wb_kubectl -n "$_M20_NS" get ciliumnetworkpolicies.cilium.io "$_E37_CNP" -o json 2>/dev/null |
          jq -e '.metadata.labels["medisphere.internal/ticket"] == "SEC-2137"' >/dev/null 2>&1; then
          wb_kubectl -n "$_M20_NS" delete ciliumnetworkpolicies.cilium.io "$_E37_CNP" >/dev/null 2>&1 || wb_avert "politique $_E37_CNP non retirée"
        fi
        m20_oublier E37 cnp
      fi
      ;;
  esac
  m20_rafraichir hard "$_M20_APP_DEV"
}

panne_E37_v1() { m20_preparer "$_M20_APP_DEV" && m20_essayer E37 4 1; }
panne_E37_v2() { m20_preparer "$_M20_APP_DEV" && m20_essayer E37 4 2; }
panne_E37_v3() { m20_preparer "$_M20_APP_DEV" && m20_essayer E37 4 3; }
panne_E37_v4() { m20_preparer "$_M20_APP_DEV" && m20_essayer E37 4 4; }

verifier_E37() {
  case "${WB_VAR:-}" in
    3) _e37_erreur_depot "$_E37_APP_LABO" '.' ;;
    *) _e37_erreur_depot "$_M20_APP_DEV" '.' ;;
  esac
}

annuler_E37() {
  case "${WB_VAR:-}" in
    [1-4]) _e37_defaire "$WB_VAR" ;;
    *) local v; for v in 1 2 3 4; do _e37_defaire "$v"; done ;;
  esac
  m20_oublier E37 debut
  m20_journal E37 "annulation"
}

resume_E37() {
  case "${WB_VAR:-}" in
    3) echo "L'application de labo est en erreur dans Argo CD : « impossible de lire le dépôt »." ;;
    *) echo "Argo CD affiche une erreur de comparaison sur MédiAgenda : il ne lit plus le dépôt." ;;
  esac
}

symptome_E37() {
  case "${WB_VAR:-}" in
    3)
      wb_symptome "Ticket INC-4737 — De : Karim Benali" \
        "L'application labo affiche une erreur rouge dans Argo CD et son statut de synchronisation" \
        "est « Unknown ». Le dépôt formation/gitops-labo est pourtant en ligne, je le clone sans souci." \
        "Les autres applications ont l'air normales. Remets labo en état et dis-moi ce qui a bougé." \
        "" \
        "Temps cible : 30 min. Contrôle : lab/bin/check 20 37"
      ;;
    *)
      wb_symptome "Ticket INC-4737 — De : Karim Benali" \
        "Argo CD affiche une erreur de comparaison sur mediagenda-dev (et sans doute ailleurs) :" \
        "statut « Unknown », message qui parle du dépôt. Les pods tournent, mais plus rien de ce qu'on" \
        "fusionne n'arrivera dans le cluster. Je clone mediagenda/deploiement sans problème depuis" \
        "adm01. Trouve ce qui empêche Argo CD de lire Git et répare-le à la source." \
        "" \
        "Temps cible : 30 min. Contrôle : lab/bin/check 20 37"
      ;;
  esac
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 20 E37 4 "$@"; }
fi
