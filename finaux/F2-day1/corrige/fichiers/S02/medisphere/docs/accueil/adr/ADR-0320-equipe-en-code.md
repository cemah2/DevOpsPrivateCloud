# ADR-0320 — Une équipe en un changement : fichier déclaratif, rendu et propagation

| | |
|---|---|
| Statut | Accepté |
| Date | <AAAA-MM-JJ> |
| Décideurs | Claire Morel ; relecture Karim Benali (technique), Sophie Laurent (sécurité) |
| Ticket | PLAT-3202 (F2-S02) |
| Remplace | la procédure manuelle RB-280 (M28-E12) pour toute nouvelle équipe ; RB-280 reste la référence des équipes historiques |

## Contexte

Accueillir une équipe touchait onze endroits : annuaire (personnes, groupe), Keycloak (OTP des prestataires), GitLab (groupe, appartenances, jetons), Capsule (utilisateurs, locataire, quotas, priorités), espaces et quotas (`plateforme/k8s`), coffre (politiques, groupe externe, rôles ESO, rôles CI), Argo CD (AppProject, identifiants de dépôt), Grafana (dossier, équipe), Alertmanager (route), Kyverno (espaces où la signature est exigée), portail (fournisseurs du catalogue). RB-280 décrivait onze MR à la main dans sept dépôts : un jour ouvré dans le meilleur cas,, et chaque étape oubliée ne se voit qu'au premier incident (une route d'alertes, un rôle ESO, un espace hors de la politique de signature). Trois arrivées tombent le même mois (MédiVisio, Data, AxiomDev), puis un départ.

Contraintes : rien à la main, chaque changement relu, aucune identité de CI toute-puissante, aucune donnée supprimée par un automate, et les dépôts existants restent ceux qui appliquent (leurs pipelines, leurs garde-fous et leurs états OpenTofu ont fait leurs preuves).

## Options étudiées

| Option | Pour | Contre |
|---|---|---|
| A. Un pipeline central qui applique tout (Ansible + OpenTofu + `kubectl` + API GitLab) | un seul endroit, rapide | une identité qui peut tout (annuaire, coffre, cluster) ; deuxième chemin d'application à côté des dépôts existants ; deux états OpenTofu pour les mêmes objets |
| B. **Un fichier par équipe, rendu puis propagé par MR dans les dépôts qui appliquent** | chaque brique reste appliquée par son dépôt, ses contrôles et son identité ; l'équipe-source est relue une fois ; le rendu se lit (diff) avant d'agir | une MR par dépôt cible à fusionner (automatisé) ; propagation en minutes, pas en secondes |
| C. Les dépôts cibles lisent `plateforme/equipes` eux-mêmes (sous-module, téléchargement) | pas de MR de propagation | chaque dépôt doit savoir lire le format ; une modification d'équipe ne se voit dans aucun dépôt cible (pas de diff relu) ; ordre d'application difficile à tenir |
| D. Le modèle Backstage crée tout directement | interface agréable | la logique vit dans un formulaire ; pas de source de vérité relisible ; le portail aurait besoin des droits de tout le monde |
| E. Crossplane (compositions « Équipe ») | modèle déclaratif riche | aucun fournisseur maintenu pour FreeIPA ni OpenBao ; un opérateur de plus avec des droits larges ; fiche `annexes/decouverte/crossplane.md` |

## Décision

