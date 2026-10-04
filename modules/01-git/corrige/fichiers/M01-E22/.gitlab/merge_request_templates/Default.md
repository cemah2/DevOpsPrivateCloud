## Contexte

<!-- Pourquoi ce changement ? Lien vers le ticket (PLAT-…, SEC-…, INC-…). Deux à cinq lignes. -->

Ticket :

## Ce qui change

<!-- Liste courte, du point de vue de celui qui exploite : fichiers, services, comportements. -->

-

## Comment je l'ai vérifié

<!-- Commandes lancées et résultat observé (copie la sortie utile, pas tout le terminal).
     Un relecteur doit pouvoir refaire la vérification. -->

```
$
```

## Impact

<!-- Coche ce qui s'applique et détaille juste en dessous. -->

- [ ] Sécurité : droits, secrets, exposition d'un service → avis de Sophie Laurent demandé
- [ ] Réseau : nouveau flux → `docs/socle/matrice-flux.md` mis à jour
- [ ] Inventaire : hôte, VM, service ajouté ou modifié → `docs/socle/inventaire.md` mis à jour
- [ ] Sauvegarde / restauration concernées
- [ ] Rupture de compatibilité (`!` ou `BREAKING CHANGE:` dans un commit)
- [ ] Aucun de ces impacts

## Retour arrière

<!-- Comment annuler si ça se passe mal : revert de la MR suffit-il ? Données à restaurer ? -->

## Avant de demander la revue

- [ ] Les commits suivent Conventional Commits, sans `wip` ni `fixup!` restants
- [ ] Branche à jour de `main` (rebase), pipeline vert
- [ ] `pre-commit run --all-files` passe en local
- [ ] Aucun secret, aucune adresse personnelle, aucun fichier lourd ajouté
- [ ] Documentation à jour (README, runbook, ADR si décision structurante)

## Points d'attention pour les relecteurs

<!-- Ce sur quoi tu veux un avis, ce dont tu n'es pas sûr. -->
