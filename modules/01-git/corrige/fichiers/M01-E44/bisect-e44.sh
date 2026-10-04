#!/usr/bin/env bash
# bisect-e44.sh — script de test pour « git bisect run » sur ~/src/labo-e44 (M01-E44, DEV-280).
#
# Rangé HORS du dépôt (~/src/bisect-e44.sh) : pendant la bisection, Git extrait des commits
# anciens ; un script versionné changerait d'un commit à l'autre, ou disparaîtrait.
# Usage : cd ~/src/labo-e44 && git bisect start main v1.0.0 && git bisect run ~/src/bisect-e44.sh
#
# Codes de sortie interprétés par git bisect run :
#   0       bon commit
#   1       mauvais commit (la régression est présente)
#   125     commit non testable : sauté (git bisect skip)
#   > 127   arrêt de la bisection (réservé aux erreurs du script lui-même)

# Un commit dont le code ne se charge même pas (erreur de syntaxe dans un fichier sans
# rapport avec la régression) n'est ni bon ni mauvais : on le saute.
for f in bin/flux-check lib/*.sh; do
  [[ -e "$f" ]] || exit 125
  bash -n "$f" 2>/dev/null || exit 125
done

# Le test de bout en bout du projet : il compare la sortie à la sortie attendue.
[[ -x tests/test.sh ]] || exit 125
tests/test.sh >/dev/null 2>&1 || exit 1
exit 0