**Option B.** Projet `plateforme/equipes` : un fichier `equipes/<equipe>.yaml` par équipe (schéma `schema/equipe.schema.json`, format décrit dans l'introduction de F2). Sa CI :

1. **valide** (schéma JSON, puis règles de cohérence : noms réservés, responsable, budget ≥ quotas des espaces, production ⇒ `medisphere-critique`, prestataire ⇒ date d'expiration, OTP et compte GitLab externe) ;
2. **mesure** le coût en capacité (`outils/capacite.py`, bloquant) contre le relevé de `config/plateforme.yaml` ;
3. **rend** de façon complète et déterministe les fichiers que chaque dépôt cible attend (gabarits Jinja2 relus) ;
4. sur `main` : crée ce qui n'existe que dans GitLab (groupe, projet `<equipe>/gitops`, jetons de groupe rangés dans OpenBao, comptes de service membres), puis **propage** : une MR par dépôt cible, sur des chemins que le générateur possède et qu'il est seul à écrire, fusionnée automatiquement si le pipeline **du dépôt cible** réussit.

Les dépôts cibles appliquent les rendus fusionnés **sans clic** (changement standard pré-approuvé), à trois conditions vérifiées par leur pipeline : commit de `svc-equipes`, aucun fichier hors des chemins rendus, aucun plan OpenTofu qui détruit quoi que ce soit (sinon : application manuelle après lecture du plan).

Le modèle Backstage **`nouvelle-equipe`** est une interface : il produit `equipes/<equipe>.yaml` et ouvre la MR sur `plateforme/equipes` (il ne crée rien d'autre).

Décisions annexes :
- **Capacité** : un budget d'équipe (GlobalResourceQuota de son locataire) est une promesse, pas une réservation. CPU engagé jusqu'à 1,5 fois le reste allouable (compressible), mémoire jamais au-delà de 1,0 (OOM, éviction) ; relevé daté dans `config/plateforme.yaml` et `docs/accueil/capacite.md`, refait à chaque arrivée.
- **Une équipe = un locataire**, un espace par environnement nommé `<equipe>-<environnement>` (pas un espace par service comme le modèle du M28) : les quotas, le coffre, les alertes et l'AppProject sont posés une fois par environnement, et les services d'une équipe s'y ajoutent sans ticket (ApplicationSet de l'équipe, F2-S04, ADR-0321).
- **Responsable Maintainer, développeurs Developer** dans GitLab, par une extension de l'outil `synchro-gitlab` (lignes par personne) plutôt qu'un groupe de l'annuaire par rôle.
- **Rôles CI des services** liés au **chemin** du projet (`project_path`) et non à son identifiant : le projet est créé par l'équipe après le rendu. Risque : un Maintainer de l'équipe peut recréer un projet du même chemin ; accepté (il en est déjà propriétaire).
- **Politique `ci-plateforme-equipes`** : écriture des jetons `kv/+/ci/promotion` et `kv/plateforme/argocd/depot-*` pour toute équipe. Accepté : le pipeline n'écrit que ce qu'un fichier relu demande ; à resserrer si les équipes se multiplient (une politique rendue par équipe).
- **Départ** : `etat: retiree` désactive les personnes, vide les groupes, retire les droits (coffre, Argo CD, Grafana, routes) et révoque les jetons de groupe ; les espaces et le locataire (`Prune=false`, `preventDeletion`) ne sont **jamais** supprimés par un automate : RB-320, § Départ.

## Conséquences

- Arrivée d'une équipe : une MR relue (≈ 30 min de relecture), puis ≈ 20 min de propagation et d'application automatiques ; mesuré en S02 (`docs/accueil/mesures/`).
- Préalables faits une fois (S02) : annuaire et `synchro-gitlab` lisent les fichiers rendus ; Capsule lit sa liste d'utilisateurs rendue ; Applications `equipes-k8s` et `equipes-gitops` ; `AlertmanagerConfig` sélectionnés par étiquette ; politique de signature par étiquette d'espace ; portail découvrant toute l'instance et tous les groupes de personnes ; CronJob de rattachement des espaces ; règles d'application automatique des rendus.
- Nouvelles identités : compte de service GitLab `svc-equipes` (création de groupes, Developer des dépôts cibles avec droit de fusion sur `main` par MR), rôle JWT `ci-plateforme-equipes`.
- Ce qui reste manuel : relecture de la MR d'équipe ; relevé de capacité ; la synchronisation des groupes Keycloak avant le premier plan OTP d'un prestataire ; tout plan qui détruit.
- Une modification à la main d'un fichier rendu est écrasée au rendu suivant ; une dérive dans le cluster est corrigée par Argo CD (`selfHeal`).
