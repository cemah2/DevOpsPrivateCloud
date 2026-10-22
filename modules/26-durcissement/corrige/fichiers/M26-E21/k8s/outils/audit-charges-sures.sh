#!/usr/bin/env bash
# plateforme/k8s — outils/audit-charges-sures.sh (M26-E21, SEC-2721)
# Mesure, pod par pod et conteneur par conteneur, l'écart des charges EN SERVICE à la norme
# « charge sûre » de MédiSphère (docs/securite/durcissement/charges-sures.md) :
#   C1 runAsNonRoot (pod ou conteneur)        C5 seccomp RuntimeDefault ou Localhost (pod ou conteneur)
#   C2 allowPrivilegeEscalation: false        C6 aucun jeton de compte de service monté (sauf exception)
#   C3 readOnlyRootFilesystem: true           C7 image par condensé (@sha256) hors dev
#   C4 capabilities.drop contient ALL         C8 requests cpu/mémoire et limite mémoire
# C6 regarde le RÉSULTAT (volume projeté serviceAccountToken injecté par l'admission), pas le champ
# automountServiceAccountToken : le refus peut venir du pod OU de son ServiceAccount.
# Exceptions INSCRITES au registre (exceptions.md), et seulement elles :
#   - C6 : instances CloudNativePG (étiquette cnpg.io/podRole=instance) : le gestionnaire d'instance
#          parle à l'API Kubernetes (EXC-K-002).
# Lecture seule. Usage : outils/audit-charges-sures.sh [regex des espaces=^(mediagenda|medidoc)-]
# Sortie : une ligne par écart « espace<TAB>pod<TAB>conteneur<TAB>critère », puis un bilan ;
# code 0 si aucun écart, 1 sinon (utilisable en CI ou dans une minuterie).
set -euo pipefail

motif="${1:-^(mediagenda|medidoc)-}"
for outil in kubectl jq; do
  command -v "$outil" >/dev/null || { echo "outil manquant : $outil" >&2; exit 2; }
done

# Le filtre est une fonction jq : il est repris tel quel par le check M26-E21.
# shellcheck disable=SC2016  # variables jq entre apostrophes
filtre='
  def conteneurs($p): [($p.spec.initContainers // [])[], $p.spec.containers[]];
  def ecarts($p; $c):
    ($p.spec.securityContext // {}) as $ps | ($c.securityContext // {}) as $cs
    | ($p.metadata.namespace | test("-dev$")) as $dev
    | [ (if (($cs.runAsNonRoot // $ps.runAsNonRoot) == true) then empty else "C1 runAsNonRoot" end),
        (if $cs.allowPrivilegeEscalation == false then empty else "C2 allowPrivilegeEscalation" end),
        (if $cs.readOnlyRootFilesystem == true then empty else "C3 readOnlyRootFilesystem" end),
        (if (($cs.capabilities.drop // []) | index("ALL")) != null then empty else "C4 capabilities.drop ALL" end),
        (if ((($cs.seccompProfile.type // $ps.seccompProfile.type) // "") | test("^(RuntimeDefault|Localhost)$"))
           then empty else "C5 seccompProfile" end),
        (if ($dev or ($c.image | test("@sha256:[a-f0-9]{64}$"))) then empty else "C7 image sans condensé" end),
        (if ($c.resources.requests.cpu and $c.resources.requests.memory and $c.resources.limits.memory)
           then empty else "C8 ressources" end) ];
  .items[]
  | select(.metadata.namespace | test($motif))
  | select(.status.phase == "Running" or .status.phase == "Pending")
  | . as $p
  | ( (if ([($p.spec.volumes // [])[] | select(any(.projected.sources[]?; has("serviceAccountToken")))] | length) == 0
            or (($p.metadata.labels["cnpg.io/podRole"] // "") == "instance")
         then empty
         else [$p.metadata.namespace, $p.metadata.name, "-", "C6 jeton de compte de service monté"] end),
      (conteneurs($p)[] as $c | ecarts($p; $c)[] | [$p.metadata.namespace, $p.metadata.name, $c.name, .]) )
  | @tsv'

resultat="$(kubectl get pods -A -o json | jq -r --arg motif "$motif" "$filtre")"
if [[ -z "$resultat" ]]; then
  echo "Aucun écart : toutes les charges des espaces /$motif/ respectent la norme."
  exit 0
fi
printf '%s\n' "$resultat"
echo "---"
printf '%s\n' "$resultat" | cut -f4 | sort | uniq -c | sort -rn
echo "$(printf '%s\n' "$resultat" | wc -l) écart(s)."
exit 1
