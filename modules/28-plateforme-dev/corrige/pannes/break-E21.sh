# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et yq entre apostrophes
# break-E21.sh — M28-E21 « Panne : une équipe ne peut plus créer d'espace » (locataire medidoc).
#
# Variantes (jamais les droits de la plateforme ni d'Argo CD : administrators, users autres que
# oidc:medidoc et ClusterRoles de Capsule ne sont pas touchés) :
#   1. commit de Lucas dans plateforme/k8s (locataires/<fichier du Tenant medidoc>) : quota d'espaces
#      ramené au nombre d'espaces existants (« on fait le ménage d'abord ») ;
#   2. commit de Lucas dans le même fichier : propriétaire « oidc:medidoc » renommé « oidc:medi-doc »
#      (« harmonisation des noms de groupes ») — dans owners seulement : le groupe n'est plus
#      propriétaire de rien, Capsule refuse la création ;
#   3. commit de Lucas dans plateforme/gitops (valeurs/capsule/values.yaml) : protectedNamespaceRegex
#      trop large, qui « protège » aussi les noms medi*- des équipes ;
#   4. (seulement si WB_M28_E21_WEBHOOK=oui) CiliumNetworkPolicy « capsule-durcissement » posée à la
#      main dans capsule-system : n'admet en entrée que les pods de capsule-system ; l'apiserver ne
#      joint plus les webhooks de Capsule. ⚠️ Tant qu'elle est là : plus aucune création d'espace dans le
#      cluster, plus aucun pod créé dans les espaces des locataires (production comprise).
# Constat : création d'espace en dry-run serveur avec impersonation du groupe oidc:medidoc
# (WB_K8S_ADMIN_KUBECONFIG = admin.conf : seul compte non interactif qui peut emprunter une identité).
# Annulation : commit inverse (si le fichier n'a pas bougé) ; suppression de la politique ajoutée.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m28-commun.sh
source "$WB_ROOT/modules/28-plateforme-dev/corrige/pannes/_m28-commun.sh"

_E21_CNP=capsule-durcissement
_E21_REGEX='^(kube-|capsule-|keda|vpa|portail|messagerie|medi[a-z]*-)'

# _e21_essai — 0 si l'équipe MédiDoc PEUT créer un espace de revue (dry-run serveur, rien n'est créé).
_e21_essai() {
  wb_kubectl create namespace "medidoc-revue-verif-$RANDOM" --dry-run=server \
    --as=wb-verif-medidoc --as-group=oidc:medidoc --as-group=system:authenticated >/dev/null 2>&1
}
_e21_refuse() { ! _e21_essai; }

# Fichier du Tenant medidoc dans plateforme/k8s (locataires/).
_e21_fichier_tenant() {
  m28_git_chercher plateforme/k8s 'kind: Tenant' locataires | while IFS= read -r f; do
    if m28_git_lire plateforme/k8s "$f" | yq -e 'select(.kind == "Tenant" and .metadata.name == "medidoc")' >/dev/null 2>&1; then
      printf '%s\n' "$f"
    fi
  done | head -n 1
}

_e21_sain() {
  m28_outils || return 1
  if ! wb_kubectl get tenants.capsule.clastix.io medidoc >/dev/null 2>&1; then
    echo "Locataire medidoc absent : termine M28-E05." >&2
    return 1
  fi
  if ! _e21_essai; then
    echo "L'équipe MédiDoc ne peut DÉJÀ pas créer d'espace (dry-run refusé) : répare d'abord (lab/bin/check 28 21)." >&2
    echo "(Les pannes exigent admin.conf : WB_K8S_ADMIN_KUBECONFIG.)" >&2
    return 1
  fi
}

_e21_v1_effective() {
  wb_kubectl get tenants.capsule.clastix.io medidoc -o json 2>/dev/null |
    jq -e '(.spec.namespaceOptions.quota // 0) > 0 and (.spec.namespaceOptions.quota <= (.status.size // 0))' >/dev/null 2>&1 && _e21_refuse
}
_e21_v2_effective() {
  wb_kubectl get tenants.capsule.clastix.io medidoc -o json 2>/dev/null |
    jq -e '[.spec.owners[]?.name] | index("oidc:medidoc") == null' >/dev/null 2>&1 && _e21_refuse
}
_e21_v3_effective() {
  wb_kubectl get capsuleconfigurations.capsule.clastix.io default -o jsonpath='{.spec.protectedNamespaceRegex}' 2>/dev/null |
    grep -q 'medi' && _e21_refuse
}
_e21_v4_effective() { _e21_refuse; }

_e21_sans_effet() {
  m28_git_annuler E21 || true
  return 10
}

