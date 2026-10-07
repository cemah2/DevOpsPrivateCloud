# M04-E34 — Cahier des charges : rôle `node_exporter`

> Ne lis ce fichier qu'au démarrage du chrono (T0). Durée : 2 h 30 jusqu'à la MR prête à fusionner.

**Demandeur** : Karim Benali (équipe Plateforme) · **Consommateur** : supervision Prometheus du module 21.

## Contexte

Chaque VM du socle exposera ses métriques système à Prometheus (module 21). On utilise l'exportateur
officiel du projet Prometheus **tel que packagé par Debian 13** (paquet `prometheus-node-exporter`,
version 1.9.x). Aucun binaire téléchargé, aucune compilation.

## Exigences

| # | Exigence |
|---|---|
| X1 | Le paquet `prometheus-node-exporter` est installé ; le service du même nom est activé au démarrage et tourne. |
| X2 | L'exportateur n'écoute **que** sur l'adresse IPv4 principale de l'hôte (celle de sa route par défaut), sur le port `9100` par défaut, modifiable par variable. Jamais sur toutes les adresses. |
| X3 | Les collecteurs `infiniband`, `zfs`, `nfs` et `nfsd` sont désactivés par défaut ; la liste est une variable (une liste vide est permise). |
| X4 | Le collecteur `systemd` ne publie l'état que des unités utiles au socle, données par une variable (liste de noms d'unités sans suffixe) ; par défaut : `ssh`, `chrony`, `nftables`, `dnsmasq`, `gitlab-runner`, `semaphore`. Attention à l'échappement des expressions régulières dans `/etc/default/prometheus-node-exporter` lu par systemd (lis l'en-tête du fichier livré par Debian). |
| X5 | Le collecteur `textfile` publie une métrique d'inventaire `medisphere_info` de valeur `1`, avec les étiquettes `site="par1"` et `role` = le ou les groupes `role_*` de l'hôte dans l'inventaire (séparés par des virgules s'il y en a plusieurs, `aucun` sinon). Fichier dans le dossier `textfile` par défaut de Debian, lisible par l'exportateur, jamais à moitié écrit au moment où il est lu. |
| X6 | Un changement de paramètres redémarre le service une seule fois ; une exécution sans changement ne le redémarre pas. |
| X7 | Les variables du rôle sont décrites et **validées** par `meta/argument_specs.yml` (types, valeurs par défaut, description) ; un port hors de 1024-65535 est refusé avant toute action. |
| X8 | Le rôle passe `ansible-lint` avec le profil `production`, fonctionne avec ansible-core 2.19 et 2.21 (FQCN, faits lus dans `ansible_facts['…']`, conditions booléennes). |
| X9 | Un scénario Molecule `node_exporter` (instance VMID **2049**, `m04-mol-nodeexp`, placée aussi dans un groupe `role_test` de l'inventaire du scénario) applique le rôle, vérifie l'idempotence et contrôle par HTTP, **sur l'adresse principale** de l'instance (la requête part de l'instance elle-même : depuis `runner01`, seul SSH est ouvert vers `vsandbox`) : la page `/metrics` répond, contient `node_exporter_build_info`, `medisphere_info` avec les bonnes étiquettes et l'état de `ssh.service`, aucune métrique du collecteur `zfs` ; et rien n'écoute sur `127.0.0.1:9100` ni sur toutes les adresses. |
| X10 | Le job Molecule du rôle est ajouté à la CI (même modèle que les autres rôles) et tourne sur la MR. |
| X11 | Un `README.md` du rôle : but, variables, exemple d'utilisation, limites (pas de TLS ni d'authentification : à traiter au module 21 ; le filtrage réseau n'est **pas** géré par ce rôle). |

## Hors périmètre

- Le pare-feu de `gw01` et la matrice des flux (Prometheus n'existe pas encore).
- L'application du rôle au socle.
- TLS et authentification de l'exportateur (`--web.config.file`).

## Livrables

- `roles/node_exporter/` (au minimum `defaults/`, `handlers/`, `meta/` avec `argument_specs.yml`, `tasks/`, `templates/`, `README.md`).
- `molecule/node_exporter/` (`molecule.yml`, `converge.yml`, `verify.yml`, `inventaire/hosts.yml`).
- `.gitlab-ci.yml` modifié.
- Une MR au format de l'équipe (Conventional Commits, description : ce qui est fait, comment c'est testé, ce qui ne l'est pas), pipeline vert.
