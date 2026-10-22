# Livrer des secrets à Kubernetes : comparaison et décision

> Propriétaire : équipe Plateforme · Relu par : Karim Benali, Sophie Laurent · Tickets : PLAT-2618 (M25-E18), PLAT-2619 (M25-E19)
> Essais faits dans `wb-essais` sur `k8s-par1` (Kubernetes 1.36, OpenBao 2.6) ; tout a été désinstallé après.

## 1. Les quatre approches essayées

| | External Secrets Operator 2.13 (retenu, M25-E12) | SOPS 3.13 + age / transit | Sealed Secrets 0.40 | Secrets Store CSI 1.6 + fournisseur OpenBao 2.0 |
|---|---|---|---|---|
| Ce qui est dans Git | une **référence** (`ExternalSecret` : quel chemin, quelle clé, quel rafraîchissement) | le secret **chiffré** (valeurs `ENC[…]`, métadonnées lisibles) | le secret **chiffré** pour UN cluster (`SealedSecret`) | une **référence** (`SecretProviderClass`) |
| Où vit la valeur | OpenBao | Git (chiffrée) | Git (chiffrée) + etcd | OpenBao |
| Qui déchiffre | OpenBao (le contrôleur lit avec son identité Kubernetes) | le poste ou le job qui a un droit sur `sops-plateforme` ou la clé age | le contrôleur, avec **sa** clé privée (Secret de son espace) | OpenBao (le fournisseur lit avec l'identité **du pod**) |
| Arrivée dans le pod | Secret Kubernetes (variables, fichiers) | Secret appliqué par un outil qui sait déchiffrer (non natif dans Argo CD : greffon KSOPS ou helm-secrets) | Secret Kubernetes | fichier dans un volume CSI ; Secret recopié en option (`secretObjects`) |
| Secret dans etcd | oui | oui | oui (le Secret produit) | **non**, sauf `secretObjects` |
| Rotation | change dans OpenBao → rafraîchi (`refreshInterval`) ; redémarrage contrôlé (E15) | nouvelle valeur = un commit ; changer la clé de données = `sops rotate` | nouveau scellement = un commit ; renouvellement de la clé du contrôleur tous les 30 j (l'ancien reste valable) | relecture périodique (`rotationPollInterval`, fonction **alpha**) ; l'application doit relire le fichier |
| Secrets dynamiques (PostgreSQL, PKI) | oui (générateur `VaultDynamicSecret`, E14) | non | non | oui (chaque montage = un bail ; renouvellement par l'agent) |
| Si OpenBao est injoignable | les Secrets déjà créés restent, les pods démarrent ; pas de mise à jour | sans effet sur le cluster ; plus de déchiffrement transit sur les postes (clé age de secours) | sans effet | **le pod ne démarre pas** (bloqué en `ContainerCreating`, volume non monté) |
| Audit « qui a lu » | OpenBao : l'identité du contrôleur (une par espace avec un SecretStore par espace) | Git : qui a modifié ; OpenBao : qui a déchiffré par transit | aucun au-delà de l'API Kubernetes | OpenBao : l'identité **de chaque pod** |
| Retrait d'un accès | politique ou rôle OpenBao | `.sops.yaml` + `updatekeys` + **`rotate`** + rotation des valeurs (l'historique Git reste déchiffrable par l'ancienne clé) | impossible pour l'historique : qui a la clé privée descelle tout ; tourner les valeurs | politique ou rôle OpenBao |
| Plan de reprise | OpenBao (instantanés, E26) | Git + clé age de secours hors ligne | **sauvegarder la clé privée du contrôleur** (sinon tout est perdu à la reconstruction du cluster) ; la sauvegarde devient un secret de premier rang | OpenBao |
| Composants en plus | contrôleur (Argo CD) | aucun dans le cluster ; outil sur les postes | contrôleur + CLI `kubeseal` | DaemonSet **privilégié** (pilote) + DaemonSet fournisseur + agent ; espace en PSA `privileged` |
| Fit GitOps (Argo CD) | natif (objets ordinaires, diff propre) | greffon de gestion de configuration à installer et à protéger (il détient le droit de déchiffrer) | natif | natif (objets ordinaires) |

## 2. Ce que nous avons mesuré (M25-E19)

| Mesure | Résultat (à reporter de tes essais) |
|---|---|
| Délai entre `bao kv put` et la nouvelle valeur dans le fichier CSI (rotation 2 min) | `<MESURE>` (entre 0 et 2 min + délai de l'agent) |
| Variable d'environnement après la même rotation | inchangée jusqu'au redémarrage du conteneur |
| Pod CSI créé pendant que la politique `essai-csi` est retirée | `ContainerCreating`, événement `FailedMount` (`permission denied` remonté par le fournisseur) |
| `SealedSecret` copié dans un autre espace | refusé par le contrôleur (portée `strict` : nom et espace font partie du chiffré) |
| `kubeseal --recovery-unseal` avec la clé privée sauvegardée | toutes les valeurs relues **hors cluster** |
| Mémoire des composants (`container_memory_working_set_bytes` dans Prometheus, M21) | contrôleur Sealed Secrets `<MESURE>` ; pilote CSI + fournisseur + agent, **par nœud** `<MESURE>` |

## 3. Décision

1. **External Secrets Operator** est la voie unique pour les Secrets des applications et de la plateforme dans `k8s-par1` (M25-E12, E13) : la valeur reste dans le coffre, l'accès se retire en un endroit, l'audit nomme l'espace demandeur, les secrets dynamiques sont possibles, et l'indisponibilité du coffre n'empêche pas les pods de démarrer.
2. **Secrets Store CSI** : **non retenu** aujourd'hui. Intéressant pour un secret qui ne doit jamais entrer dans etcd et pour l'audit par pod, mais : pilote privilégié sur chaque nœud, rotation alpha, démarrage des pods dépendant du coffre, et un cas d'usage réel qui manque. Réexamen si une exigence HDS impose « aucun secret dans etcd » (le chiffrement d'etcd reste `secretbox`, ADR-0251).
3. **Sealed Secrets** : **non retenu**. Il déplace le problème vers la clé privée du contrôleur (un secret de plus, à sauvegarder et à protéger plus que tous les autres), sans rotation ni retrait d'accès sur l'historique, et sans audit de lecture.
4. **SOPS** : **non retenu pour le cluster** (greffon de déchiffrement à donner à Argo CD, secret dans Git pour toujours). Autorisé pour les dépôts d'essai et de formation (`formation/sops-labo`) avec la clé `sops-plateforme` et une clé age de secours hors ligne. Les fichiers d'amorçage restent en Ansible Vault (bris de glace, avant que le coffre existe).
5. Hors de ce choix : l'**amorçage** (racine MédiSphère, identité d'ESO) reste créé par `secrets-k8s.sh` (PLAN §4.12).

## 4. Ce qui a été désinstallé

Applications `essai-sealed-secrets`, `essai-csi-driver`, `essai-openbao-csi` (cascade : CRD, contrôleur, DaemonSets) ; espaces `sealed-secrets` et `essai-csi` ; rôle `essai-csi` et politique `essai-csi` d'OpenBao ; secret `kv/plateforme/essais/csi-demo` ; entrées de `plateforme/charts-miroir` et de `outils_k8s` (`kubeseal`) ; objets de `wb-essais`.
