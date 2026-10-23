#!/usr/bin/env bash
# plateforme/k8s — outils/amorcer-secrets.sh (F1-S08, PLAT-3108 ; reprise vérifiée en F1-S09, SEC-3109)
# Ce qui reste de secrets-k8s.sh (M19-M25) : l'AMORÇAGE d'un cluster neuf, avant External Secrets.
#
#   outils/amorcer-secrets.sh appliquer   crée chaque Secret de outils/amorcage.conf depuis OpenBao
#   outils/amorcer-secrets.sh verifier    dit, pour chaque Secret, s'il a été ADOPTÉ par son ExternalSecret
#   outils/amorcer-secrets.sh nettoyer    retire la marque d'amorçage des Secrets adoptés
#
# Règles (SEC-3109) :
#   - lecture dans OpenBao avec TA session (bao login -method=oidc) : chaque lecture est dans l'audit
#     d'OpenBao (locataire Loki « audit ») sous ton identité ;
#   - aucune valeur sur une ligne de commande, dans un fichier ni dans l'historique : bao → jq →
#     kubectl apply par des tubes ; rien n'est affiché ;
#   - chaque Secret porte l'étiquette medisphere.internal/amorcage=f1 ; un Secret qui la porte encore
#     SANS propriétaire après S09 est un oubli (verifier sort en 1) ;
#   - un Secret qui existe déjà n'est pas réécrit (relance sans danger).
# Prérequis : bao (OpenBao 2.7), jq, kubectl ; BAO_ADDR=https://openbao.par1.medisphere.internal:8200.

set -euo pipefail

ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="${AMORCAGE_CONF:-$ICI/amorcage.conf}"
CTX="${KUBECTL_CONTEXTE:-k8s-par1}"
MARQUE=medisphere.internal/amorcage
export BAO_ADDR="${BAO_ADDR:-https://openbao.par1.medisphere.internal:8200}"

k() { kubectl --context "$CTX" "$@"; }

# lignes — lignes utiles du fichier de configuration.
lignes() { grep -vE '^[[:space:]]*(#|$)' "$CONF"; }

# manifeste ESPACE SECRET TYPE ETIQUETTES_JSON CORRESPONDANCES_JSON — lit le JSON de « bao kv get »
#   sur l'entrée standard et écrit le manifeste du Secret (données en base64) sur la sortie.
manifeste() {
  jq -c --arg ns "$1" --arg nom "$2" --arg type "$3" --argjson et "$4" --argjson cor "$5" --arg m "$MARQUE" '
    .data.data as $d
    | (if ($cor | length) == 0 then $d else ($cor | with_entries(.value = $d[.value])) end) as $v
    | if ($v | to_entries | any(.value == null)) then error("propriété absente dans OpenBao") else . end
    | {apiVersion: "v1", kind: "Secret", type: $type,
       metadata: {name: $nom, namespace: $ns, labels: ($et + {($m): "f1"})},
       data: ($v | map_values(tostring | @base64))}'
}

appliquer() {
  local ns nom chemin reste type et cor mot
  bao token lookup >/dev/null 2>&1 || { echo "Session OpenBao absente ou expirée : bao login -method=oidc" >&2; exit 1; }
  while read -r ns nom chemin reste; do
    type=Opaque; et='{}'; cor='{}'
    for mot in $reste; do
      case "$mot" in
        type=*) type="${mot#type=}" ;;
        etiquette=*) mot="${mot#etiquette=}"; et="$(jq -c --arg c "${mot%%=*}" --arg v "${mot#*=}" '. + {($c): $v}' <<<"$et")" ;;
        *=*) cor="$(jq -c --arg c "${mot%%=*}" --arg p "${mot#*=}" '. + {($c): $p}' <<<"$cor")" ;;
      esac
    done
    if ! k get namespace "$ns" >/dev/null 2>&1; then
      echo "espace $ns absent : applique d'abord espaces/ (task espaces)" >&2
      exit 1
    fi
    if k -n "$ns" get secret "$nom" >/dev/null 2>&1; then
      echo "existe déjà : $ns/$nom (inchangé)"
      continue
    fi
    bao kv get -format=json "kv/$chemin" | manifeste "$ns" "$nom" "$type" "$et" "$cor" |
      k apply --server-side --field-manager=amorcage-f1 -f - >/dev/null
    echo "créé : $ns/$nom (depuis kv/$chemin)"
  done < <(lignes)
}

# etat ESPACE SECRET — « adopte », « orphelin » ou « absent ».
etat() {
  local j
  j="$(k -n "$1" get secret "$2" -o json 2>/dev/null)" || { echo absent; return; }
  if jq -e 'any(.metadata.ownerReferences[]?; .kind == "ExternalSecret")' >/dev/null <<<"$j"; then echo adopte; else echo orphelin; fi
}

verifier() {
  local ns nom _ e ko=0
  while read -r ns nom _; do
    e="$(etat "$ns" "$nom")"
    printf '%-14s %-32s %s\n' "$ns" "$nom" "$e"
    [[ "$e" == adopte ]] || ko=1
  done < <(lignes)
  # Tout Secret marqué qui n'est pas dans la liste (amorçage à la main) est aussi un écart.
  k get secrets -A -l "$MARQUE" -o json |
    jq -r '.items[] | select([.metadata.ownerReferences[]? | select(.kind == "ExternalSecret")] | length == 0)
           | "orphelin marqué : \(.metadata.namespace)/\(.metadata.name)"'
  return "$ko"
}

nettoyer() {
  local ns nom _
  while read -r ns nom _; do
    if [[ "$(etat "$ns" "$nom")" == adopte ]]; then
      k -n "$ns" label secret "$nom" "$MARQUE-" >/dev/null 2>&1 || true
    fi
  done < <(lignes)
}

case "${1:-}" in
  appliquer) appliquer ;;
  verifier) verifier ;;
  nettoyer) nettoyer ;;
  *) echo "Usage : $0 appliquer | verifier | nettoyer" >&2; exit 2 ;;
esac
