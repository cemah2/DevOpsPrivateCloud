# RB-342 — Monter un composant de plateforme (Argo CD, Helmfile ou miroir des charts)

| | |
|---|---|
| Fiche type | CHG-3405 |
| Où vit le composant | **couche de base sous Helmfile** (`plateforme/k8s`) : Cilium, cert-manager, ExternalDNS, ceph-csi, CNPG et son plugin, Velero, metrics-server, runners, BuildKit, agent GitLab, **Argo CD** ; **tout le reste sous Argo CD** (`plateforme/gitops`, chart recopié par `plateforme/charts-miroir`) |

## 1. Lire avant d'écrire

1. Notes de version de **chaque** version sautée (pas seulement la dernière), guide de montée s'il existe (Argo CD : `operator-manual/upgrading/<a>-<b>`), CHANGELOG du chart.
2. Chercher : API supprimées (`outils/inventaire-api-supprimees.sh`), CRD modifiées, valeurs renommées (`helm show values` ancienne et nouvelle, `diff`), versions de Kubernetes déclarées (matrice), images nouvelles (cache Harbor), droits RBAC nouveaux (AppProject `plateforme`).
3. Écrire dans la fiche ce qui touche MédiSphère et ce qui ne le touche pas, avec la raison.

## 2. Préparer

- **Charts sous Argo CD** : MR `plateforme/charts-miroir` (version, empreinte relevée dans l'index et recalculée), pipeline vert, chart signé dans Harbor `charts/` ; puis MR `plateforme/gitops` (`targetRevision`, valeurs).
- **Couche de base** : MR `plateforme/k8s` (`releases/*.yaml.gotmpl`), `helmfile -e par1 -l composant=<nom> diff` relu.
- `helm template` avec nos valeurs ; kubeconform (`validation`) ; schémas `schemas-crd` régénérés après.
- **CRD avant contrôleurs** : quand les CRD sont dans un chart séparé (ex. mariadb-operator, F4-S12) ou dans un dossier `vendor/` (opérateurs RabbitMQ, M27), leur Application ou leur étape passe **avant** (vague Argo CD inférieure, ou `needs` Helmfile) ; un contrôleur neuf sur des CRD anciennes échoue au démarrage ou ignore des champs.

## 3. Exécuter

Une vague par composant, mesurée (RB-340). Contrôle de passage propre au composant (réplicas prêts, objets `Ready`, fonction essayée : une politique qui refuse, un `ScaledObject` qui monte, une base qui archive).

## 4. Revenir en arrière

| Cas | Méthode | Limite |
|---|---|---|
| Application Argo CD | **revert** de la MR dans Git | les CRD montées ne redescendent pas ; l'objet garde la version stockée |
| « Rollback » de l'interface d'Argo CD | à éviter : refusé avec la synchronisation automatique, et Git ne dit plus la vérité | — |
| Release Helmfile | revert + `helmfile apply` | idem pour les CRD |
| Chart miroir | rien à défaire : l'ancienne version reste publiée et signée dans Harbor | — |

## 5. Clore

Mesure dans la fiche, matrice de compatibilité mise à jour, `schemas-crd` republié, `lab/bin/check F4 5`.
