# ADR-0251 — Chiffrement des Secrets dans etcd : `secretbox` conservé, KMS v2 en attente

| | |
|---|---|
| Statut | Acceptée |
| Date | <DATE> |
| Décideurs | Sophie Laurent, Karim Benali, Claire Morel ; rédaction : <MOI> |
| Ticket | PLAT-2631 (M25-E31) |
| Remplace / complète | **revient sur** la cible écrite au M14-E28 (`docs/kubernetes/securite/chiffrement-secrets.md` : « KMS v2 avec Vault au module 25 ») et sur la KEK de la classe `ceph-rbd-chiffre` (M16-E26, ADR-0160 : « bascule vers un KMS externe au M25 ») |

## Contexte

- Depuis le M14-E28, les Secrets sont chiffrés dans etcd par le fournisseur local **`secretbox`** ; la clé est dans `EncryptionConfiguration` sur le disque des trois nœuds de contrôle. Un disque ou une sauvegarde de nœud de contrôle volés suffisent à tout lire. Le M14 avait fixé la cible : **KMS v2** avec le coffre (la clé maîtresse reste hors des nœuds).
- Au M25, la plupart des Secrets applicatifs **viennent** du coffre (ESO) : leur source de vérité est protégée ; leur copie dans etcd reste chiffrée par `secretbox`.
- Ce qui existe (relevé du `<DATE>`, annexe des versions du bloc F) : **aucun plugin KMS v2 maintenu pour OpenBao** ; celui de HashiCorp (`vault-kube-kms`) exige **Vault Enterprise** et reste **bêta** ; le projet Trousseau (Ondat) est **abandonné**. Écrire notre propre plugin (gRPC, socket Unix, sur chaque nœud de contrôle, devant le moteur `transit`) est possible mais en ferait un composant critique du serveur d'API sans communauté.
- Même constat pour la KEK de `ceph-rbd-chiffre` : ceph-csi 3.18 connaît des fournisseurs KMS `vault`, `vaulttokens`, `vaulttenantsa` qui parlent l'API Vault ; leur fonctionnement avec OpenBao n'est **pas documenté** par le projet (non vérifié dans le lab).

## Options

| Option | Protège contre le vol d'un disque de nœud de contrôle | Disponibilité du serveur d'API | Maintenance | Retenu |
|---|---|---|---|---|
| `secretbox` (actuel) | non | aucune dépendance | rotation de clé manuelle (M14-E28) | **oui, avec compensations** |
| `aesgcm` / `aescbc` | non | idem | `aescbc` déconseillé par Kubernetes ; `aesgcm` impose une rotation fréquente | non |
| KMS v2 + `vault-kube-kms` | oui | dépend du coffre | Vault Enterprise, bêta | non (licence et maturité) |
| KMS v2 + plugin maison vers `transit` d'OpenBao | oui | dépend du plugin **et** du coffre au démarrage du serveur d'API | code à maintenir, critique | non (risque supérieur au gain) |
| Pas de chiffrement dans etcd, tout par ESO | non | — | — | non (régression) |

## Décision

1. **`secretbox` est conservé** ; la cible KMS v2 du M14 n'est **pas atteinte** et n'est plus datée.
2. Compensations : accès SSH aux nœuds de contrôle réservé à `plateforme-admins` (HBAC, M24) ; disques des nœuds de contrôle et sauvegardes etcd chiffrés (instantanés etcd `age`, M14-E24) ; rotation **annuelle** de la clé `secretbox` tracée (politique de rotation, M25-E33) ; contrôle périodique de l'absence de Secrets en clair (`outils/secrets-en-clair.sh`, M14) ; les Secrets les plus sensibles ne transitent plus par Git et ont une durée courte (identifiants dynamiques, certificats de 72 h).
3. KEK de `ceph-rbd-chiffre` : reste dans un Secret Kubernetes (M16) ; essai du fournisseur `vaulttenantsa` de ceph-csi contre OpenBao inscrit au plan de travail (jamais en production sans essai).

## Conséquences

- ⚠️ Un attaquant qui obtient le disque d'un nœud de contrôle **et** sa configuration lit les Secrets du cluster. Acceptation : Sophie Laurent, inscrite au registre des risques (risque résiduel « moyen »), compensations ci-dessus.
- ✅ Le serveur d'API ne dépend pas du coffre pour démarrer (un coffre fermé n'arrête pas le cluster).
- ⚠️ La promesse du M14 et de l'ADR-0160 est retirée : les deux documents renvoient désormais à cet ADR.

## Révision

Rouvrir dès que l'une de ces conditions est observée : un plugin KMS v2 pour OpenBao (ou générique, compatible API transit) est publié et maintenu (au moins deux versions correctives en six mois) ; `vault-kube-kms` sort de bêta **et** une licence Vault Enterprise est décidée (ADR-0250) ; un audit (HDS, ISO 27001) refuse explicitement `secretbox` ; un HSM est disponible.
