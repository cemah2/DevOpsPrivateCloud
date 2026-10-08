# RB-100 — Accueillir une équipe sur OpenStack

| | |
|---|---|
| Version | 1.0 (M10-E22, PLAT-1132) |
| Propriétaire | Équipe Plateforme ; relu par Nadia Roussel (astreinte), Sophie Laurent (RSSI) |
| Durée | 45 min à 1 h 30 (hors attente de la MR) |
| Droits | `medisphere-admin` sur `adm01` ; droit de fusion sur `plateforme/openstack` et `plateforme/infra` ; accès Vault `critique` |
| Liés | RB-060 (ajouter un hôte), `docs/cloud/capacite.md`, `docs/cloud/roles.md`, `docs/cloud/reseau-externe.md`, `donnees/identite.yml` (`plateforme/openstack`), `envs/openstack-projets` (`plateforme/infra`) |

## 1. Quand l'utiliser

- Une équipe de MédiSphère demande un ou des projets OpenStack (dev, prod).
- Une équipe existante demande un projet supplémentaire, ou part (section 7).

**N'en relève pas** : une hausse de quota d'un projet existant (MR sur `capacite.md` + `envs/openstack-projets`, sans le reste) ; un accès ponctuel d'un individu (ajout au groupe de l'équipe dans `donnees/identite.yml`, section 4.1 seulement) ; un besoin de réseau provider, de gabarit spécial ou d'IP publiée (décision d'architecture : ADR).

## 2. Ce qu'on demande à l'équipe (formulaire, dans le ticket)

| Champ | Exemple (`medidoc`) |
|---|---|
| Nom court de l'équipe (`[a-z]+`) | `medidoc` |
| Projets voulus | `medidoc-dev`, `medidoc-prod` |
| Responsable (validera les accès) | lead de l'équipe |
| Membres (prénom.nom) | 3 personnes |
| Besoin de ressources (instances, vCPU, mémoire, Go, IP flottantes, répartiteurs) par projet | voir `capacite.md` |
| CI : oui / non, projet GitLab | `medidoc/medidoc` |
| Données de santé en production ? | oui → revue Sophie obligatoire |

Refuser de commencer sans le responsable et le besoin chiffré.

## 3. Prérequis

- [ ] Capacité : la somme des quotas de mémoire, **nouveaux compris**, reste sous la mémoire utilisable (`capacite.md`, section 1). Sinon : arbitrage de Claire **avant** toute création.
- [ ] Sous-réseaux choisis, sans chevauchement (`grep cidr envs/openstack-projets/terraform.tfvars`) : `192.168.<NNN>.0/24`.
- [ ] `OS_CLOUD=medisphere-admin` fonctionne (`openstack token issue`).
- [ ] Copie de travail à jour de `plateforme/infra` et `plateforme/medisphere`.

## 4. Étapes

Variables du runbook, dans le shell de `adm01` : `export OS_CLOUD=medisphere-admin EQ=medidoc DOM=medisphere`.

### 4.1 Projets, groupe, comptes et rôles (code d'identité)

