# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # « $patch: delete » et filtres jq littéraux entre apostrophes
# break-E42.sh — M20-E42 « Panne : le cluster de l'agence est Unknown »
#
# Cible : le cluster k3s lyo-k3s01 (VM 2201, 10.10.99.61) enregistré dans Argo CD (Secret de
# cluster étiqueté site=lyo1, M20-E26) et l'Application qui y déploie. Variantes :
#   1. Secret de cluster « restauré d'une ancienne copie » : jeton du compte argocd-gestion périmé
#      (refus d'authentification, 401) ;
#   2. pare-feu local de lyo-k3s01 : une table nftables refuse l'API (6443) depuis le VLAN 40 et
#      le réseau des pods de k8s-par1 (« durcissement » de l'agence) ;
#   3. Secret de cluster : autorité (caData) remplacée par la racine MédiSphère, qui n'a pas signé
#      le certificat de l'API de k3s (x509) ;
#   4. liaisons RBAC du compte argocd-gestion supprimées sur lyo-k3s01 (sauvegardées sur la VM,
#      /var/lib/workbook/M20-E42.*) : authentifié mais plus aucun droit (403).
# Si lyo-k3s01 n'existe plus (détruite au mini-projet M20-E46), l'injection refuse proprement.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m20-commun.sh
source "$WB_ROOT/modules/20-gitops/corrige/pannes/_m20-commun.sh"

_E42_MARQUE="sauvegarde-2026-08"
_E42_TABLE=filtrage_agence
_E42_SA=argocd-gestion

# _e42_secret — nom du Secret de cluster de l'agence (étiquette site=lyo1).
_e42_secret() {
  wb_kubectl -n "$_M20_NS" get secrets -l argocd.argoproj.io/secret-type=cluster,site=lyo1 -o json 2>/dev/null |
    jq -r '.items[0].metadata.name // empty'
}

# _e42_apps — Applications qui déploient sur ce cluster (par adresse ou par nom).
_e42_apps() {
  local s serveur nom
  s="$(wb_kubectl -n "$_M20_NS" get secret "$1" -o json 2>/dev/null)" || return 1
  serveur="$(jq -r '.data.server // "" | @base64d' <<<"$s")"
  nom="$(jq -r '.data.name // "" | @base64d' <<<"$s")"
  wb_kubectl -n "$_M20_NS" get applications.argoproj.io -o json 2>/dev/null | jq -r --arg s "$serveur" --arg n "$nom" '
    .items[] | select((.spec.destination.server // "") == $s or ((.spec.destination.name // "") == $n and $n != "")) | .metadata.name'
}

_e42_cluster_ko() {
  local a ko=1
  while read -r a; do
    [[ -n "$a" ]] || continue
    m20_rafraichir hard "$a"
    if m20_app "$a" | jq -e '.status.sync.status == "Unknown"
        or ([.status.conditions[]? | select(.type | test("ComparisonError|UnknownError"))] | length > 0)' >/dev/null 2>&1; then
      ko=0
    fi
  done < <(m20_lire E42 apps)
  return "$ko"
}

_e42_config() { wb_kubectl -n "$_M20_NS" get secret "$1" -o json 2>/dev/null | jq -r '.data.config // "" | @base64d'; }

# _e42_remplacer_config SECRET 'filtre jq sur la configuration ($v)' VALEUR — réécrit .data.config
# et marque le Secret.
_e42_remplacer_config() {
  local s="$1" f="$2" c
  c="$(_e42_config "$s" | jq -c --arg v "$3" "$f")" || return 1
  [[ -n "$c" ]] || return 1
  wb_kubectl -n "$_M20_NS" get secret "$s" -o json | jq --arg c "$(printf '%s' "$c" | base64 -w0)" --arg m "$_E42_MARQUE" '
    .data.config = $c | .metadata.annotations["medisphere.internal/restaure-depuis"] = $m | del(.metadata.managedFields)' |
    wb_kubectl replace -f - >/dev/null
}

_e42_joignable() { remote "$_M20_LYO_HOTE" true </dev/null >/dev/null 2>&1; }

_m20E42_une() {
  local n="$1" s jeton ca
  m20_debut E42
  s="$(m20_lire E42 secret)"
  case "$n" in
    1)
      _e42_config "$s" | jq -e '.bearerToken // "" | length > 20' >/dev/null 2>&1 || return 10
      m20_sauver_objet E42 secret "$s" "$_M20_NS" || return 1
      jeton="eyJhbGciOiJSUzI1NiIsImtpZCI6Imx5by0yMDI2LTA4In0.$(openssl rand -base64 96 | tr -d '\n=' | tr '+/' '-_').$(openssl rand -base64 64 | tr -d '\n=' | tr '+/' '-_')"
      _e42_remplacer_config "$s" '.bearerToken = $v' "$jeton" || return 1
      m20_journal E42 "Secret $s : jeton remplacé par une ancienne valeur"
      ;;
    2)
      _e42_joignable || return 10
      wb_exec "$_M20_LYO_HOTE" TABLE="$_E42_TABLE" >/dev/null <<'EOF' || return $?
command -v nft >/dev/null 2>&1 || exit 10
nft list table inet "$TABLE" >/dev/null 2>&1 && exit 10
nft -f - <<NFT || exit 1
table inet $TABLE {
  chain entree {
    type filter hook input priority -10; policy accept;
    ip saddr { 10.10.40.0/24, 10.240.0.0/16 } tcp dport 6443 counter drop comment "LYO-2142 : API réservée à l'agence"
  }
}
NFT
journal "table inet $TABLE posée : 10.10.40.0/24 et 10.240.0.0/16 refusés vers 6443"
EOF
      m20_ecrire E42 nft posee
      ;;
    3)
      [[ -r /usr/local/share/ca-certificates/medisphere-root-ca.crt ]] || return 10
      _e42_config "$s" | jq -e '(.tlsClientConfig.insecure // false) == false and ((.tlsClientConfig.caData // "") | length > 0)' >/dev/null 2>&1 || return 10
      m20_sauver_objet E42 secret "$s" "$_M20_NS" || return 1
      ca="$(base64 -w0 </usr/local/share/ca-certificates/medisphere-root-ca.crt)"
      _e42_remplacer_config "$s" '.tlsClientConfig.caData = $v' "$ca" || return 1
      m20_journal E42 "Secret $s : caData remplacée par la racine MédiSphère"
      ;;
    4)
      _e42_joignable || return 10
      wb_exec "$_M20_LYO_HOTE" SA="$_E42_SA" >/dev/null <<'EOF' || return $?
