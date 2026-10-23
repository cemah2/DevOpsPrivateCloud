# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres yq/jq et scripts distants entre apostrophes
# break-E36.sh — M24-E36 « Panne : kubectl refuse les jetons »
#
# Le fichier d'authentification structurée de kube-apiserver (WB_M24_AUTHN_FICHIER, défaut
# /etc/kubernetes/authentification/config.yaml, posé par le rôle k8s_plan_controle en M24-E16) est
# modifié À LA MAIN, de la même façon, sur LES TROIS nœuds de contrôle (choix assumé : un seul nœud
# donnerait un refus intermittent, une requête sur trois, c'est l'objet de M24-E38 v3). kube-apiserver
# relit le fichier de lui-même (surveillance d'environ une minute) : aucun redémarrage.
#   1. audience attendue changée : « kubernetes » → « kubernetes-par1 » : tous les jetons refusés (401) ;
#   2. préfixe des groupes changé : « oidc: » → « oidc- » : authentifié, mais plus aucune liaison RBAC
#      ne correspond (403 partout, sauf ce qui est lié à l'utilisateur lui-même) ;
#   3. règle de validation ajoutée (claimValidationRules, CEL) qui réserve kubectl aux groupes
#      « plateforme* » : Julien, Nadia et Sophie refusés (401), l'apprenant et Karim passent.
# Le fichier est réécrit en place (même inode) et sauvegardé avant ; la panne est constatée par les
# métriques de rechargement de chaque kube-apiserver
# (apiserver_authentication_config_controller_automatic_reload_last_timestamp_seconds{status="success"}).
# Ce qui ne marcherait PAS comme panne, et pourquoi (corrigé) : une racine de confiance fausse ou un
# émetteur injoignable à chaud — le rechargement échoue et kube-apiserver garde l'ancienne configuration.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m24-commun.sh
source "$WB_ROOT/modules/24-identite/corrige/pannes/_m24-commun.sh"

_e36_t1() {
  yq 'select(.kind == "AuthenticationConfiguration")
      | (.jwt[] | select(.issuer.url == strenv(EM)) | .issuer.audiences) |= [.[] | select(. == "kubernetes") | "kubernetes-par1"] + [.[] | select(. != "kubernetes")]
      | select([.jwt[].issuer.audiences[]] | any_c(. == "kubernetes-par1"))'
}
_e36_i1() { yq '(.jwt[].issuer.audiences[] | select(. == "kubernetes-par1")) = "kubernetes"'; }
_e36_t2() {
  yq 'select(.kind == "AuthenticationConfiguration")
      | (.jwt[] | select(.issuer.url == strenv(EM)) | .claimMappings.groups | select(.prefix == "oidc:") | .prefix) = "oidc-"
      | select([.jwt[].claimMappings.groups.prefix] | any_c(. == "oidc-"))'
}
_e36_i2() { yq '(.jwt[].claimMappings.groups | select(.prefix == "oidc-") | .prefix) = "oidc:"'; }
_E36_REGLE="claims.groups.exists(g, g.startsWith('plateforme'))"
_e36_t3() {
  R="$_E36_REGLE" yq 'select(.kind == "AuthenticationConfiguration")
      | (.jwt[] | select(.issuer.url == strenv(EM)) | .claimValidationRules) += [{"expression": strenv(R), "message": "kubectl réservé à l équipe Plateforme pendant l audit (SEC-2536, Lucas)"}]'
}
_e36_i3() { R="$_E36_REGLE" yq 'del(.jwt[].claimValidationRules[]? | select(.expression == strenv(R))) | del(.jwt[] | select(.claimValidationRules == []) | .claimValidationRules)'; }

# _e36_lire NŒUD — contenu actuel du fichier.
_e36_lire() { m24_ssh "$1" "cat $(printf '%q' "$_M24_AUTHN")"; }

# _e36_ecrire NŒUD CONTENU — sauvegarde (une fois) puis réécriture en place.
_e36_ecrire() {
  m24_wb_exec "$1" "F=$_M24_AUTHN" "C=$2" <<'EOF'
[ -f "$F" ] || exit 1
sauver "$F"
printf '%s\n' "$C" | ecrire_en_place "$F"
journal "$F modifié à la main (fichier d'authentification structurée)"
EOF
}

# _e36_rechargement_ok NŒUD DEPUIS — ce kube-apiserver a rechargé le fichier avec succès après DEPUIS.
_e36_rechargement_ok() {
  local t
  t="$(m24_wb_exec "$1" <<'EOF' 2>/dev/null
a="$(sed -n 's/.*--advertise-address=\([0-9.]*\).*/\1/p' /etc/kubernetes/manifests/kube-apiserver.yaml | head -n 1)"
kubectl --kubeconfig /etc/kubernetes/admin.conf --server "https://${a:-127.0.0.1}:6443" --request-timeout=20s get --raw /metrics 2>/dev/null |
  awk '/^apiserver_authentication_config_controller_automatic_reload_last_timestamp_seconds\{.*status="success"/ {print $2}' | sort -g | tail -n 1
EOF
)" || return 1
  [[ -n "$t" ]] && awk -v t="$t" -v d="$2" 'BEGIN { exit !(t + 0 >= d + 0) }'
}

