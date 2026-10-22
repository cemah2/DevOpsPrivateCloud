# ADR-0200 — GitOps : Argo CD, promotion par MR et par digest, frontière avec Helmfile

| | |
|---|---|
| Statut | Acceptée |
| Date | <DATE> |
| Décideurs | Claire Morel, Karim Benali, Sophie Laurent ; rédaction : <MOI> |
| Ticket | PLAT-2131 (M20-E31) |
| Remplace / complète | complète ADR-0170 (rendu commité du chart) et ADR-0190 (chaîne de CI) |

## Contexte

- Jusqu'au M19, les changements étaient **poussés** : `helmfile apply` et `kubectl apply --server-side -k` depuis `adm01`, puis le job `deployer-dev` par l'agent GitLab. Personne ne voyait la dérive (corrections « vite fait » à la main), la CI détenait des droits d'écriture sur `mediagenda-dev`, et la production dépendait du poste d'un administrateur.
- Exigences : Git comme seule source de vérité ; aucun droit d'écriture pour la CI des applications (SEC-2130) ; promotions relues ; déploiements progressifs ; gestion de l'agence LYO1 depuis PAR1 ; GitLab CE (pas d'environnements protégés ni d'approbations obligatoires, ADR-0051) ; lab à ≈ 100 Go de mémoire.
- Mesures et incidents du module (comptes rendus de `docs/livraison/gitops/`) :
  1. **E23** (Flux sur `flux01`) : <ex. 4 contrôleurs, ≈ 260 Mio ; aucune interface ; amorçage par `flux bootstrap gitlab` en 6 min ; diagnostic par `flux get`/`flux events`>.
  2. **E27** (HA d'Argo CD) : <ex. ≈ 1 Gio de mémoire après HA ; délai de synchronisation médian de 1 min 54 s sans webhook, 4 s avec>.
  3. **E28** (reconstruction) : <ex. RTO 41 min ; aucun pod applicatif recréé ; `server.secretkey` et mots de passe locaux absents de Git : export chiffré nécessaire>.
  4. **E25** : <ex. 9 flux sortants à décrire pour Argo CD ; un oubli (crochet `redis-secret-init`) aurait cassé la montée de version suivante>.
  5. **E35-E42** (pannes) : <ex. 3 des 8 pannes diagnostiquées en moins de 10 min grâce à l'interface (diff, arbre, événements)>.

## Options et évaluation

Critères : (a) où sont les droits d'écriture ; (b) multi-locataire (projets, RBAC, interface pour les équipes) ; (c) multi-cluster ; (d) visibilité de l'état et de la dérive ; (e) coût d'exploitation mesuré ; (f) écosystème (déploiement progressif, notifications) ; (g) dépendances et pérennité.

| Option | (a) | (b) | (c) | (d) | (e) | (f) | (g) |
|---|---|---|---|---|---|---|---|
| **Pousser depuis la CI** (M19) | la CI (jetons de CI = production) | RBAC GitLab seulement | un agent par cluster | aucune (on ne voit que le dernier job) | faible | aucun | GitLab Premium pour protéger les environnements |
| **Flux 2.9** | contrôleurs dans le cluster | comptes de service et impersonation par Kustomization ; pas d'interface native | un Flux par cluster (ou pilotage distant par kubeconfig) | `flux get`, événements, métriques ; pas d'UI | faible (mesure E23) | Flagger (progressif), notification-controller | CNCF diplômé ; ControlPlane, Flux Operator |
| **Argo CD 3.5** | contrôleur dans le cluster | AppProjects, RBAC, interface, rôles de projet, SSO (M24) | un Argo CD central, Secrets de cluster, générateur `clusters` (E26) | interface, diff, arbre, santé, historique | moyen (mesure E27, E25, E28) | Argo Rollouts (canary par Gateway API, analyses), notifications intégrées | CNCF diplômé ; Akuity, Intuit, Red Hat |

Kargo (1.12, Akuity) est cité pour la **promotion** : étapes, vérifications et « freight » entre environnements, au-dessus d'Argo CD. Non retenu maintenant (un outil de plus, CRD et contrôleurs, pour un besoin que la MR de promotion couvre) ; à réévaluer au-delà de trois applications promues en continu.

## Décision

1. **Argo CD** est l'outil GitOps de MédiSphère, installé par Helmfile ; Flux n'est pas retenu (pas d'interface pour les équipes, multi-locataire par impersonation plus difficile à expliquer aux équipes, pas d'équivalent intégré d'Argo Rollouts à notre périmètre).
2. **Promotion** : la CI ouvre une MR qui recopie le **digest** de l'image d'un overlay à l'autre (`outils/promouvoir.sh`, `promotion.md`) ; `dev` et `recette` se synchronisent automatiquement (`prune`, `selfHeal`), **`prod` à la main**, hors fenêtre `deny` (`politique-changements.md`), par un compte de `role:plateforme-admin`. Pas de branche par environnement (corrections à reporter par *cherry-pick*, écart entre environnements invisible dans un `diff` de dossiers) ; pas d'étiquettes Git mobiles. *Source Hydrator* (bêta en 3.5) suivi pour remplacer le rendu commité (ADR-0170).
3. **Frontière** : la couche de base (Cilium, CoreDNS, cert-manager, ExternalDNS, ceph-csi, CNPG, Velero, metrics-server, runners et agent de CI, **Argo CD lui-même**) reste sous **Helmfile** : ce qui fait tourner Argo CD ne peut pas dépendre d'Argo CD (une synchronisation ratée de Cilium couperait Argo CD de son propre cluster). Tout le reste — applications, Argo Rollouts, observabilité (M21-M23), services des blocs F et G — passe sous **Argo CD**, projet `plateforme`, charts recopiés par `plateforme/charts-miroir`.
4. **Secrets** : jamais dans Git ; créés par `plateforme/k8s/outils/secrets-k8s.sh` depuis Ansible Vault `critique`, référencés par nom, **jusqu'au M25** (External Secrets et OpenBao). Argo CD ne les voit pas (pas d'annotation de suivi) et ne les supprime pas.
5. **Sécurité** : RBAC au moindre privilège testé en CI (E24), espace `argocd` en refus par défaut (E25), CI sans aucun droit d'écriture sur les espaces applicatifs (E30), export chiffré quotidien (E28).

## Conséquences

- Positives : la dérive se voit et se corrige seule en dev et recette ; plus aucun jeton de CI ne vaut accès à la production ; la promotion est un diff lisible ; l'agence LYO1 se gère d'ici ; les équipes voient leur état sans `kubectl`.
- Négatives : un composant critique de plus (≈ 1 Gio en HA, sa propre sauvegarde, ses flux) ; deux mécanismes à connaître (Helmfile pour la base, Argo CD pour le reste) ; la reconstruction dépend d'un export chiffré pour les comptes locaux jusqu'au SSO (M24) ; les Secrets hors Git restent une étape manuelle à chaque reconstruction jusqu'au M25.
- À faire : SSO Keycloak (M24, rôles de projet déjà prêts) ; External Secrets (M25) ; TLS de bout en bout Gateway → serveur (M26) ; analyses Prometheus des canary (M21).

## Révision

Cette ADR est revue : à la sortie d'Argo CD 3.6 (GA prévue le 03/11/2026) et à chaque mineure ; au-delà de **3 clusters** gérés ou de **5 équipes** (instance unique ou une par domaine ? Kargo ?) ; si le délai de reconstruction (RTO mesuré en E28) dépasse 1 h ; si l'éditeur ou la gouvernance du projet change.
