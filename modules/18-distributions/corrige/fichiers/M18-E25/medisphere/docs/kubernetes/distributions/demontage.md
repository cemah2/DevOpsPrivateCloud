# Démontage du module 18 (M18-E25)

> Ordre écrit **avant** de commencer. Chaque étape : commande, preuve (sortie ou capture), date. Les interventions manuelles sont signalées avec leur raison.

| # | Étape | Pourquoi à ce rang | Commande | Preuve |
|---|---|---|---|---|
| 1 | Recettes et essais : `task recette:detruire`, `kind delete clusters --all`, `k3d cluster delete --all` (sur `m18-dev01`) | ne dépendent de rien | | `k3d cluster list` vide |
| 2 | `capi-essai` (et `capo-essai`) supprimés **par Cluster API** : `kubectl delete cluster …`, attente | les contrôleurs doivent supprimer VMs et adresses tant que le cluster de gestion, le jeton et les templates existent | | `kubectl get machines,proxmoxmachines -A` vide ; `qm list` sans 5180-5189 |
| 3 | Objets restants de `capi/` (gabarits, CRS, MHC), espace `capi-essai` | sans propriétaire, non supprimés en 2 | | |
| 4 | Archive finale de `k3s01` (si l'ADR la garde) | dernière trace de l'état Cluster API | `task gestion:sauvegarder` | objet `gestion/…` |
| 5 | VMs par OpenTofu (`envs/m18` vide) | après 2 : sinon VMs orphelines | `tofu plan` (que des destructions), `tofu apply` | `qm list` sans 2181-2188, 5191-5193 ; état vide |
| 6 | DNS et NetBox | objets décrivant des VMs disparues | | `dig` et API NetBox vides |
| 7 | Templates 9060-9069 (selon l'ADR) | après 2 : la réparation en dépendait | | `qm list` sans 9060-9069 |
| 8 | `wb-capi` : ACL, jeton, utilisateur, rôle `WBCapi`, `pve-capi.env` (selon l'ADR) | après 2 : CAPMOX en avait besoin pour supprimer | | `pveum user list` sans `wb-capi@pve` |
| 9 | Compartiment et identité `etcd-m18` (selon l'ADR) | plus de banc à restaurer | identité d'administration de `s3-01`, rôle `seaweedfs` | `aws s3 ls` sans `etcd-m18` |
| 10 | Flux provisoires (refs `M18-E14`, `M18-E16`) retirés, rôle `pare_feu` rejoué (passive puis active) | plus aucun client | | `nft list ruleset` des deux passerelles, matrice des flux |
| 11 | Fichiers de `~/.config/workbook/m18/` devenus inutiles | après tout le reste (servaient au démontage) | | `ls -la ~/.config/workbook/m18/` |
| 12 | Registre des secrets mis à jour | | | MR |
| 13 | `k8s-par1` redémarré (nœuds de contrôle, puis travailleurs), `lab/bin/check 14 46` | rend le lab aux modules suivants | | sortie du contrôle |
