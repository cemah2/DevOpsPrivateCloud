# Modèles du portail (*scaffolder*)

> Plateforme développeurs — M28-E08 (DEV-2908). Responsable : équipe Plateforme. Projet : `plateforme/portail-modeles`.

## Modèle `nouveau-service`

### Ce que l'équipe saisit

| Champ | Contrainte |
|---|---|
| Équipe | un `Group` du catalogue (`spec.type: equipe`) |
| Locataire | ceux de l'équipe : `medidoc` → `medidoc` ; `mediagenda` → `mediagenda` ou `medinotif` |
| Nom | `<locataire>-<nom>`, minuscules, chiffres, tirets, 4 à 40 caractères (motif vérifié par le formulaire **et** par le backend) |
| Langage | `python` ou `go` |
| Description | une phrase |

### Ce que le modèle fait

| Étape | Action (1.56) | Résultat |
|---|---|---|
| 1-2 | `fetch:template` | squelette du code (`squelettes/<langage>`) et du déploiement (`squelettes/deploiement`) |
| 3-4 | `fetch:template` | propositions pour la plateforme (`propositions/k8s`, `propositions/gitops`) |
| 5 | `publish:gitlab` | projet `<locataire>/<nom>` : code, Dockerfile (utilisateur 10000), CI (`construction-image`, `securite`, `promotion` vers `dev`), `catalog-info.yaml` |
| 6 | `publish:gitlab` | projet `<locataire>/<nom>-deploiement` : `base/` (Deployment `restricted`, sondes, `requests`, Service, CNP de refus par défaut, étiquette `backstage.io/kubernetes-id`) et `overlays/dev` |
| 7 | `publish:gitlab:merge-request` | **MR** dans `plateforme/k8s` : `espaces/<nom>-dev/` (Namespace rattaché au locataire, Pod Security, quota, LimitRange), assignée à Karim, `commitAction: create` (n'écrase rien) |
| 8 | `publish:gitlab:merge-request` | **MR** dans `plateforme/gitops` : `applications/<nom>.yaml` (Application `<nom>-dev`, projet du locataire) |
| 9 | `catalog:register` | le Component apparaît dans le catalogue sans attendre la découverte |

Un fichier par service dans des dossiers existants : pas de conflit entre deux créations simultanées.

### Ordre de fusion (Plateforme)

1. MR `plateforme/k8s` → `task espaces`, puis ajouter l'espace à `outils/rattacher-locataires.sh` et le lancer.
2. MR `plateforme/gitops` → l'Application `<nom>-dev` se synchronise ; elle reste `Degraded` (image absente) jusqu'à la première promotion.
3. Premier pipeline de `main` du code → MR de promotion dans `<nom>-deploiement` → fusion par l'équipe → le service tourne en `dev`.

Essai `medidoc-vignettes` : projets `medidoc/medidoc-vignettes` et `medidoc/medidoc-vignettes-deploiement`, MR `feat(espaces): medidoc-vignettes-dev …` et `feat(applications): medidoc-vignettes-dev …` ouvertes par `svc-portail`, service prêt en `dev` ≈ 20 min après le formulaire (dont la relecture).

## Droits de `svc-portail`

| Où | Rôle | Pourquoi ce rôle et pas plus |
|---|---|---|
| groupes `mediagenda`, `medinotif`, `medidoc` | Developer | créer un projet : réglage de groupe « rôles autorisés à créer des projets » = Developer ; premier envoi sur `main` : protection par défaut « protégée contre les poussées, premier envoi autorisé aux développeurs » (`developer_can_initial_push`) |
| `plateforme/k8s`, `plateforme/gitops` | Developer | pousser une branche `portail/<nom>` et ouvrir une MR ; `main` protégée, fusion réservée aux mainteneurs |
| groupe `plateforme` | Reporter | découverte du catalogue (E07) |
| instance | aucun | ni administrateur, ni propriétaire d'un groupe, utilisateur **externe** (ne voit que ses appartenances) |

Les actions s'exécutent avec le jeton de l'intégration (`integrations.gitlab[].token`) : quiconque peut lancer un modèle agit **avec les droits de `svc-portail`**, dans les limites du modèle. D'où : pas de modèle qui écrit sur `main` d'un dépôt de la plateforme, et la politique de permissions du portail (palier 3, M28-E16) réservera certains modèles à certains groupes.

## Ce que le modèle ne fait pas (encore)

- secrets applicatifs (chemin OpenBao, rôle ESO, SecretStore) : MR manuelle sur `plateforme/secrets` et `plateforme/k8s` ;
- base de données, file, compartiment : demande à la Plateforme ;
- environnements `recette` et `prod`, exposition par la Gateway (HTTPRoute, DNS) : MR sur le dépôt de déploiement, relue ;
- autoscaling (HPA ou ScaledObject) et VPA : à ajouter dans le déploiement, d'après `autoscaling.md` ;
- tableau de bord et alertes : modèle `plateforme/observabilite` à écrire.