command -v k3s >/dev/null 2>&1 || exit 10
K="k3s kubectl"
n=0
while read -r nom sujets; do
  case ",$sujets," in *",$SA,"*) ;; *) continue ;; esac
  $K get clusterrolebinding "$nom" -o yaml > "$WB_DIR/$WB_EX.crb.$nom.yaml" || exit 1
  $K delete clusterrolebinding "$nom" >/dev/null || exit 1
  journal "ClusterRoleBinding $nom supprimée (sauvegarde $WB_DIR/$WB_EX.crb.$nom.yaml)"
  n=$((n + 1))
done < <($K get clusterrolebindings -o custom-columns=N:.metadata.name,S:.subjects[*].name --no-headers 2>/dev/null)
while read -r ns nom sujets; do
  case ",$sujets," in *",$SA,"*) ;; *) continue ;; esac
  $K -n "$ns" get rolebinding "$nom" -o yaml > "$WB_DIR/$WB_EX.rb.$ns.$nom.yaml" || exit 1
  $K -n "$ns" delete rolebinding "$nom" >/dev/null || exit 1
  journal "RoleBinding $ns/$nom supprimée (sauvegarde $WB_DIR/$WB_EX.rb.$ns.$nom.yaml)"
  n=$((n + 1))
done < <($K get rolebindings -A -o custom-columns=NS:.metadata.namespace,N:.metadata.name,S:.subjects[*].name --no-headers 2>/dev/null)
[ "$n" -gt 0 ] || exit 10
EOF
      m20_ecrire E42 rbac posee
      ;;
  esac
  m20_journal E42 "variante $n posée"
  m20_attendre 300 _e42_cluster_ko || { _e42_defaire "$n"; return 10; }
}

