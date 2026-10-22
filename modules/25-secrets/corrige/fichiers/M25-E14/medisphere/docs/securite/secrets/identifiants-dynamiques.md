# Identifiants dynamiques de MédiAgenda

| | |
|---|---|
| Tickets | DEV-2614 (M25-E14), SEC-2615 (M25-E15) |
| Propriétaires | Équipe Plateforme (coffre, base) ; équipe MédiAgenda (component, application) |
| Configuration | `plateforme/secrets` : `tofu/db-mediagenda.tf` ; `plateforme/k8s` : `espaces/mediagenda-<env>/` (rôles gérés, Service, générateurs) ; `mediagenda/deploiement` : `components/identifiants-dynamiques` |

## 1. Schéma

```
                 kv/… (rien)          db-mediagenda/creds/mediagenda-api-<env>
pod ESO ─(jeton projeté, aud openbao)─▶ OpenBao ─(rôle « openbao », TLS vérifié)─▶ PostgreSQL (primaire CNPG)
   │      méthode k8s-par1, rôle eso-<espace>      CREATE ROLE "v-…" VALID UNTIL … IN ROLE mediagenda_api
   ▼
Secret mediagenda-db-api (clé uri) ──▶ API MédiAgenda (MEDIAGENDA_DB_URL, lue au démarrage)
Secret mediagenda-db-migrateur     ──▶ Job de migration (hook Sync, vague -1)
```

Chemin réseau : `vault01-03` → Service `mediagenda-db-openbao` (10.10.41.64 recette, 10.10.41.65 prod, `externalTrafficPolicy: Local`) → primaire ; CiliumNetworkPolicy `mediagenda-db-depuis-openbao` (10.10.20.21-23 seulement). TLS : `sslmode=verify-ca` avec la CA du Cluster (`/etc/openbao/postgresql/mediagenda-<env>-ca.crt`) ; pas `verify-full` : le certificat de CNPG ne contient pas l'adresse 10.10.41.64.

## 2. Comptes PostgreSQL

| Compte | Créé par | Droits | Durée | Supprimé par |
|---|---|---|---|---|
| `mediagenda` (propriétaire) | CNPG (initdb) | tout sur la base ; propriétaire des objets | permanent | — |
| `openbao` | CNPG (`managed.roles`) | `LOGIN`, `CREATEROLE`, option ADMIN (sans héritage ni `SET ROLE`) sur `mediagenda` et `mediagenda_api` | permanent ; mot de passe connu d'OpenBao seul (`rotate-root`) | — |
| `mediagenda_api` | CNPG (`managed.roles`), droits par `sql/preparer-openbao.sql` | `SELECT/INSERT/UPDATE/DELETE` sur les tables, séquences ; droits par défaut sur les futures | permanent, sans connexion | — |
| `v-…-mediagenda-api-<env>-…` | OpenBao, à chaque lecture de `creds` | membre de `mediagenda_api` | bail 1 h (`VALID UNTIL`), renouvelable jusqu'à 24 h | OpenBao à la fin du bail (`DROP ROLE`) |
| `v-…-mediagenda-migrateur-<env>-…` | OpenBao | membre de `mediagenda`, session en `role = mediagenda` : objets créés **au nom de** `mediagenda` | 1 h / 24 h | OpenBao (`DROP ROLE`) |

## 3. Ce qui se passe à l'expiration

ESO lit un nouvel identifiant à chaque rafraîchissement (30 min) et ne révoque pas l'ancien : son bail court jusqu'à son terme (1 h après sa création), puis OpenBao le révoque : `DROP ROLE`. Les sessions encore ouvertes par ce compte **cessent de fonctionner** (`invalid role OID`, essai du banc). Un pod qui a lu l'ancien Secret au démarrage doit donc avoir redémarré **dans les 30 minutes** qui suivent un rafraîchissement : c'est Reloader qui s'en charge (M25-E15). Sans lui, l'API passe en `/pret` 503 au plus tard une heure après le premier rafraîchissement.

## 4. Retour au compte propriétaire (bris de glace)

Coffre fermé, ESO en erreur, ou identifiants refusés : `git revert` du commit qui inclut `components/identifiants-dynamiques` dans l'overlay ; l'API et le Job relisent `mediagenda-db-app` (Secret de CNPG, inchangé). En prod, synchronisation manuelle (M20). À rétablir dès que la cause est corrigée ; le compte propriétaire n'est pas fait pour tourner en continu.

Si OpenBao a perdu la connexion (mot de passe d'`openbao` inconnu de lui, après une restauration par exemple) : nouveau mot de passe initial par le superutilisateur (`kubectl cnpg psql … ALTER ROLE openbao PASSWORD …` lu sur l'entrée standard), écrit dans OpenBao par l'entrée standard, puis `rotate-root` ; personne ne le garde.

## 5. Entretien

- CA de CNPG : 90 jours, renouvelée par l'opérateur 7 jours avant l'échéance ; la copie déposée sur `vault01-03` doit suivre (MR `plateforme/ansible`). Correction de fond : certificat serveur signé par la PKI de services (M25-E16, « Pour aller plus loin »).
- Ajout d'un environnement : connexion et rôles (`tofu/db-mediagenda.tf`), rôles gérés et Service (Cluster), SQL de préparation, générateurs, politique `eso-<espace>` (chemins `creds`).