Tout passe par une MR sur `plateforme/openstack` (code d'identité de M10-E05), relue par Sophie si l'équipe traite des données de santé :

- `donnees/identite.yml` :
  - `identite_projets` : `{nom: medidoc-dev, description: "MédiDoc : développement et recette — <ticket>"}` et `medidoc-prod` ;
  - `identite_groupes` : `equipe-medidoc` (membres, rôles `member` sur `medidoc-dev`, `reader` sur `medidoc-prod`) ; ajouter `reader` et `support` sur les deux projets au groupe `equipe-support` (le rôle `support` n'est **pas** hérité : choix de M10-E23) ;
  - `identite_utilisateurs` : les membres absents du domaine (`prenom.nom`, description, courriel) ;
- `donnees/vault-identite.yml` (chiffré, `critique`) : un mot de passe initial **généré** (`openssl rand -base64 24`) par nouveau compte.

Puis, depuis `~/src/openstack` :
```
admin@adm01:~/src/openstack$ uv run ansible-playbook playbooks/identite.yml --check --diff
admin@adm01:~/src/openstack$ uv run ansible-playbook playbooks/identite.yml
admin@adm01:~/src/openstack$ uv run ansible-playbook playbooks/identite.yml     # second passage : changed=0
```
**Attendu** : projets créés, `changed=0` au second passage. **Sinon** : nom de projet déjà pris → arrêter, vérifier avec le demandeur (pas de suffixe improvisé).

L'audit (`equipe-securite`) est hérité du domaine : rien à faire.

**Jamais** : `admin` sur un projet d'équipe (il est global) ; un rôle donné à une personne plutôt qu'au groupe ; un projet ou un rôle créé à la main « en attendant la MR ».

Mot de passe initial : remis à chaque personne par un canal séparé (appel + lien de partage à usage unique), jamais par le ticket ; la personne le change à sa première connexion (`openstack user password set`). Keystone ne l'impose que si `[security_compliance] change_password_upon_first_use` est actif (point du palier 3).

**Contrôle** : `openstack role assignment list --effective --names --project medidoc-dev --project-domain medisphere` : `member` pour les membres, `reader` + `support` pour le support, `reader` pour la sécurité et l'équipe Plateforme selon E05, **aucun** `admin`.

### 4.2 Quotas et socle réseau (code)

1. MR sur `plateforme/medisphere` : lignes de l'équipe dans `docs/cloud/capacite.md` (quotas justifiés).
2. MR sur `plateforme/infra` : entrées `$EQ-dev`, `$EQ-prod` dans `envs/openstack-projets/terraform.tfvars` (cidr, quotas) et dans `repartiteurs` (`octavia.tf`).
3. Lire le plan dans la MR : **uniquement** des créations pour la nouvelle équipe (quotas ×4, réseau, sous-réseau, routeur, interface, groupe, règles). Toute modification d'une autre équipe → arrêter.
4. Fusion, `apply:openstack-projets` (manuel).

**Contrôle** : `openstack network list --project $EQ-dev` → `$EQ-dev-net` MTU 1500 ; `openstack router show $EQ-dev-routeur -c external_gateway_info` → `ext-net` ; `openstack quota show --usage $EQ-dev`.

### 4.3 Accès de la CI (si demandé)

L'application credential appartient à un **compte de service** (domaine `Default`, comme les autres comptes de service), pas à une personne :
```
admin@adm01:~$ openstack user create --domain Default --description "CI de $EQ" --password-prompt svc-ci-$EQ
admin@adm01:~$ openstack role add --user svc-ci-$EQ --user-domain Default --project $EQ-dev --project-domain $DOM member
```
Puis, **en tant que `svc-ci-$EQ`** (variables `OS_*` d'un seul shell, mot de passe lu par `read -s`, sur le modèle de `creer-identite-tofu.sh` de M10-E15) : `openstack application credential create --expiration <J+90> --description "CI $EQ-dev" ci-$EQ-dev`. Le secret est affiché **une fois** : il va directement dans les variables protégées et masquées du projet GitLab de l'équipe (`OS_APPLICATION_CREDENTIAL_ID`, `OS_APPLICATION_CREDENTIAL_SECRET`), jamais dans un ticket ni un courriel. Le mot de passe de `svc-ci-$EQ` est ensuite changé pour une valeur aléatoire oubliée (le compte ne sert qu'à renouveler l'application credential, en repassant par l'administrateur).

Registre des secrets : une ligne par application credential (propriétaire, expiration, emplacement, procédure de rotation).

### 4.4 Remise à l'équipe

Envoyer (ticket ou wiki de l'équipe) : URL `https://openstack.par1.medisphere.internal/`, domaine `medisphere`, un `clouds.yaml` **sans secret** (auth par mot de passe : `auth_url`, `project_name`, `project_domain_name`, `user_domain_name`, `region_name: RegionOne`, `interface: public`, `cacert`), la racine « MédiSphère Root CA », le lien vers `docs/cloud/guide-utilisateur.md`, les quotas, la politique réseau (`reseau-externe.md` : ce qui sort et entre), le contact du support.

Accès réseau : depuis le VPN d'administration, Horizon et la console sont ouverts (M10-E17). Rien d'autre à ouvrir pour une équipe.

### 4.5 Contrôle final par l'équipe

Avec **un membre** de l'équipe (pas avec `medisphere-admin`) :
- [ ] connexion à Horizon, domaine `medisphere`, projets visibles : les siens seulement ;
- [ ] `openstack --os-cloud <son cloud> server list` réussit (vide) ;
- [ ] création d'une instance `m1.petit` dans `$EQ-dev-net`, IP flottante, SSH depuis le VPN ; suppression ;
- [ ] sur `$EQ-prod`, une création est **refusée** (403 : `reader`).

Clore le ticket avec les sorties de ces contrôles.

## 5. Documentation

- `docs/cloud/capacite.md` (quotas, tableau « qui peut quoi ») ; registre des secrets ; liste des équipes dans `docs/cloud/guide-utilisateur.md`.

## 6. Retour arrière (pendant l'accueil)

Dans l'ordre inverse : retirer l'entrée de `terraform.tfvars` (MR, apply : réseau, routeur, groupe de sécurité supprimés ; quotas inchangés), révoquer l'application credential et supprimer `svc-ci-$EQ`, retirer l'équipe de `donnees/identite.yml` puis supprimer à la main ce que le playbook ne retire pas (rôles, groupe, comptes créés pour l'occasion, projets : `openstack project set --disable` puis `openstack project delete`).

## 7. Retrait d'une équipe

1. Annonce et date (ticket CHG), export éventuel des données par l'équipe (volumes, images).
2. Ressources des projets, **dans cet ordre** (chaque commande avec `--project`) : répartiteurs (`openstack loadbalancer delete --cascade`), piles Heat, instances, IP flottantes, volumes et instantanés, sauvegardes de volumes, images privées, groupes de sécurité non gérés, ports orphelins. Contrôle : `openstack port list --project <p>` ne montre plus que ceux du socle OpenTofu.
3. Socle : retirer l'équipe de `envs/openstack-projets` (MR, apply).
4. Quotas : remettre à 0 (`openstack quota set` + `openstack loadbalancer quota set`), car le `destroy` OpenTofu des quotas ne fait rien.
5. Accès : révoquer les application credentials, retirer les variables CI, supprimer `svc-ci-$EQ` ; dans `donnees/identite.yml`, retirer le groupe `equipe-$EQ` et les rôles du support sur ces projets (MR) — le playbook ne **supprime** rien de ce qui a disparu de la liste : retrait par `openstack role remove`, `openstack group delete`, et désactivation (pas suppression, pour l'audit) des comptes des personnes qui quittent MédiSphère.
6. Projets : `openstack project set --disable`, puis suppression après 30 jours (traçabilité) et retrait de `identite_projets`.
7. Documentation et registre des secrets.

**Contrôle** : `openstack role assignment list --names --project <p>` vide ; `openstack floating ip list --project <p>`, `volume list`, `loadbalancer list` vides.

## 8. Pièges connus

- Donner `admin` « pour débloquer » : c'est donner tout le cloud.
- Créer les projets à la main **et** dans le code, ou par OpenTofu : un seul propriétaire par objet (code d'identité pour projets, groupes et rôles ; OpenTofu pour le socle).
- Croire que retirer une ligne de `donnees/identite.yml` retire l'objet : le playbook ne fait que créer et mettre à jour.
- Application credential créée par une personne : elle disparaît avec son compte, et la CI s'arrête.
- Sous-réseau qui chevauche un VLAN du lab (10.10.0.0/16) : routage incohérent derrière le SNAT.
- Oublier `support` sur un nouveau projet : le support ne peut plus aider (pas d'héritage pour ce rôle, choix volontaire).
- Supprimer un projet avant ses ressources : ports, IP flottantes et volumes orphelins, invisibles dans Horizon.
