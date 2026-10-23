# ADR-0280 — Plateforme développeurs : portail, locataires, autoscaling

| | |
|---|---|
| Statut | Accepté (<DATE>) |
| Décideurs | Claire Morel, Karim Benali, Sophie Laurent (RSSI, pour l'isolation), Julien Petit (pour les équipes) |
| Ticket | PLAT-2917 |
| Remplace / complète | complète ADR-0200 (GitOps), ADR-0210 (métriques), ADR-0260 (durcissement), ADR-0270 (messagerie) |

## Contexte

Lancer un service coûtait six tickets et dix jours ; MédiNotif prenait une heure de retard pendant les campagnes de rappel ; MédiAgenda gardait trois pods la nuit ; les équipes ne savaient pas qui possédait quoi. Contraintes : équipe Plateforme de quatre personnes et un stagiaire ; logiciels libres hébergés chez nous ; un seul cluster `k8s-par1` (trois travailleurs de 4 vCPU et 10 Go) dans un lab de 128 Go occupé à 111 Go ; tout en code, GitOps (rien appliqué à la main sur les espaces applicatifs).

Mesures du module (lab de référence) : Backstage ≈ 450 Mio par réplica + `portail-db` ≈ 200 Mio ; Capsule ≈ 60 Mio ; un vCluster `vc-essai` ≈ 900 Mio et 2 Go de volume ; KEDA ≈ 150 Mio ; VPA ≈ 200 Mio ; démarrage à froid de MédiNotif 22 s ; création d'un service fictif par le modèle `nouveau-service` : 4 min et deux MR à relire (au lieu de six tickets).

## Décisions

### 1. Portail : Backstage

**Retenu** : Backstage 1.56 (catalogue alimenté par les `catalog-info.yaml` de GitLab et les groupes de FreeIPA, modèles qui ouvrent des MR, TechDocs, vue Kubernetes), deux réplicas, base sauvegardée, montée mensuelle outillée (`versions:bump`).

Coût assumé : ≈ 1,1 Gio de mémoire au total, une image à construire (TypeScript, Node 24), une demi-journée par mois de montée de version, un compte de service GitLab à jetons expirables.

Écartés : *pas de portail* (README et modèles de projet GitLab) — moins cher, mais ni catalogue ni propriétaires ni vue d'ensemble, et le « chemin balisé » reste un document ; *portails commerciaux ou SaaS* — données de l'organisation hors de chez nous, coût par développeur.

Garde-fou : le portail **n'est pas** un point de passage obligé. Il ouvre des MR ; GitLab et Argo CD restent la source de vérité et la voie de secours (RB-284).

### 2. Multi-locataire : Capsule, pas un vCluster par équipe

**Retenu** : Capsule 0.15 (≥ 0.15.0 : correctif GHSA-p8j8-x28r-3c9v), un locataire par équipe (`mediagenda`, `medinotif`, `medidoc`) défini dans `plateforme/k8s/locataires/` : préfixe imposé, budget global, classes de stockage et de priorité, PSA `restricted` imposée, cloison réseau par locataire, Services exposés interdits. Isolation éprouvée par un essai d'intrusion (M28-E15, quatre trous bouchés).

Écarté pour l'usage courant : un vCluster 0.37 par équipe — ≈ 900 Mio par équipe (×3 = un dixième de la mémoire des travailleurs), un plan de contrôle de plus à mettre à jour, à superviser et à sauvegarder par équipe, et une isolation qui reste celle des nœuds partagés. **Il se justifierait** pour une équipe qui doit installer ses propres CRD ou opérateurs, ou tester une autre version de Kubernetes ; il se crée alors dans son locataire, pour une durée limitée.

Contrainte acceptée : Capsule 0.15 n'accepte que la dernière mineure de Kubernetes (≥ 1.36.0) : chaque montée de Kubernetes attend la version de Capsule correspondante (à vérifier avant le changement).

### 3. Autoscaling

**Retenu** :
- **HPA** (`autoscaling/v2`, CPU, comportement explicite) pour MédiAgenda (Rollout), recette et prod, `replicas` retiré de Git.
- **KEDA 2.21** pour MédiNotif : file `notifications` (le vrai signal), `cron` pour les campagnes connues à l'avance, débit de publication de MédiAgenda (anticipation), `fallback` et comportement d'HPA ; **mise à zéro en recette** seulement (22 s de démarrage à froid acceptés), minimum 2 en prod.
- **VPA 1.7.1 en recommandation seulement** (`updateMode: "Off"`), recommandations remises aux équipes par une MR mensuelle (`outils/recommandations-vpa.sh`). Pas de mode automatique : il redémarre ou redimensionne des pods sans revue, et se battrait avec un HPA sur le CPU ou la mémoire ; jamais VPA et HPA sur la même ressource.
- **Pas d'autoscaling de nœuds** : le Cluster Autoscaler sait piloter Cluster API (fournisseur `clusterapi`), mais `k8s-par1` est construit par OpenTofu et kubeadm, pas par Cluster API, et surtout la capacité physique de `pve01` est fixe : ajouter un travailleur, c'est prendre la mémoire d'autre chose. Karpenter n'a pas de fournisseur Proxmox maintenu par son projet (seulement des fournisseurs communautaires). À la place : budgets par locataire, classes de priorité (`medisphere-critique` > `standard` > `ci` > `lot`), bilan de capacité trimestriel (`capacite.md`).

### 4. Écartés pour l'instant

| Outil | Pourquoi pas maintenant | Signal qui ferait revoir la décision |
|---|---|---|
| **Crossplane 2.4** | Rien à piloter derrière : pas d'API de services managés ; les fournisseurs Proxmox ou PowerDNS sont communautaires et jeunes ; OpenTofu (`plateforme/infra`) et Ansible font déjà ce travail, avec état, revue et compétences de l'équipe. Fiche : `annexes/decouverte/crossplane.md` | une demande récurrente de ressources hors cluster en libre-service (bases, compartiments S3, DNS) par plus de deux équipes, ou l'adoption d'un cloud public |
| **Tilt / Skaffold** | La boucle de développement locale des équipes repose sur `docker compose` (M12) et suffit à trois services simples ; le cluster partagé n'est pas un poste de développement. Fiche : `annexes/decouverte/tilt-skaffold.md` | une application qui ne se lance plus en local sans le cluster (dépendances à des opérateurs, CRD), ou plus de dix minutes entre une modification et son essai |

## Conséquences et risques

| Risque | Mesure |
|---|---|
| Le portail devient un passage obligé | il n'ouvre que des MR ; RB-284 ; deux réplicas ; sauvegarde |
| Démarrage à froid et source muette pendant que MédiNotif dort (recette) | accepté en recette ; prod à 2 minimum ; alertes `KedaScalerEnErreur`, `KedaAbsent` |
| Préemption de composants de plateforme non classés (priorité 0) | budgets avec marge, `lot` sans préemption ; classe `medisphere-plateforme` à étudier avant le F2 |
| Contournement d'autorisation dans Capsule | version minimale 0.15.0, essai d'intrusion rejoué à chaque montée |
| Montée de Kubernetes freinée par Capsule | vérification de compatibilité dans la procédure de montée (M14) |

## Révision

À la première des échéances : un an ; une quatrième équipe ; un signal du tableau du § 4 ; un incident de priorité 1 attribuable à la plateforme développeurs.
