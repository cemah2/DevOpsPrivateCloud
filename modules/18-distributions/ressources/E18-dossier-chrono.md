# M18-E18 — Dossier : cluster de recette éphémère

> À ouvrir à T0. Le chronomètre tourne.

## Le besoin (Julien Petit, DEV-1918)

L'équipe MédiAgenda veut valider la branche `canal-sms` sans attendre la recette partagée. Il lui faut un cluster **à elle**, jetable, avec MédiAgenda 1.1.0 dessus, exactement comme la recette (même chart, même image signée), mais sans rien partager avec `k8s-par1`. Elle le gardera une journée au plus.

## Les exigences

| # | Exigence | Comment on le vérifie |
|---|---|---|
| X1 | Le cluster s'appelle `recette-mediagenda`. Il est créé depuis un fichier **versionné** de `plateforme/distributions` (dossier `k3d/` ou `capi/`), en Kubernetes **v1.36.x**, avec au moins 2 nœuds. | `lab/bin/check 18 18` lit les nœuds et leur version. |
| X2 | Les images du cluster viennent de Harbor (cache ou projets MédiSphère), y compris celle de k3s si tu choisis k3d. Aucun tirage direct de Docker Hub. | Configuration des miroirs lue dans le dépôt ; images des pods. |
| X3 | Le kubeconfig est `~/.config/workbook/m18/recette-mediagenda.kubeconfig` sur `adm01`, en 600. | Lecture du fichier. |
| X4 | L'opérateur CloudNativePG est installé dans `cnpg-system`, à la **même version de chart** que dans le Helmfile de `plateforme/k8s` (release `cnpg`, `releases/30-stockage.yaml.gotmpl`, M17-E10). | Release Helm. |
| X5 | MédiAgenda est installée dans l'espace `mediagenda-recette` par la release Helm `mediagenda`, depuis `oci://registry.par1.medisphere.internal/charts/mediagenda`. La version du chart est celle de la recette partagée (`CHART_VERSION` de `chart.env` sur `main` de `mediagenda/deploiement` : `k8s-par1` est éteint, c'est le dépôt qui fait foi), et sa signature a été vérifiée (`cosign verify` avec `docs/registre/cosign.pub`, sur le digest `CHART_DIGEST`) **avant** l'installation. | Release Helm, feuille de temps (sortie de `cosign verify`). |
| X6 | L'image est `medisphere/mediagenda-api:v1.1.0`, tirée avec le robot `robot$k8s-pull` (Secret `harbor-pull` créé depuis `~/.config/workbook/harbor-k8s-pull.env`, jamais écrit dans un dépôt). | Image des pods, Secret présent. |
| X7 | La base PostgreSQL est un `Cluster` CloudNativePG rendu par le chart, sur la classe de stockage du cluster éphémère. Valkey est le sous-chart. Les valeurs sont dans un fichier versionné (`recette-mediagenda-values.yaml`). | Pods prêts, `Cluster` sain. |
| X8 | L'API répond en HTTP sur `http://<HÔTE>:8080/sante`, depuis `adm01` : `version` `v1.1.0`, `environnement` `recette`. `<HÔTE>` est `m18-dev01` (k3d) ou une adresse de 10.10.40.150-169 (Cluster API), à noter dans la feuille. | `curl` depuis `adm01`. |
| X9 | L'espace `mediagenda-recette` porte les étiquettes `medisphere.internal/proprietaire=mediagenda` et `medisphere.internal/expiration=<AAAA-MM-JJ>` (le lendemain). Le cluster lui-même les porte aussi, là où l'outil le permet (étiquettes k3d, `metadata.labels` du `Cluster`). | Étiquettes de l'espace. |
| X10 | Une commande crée tout (cluster, opérateur, application) et une commande détruit tout (cluster, kubeconfig) : `task recette:creer` et `task recette:detruire` dans `plateforme/distributions`. | Taskfile sur `main` (après le chrono, par MR). |

## Ce qui n'est pas demandé

- Pas de TLS ni de Gateway : le service est exposé en HTTP simple, sur le réseau du lab, pour une journée.
- Pas de politiques réseau du chart : elles sont écrites pour `k8s-par1` (Cilium, Gateway `gw-par1`). Désactive-les dans les valeurs et écris dans le retour d'expérience qui, sur ton cluster éphémère, aurait appliqué des `NetworkPolicy` standard, et ce qu'elles auraient bloqué.
- Pas de sauvegarde de la base : les données sont jetables.

## Feuille de temps

| Jalon | Heure | Remarque |
|---|---|---|
| T0 — ouverture du dossier | | |
| Choix de l'outil (k3d ou Cluster API) et raison | | |
| T1 — cluster prêt (nœuds `Ready`) | | |
| T2 — opérateur CloudNativePG prêt | | |
| T3 — signature du chart vérifiée, release installée | | |
| T4 — `/sante` vert depuis `adm01`, `lab/bin/check 18 18` vert | | |
| T5 — cluster détruit, kubeconfig supprimé | | |
| Gestes manuels (commande, raison) | | |

## Retour d'expérience (une demi-page)

- Où est passé le temps ?
- Qu'est-ce qui ne passerait pas à cinq équipes le même jour (mémoire, adresses, VMID, quotas Harbor) ?
- Que faudrait-il pour que Julien le fasse seul (M20, M28) ?
- Ce que ce résultat change dans l'ADR-0180.
