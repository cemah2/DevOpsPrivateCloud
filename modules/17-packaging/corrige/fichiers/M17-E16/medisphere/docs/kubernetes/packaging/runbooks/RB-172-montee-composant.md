# RB-172 — Monter un composant de plateforme par Helmfile

*Créé en M17-E16 (CHG-1816). Périmètre : releases de `plateforme/k8s` (`releases/*.yaml.gotmpl`), cluster `k8s-par1`.*

## Avant (J-2)

1. **Inventaire** : version installée (`helm list -A`) et dernière version de la même mineure (`helm search repo <dépôt>/<chart> --versions`, ou `helm show chart oci://… --version …`). Une mineure ou une majeure passe d'abord par l'ADR-0141 (politique de versions, M14).
2. **Notes de version** entre les deux versions : valeurs renommées ou supprimées, CRD, changements de comportement, version de Kubernetes exigée. Comparer `helm show values` des deux versions.
3. **Retour arrière** propre au composant, écrit dans la MR :
   - sans état (metrics-server) : retour de l'épinglage par MR (en urgence : `helm rollback`, **suivi** du revert dans le dépôt) ;
   - avec CRD et objets (cert-manager, CNPG, Velero, ceph-csi) : sauvegarde des objets (`kubectl get … -o yaml`, Velero) ; le projet accepte-t-il un retour arrière ? Sinon, correction vers l'avant.
4. **Fenêtre** annoncée à l'astreinte (ticket CHG-), avec ce qui peut être perturbé (webhooks, émission de certificats, attachement de volumes).

## Pendant

1. MR : épinglage, tableau d'inventaire, `helmfile -e par1 -l composant=<nom> diff --suppress-secrets --context 3` collé, notes résumées, retour arrière. Revue par un pair.
2. Après fusion, depuis `adm01` (clone à jour de `main`) :
   ```
   helmfile -e par1 -l composant=<nom> diff
   helmfile -e par1 -l composant=<nom> apply
   ```
   La release cible porte `rollbackOnFailure: true` (Helm 4 `--rollback-on-failure`, attente `watcher`). **Ne jamais interrompre** un `apply` en cours : la release resterait en `pending-*` (RB-170).
3. Vérifications fonctionnelles du composant (pas seulement « pods prêts ») : pour cert-manager, émission d'un `Certificate` d'essai dans `wb-essais` puis suppression ; pour ceph-csi, création d'un PVC d'essai ; pour Velero, une sauvegarde d'essai.
4. `helmfile -e par1 diff --detailed-exitcode` : **0** sur toute la plateforme.

## Si ça se passe mal

| Situation | Action |
|---|---|
| `apply` échoue, retour automatique fait | lire `helm history <release> -n <espace>` (révision `failed` puis retour), journaux du composant ; corriger la MR |
| `another operation … in progress` | RB-170 |
| conflit de propriété des champs | RB-171 |
| régression constatée après coup, composant sans état | `helm rollback` immédiat, puis **revert de la MR** dans l'heure |
| régression, composant avec CRD | pas de `helm rollback` ; correctif suivant ou réglage par MR ; en dernier recours, restauration (Velero, sauvegarde des objets) |

## Après

- Clore le ticket avec les durées (fenêtre, application, vérifications).
- Mettre à jour le tableau d'inventaire de `docs/kubernetes/packaging/` et ce runbook si quelque chose a surpris.
