# Admission : politiques natives ou Kyverno ?

> `plateforme/medisphere` — `docs/securite/durcissement/admission-native-ou-kyverno.md` (M26-E17, SEC-2717).
> Décision de travail ; la stratégie d'ensemble est dans l'ADR-0260 (E31).

## Ce qui tourne aujourd'hui

| Politique | Mécanisme | Mode | Fichier |
|---|---|---|---|
| `medisphere-images` (registre, pas de `latest`) | VAP native | Deny | `plateforme/k8s/admission/10-images-medisphere.yaml` (M14-E18) |
| `classes-stockage` | VAP native | Deny | `plateforme/k8s/admission/classes-stockage.yaml` (M16-E20) |
| `medisphere-interdire-hostpath` | VAP native + ConfigMap de paramètres | Deny | `admission/20-interdire-hostpath.yaml` |
| `medisphere-etiquette-equipe-par-defaut` | MAP native (GA 1.36) | — | `admission/30-etiquette-equipe-par-defaut.yaml` |
| `medisphere-etiquettes-espace-protegees` | VAP native | Deny | `admission/40-etiquettes-espace-protegees.yaml` |
| `registres-autorises`, `exiger-*`, `interdire-identifiants-url` | Kyverno `ValidatingPolicy` | Audit → Deny | `plateforme/politiques/kyverno/validation/` |
| `exiger-signature-medisphere` | Kyverno `ImageValidatingPolicy` | Deny (recette, prod) | `plateforme/politiques/kyverno/images/` |
| `seccomp-par-defaut`, `networkpolicy-par-defaut` | Kyverno `MutatingPolicy`, `GeneratingPolicy` | — | `plateforme/politiques/kyverno/{mutation,generation}/` |

## Comparaison

| Critère | VAP / MAP natives | Kyverno 1.19 (politiques CEL) |
|---|---|---|
| Où ça tourne | Dans le kube-apiserver | Webhook (3 réplicas, espace `kyverno`) |
| Panne possible | Aucune dépendance externe ; `failurePolicy` ne joue que sur les erreurs d'évaluation | Contrôleur absent + `failurePolicy: Fail` = plus aucune création dans le périmètre |
| Langage | CEL | CEL (même syntaxe), plus des bibliothèques Kyverno (HTTP, contexte, images) |
| Ce que l'objet ne contient pas | Rien : la politique ne voit que la requête, son espace (`namespaceObject`) et ses paramètres | Données externes : registre (signatures Cosign, attestations), appels HTTP, autres objets du cluster |
| Rapports sur l'existant | Non (seulement l'audit de l'API, au fil des requêtes) | Analyse de fond, `PolicyReport` ; Kyverno rapporte aussi les VAP (`source: ValidatingAdmissionPolicy`) |
| Exceptions | Par conception de la liaison (sélecteurs) ou des paramètres | `PolicyException` datées, partielles, dans un espace réservé |
| Génération d'objets | Non | `GeneratingPolicy` |
| Tests hors cluster | `kubectl apply --dry-run=server` (il faut un API server) | `kyverno test` en CI, sans cluster |
| Disponibilité dans le temps | API stable du projet Kubernetes | `ClusterPolicy` disparaît en 1.20 : seuls les types CEL restent |

## Règle de choix chez MédiSphère

1. **Natif** quand la règle ne dépend que de l'objet, de son espace et de paramètres, qu'elle protège le
   cluster lui-même (étiquettes d'espace, `hostPath`, registres de base) et qu'elle doit continuer de
   fonctionner si Kyverno est arrêté. C'est la ceinture.
2. **Kyverno** dès qu'il faut une donnée externe (signature), un rapport sur l'existant, une génération,
   une exception datée, ou des tests en CI par les équipes. Ce sont les bretelles, et l'outil des équipes.
3. **Une règle, un endroit.** Si une règle native et une politique Kyverno disent la même chose, on garde
   la native et on retire l'autre (ou l'inverse), sinon deux messages différents pour un même refus.
4. **Mutations** : uniquement sur des objets que Git ne décrit pas (pods créés par les contrôleurs). Une
   mutation d'un objet versionné fabrique une différence permanente avec le dépôt.

## OPA Gatekeeper

Gatekeeper 3.23 (Rego, `ConstraintTemplate`/`Constraint`, mutation séparée, synchronisation de données
du cluster pour les règles référentielles) reste une option sérieuse quand une organisation a déjà
des politiques Rego (Conftest en CI, autres systèmes). Chez MédiSphère : un deuxième langage, aucune
vérification de signature intégrée, et la même fonction que Kyverno. Non retenu. Gatekeeper sait aussi
produire des `ValidatingAdmissionPolicy` à partir de modèles écrits en CEL (intégration VAP, à relire
dans la documentation de la 3.23) : la même direction que la nôtre, le natif pour ce qui peut l'être.

## Limites connues

- `namespaceObject` n'est **pas** disponible dans les `matchConditions` d'une MAP ou d'une VAP (seulement
  dans les variables, validations et mutations) : la condition échoue (« no such key: metadata ») et,
  avec `failurePolicy: Ignore`, la politique ne fait **rien**, sans bruit. Le filtrage par espace passe
  par le `namespaceSelector` de la liaison.
- Les VAP ne voient pas les conteneurs éphémères ajoutés par `pods/ephemeralcontainers` (sous-ressource).
- Une liste blanche de `hostPath` par préfixe est aussi large que son préfixe : `falco` a besoin de `/etc`
  en lecture, ce qui inclut `/etc/kubernetes/pki` sur les nœuds de contrôle. Réduire les moteurs de
  conteneurs du chart Falco (seul containerd) réduit aussi ses montages.
