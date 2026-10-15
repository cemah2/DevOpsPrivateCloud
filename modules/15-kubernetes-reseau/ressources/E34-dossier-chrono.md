# Dossier CHRONO — M15-E34 « Publier une nouvelle application en temps limité »

> **Ticket DEV-1634** — ouvert à T0. Ne lis ce dossier qu'au lancement du chrono.

## Le besoin

L'équipe MédiDoc veut tester son service de documents depuis les postes de l'équipe (MGMT, VPN) avec une
vraie adresse, un vrai certificat et un vrai nom, dans son espace `medidoc-dev`. Elle livre son Deployment
([`E34-medidoc/deployment.yaml`](E34-medidoc/deployment.yaml)) ; tout le reste revient à la Plateforme.

## Ce qui existe déjà (préparé la veille, hors chrono)

- L'espace `medidoc-dev` (M14-E33 : quotas, LimitRange, RBAC, PSA `restricted`) et son Secret `harbor-pull`.
- L'image `registry.par1.medisphere.internal/medisphere/medidoc:<VERSION-MEDIDOC>`, signée (M13).
- Sur `s3-01` : le compartiment `medidoc-dev` et son identité, clés dans `~/.config/workbook/s3-medidoc-dev.env`
  (600, variables `AWS_ACCESS_KEY_ID` et `AWS_SECRET_ACCESS_KEY`) et en Vault `lab`.
- La segmentation de M15-E28 (label d'équipe `medidoc` et cloisons de l'espace).

## Exigences (vérifiées par `lab/bin/check 15 34`)

1. **Application** : le Deployment `medidoc` (2 réplicas) est prêt dans `medidoc-dev` ; les objets qu'il
   suppose (Secret `medidoc-s3`, ConfigMap `racine-medisphere`) sont créés **par le code** de la plateforme,
   sans secret dans le dépôt.
2. **Service** : `medidoc`, type `ClusterIP`, port 80 nommé `http`, vers le port `http` des pods.
3. **Route** : `HTTPRoute` `medidoc` dans `medidoc-dev`, attachée à l'écouteur HTTPS de `gw-par1`, nom
   **`medidoc-dev.apps.par1.medisphere.internal`**, acceptée par la Gateway et dont les références sont
   résolues. L'espace porte ce qu'il faut pour y être autorisé.
4. **Nom** : `medidoc-dev.apps.par1.medisphere.internal` résout vers 10.10.41.10 sur `dns01` **et** `dns02`,
   écrit par ExternalDNS (aucun enregistrement à la main).
5. **Certificat** : depuis `adm01`, `https://medidoc-dev.apps.par1.medisphere.internal/readyz` répond 200
   avec un certificat valide pour ce nom, vérifié contre la racine MédiSphère ; `http://…` redirige vers HTTPS.
6. **Politiques** : dans `medidoc-dev`, tout est refusé par défaut en entrée **et** en sortie ; sont seuls
   autorisés : l'entrée depuis la Gateway vers le port 8080 ; la sortie vers le DNS du cluster ; la sortie
   vers `s3-01` en TCP 8333. Aucune sortie vers Internet, aucun accès à MédiAgenda (ni dans un sens ni dans
   l'autre).
7. **Traçabilité** : la matrice des flux du cluster (`docs/kubernetes/reseau/matrice-flux-cluster.md`)
   contient les flux de MédiDoc ; la feuille de temps ci-dessous et le retour d'expérience sont dans
   `docs/kubernetes/reseau/chrono/E34-medidoc.md` de `plateforme/medisphere`.

Un document de test se dépose et se relit par le nom publié :

```
admin@adm01:~$ curl -sf -F patient=PAT-TEST-0001 -F fichier=@/etc/hostname https://medidoc-dev.apps.par1.medisphere.internal/documents
admin@adm01:~$ curl -sf https://medidoc-dev.apps.par1.medisphere.internal/documents?limite=5
```

## Feuille de temps (à recopier dans `docs/kubernetes/reseau/chrono/E34-medidoc.md`)

| Jalon | Heure | Écart | Gestes manuels (commande, raison) |
|---|---|---|---|
| T0 — dossier ouvert | | | |
| T1 — application prête (Secret, ConfigMap, Deployment, Service) | | | |
| T2 — route acceptée, nom publié | | | |
| T3 — HTTPS vérifié, politiques en place, document de test relu | | | |
| T4 — `lab/bin/check 15 34` vert, documentation poussée | | | |

## Retour d'expérience (une demi-page)

Ce qui a pris du temps, ce qui manquait dans l'outillage, ce qui doit devenir un modèle (route, politiques,
création des Secrets depuis Vault), et ce qu'il faudrait pour que l'équipe le fasse seule.
