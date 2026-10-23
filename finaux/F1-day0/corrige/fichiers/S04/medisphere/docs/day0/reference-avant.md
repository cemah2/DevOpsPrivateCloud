# Référence des données avant la fenêtre CHG-3107 (F1-S04)

> Modèle (corrigé F1-S04). Produit par `plateforme/k8s/outils/photographie-donnees.sh` la veille de la
> fenêtre, puis complété à la main pour ce que le script ne mesure pas. Les valeurs ci-dessous sont des
> EXEMPLES de forme : remplace-les par ta photographie. Comptes et noms seulement, aucune donnée de patient.

| Mesure | Valeur |
|---|---|
| Rendez-vous en production (mediagenda-prod) | 1842 |
| Rendez-vous en recette (mediagenda-recette) | 12577 |
| Dernière archive WAL de mediagenda-db (prod) | 00000004000000000000002A à 2026-11-03T21:58:12Z |
| Messages en file, vhost medinotif-prod | notifications 0;notifications.rebut 3 |
| Messages en file, vhost medinotif-recette | notifications 0;notifications.rebut 0 |
| ExternalSecret (total / Ready) | 41 / 41 |
| Certificats cert-manager (total / Ready) | 23 / 23 |
| Certificat expirant le plus tôt | messagerie/rabbitmq-tls (2026-11-29T08:00:00Z) |
| Applications Argo CD (total / Synced+Healthy) | 47 / 47 |
| PVC (nombre, capacité totale en Gi) | 38, 412 Gi |
| Versions des nœuds (kubelet) | k8s-cp01=v1.36.5 … k8s-w03=v1.36.5 |
| Releases Helm de la couche de base | argocd=argo-cd-10.10.5 cert-manager=cert-manager-v1.21.1 … |

## Complété à la main

| Mesure | Valeur | Comment |
|---|---|---|
| Messages de `notifications.rebut` (prod) | 3, examinés et **acceptés comme perdus** (accord de Julien, noté dans CHG-3104 le <date>) | les messages en file ne sont pas sauvegardés |
| Dernière sauvegarde CNPG `completed` (prod, recette, portail) | `<nom>` à `<heure>` | `kubectl get backups.postgresql.cnpg.io -A` |
| Sauvegarde Velero complète | `f1-avant-chg3107` `Completed` à `<heure>` | `velero backup describe` |
| Instantané etcd téléchargé et déchiffré | `horaire/<horodatage>.db.age` → `etcdutl snapshot status` OK | RB-141 §3 |
| Lisibilité PBS | VM 5311 restaurée depuis `k8s-cp01` (`--unique`, carte coupée), démarrée jusqu'à l'invite, détruite | durée de restauration : <N> min |

## Gel (CHG-3107, F1-S07)

> Ajouté pendant la fenêtre, après `outils/day0/10-gel.sh` (fichiers `~/day0/compteurs-gel.txt` et
> `~/day0/files-gel.tsv`). C'est **cette** section, et non la photographie de la veille, que S11 compare
> aux données remises.

| Mesure | Au gel | Veille (ci-dessus) | Écart expliqué |
|---|---|---|---|
| Heure du gel | `<AAAA-MM-JJTHH:MM>` | — | — |
| Rendez-vous (prod) | `<N>` | 1842 | `<N>` rendez-vous pris entre la photographie et le gel |
| Rendez-vous (recette) | `<N>` | 12577 | tests nocturnes de la recette, par exemple |
| Messages en file (medinotif-recette, medinotif-prod) | 0, 0 | 0, 0 | files vidées par MédiNotif, jamais purgées |
| ExternalSecrets | `<N>` | 41 | |
| Certificats (cert-manager) | `<N>` | 23 | |
| Sauvegardes de base après le gel | `mediagenda-db-gel-<horodatage>` (recette, prod), `portail-db-gel-<horodatage>` : `completed` | — | dernier point de reprise, postérieur à la dernière écriture |
| Topologie des files | `files-gel.tsv` (vhost, file, type, arguments) | — | comparée en S11 |