_m28E21_une() {
  local n="$1" f taille
  case "$n" in
    1 | 2)
      f="$(_e21_fichier_tenant)"
      [[ -n "$f" ]] || return 10
      if ((n == 1)); then
        taille="$(wb_kubectl get tenants.capsule.clastix.io medidoc -o jsonpath='{.status.size}' 2>/dev/null)"
        [[ "$taille" =~ ^[0-9]+$ ]] && ((taille >= 1)) || return 10
        _m28_transformer() {
          TAILLE="$taille" yq '(select(.kind == "Tenant" and .metadata.name == "medidoc") | .spec.namespaceOptions.quota) = (strenv(TAILLE) | tonumber)'
        }
        m28_git_modifier E21 plateforme/k8s "$f" "chore(locataires): MédiDoc fait le ménage avant de créer d'autres espaces (M28-E21)

Quota aligné sur l'existant en attendant la revue des budgets. -- Lucas" || return $?
      else
        _m28_transformer() {
          yq '(select(.kind == "Tenant" and .metadata.name == "medidoc") | .spec.owners[] | select(.name == "oidc:medidoc") | .name) = "oidc:medi-doc"'
        }
        m28_git_modifier E21 plateforme/k8s "$f" "style(locataires): noms de groupes harmonisés avec des tirets (M28-E21)

-- Lucas" || return $?
      fi
      m28_rafraichir locataires
      if ((n == 1)); then
        m28_attendre 480 _e21_v1_effective || _e21_sans_effet || return $?
      else
        m28_attendre 480 _e21_v2_effective || _e21_sans_effet || return $?
      fi
      ;;
    3)
      f="valeurs/capsule/values.yaml"
      m28_git_lire plateforme/gitops "$f" >/dev/null 2>&1 || return 10
      _m28_transformer() {
        local t
        t="$(mktemp)"
        cat >"$t"
        yq -e '.manager.options' "$t" >/dev/null 2>&1 || { rm -f "$t"; return 10; }
        RX="$_E21_REGEX" yq '.manager.options.protectedNamespaceRegex = strenv(RX)' "$t"
        rm -f "$t"
      }
      m28_git_modifier E21 plateforme/gitops "$f" "sec(capsule): protéger les espaces de la plateforme et des applications contre une création accidentelle (M28-E21)

-- Lucas" || return $?
      m28_rafraichir capsule
      m28_attendre 480 _e21_v3_effective || _e21_sans_effet || return $?
      ;;
    4)
      [[ "${WB_M28_E21_WEBHOOK:-}" == oui ]] || return 10
      wb_k8s_sauver ciliumnetworkpolicies.cilium.io "$_E21_CNP" capsule-system
      wb_kubectl apply -f - >/dev/null <<EOF || return 1
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: $_E21_CNP
  namespace: capsule-system
  labels:
    medisphere.internal/auteur: lucas.martin
  annotations:
    medisphere.internal/commentaire: "durcissement : seul capsule-system parle à capsule-system (essai Lucas)"
spec:
  description: "Durcissement de capsule-system (essai)"
  endpointSelector: {}
  ingress:
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: capsule-system
EOF
      m28_attendre 120 _e21_v4_effective || return 1
      ;;
  esac
  m28_journal E21 "variante $n posée"
}

panne_E21_v1() { _e21_sain && m28_essayer E21 4 1; }
panne_E21_v2() { _e21_sain && m28_essayer E21 4 2; }
panne_E21_v3() { _e21_sain && m28_essayer E21 4 3; }
panne_E21_v4() { _e21_sain && m28_essayer E21 4 4; }

verifier_E21() {
  case "$WB_VAR" in
    1) _e21_v1_effective ;;
    2) _e21_v2_effective ;;
    3) _e21_v3_effective ;;
    4) _e21_v4_effective ;;
    *) return 1 ;;
  esac
}

annuler_E21() {
  wb_k8s_restaurer || true
  m28_git_annuler E21 || true
  m28_rafraichir locataires capsule
  m28_journal E21 "annulation"
}

resume_E21() { echo "L'équipe MédiDoc ne peut plus créer ses espaces de revue."; }

symptome_E21() {
  wb_symptome "Ticket INC-5521 — De : Julien Petit (pour l'équipe MédiDoc)" \
    "L'équipe MédiDoc n'arrive plus à créer ses espaces de revue (medidoc-revue-<n>) : la commande" \
    "kubectl create namespace est refusée depuis ce matin, alors que ça marchait la semaine dernière." \
    "Ils ont une démo cet après-midi. Ils n'ont rien changé, disent-ils." \
    "" \
    "Pour reproduire sans leur compte : kubectl … --as=<utilisateur> --as-group=oidc:medidoc \\" \
    "  --as-group=system:authenticated create ns medidoc-revue-essai --dry-run=server" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 28 21"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 28 E21 4 "$@"; }
fi
