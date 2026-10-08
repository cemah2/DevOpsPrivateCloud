# Libre-service sur le cloud OpenStack

> Pour les équipes de développement. Propriétaire : équipe Plateforme. Créé par DEV-1157 (M10-E31).

## Ce que l'offre fournit

Un **environnement d'application** complet dans le projet OpenStack de ton équipe, décrit dans **ton** dépôt GitLab et créé par **ton** pipeline, sans ticket à la plateforme :
- réseau privé, routeur vers `ext-net`, résolveurs du socle ;
- 2 à 4 serveurs (Debian 13, `m1.petit` ou `m1.moyen`) répartis sur les calculs ;
- un volume de données (XFS, monté sur `/srv/donnees`) sur le premier serveur ;
- un répartiteur TCP sur le port 80 avec contrôle de santé, et une IP flottante joignable depuis MGMT et le VPN d'administration.

La brique est le module `openstack-env-app` de `plateforme/tofu-modules` ; ton dépôt ne contient que des **valeurs** (exemple : `mediagenda/recette-infra`).

## Comment l'utiliser

1. Demander à la plateforme (une fois) : un projet GitLab dans le groupe de ton équipe, une application credential du projet OpenStack de ton équipe (rôle `member`, expiration à un an), un compartiment d'état S3 et son identité, la phrase de chiffrement de l'état. Tout arrive en variables **protégées et masquées** du projet GitLab : tu ne vois jamais les secrets, et tu n'en as pas besoin.
2. Copier le dépôt modèle (`mediagenda/recette-infra`), changer `prefixe`, `cidr`, les variables.
3. MR : le pipeline montre le plan dans la MR ; après fusion, lancer `appliquer` (manuel). L'URL est dans la sortie du job.
4. Détruire : pipeline lancé à la main sur `main` avec la variable `DETRUIRE=<prefixe>`, puis job `detruire`.
5. Monter de version du module : MR qui change `?ref=vX.Y.Z` ; lire le journal des changements du module avant.

## Ce qu'elle ne fournit pas (et pourquoi)

| Demande | Réponse |
|---|---|
| Terminaison TLS, HTTPS sur le répartiteur | Non : fournisseur OVN, L4 seulement (ADR-0100). Terminer le TLS dans l'application, ou un proxy dans tes instances. |
| Routage par chemin ou par nom d'hôte (L7), redirections | Non (même raison). |
| `ROUND_ROBIN` | Non : `SOURCE_IP_PORT` seulement ; la répartition est bonne avec beaucoup de connexions, inégale avec peu (un test avec `curl` en boucle tombe parfois plusieurs fois de suite sur le même serveur : c'est normal). |
| IP flottante sur un serveur | Seulement l'accès d'administration temporaire (`acces_admin = true`, par MR, puis retour à `false`). |
| Ouvrir le port 80 à « tout le monde » | Les clients autorisés sont listés (`clients_http`). |
| Gabarits plus gros, plus d'instances | Hors libre-service : ticket à la plateforme (quotas, capacité, E33). |

## Pièges du répartiteur OVN

- Les serveurs voient l'**adresse du client**, pas celle du répartiteur : leurs groupes de sécurité doivent autoriser les clients (le module le fait pour `clients_http`). Une règle « depuis le sous-réseau seulement » laisserait le répartiteur `ONLINE` (contrôles de santé OK) mais les clients sans réponse.
- Les contrôles de santé partent d'une adresse du sous-réseau des serveurs (port créé par le fournisseur) : le module autorise le sous-réseau sur le port 80.
- `operating_status` `ONLINE` du répartiteur ne prouve pas que les clients passent : teste depuis un poste client.

## Évolutions

Demande par ticket `DEV-` à la plateforme, avec le besoin (pas la solution). Les évolutions du module sont publiées par étiquette ; les équipes montent de version quand elles le décident.
