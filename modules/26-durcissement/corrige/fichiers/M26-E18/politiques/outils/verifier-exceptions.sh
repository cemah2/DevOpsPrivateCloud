#!/bin/sh
# plateforme/politiques — outils/verifier-exceptions.sh (M26-E18)
# Contrôle des PolicyException de kyverno/exceptions/ AVANT fusion (job kyverno:exceptions) et chaque
# lundi (pipeline planifié) : une exception est une politique désactivée, elle doit être justifiée,
# bornée et datée. Règles (registre docs/securite/durcissement/exceptions.md, procédure RB-261) :
#   - apiVersion policies.kyverno.io/v1, kind PolicyException, espace absent ou kyverno-exceptions ;
#   - fichier listé dans kyverno/exceptions/kustomization.yaml (sinon jamais appliqué) ;
#   - spec.expiresAt présent (AAAA-MM-JJTHH:MM:SSZ), dans le futur, à 92 jours au plus (un trimestre) ;
#   - au moins une matchCondition (sans elle, l'exception vaut pour TOUT le cluster) ;
#   - chaque policyRefs désigne une politique qui existe dans kyverno/ (même nom, même kind) ;
#   - properties : raison, ticket, valideur, revue (AAAA-MM-JJ) ; valideur autorisé.
# Échéance à moins de 14 jours : avertissement (le pipeline planifié échoue alors : voir plus bas).
# POSIX sh (l'image de CI d'E07 est une Alpine sans bash) ; outils : yq (mikefarah 4.x), date, awk.
# Usage : outils/verifier-exceptions.sh [dossier=kyverno/exceptions]
set -eu

dossier="${1:-kyverno/exceptions}"
racine_kyverno="$(dirname "$dossier")"
valideurs="sophie.laurent"   # RSSI ; un second valideur s'ajoute ici, par MR relue
max_jours=92
alerte_jours=14

command -v yq >/dev/null || { echo "outil manquant : yq" >&2; exit 2; }
[ -d "$dossier" ] || { echo "dossier absent : $dossier" >&2; exit 2; }

# Dates en UTC au format de expiresAt : la comparaison de chaînes suffit (même format, même fuseau).
maintenant_s="$(date -u +%s)"
fmt='+%Y-%m-%dT%H:%M:%SZ'
maintenant="$(date -u -d "@$maintenant_s" "$fmt")"
limite="$(date -u -d "@$((maintenant_s + max_jours * 86400))" "$fmt")"
alerte="$(date -u -d "@$((maintenant_s + alerte_jours * 86400))" "$fmt")"
avant() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a < b) }'; }

erreurs=0
nb=0
erreur() { echo "ÉCHEC  $1 : $2"; erreurs=$((erreurs + 1)); }

# Politiques connues : « Kind/nom » de tout objet policies.kyverno.io hors exceptions et tests.
connues="$(find "$racine_kyverno" -name '*.yaml' ! -path '*/exceptions/*' ! -path '*/tests/*' \
  -exec yq -N 'select(.apiVersion == "policies.kyverno.io/*" and .kind != "PolicyException") | .kind + "/" + .metadata.name' {} + \
  | sort -u)"
listes="$(yq -r '.resources[]' "$dossier/kustomization.yaml" 2>/dev/null || true)"

for f in "$dossier"/*.yaml; do
  [ -e "$f" ] || continue
  base="$(basename "$f")"
  [ "$base" = kustomization.yaml ] && continue
  nb=$((nb + 1))
  if [ "$(yq -r '.apiVersion' "$f")" != "policies.kyverno.io/v1" ] || [ "$(yq -r '.kind' "$f")" != "PolicyException" ]; then
    erreur "$base" "attendu : apiVersion policies.kyverno.io/v1, kind PolicyException"
    continue
  fi
  ns="$(yq -r '.metadata.namespace // ""' "$f")"
  [ -z "$ns" ] || [ "$ns" = kyverno-exceptions ] || erreur "$base" "espace $ns : Kyverno ne lit que kyverno-exceptions"
  printf '%s\n' "$listes" | grep -qxF "$base" || erreur "$base" "absent de kustomization.yaml (jamais appliqué)"

  echeance="$(yq -r '.spec.expiresAt // ""' "$f")"
  if [ -z "$echeance" ]; then
    erreur "$base" "spec.expiresAt absent (une exception sans échéance est permanente)"
  elif ! printf '%s' "$echeance" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'; then
    erreur "$base" "spec.expiresAt au format AAAA-MM-JJTHH:MM:SSZ (UTC) attendu : $echeance"
  elif ! avant "$maintenant" "$echeance"; then
    erreur "$base" "échue depuis le $echeance : retire-la ou renouvelle-la (RB-261)"
  elif avant "$limite" "$echeance"; then
    erreur "$base" "échéance $echeance au-delà de $max_jours jours"
  elif avant "$echeance" "$alerte"; then
    echo "ATTENTION  $base : échéance proche ($echeance)"
    # Le pipeline planifié (lundi) échoue pour prévenir l'équipe ; une MR, elle, reste possible.
    [ "${PLANIFIE:-}" != exceptions ] || erreur "$base" "échéance à moins de $alerte_jours jours"
  fi

  [ "$(yq -r '(.spec.matchConditions // []) | length' "$f")" -ge 1 ] \
    || erreur "$base" "aucune matchCondition : l'exception vaudrait pour tout le cluster"

  for ref in $(yq -r '.spec.policyRefs[] | .kind + "/" + .name' "$f"); do
    printf '%s\n' "$connues" | grep -qxF "$ref" || erreur "$base" "policyRefs vers une politique inconnue : $ref"
  done

  for cle in raison ticket valideur revue; do
    [ -n "$(yq -r ".spec.properties.$cle // \"\"" "$f")" ] || erreur "$base" "properties.$cle manquant"
  done
  valideur="$(yq -r '.spec.properties.valideur // ""' "$f")"
  if [ -n "$valideur" ]; then
    printf '%s\n' "$valideurs" | tr ' ' '\n' | grep -qxF "$valideur" \
      || erreur "$base" "valideur non autorisé : $valideur (autorisés : $valideurs)"
  fi
  revue="$(yq -r '.spec.properties.revue // ""' "$f")"
  if [ -n "$revue" ] && ! printf '%s' "$revue" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
    erreur "$base" "properties.revue : AAAA-MM-JJ attendu"
  fi
done

echo "$nb exception(s) contrôlée(s), $erreurs erreur(s)."
[ "$erreurs" -eq 0 ]
