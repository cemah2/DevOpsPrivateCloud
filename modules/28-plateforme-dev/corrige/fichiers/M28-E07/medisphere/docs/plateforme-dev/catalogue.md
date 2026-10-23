# Catalogue du portail

> Plateforme développeurs — M28-E07 (PLAT-2907). Responsable : équipe Plateforme.

## Sources

| Source | Module (1.56) | Ce qu'elle apporte | Fréquence |
|---|---|---|---|
| Annuaire FreeIPA (`ldaps://ipa01`) | `catalog-backend-module-ldap` (fournisseur `ldapOrg.freeipa`) | `User` (personnes actives, `name` = `uid`) et `Group` (équipes et fonctions : `plateforme`, `plateforme-admins`, `mediagenda`, `medidoc`, `securite`, `support`, `direction` ; `spec.type: equipe` fixé) avec leurs membres | 30 min |
| GitLab (`git01`) | `catalog-backend-module-gitlab` (un fournisseur par groupe : `mediagenda`, `medidoc`, `medinotif`, `plateforme`) | les `catalog-info.yaml` à la racine de la branche `main` de chaque projet | 15 min |
| `plateforme/medisphere` (découvert comme les autres) | — | `Domain` `soins`, `System` `mediagenda`, `medinotif`, `medidoc`, `plateforme`, `Resource` partagées | 15 min |
| `plateforme/portail-modeles` (emplacement dédié, E08) | — | `Template` | 15 min |

## Règles

- **Depuis les dépôts** : `Component`, `System`, `API`, `Resource`, `Location`, `Domain` seulement (`catalog.rules`). Un `User` ou un `Group` écrit dans un dépôt est refusé (essai `formation/catalogue-essai` : erreur de traitement « … kind Group … not allowed », aucune entité créée) : l'organisation vient de l'annuaire, et personne ne s'invente une équipe.
- **Propriétaire** : toujours un **groupe** de l'annuaire (`group:default/<équipe>`), jamais une personne. Un propriétaire inexistant n'empêche pas l'ingestion mais laisse une relation pendante : la revue mensuelle (`/api/catalog/entities?filter=kind=component`) la repère.
- **Systèmes** : MédiNotif est un système à part (cycle de vie, file, équipe d'astreinte), possédé par `mediagenda`.

## Comptes

| Compte | Où | Droits | Pourquoi |
|---|---|---|---|
| `svc-portail` (compte système FreeIPA) | `cn=sysaccounts,cn=etc` | lecture par les ACI par défaut (personnes, groupes) | module LDAP ; ni Kerberos, ni connexion aux machines |
| `svc-portail` (compte de service d'**instance** GitLab, 19.5) | `POST /api/v4/service_accounts` (`external` vaut `true` par défaut en 19.5 : un utilisateur externe ne voit **que** les projets dont il est membre — c'est voulu) | jeton personnel `api`, expiration 90 jours (rotation planifiée, à décrire au palier 3) ; membre **Reporter** de `plateforme` ; **Developer** de `mediagenda`, `medinotif`, `medidoc` (création de projets : réglage de groupe « rôle minimal pour créer un projet » = Developer) ; **Developer** de `plateforme/gitops` et `plateforme/k8s` (branches et MR ; `main` protégée, fusion par les mainteneurs) | lecture des `catalog-info.yaml` (E07) ; création de projets et MR des modèles (E08) |

Portée `api` : `read_api` + `read_repository` ne suffisent pas pour créer un projet et ouvrir une MR (E08). La limite réelle est l'**appartenance** : `svc-portail` n'est ni administrateur, ni propriétaire d'un groupe, ni mainteneur des dépôts de la plateforme.

Création (avec ton jeton d'administration, une fois) :

```
admin@adm01:~$ curl -sS -K <(printf 'header = "PRIVATE-TOKEN: %s"\n' "$(<~/.config/workbook/gitlab-admin.token)") -X POST \
    "https://git01.par1.medisphere.internal/api/v4/service_accounts" \
    --data-urlencode "name=Portail Backstage" --data-urlencode "username=svc-portail" | jq '{id, username, external}'
admin@adm01:~$ curl -sS -K <(printf 'header = "PRIVATE-TOKEN: %s"\n' "$(<~/.config/workbook/gitlab-admin.token)") -X POST \
    "https://git01.par1.medisphere.internal/api/v4/users/<ID>/personal_access_tokens" \
    --data-urlencode "name=portail" --data-urlencode "scopes[]=api" --data-urlencode "expires_at=<AAAA-MM-JJ>" \
  | jq -r .token | bao kv patch kv/plateforme/portail gitlab_token=-
```

## Contrôles

- `julien.petit` → `memberOf` `group:default/mediagenda` ; `mediagenda-api` → `ownedBy` `group:default/mediagenda`, `partOf` `system:default/mediagenda`.
- Erreurs de traitement : `GET /api/catalog/entities?filter=metadata.annotations.backstage.io/managed-by-location` + journaux du plugin (`kubectl -n portail logs deploy/portail | grep -i catalog`).