_m24E36_une() {
  local n="$1" noeud avant apres fn
  fn="_e36_t$n"
  # Préparer les trois nouveaux contenus avant de toucher à quoi que ce soit.
  local -A neuf=()
  for noeud in "${_M24_CP[@]}"; do
    avant="$(_e36_lire "$noeud")" || return 10
    apres="$(EM="$_M24_EMETTEUR" "$fn" <<<"$avant" 2>/dev/null)" || return 10
    if [[ -z "$apres" ]] || [[ "$apres" == "$avant" ]]; then return 10; fi
    neuf[$noeud]="$apres"
  done
  m24_ecrire E36 variante "$n"
  m24_ecrire E36 depuis "$(m24_maintenant)"
  for noeud in "${_M24_CP[@]}"; do
    _e36_ecrire "$noeud" "${neuf[$noeud]}" || return 1
  done
  m24_journal E36 "variante $n posée sur ${_M24_CP[*]}"
}

verifier_E36() {
  local d noeud
  d="$(m24_lire E36 depuis)"
  [[ -n "$d" ]] || return 1
  for noeud in "${_M24_CP[@]}"; do
    m24_attendre 180 _e36_rechargement_ok "$noeud" "$d" || return 1
  done
}

panne_E36_v1() { m24_sain_keycloak && m24_sain_hote "$(m24_cp1)" && m24_essayer E36 3 1; }
panne_E36_v2() { m24_sain_keycloak && m24_sain_hote "$(m24_cp1)" && m24_essayer E36 3 2; }
panne_E36_v3() { m24_sain_keycloak && m24_sain_hote "$(m24_cp1)" && m24_essayer E36 3 3; }

# Annulation : sur chaque nœud, transformation INVERSE appliquée au contenu courant (elle ne change
# rien si la marque n'y est plus : réparation de l'apprenant conservée) ; puis oubli des sauvegardes.
annuler_E36() {
  local v noeud avant apres
  v="$(m24_lire E36 variante)"
  for noeud in "${_M24_CP[@]}"; do
    if [[ -n "$v" ]]; then
      avant="$(_e36_lire "$noeud" 2>/dev/null || true)"
      if [[ -z "$avant" ]]; then
        # Nœud injoignable ou fichier illisible : la sauvegarde reste dans /var/lib/workbook.
        wb_avert "$noeud : fichier d'authentification non relu, rien rétabli (sauvegarde M24-E36 gardée dans /var/lib/workbook)"
        continue
      fi
      apres="$("_e36_i$v" <<<"$avant" 2>/dev/null || true)"
      if [[ -n "$apres" && "$apres" != "$avant" ]] && ! _e36_ecrire "$noeud" "$apres" >/dev/null 2>&1; then
        wb_avert "$noeud : fichier d'authentification non rétabli (sauvegarde M24-E36 gardée dans /var/lib/workbook)"
        continue
      fi
    fi
    m24_wb_exec "$noeud" <<'EOF' >/dev/null 2>&1 || true
m="$WB_DIR/$WB_EX.manifeste"
if [ -f "$m" ]; then
  while IFS="$(printf '\t')" read -r src dst; do [ "$dst" = ABSENT ] || rm -f -- "$dst"; done < "$m"
  rm -f "$m"
fi
journal "annulation : transformation inverse appliquée si nécessaire"
EOF
  done
  m24_oublier E36 variante
  m24_oublier E36 depuis
  m24_journal E36 "annulation"
}

resume_E36() { echo "kubectl par OIDC est refusé depuis une heure (401 ou 403 selon les personnes) ; admin.conf passe."; }

symptome_E36() {
  local detail
  case "$WB_VAR" in
    1) detail="Ce matin, kubectl me répond « You must be logged in to the server (Unauthorized) », à moi comme à Karim. Je me suis reconnecté (navigateur, OTP) : pareil." ;;
    2) detail="Ce matin, kubectl me connecte bien (kubectl auth whoami répond) mais tout est « Forbidden », même lister les pods de mediagenda-dev." ;;
    *) detail="Ce matin, kubectl me répond « Unauthorized ». Nadia et Sophie aussi. Karim dit que chez lui « tout marche »." ;;
  esac
  wb_symptome "Ticket INC-5136 — De : Julien Petit" \
    "$detail" \
    "Rien n'a changé de notre côté. Je dois livrer en recette avant midi." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 24 36"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 24 E36 3 "$@"; }
fi
