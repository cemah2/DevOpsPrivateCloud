#!/usr/bin/env bash
# audit-valeurs-helm.sh — cherche, dans les valeurs FOURNIES de toutes les releases Helm du cluster,
# ce qui ressemble à un secret (M17-E15, ticket SEC-1833). N'affiche JAMAIS une valeur : seulement
# « espace/release : chemin (raison) ».
#
# Usage : outils/audit-valeurs-helm.sh [--kubeconfig FICHIER]
# Sortie : 0 si rien n'est trouvé, 1 si au moins une valeur suspecte, 2 en cas d'erreur d'accès.
# Droits nécessaires : lire les Secrets de release Helm (« helm get values ») de tous les espaces.
set -euo pipefail

kubeconfig=()
if [[ "${1:-}" == "--kubeconfig" && -n "${2:-}" ]]; then
  kubeconfig=(--kubeconfig "$2")
fi

for c in helm jq; do
  command -v "$c" >/dev/null 2>&1 || { echo "outil manquant : $c" >&2; exit 2; }
done

# Clés (dernier élément du chemin) dont une valeur NON VIDE est suspecte. Les noms de référence
# (existingSecret, secretName, secretKey…) désignent un Secret, ils ne le contiennent pas : exclus.
# shellcheck disable=SC2016  # programme jq
filtre='
  def suspecte_cle: test("^(password|passwd|pass|motdepasse|mot_de_passe|token|apitoken|apikey|api_key|secretaccesskey|aws_secret_access_key|accesskeysecret|tsigsecret|secretcontents|privatekey|private_key|clientsecret|client_secret|webhooksecret)$"; "i");
  def reference: test("^(existingsecret|secretname|secretkey|secretref|existingsecretkey|.*secretkeyref)$"; "i");
  def suspecte_valeur: (type == "string") and (test("^[a-z][a-z0-9+.-]*://[^/@:\\s]+:[^/@\\s]+@") or test("-----BEGIN [A-Z ]*PRIVATE KEY-----"));
  [ paths(scalars) as $p
    | getpath($p) as $v
    | ($p | map(tostring)) as $s
    | ($s | last) as $cle
    | select(($cle | reference) | not)
    | if (($cle | suspecte_cle) and ($v | tostring | length) > 0) then "\($s | join(".")) (nom de clé)"
      elif ($v | suspecte_valeur) then "\($s | join(".")) (forme de la valeur)"
      else empty end
  ]
  # Un objet entier sous une clé de contenu (ex. secretContents: {cloud: "…"}) :
  + [ paths(objects) as $p | ($p | map(tostring)) as $s
      | select(($s | last // "") | test("^(secretcontents|credentials\\.secretcontents)$"; "i"))
      | select((getpath($p) | length) > 0) | "\($s | join(".")) (contenu d’identifiants)" ]
  | unique | .[]
'

releases="$(helm "${kubeconfig[@]}" list -A -o json 2>/dev/null)" || { echo "lecture des releases impossible" >&2; exit 2; }
trouve=0
while IFS=$'\t' read -r ns nom; do
  [[ -n "$nom" ]] || continue
  valeurs="$(helm "${kubeconfig[@]}" get values "$nom" -n "$ns" -o json 2>/dev/null)" || { echo "$ns/$nom : valeurs illisibles" >&2; trouve=1; continue; }
  [[ "$valeurs" == "null" ]] && continue
  while IFS= read -r ligne; do
    [[ -n "$ligne" ]] || continue
    printf '%s/%s : %s\n' "$ns" "$nom" "$ligne"
    trouve=1
  done < <(jq -r "$filtre" <<<"$valeurs")
done < <(jq -r '.[] | [.namespace, .name] | @tsv' <<<"$releases")

if ((trouve)); then
  echo "Valeurs suspectes trouvées : fais porter ces secrets par un Secret existant, puis RENOUVELLE-les (ils restent dans l'historique des releases)." >&2
  exit 1
fi
echo "Aucune valeur suspecte dans les releases Helm."
