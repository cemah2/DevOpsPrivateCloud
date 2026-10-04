# Politique de signature — plateforme

> Exemple de livrable M01-E27 (SEC-254), section à ajouter à `CONTRIBUTING.md`
> ou à `docs/socle/securite/signature.md` de `plateforme/medisphere`.

1. **Tout commit humain poussé sur un projet `plateforme/*` est signé** (SSH, clé dédiée à la signature, déclarée dans GitLab avec l'usage *Signing* et une date d'expiration d'un an au plus). L'adresse du commit est une adresse vérifiée du compte.
2. **Toute étiquette posée à la main est annotée et signée** (`git tag -s`). Les étiquettes `vX.Y.Z` posées par semantic-release ne le sont pas : leur authenticité repose sur la protection des étiquettes `v*` (création réservée aux Maintainers, donc au bot) et sur le pipeline qui les crée.
3. **Commits créés par GitLab** (fusion, rebase, *squash*, suggestions acceptées dans l'interface) : non signés tant que la signature côté serveur n'est pas configurée ; leur traçabilité vient de la MR (auteur, relecteurs, pipeline). Action ouverte : configurer la clé de signature de Gitaly (à étudier).
4. **Vérification** : un contrôle hebdomadaire liste les commits non signés arrivés sur `main` hors commits de fusion (`git log --no-merges --format='%h %G? %an %s' <depuis>..main | grep -v ' G '`). Le contrôle n'est pas encore bloquant : CE n'offre pas la règle de push « commits signés » (Premium) ; un hook serveur pourrait l'imposer (M01-E26), au prix d'une liste de clés à maintenir sur `git01`.
5. **Clé compromise ou perdue** : *révoquer* la clé dans GitLab (les commits qu'elle a signés passent « Unverified » : c'est voulu, on ne sait plus qui les a signés) — et non la *supprimer* (les anciens commits resteraient « Verified ») ; prévenir la RSSI ; générer une nouvelle clé ; mettre à jour `allowed_signers` (`valid-before` sur l'ancienne) ; relire les commits signés depuis la date présumée de compromission.
