# Retrait de Jenkins et de SonarQube (M19-E46, ADR-0190)

> Procédure suivie le jour de la livraison `ci-v1`. Chaque étape a sa vérification ; rien n'est
> supprimé avant d'avoir été exporté si on peut en avoir besoin.

## Avant

1. Exporter ce qui sert de preuve à l'ADR : comparatif (`comparatif-jenkins.md`), captures des résultats d'analyse SonarQube de `mediagenda/api` (fichier joint à l'ADR, pas la base).
2. Vérifier qu'aucun pipeline ne dépend encore des deux outils : recherche de `SONAR_`, `sonar-scanner`, `JENKINS_` dans les `.gitlab-ci.yml` et les composants (`gl "search?scope=blobs&search=sonar"` par projet).

## Retrait (dans `plateforme/k8s`, par MR)

1. Retirer les releases `jenkins` et `sonarqube` du Helmfile (`installed: false`, puis suppression des blocs à la MR suivante) ; `helmfile -e par1 -l composant=jenkins apply`, idem `sonarqube`.
2. Supprimer le cluster CNPG `sonarqube-db` (décrit dans `plateforme/k8s`) **après** avoir vérifié qu'aucune sauvegarde n'est à garder (ADR-0190 : non) ; puis les PVC restants de l'espace.
3. Retirer les HTTPRoute ; ExternalDNS retire `jenkins.apps…` et `sonarqube.apps…` (vérifier `dig @10.10.20.10`). Si ExternalDNS est en `upsert-only`, retirer les enregistrements par le même code.
4. Supprimer les espaces `jenkins` et `sonarqube` (fichiers de `espaces/`), leurs Secrets (Vault : `secrets/jenkins.yml`, `secrets/sonarqube.yml` archivés puis retirés du dépôt de secrets).
5. Variables de CI `SONAR_HOST_URL`, `SONAR_TOKEN` (projets et groupes) supprimées ; jeton d'analyse et jeton `sonar-checks` révoqués dans SonarQube **avant** l'arrêt (ou considérés morts avec l'instance) ; fichier `~/.config/workbook/sonar-checks.token` supprimé.
6. `vm.max_map_count` : laissé à 524288 (OpenSearch au M22 en a besoin).

## Vérifier

```
kubectl get ns jenkins sonarqube                 # NotFound
helm list -A | grep -E 'jenkins|sonarqube'        # rien
dig +short @10.10.20.10 sonarqube.apps.par1.medisphere.internal   # rien
lab/bin/check 19 46
```
