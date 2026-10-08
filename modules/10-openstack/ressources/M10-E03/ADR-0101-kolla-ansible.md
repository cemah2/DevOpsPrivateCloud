# ADR-0101 — Déployer OpenStack avec Kolla-Ansible

- **Statut** : acceptée
- **Date** : 2026-10 (comité d'architecture)
- **Rédaction** : Karim Benali ; **validation** : Claire Morel ; **consultée** : Sophie Laurent
- **Contexte de numérotation** : ADR du module 10 (`docs/cloud/adr/`). ADR-0100 (réseau et répartiteurs) suivra.

## Contexte

MédiSphère construit un IaaS interne sur OpenStack 2026.1 « Gazpacho » (décision du comité : souveraineté des données de santé, API compatibles avec l'outillage du marché, pas de licence). Il faut choisir **comment** le déployer et l'exploiter, avec une équipe de quatre personnes qui maîtrise déjà Ansible, OpenTofu, Debian et les conteneurs (bloc A), et un lab limité en mémoire (≈ 48 Go pour le profil OpenStack, PLAN §3.3).

Exigences :
1. configuration entièrement décrite dans un dépôt Git, déploiement **rejouable** (reconstruction du cloud depuis le code) ;
2. mises à jour mineures et montées de série documentées et outillées par le projet amont ;
3. ajout et retrait de nœuds de calcul sans réinstallation ;
4. secrets chiffrés au repos dans le dépôt ;
5. support des hôtes Debian 13 (image dorée du lab) ;
6. pas de dépendance à un éditeur commercial.

## Options étudiées

| Option | Pour | Contre |
|---|---|---|
| **Kolla-Ansible** (projet OpenStack officiel ; services en conteneurs Docker ou Podman, images publiées par le projet) | Ansible, déjà maîtrisé ; configuration = `globals.yml` + surcharges ; procédures d'*upgrade*, de reconfiguration, d'ajout de nœud documentées ; isolation des services (une image par service, versions cohérentes) ; Debian 13 supporté comme hôte en 2026.1 | Une couche de plus à comprendre (conteneurs, `kolla_start`, fichiers générés) ; images à tirer de `quay.io` (ou d'un registre miroir) ; exige une version d'ansible-core plus ancienne que celle de `plateforme/ansible` |
| **OpenStack-Ansible** (projet officiel ; services en conteneurs LXC ou sur l'hôte, venv Python par service) | Ansible ; très souple ; référence pour de grands déploiements | Beaucoup de rôles et de variables, courbe d'apprentissage forte ; LXC peu pratiqué par l'équipe ; empreinte mémoire plus élevée sur un petit lab |
| **Paquets de la distribution + rôles maison** (guide d'installation officiel) | Compréhension maximale de chaque fichier | Tout est à écrire et maintenir : mises à jour, cohérence des versions entre services, HA ; dette assurée pour une équipe de quatre |
| **OpenStack sur Kubernetes** (OpenStack-Helm, ou opérateurs) | Exploitation « à la Kubernetes » | Exige un Kubernetes de production **avant** l'IaaS (bloc C du plan, pas encore là) ; complexité cumulée |
| **Distribution commerciale** (Canonical, Red Hat…) | Support, outillage intégré | Contraire à l'exigence 6 ; coût ; Ubuntu ou RHEL comme hôtes |

## Décision

**Kolla-Ansible 22.x** (série 2026.1), hôtes **Debian 13**, moteur **Docker** posé par `kolla-ansible bootstrap-servers`, configuration dans le projet GitLab **`plateforme/openstack`** :

- un environnement `uv` dédié sur `adm01` (`~/src/openstack`), versions figées (`kolla-ansible==22.x.y`, `ansible-core` 2.20) ;
- `passwords.yml` et toute clé privée **chiffrés** par Ansible Vault (identité `critique`) ;
- images Kolla `debian` (même famille que l'hôte, recommandation de la documentation) ; **repli** sur `rocky` si une image indispensable marquée « non testée » sur Debian dans la matrice de support pose problème — le changement de `kolla_base_distro` se fait par reconstruction ;
- déploiement lancé depuis `adm01` par une personne habilitée (le runner n'a pas l'identité `critique`) ; l'automatisation par pipeline sera réévaluée au mini-projet ;
- les nœuds sont créés par OpenTofu (`plateforme/infra`, `envs/openstack`) et préparés par Ansible (`plateforme/ansible`, rôle `noeud_openstack`) ; Kolla ne gère que ce qui est à lui (Docker, conteneurs, configuration des services).

## Conséquences

- Deux versions d'ansible-core cohabitent sur `adm01` : chaque projet a son environnement et **ses** collections (`collections_path` local). Toute commande Kolla se lance depuis `~/src/openstack`.
- L'équipe doit savoir lire une configuration **générée** (`/etc/kolla/<service>/` sur les nœuds) et ne jamais la modifier à la main : la source est le dépôt.
- Les montées de version suivent la procédure amont (« Operating Kolla », *upgrade*) ; on attend qu'une série soit publiée **en version stable** par Kolla avant de la viser (2026.2 n'est qu'en version candidate à la date de cette ADR).
- Le plan de contrôle tient sur **un** nœud au départ (`osctl01`) : non redondant, ce qui est accepté pour le lab et mesuré (palier 3) ; Kolla sait passer à trois contrôleurs sans changer les points d'accès (VIP).
- Les images viennent de `quay.io/openstack.kolla` : le flux sortant des nœuds vers Internet (443) est nécessaire au déploiement et aux mises à jour ; un registre miroir interne (module 13) le supprimera.

## Références

- Kolla-Ansible 2026.1 : <https://docs.openstack.org/kolla-ansible/2026.1/>
- Matrice de support des images Kolla 2026.1 : <https://docs.openstack.org/kolla/2026.1/support_matrix.html>
- Notes de version Kolla-Ansible 2026.1 : <https://docs.openstack.org/releasenotes/kolla-ansible/2026.1.html>
- OpenStack-Ansible : <https://docs.openstack.org/openstack-ansible/latest/>
