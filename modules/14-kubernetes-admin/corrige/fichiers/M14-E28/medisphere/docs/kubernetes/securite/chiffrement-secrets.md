# Chiffrement au repos des Secrets de `k8s-par1`

> SEC-1528 (M14-E28). Mise en service : <DATE>. Responsable : équipe Plateforme. Revue : Sophie Laurent.

## Ce qui est en place

- `EncryptionConfiguration` sur les trois nœuds de contrôle (`/etc/kubernetes/chiffrement/configuration.yaml`, root 600), rôle `k8s_chiffrement` ; options `--encryption-provider-config` et `--encryption-provider-config-automatic-reload=true` dans la `ClusterConfiguration` (`plateforme/k8s`).
- Ressources chiffrées : `secrets`. Fournisseur : **`secretbox`** (XSalsa20 + Poly1305), clé `cle-2026-11`. La première clé (`cle-2026-10`, `aescbc`) a servi à l'activation puis a été retirée par rotation.
- Tous les Secrets ont été réécrits : `outils/secrets-en-clair.sh` ne compte plus aucun Secret en clair.

## Pourquoi pas `aescbc`

La liste de contrôle de l'audit (inspirée d'anciennes versions du CIS Benchmark) cite `aescbc`. La documentation Kubernetes le marque aujourd'hui « non recommandé » (CBC exposé aux attaques par oracle de remplissage) et `aesgcm` « non recommandé sauf rotation automatisée » (nonces aléatoires : rotation toutes les 200 000 écritures). Parmi les fournisseurs **locaux**, `secretbox` est le seul qui ne soit pas déconseillé ; la documentation note que ses primitives, relativement récentes, peuvent ne pas être acceptées dans les environnements soumis à une revue poussée. C'est notre cas (HDS) : `secretbox` est une étape, la cible est KMS v2 (module 25), et cette réserve est portée au registre des risques. Les trois partagent la même limite : **la clé est sur le disque du nœud de contrôle**, à côté de ce qu'elle protège.

## Modèle de menace

| Menace | Protégé ? | Pourquoi |
|---|---|---|
| Instantané etcd volé (S3, poste d'un administrateur, support perdu) | **Oui** | l'instantané ne contient que des valeurs chiffrées ; la clé n'y est pas (et l'instantané est en plus chiffré par `age`, E24) |
| Disque d'un nœud de contrôle récupéré (VM copiée, sauvegarde PBS de la VM) | **Non** | le disque contient `/var/lib/etcd` **et** `/etc/kubernetes/chiffrement/` : la clé voyage avec les données |
| Accès direct à etcd avec les certificats d'etcd, depuis un autre poste | Oui (les valeurs lues sont chiffrées) | mais quiconque a ces certificats a souvent aussi un accès root au nœud |
| root sur un nœud de contrôle | **Non** | il lit la clé, ou interroge l'API avec `admin.conf` |
| Compte avec `get secrets` dans un espace (humain, compte de service, pod compromis) | **Non** | l'API déchiffre pour quiconque y est autorisé : c'est le RBAC qui protège, pas ce chiffrement |
| Fuite d'un Secret dans les journaux, une variable d'environnement, une image | **Non** | hors etcd |

**KMS v2** (avec Vault, module 25) déplace la clé maîtresse **hors** des nœuds : le serveur d'API demande à un service externe de chiffrer des clés de données. Un disque de nœud de contrôle volé ne suffit plus ; la sauvegarde PBS d'une VM non plus. En échange : une dépendance de démarrage du serveur d'API envers Vault (qui doit être hautement disponible et ne pas dépendre de `k8s-par1` lui-même).

## Conséquences pour les sauvegardes et la restauration

- Un instantané etcd n'est restaurable qu'avec **la clé qui a chiffré ses Secrets** : la clé en service au moment de l'instantané (et les précédentes si une réécriture n'était pas finie).
- Une clé retirée de la configuration reste dans le Vault `critique` **35 jours** (rétention des instantanés quotidiens, E24), puis est détruite : le registre des secrets porte la date.
- RB-141 §2 cite la clé de chiffrement parmi les préalables d'une restauration.

## Rotation

- Calendrier : une fois par an, et immédiatement si un nœud de contrôle, une sauvegarde de VM ou le Vault `critique` est compromis.
- Procédure (testée le <DATE>) : nouvelle clé ajoutée en deuxième position sur les trois nœuds → vérification → nouvelle clé en premier sur les trois nœuds → vérification (Secret écrit par **chaque** serveur d'API, préfixe lu dans etcd) → réécriture de tous les Secrets (`kubectl get secrets -A -o json | kubectl replace -f -`) → `outils/secrets-en-clair.sh` → retrait de l'ancienne clé.
- Avec le rechargement automatique, aucune étape ne redémarre les serveurs d'API ; attendre le rechargement (environ une minute) sur les trois avant l'étape suivante.
