# Procès-verbal de recette — données Kubernetes MédiSphère v1 (`k8s-stockage-v1`)

| | |
|---|---|
| Ticket | PLAT-1799 |
| Date de la recette | `<AAAA-MM-JJ>` |
| Présents | Claire Morel, Karim Benali, Sophie Laurent, Nadia Roussel, Julien Petit, `<MOI>` |
| Contrôle global | `lab/bin/check 16 46` : `<N> OK, 0 KO` (sortie jointe en annexe) |

## 1. Restaurations réalisées pour la livraison

| # | Quoi | Méthode | Début | Fin | RTO mesuré | RPO obtenu | Données vérifiées | Écart |
|---|---|---|---|---|---|---|---|---|
| 1 | `mediagenda-db` à un instant donné, nouveau cluster `mediagenda-db-pitr` | CloudNativePG, plugin Barman Cloud (`bootstrap.recovery`, `targetTime`) | `<HH:MM:SS>` | `<HH:MM:SS>` | `<min>` | `<s>` (dernière transaction attendue présente) | nombre de rendez-vous, dernier identifiant, somme de contrôle de la table | |
| 2 | Espace `medidoc-dev` complet, dans `wb-restauration` | Velero (`recette-quotidienne`, `--namespace-mappings`) | | | | heure de la sauvegarde | document témoin relu par MédiDoc (empreinte SHA-256) | |

## 2. Démonstrations de la revue

| Démonstration | Consigne | Résultat | Temps | Commentaire |
|---|---|---|---|---|
| Nadia : restauration à l'heure donnée | `<HEURE-DONNÉE>` | | | |
| Julien : `medidoc-dev` supprimé « par erreur » | suppression à `<HH:MM>` | | | |

## 3. Comparaison à la politique de sauvegarde

| Donnée | RPO visé (politique) | RPO mesuré | RTO visé | RTO mesuré | Conforme |
|---|---|---|---|---|---|
| Base `mediagenda-db` | | | | | |
| Espace `medidoc-dev` (objets) | | | | | |
| Documents MédiDoc (RGW) | | | | | |

## 4. Points non redondants et réserves
- Un seul hyperviseur physique, un seul site : `ceph-par1`, `s3-01` et `k8s-par1` partagent `pve01` (traité au final F5).
- `<réserves de la revue, avec responsable et échéance>`
