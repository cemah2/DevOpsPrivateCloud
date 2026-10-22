# plateforme/gitops — ce qu'Argo CD applique au cluster `k8s-par1`

Ce dépôt est la **source de vérité** de tout ce qu'Argo CD gère : les Applications, les
ApplicationSets et les AppProjects. Les manifestes des applications vivent dans les dépôts des
équipes (`mediagenda/deploiement`, `medidoc/deploiement`, `formation/gitops-labo`) ; ce dépôt dit
**quoi** déployer, **d'où**, **où**, et **sous quelles règles**.

La couche de base du cluster (Cilium, cert-manager, ExternalDNS, ceph-csi, CNPG, Velero,
metrics-server, runners, agent GitLab, et Argo CD lui-même) reste sous Helmfile dans
`plateforme/k8s` : Argo CD ne gère jamais ce qui le fait tourner.

## Arborescence

| Dossier | Contenu | Géré par |
|---|---|---|
| `racine/` | Applications de premier niveau : `racine` (elle-même), `applications`, `projets` (M20-E07), `plateforme` (M20-E15) | `racine` |
| `projets/` | AppProjects `plateforme`, `mediagenda`, `medidoc`, `labo`, et `default` verrouillé (M20-E07) | `projets` |
| `plateforme/` | une Application par service de plateforme (Argo Rollouts, puis supervision, journaux, traces) | `plateforme` |
| `applications/` | Applications et ApplicationSets des équipes, un fichier chacun | `applications` |

Chaque dossier est lu **sans récursion**, fichiers `*.yaml` seulement : un sous-dossier (valeurs
d'un chart, essais) n'est jamais appliqué par accident.

## Règles

1. **Tout passe par une MR** sur `main` (protégée : poussée directe interdite, fusion par les
   Maintainers Karim Benali et <MOI>). Argo CD applique `main` ; rien d'autre.
2. **Ce dépôt donne des droits d'administrateur d'Argo CD** : une Application de `racine/` peut créer
   des Applications dans n'importe quel projet. Relire le champ `project` de chaque fichier.
3. **Jamais de Secret ici.** Les identifiants des dépôts (modèles `repo-creds`, un par groupe
   GitLab) sont créés par `plateforme/k8s/outils/secrets-k8s.sh appliquer argocd` depuis le Vault.
4. **Pas de finaliseur de suppression en cascade** sur `racine` ni sur les groupes : retirer ou
   casser un fichier de `racine/` ne doit jamais supprimer les charges.
5. **Ne jamais retirer `racine/racine.yaml`** : la racine se supprimerait elle-même.

## Amorçage (une seule fois, ou après une reconstruction d'Argo CD)

```
admin@adm01:~/src/gitops$ kubectl --context k8s-par1 apply --server-side --field-manager=amorcage -f racine/racine.yaml
```

La racine se synchronise ensuite seule et crée le reste.

## Ajouter une application

Un fichier dans `applications/` (projet de l'équipe, source = dépôt de l'équipe, destination = un
espace autorisé par le projet), MR, relecture, fusion. Argo CD la crée dans les trois minutes
(ou tout de suite après un rafraîchissement de `applications`).
