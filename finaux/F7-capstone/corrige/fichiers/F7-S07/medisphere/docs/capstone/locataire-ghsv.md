# Le locataire du client GHSV

> F7-S07 (PLAT-3707). Un client = **un fichier** : `equipes/ghsv.yaml` de `plateforme/equipes` (type `client`). Relu par la Plateforme et Sophie Laurent ; le bloc « contrat » par Claire Morel. Procédures liées : RB-320 (équipes en code), RB-371 (réversibilité et fin de contrat), RB-372 (identité fédérée), RB-373 (contrat d'API), RB-374 (rapport mensuel).

## 1. Ce que crée le fichier (rendu de `outils/rendre.py`, propagé par MR)

| Brique | Objet | Dépôt qui applique |
|---|---|---|
| Annuaire | groupe `ghsv` (Julien Petit, Nadia Roussel : les personnes de MédiSphère qui répondent du compte ; c'est le groupe « exploitation du GHSV » de l'ADR-0370, nominatif et revu chaque trimestre) | `plateforme/identite` |
| GitLab | groupe `ghsv` (contrat d'API reçu, `ghsv/contrat-api`) ; aucun compte du GHSV | job `gitlab:equipes` |
| Kubernetes | Tenant Capsule `ghsv` (`preventDeletion`, propriétaire `oidc:ghsv` en **lecture**), espaces `ghsv-recette` et `ghsv-prod` (quota, LimitRange, PSA `restricted`, étiquette `medisphere.internal/client: ghsv`, `SecretStore` `openbao`, route d'alertes vers `ghsv@`), aucun libre-service | `plateforme/k8s` (Application `equipes-k8s`) |
| Argo CD | AppProject `ghsv` : **une** source (`mediagenda/deploiement`), **deux** destinations ; ApplicationSet `client-ghsv` → Applications `ghsv-recette` (automatique) et `ghsv-prod` (manuelle, fenêtre CHG-2129) | `plateforme/gitops` |
| OpenBao | politique `ghsv-equipe`, rôles `eso-ghsv-recette` / `eso-ghsv-prod` ; **clés** `transit/ghsv-exports`, `ghsv-signature`, `ghsv-sauvegardes` (non exportables, non supprimables, rotation annuelle) ; politiques `ghsv-reversibilite` (groupe `ghsv`), `ghsv-dechiffrement` et `ghsv-destruction` (aucun groupe : jetons d'opération par rôles de jeton, ADR-0371) | `plateforme/secrets` (`tofu/equipes.tf`, `tofu/clients.tf`) |
| Grafana | dossier « Client GHSV », équipe | `plateforme/infra` |

## 2. Ce qui reste hors du fichier (et pourquoi)

| Élément | Où | Pourquoi pas dans le fichier |
|---|---|---|
| L'instance de MédiAgenda (`overlays/clients/ghsv-*`, components `client`, `client-donnees`) | `mediagenda/deploiement` | c'est le code de l'application, versionné et promu avec MédiAgenda (même version, mêmes images signées) |
| Royaume `ghsv-idp` (simulation) et courtier `ghsv-idp` | `plateforme/identite` | identité : configuration riche, relue par Sophie, état chiffré (RB-372) |
| Compartiments `cnpg-ghsv` (s3-01) et `ghsv-reversibilite` (RGW) | `plateforme/ceph`, rôle `seaweedfs` | identités S3 créées par les outils existants ; clés rangées dans `kv/ghsv/<env>/` |
| SLO, sondes, rapport mensuel | `plateforme/observabilite`, `plateforme/ansible`, `plateforme/outils` | F7-S10 |
| Nom global `ghsv.medisphere.internal`, PRA | `plateforme/infra` (DNS), F5 | F7-S10 |

## 3. Marque blanche

Ce que voit un utilisateur du GHSV : le nom publié (`ghsv.apps.par1…` dans le lab ; en production `rendez-vous.ghsv.example`, CNAME vers `ghsv.medisphere.internal`), le titre de la description OpenAPI (« API de rendez-vous du GHSV », variable `MEDIAGENDA_TITRE`, correctif additif de `mediagenda/api`), les messages d'erreur (neutres). L'en-tête `X-MediSphere-Site` du F5 reste : il nomme l'hébergeur, pas un secret (le GHSV connaît son hébergeur ; les patients ne lisent pas les en-têtes) et la sonde de PRA en a besoin. Décision : gardé, écrit ici.

## 4. Données et clés (ESC-06)

| Données | Protection dans la preuve de concept | Cible de production | Écart |
|---|---|---|---|
| Base (`mediagenda-db` de `ghsv-*`) | volume `ceph-rbd-chiffre` (LUKS par ceph-csi, phrase par volume dans les métadonnées du PV) | clé de chiffrement du volume tirée d'un coffre **par locataire** (ceph-csi, KMS OpenBao, chemin `ghsv`), enveloppée par `transit/ghsv-donnees` | la phrase n'est pas une « clé dédiée au GHSV » révocable par lui : **écart écrit**, lot de construction |
| Archives et sauvegardes CNPG (`cnpg-ghsv`) | compartiment propre au client, identité S3 propre | chiffrement côté serveur du compartiment par clé KMS `transit/ghsv-sauvegardes` (RGW SSE-KMS adossé à OpenBao), ou chiffrement client des archives | non chiffrées par une clé du client aujourd'hui : **écart écrit** |
| Exports de réversibilité | chiffrés avant de quitter `adm01` par une clé de données à usage unique enveloppée par `transit/ghsv-exports`, manifeste signé par `transit/ghsv-signature` | idem | — |
| Copies de PAR2 | répliques des archives (`s3-02`) et de la base (`k8s-par2`) | idem cible | même écart que les archives |

**Effacement cryptographique** (fin de contrat, ou révocation demandée par le GHSV, R-14) : supprimer les clés `transit/ghsv-*` rend illisibles toutes les enveloppes encore stockées (exports, et à la cible sauvegardes et volumes), y compris les copies de PAR2 et les sauvegardes en rétention que l'on ne peut pas effacer une à une. RB-371 §5. Tant que les écarts ci-dessus ne sont pas comblés, l'effacement de la base et des archives se fait **aussi** par destruction physique des volumes et des compartiments (procès-verbal).

**Rotation** : automatique annuelle (`auto_rotate_period`), anciennes versions conservées pour déchiffrer ; après rotation, `rewrap` des enveloppes (RB-371 §6).

## 5. Arrivée et départ d'un client

| Étape | Arrivée | Départ (fin de contrat) |
|---|---|---|
| Contrat | bloc `client.contrat` (dates), relu par Claire | date de fin atteinte : RB-371 |
| Fichier | MR créant `equipes/<client>.yaml` | MR `etat: retiree` : droits retirés, Applications supprimées **sans** leurs objets (`preserveResourcesOnDeletion`, `Prune=false`) |
| Données | — | export final, validation par le client, destruction (volumes, compartiments, copies de PAR2, clés), procès-verbal (RB-371) |
| Identité | courtier et clients Keycloak (RB-372) | suppression du fournisseur et des comptes fédérés (RB-372 §6) |

## 6. Écarts restants (preuve de concept → production)

1. Identifiants dynamiques de la base (moteur `db-ghsv` d'OpenBao) : non mis en place (adresse `LoadBalancer` 10.10.41.x par base) ; le propriétaire CNPG sert à l'API.
2. Clés du client pour les volumes et les archives : §4.
3. Pièces jointes (EF-07, 2 To/an) : hors de la preuve de concept (MédiDoc pour le GHSV, compartiment dédié).
4. Comptes des patients (EF-09) : hors de la preuve de concept (l'interface patient n'existe pas dans le lab).
