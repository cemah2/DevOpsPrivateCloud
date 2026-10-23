# Crossplane — fiche découverte

> Fiche courte du module 28 (plateforme développeurs). Crossplane **n'est pas installé** dans le lab (décision : ADR-0280, M28-E17). Version de référence relevée le 23/10/2026 : **2.4.x** (2.4.3). Projet de la CNCF.

## Ce que c'est

Crossplane transforme le cluster Kubernetes en **plan de contrôle d'infrastructure** : des ressources externes (une base de données managée, un compartiment S3, un enregistrement DNS, une VM) deviennent des objets Kubernetes, réconciliés en continu par des contrôleurs. Une équipe plateforme compose ces ressources en **API maison** (« une base pour MédiAgenda » = base + utilisateur + secret + règle réseau) que les équipes demandent en libre-service, avec le même outillage que leurs applications (Git, Argo CD, RBAC).

## Concepts (Crossplane 2)

| Concept | Rôle |
|---|---|
| **Provider** | paquet de contrôleurs qui parle à une API externe (AWS, Azure, GCP, Kubernetes, Helm, SQL…) ; beaucoup sont **générés par Upjet** depuis un fournisseur Terraform |
| **Managed resource (MR)** | une ressource externe, un objet par ressource (`Bucket`, `Instance`…) |
| **Composite resource definition (XRD)** | le schéma de l'API maison (`apiextensions.crossplane.io/v2`) |
| **Composite resource (XR)** | une instance de l'API maison ; en Crossplane 2, **à espace de noms par défaut** : plus besoin de *claims* pour les nouveaux XR |
| **Composition + fonctions** | la recette qui fabrique les ressources d'un XR ; en Crossplane 2, **uniquement par des fonctions de composition** (`function-patch-and-transform`, `function-go-templating`, `function-kcl`…) : le mode *patch-and-transform* natif est retiré |

Changements de la v2 à retenir : XR à espace de noms, *claims* hérités seulement, `ControllerConfig` retiré (remplacé par `DeploymentRuntimeConfig`), compositions par fonctions seulement.

## Ce qu'on piloterait chez MédiSphère

| Cible | Ce qui existe | Pour Crossplane |
|---|---|---|
| VMs Proxmox | OpenTofu (`plateforme/infra`, module `vm-debian`), Cluster API + CAPMOX (M18) | aucun fournisseur maintenu par le projet ; fournisseurs communautaires jeunes, ou générés depuis un fournisseur Terraform |
| DNS PowerDNS | OpenTofu, ExternalDNS (RFC 2136) dans le cluster | fournisseur communautaire ; ExternalDNS couvre déjà le besoin des applications |
| Secrets OpenBao | OpenTofu (`hashicorp/vault`), ESO | fournisseur Vault communautaire (compatibilité OpenBao à vérifier) |
| Bases PostgreSQL | CloudNativePG (déjà déclaratif) | apporte une API composée « base d'application », mais CNPG est déjà un objet Kubernetes |
| Compartiments S3 | SeaweedFS / RGW, rôles Ansible | fournisseurs S3 génériques possibles |

## Pourquoi il n'est pas retenu (ADR-0280)

- **Rien de managé à exposer** : il n'y a pas de catalogue de services managés derrière une API dans un cloud privé de cette taille ; ce que Crossplane piloterait est déjà décrit en code (OpenTofu, Ansible, CNPG) avec revue et état versionné.
- **Fournisseurs immatures** pour Proxmox et PowerDNS, et compatibilité OpenBao non garantie : on échangerait des outils maîtrisés contre des contrôleurs jeunes.
- **Coût** : un plan de contrôle de plus (fournisseurs, fonctions, mises à jour), des compétences nouvelles, pour trois équipes.

**Signal de révision** : plusieurs équipes demandent régulièrement des ressources hors cluster en libre-service (bases, compartiments, DNS), ou MédiSphère adopte un cloud public.

## Pour aller plus loin

- Documentation : <https://docs.crossplane.io/latest/>
- Nouveautés de la v2 : <https://docs.crossplane.io/latest/whats-new/>
- Fonctions de composition : <https://docs.crossplane.io/latest/composition/compositions/>
- Upjet (génération de fournisseurs) : <https://github.com/crossplane/upjet>