_e42_defaire() {
  local n="$1" s
  s="$(m20_lire E42 secret)"
  case "$n" in
    1 | 3)
      [[ -n "$s" ]] || return 0
      if wb_kubectl -n "$_M20_NS" get secret "$s" -o json 2>/dev/null |
        jq -e --arg m "$_E42_MARQUE" '.metadata.annotations["medisphere.internal/restaure-depuis"] == $m' >/dev/null 2>&1; then
        m20_restaurer_objet E42 secret "$s" "$_M20_NS"
      else
        m20_oublier_objet E42 secret "$s" "$_M20_NS"
      fi
      ;;
    2)
      if [[ -n "$(m20_lire E42 nft)" ]]; then
        wb_exec "$_M20_LYO_HOTE" TABLE="$_E42_TABLE" >/dev/null <<'EOF' || wb_avert "table nftables $_E42_TABLE non retirée de lyo-k3s01 (nft delete table inet $_E42_TABLE)"
if nft list table inet "$TABLE" >/dev/null 2>&1; then
  nft delete table inet "$TABLE" && journal "annulation : table inet $TABLE retirée"
fi
exit 0
EOF
        m20_oublier E42 nft
      fi
      ;;
    4)
      if [[ -n "$(m20_lire E42 rbac)" ]]; then
        wb_exec "$_M20_LYO_HOTE" >/dev/null <<'EOF' || wb_avert "liaisons RBAC d'argocd-gestion non rétablies sur lyo-k3s01 (sauvegardes dans /var/lib/workbook)"
K="k3s kubectl"
for f in "$WB_DIR/$WB_EX".crb.*.yaml "$WB_DIR/$WB_EX".rb.*.yaml; do
  [ -e "$f" ] || continue
  # Recréée seulement si l'apprenant ne l'a pas déjà rétablie (même nom).
  if ! $K get -f "$f" >/dev/null 2>&1; then
    sed -e '/^  resourceVersion:/d' -e '/^  uid:/d' -e '/^  creationTimestamp:/d' "$f" | $K create -f - >/dev/null && journal "annulation : $(basename "$f") recréée"
  fi
  rm -f "$f"
done
exit 0
EOF
        m20_oublier E42 rbac
      fi
      ;;
  esac
  local a
  while read -r a; do [[ -n "$a" ]] && m20_rafraichir hard "$a"; done < <(m20_lire E42 apps)
}

_e42_preparer() {
  local s apps
  s="$(_e42_secret)"
  if [[ -z "$s" ]]; then
    echo "Aucun cluster site=lyo1 enregistré dans Argo CD (lyo-k3s01 détruite au mini-projet ?) : panne sans objet, rien n'est cassé." >&2
    return 1
  fi
  apps="$(_e42_apps "$s")"
  if [[ -z "$apps" ]]; then
    echo "Aucune Application ne déploie sur le cluster de l'agence (M20-E26) : rien n'est cassé." >&2
    return 1
  fi
  if [[ -z "${_M20_ASTREINTE:-}" ]]; then
    # shellcheck disable=SC2086  # liste d'Applications voulue
    m20_sain $apps || return 1
  fi
  m20_ecrire E42 secret "$s"
  m20_ecrire E42 apps "$apps"
}

panne_E42_v1() { _e42_preparer && m20_essayer E42 4 1; }
panne_E42_v2() { _e42_preparer && m20_essayer E42 4 2; }
panne_E42_v3() { _e42_preparer && m20_essayer E42 4 3; }
panne_E42_v4() { _e42_preparer && m20_essayer E42 4 4; }

verifier_E42() { _e42_cluster_ko; }

annuler_E42() {
  case "${WB_VAR:-}" in
    [1-4]) _e42_defaire "$WB_VAR" ;;
    *) local v; for v in 1 2 4; do _e42_defaire "$v"; done ;;
  esac
  m20_oublier E42 debut
  m20_oublier E42 secret
  m20_oublier E42 apps
  m20_journal E42 "annulation"
}

resume_E42() {
  echo "Le cluster de l'agence de Lyon apparaît en erreur dans Argo CD et son application est « Unknown »."
}

symptome_E42() {
  wb_symptome "Ticket INC-4742 — De : Karim Benali" \
    "Dans Argo CD, le cluster de l'agence LYO1 (lyo-k3s01) n'est plus joignable et l'application" \
    "qui y est déployée affiche « Unknown ». Les postes de l'agence utilisent pourtant toujours" \
    "l'application locale. L'agence dit avoir « juste fait un peu de ménage ». Rétablis la gestion" \
    "du cluster depuis Argo CD sans lui donner plus de droits qu'avant." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 20 42"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 20 E42 4 "$@"; }
fi
