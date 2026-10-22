# Clé de signature des images et des charts

> Propriétaire : équipe Plateforme · Décision validée par : Sophie Laurent (RSSI), Claire Morel · Ticket : SEC-2620 (M25-E20)

## 1. État

| | Avant (M13 → M25-E19) | Depuis M25-E20 |
|---|---|---|
| Clé privée | fichier `cosign.key` chiffré par mot de passe : Ansible Vault `critique` (`secrets/cosign-ci.yml`), Secret `ci-jobs-protege/cosign-medisphere` monté par le runner protégé, variables de CI des premiers mois (M13-M19) | clé de transit **`cosign-medisphere`** (ECDSA P-256) d'OpenBao, **générée dans le coffre**, non exportable, sans sauvegarde en clair, non supprimable |
| Qui signe | tout job du runner protégé (fichier monté) | un job qui présente un jeton d'identité GitLab accepté par le rôle **`ci-signature`** : référence protégée, groupes `mediagenda`, `medidoc`, `medinotif`, `plateforme`, runner `k8s-par1-protege` ; jeton de 10 min, politique `cosign-signature` (lecture de la clé publique, signature `sha2-256`, rien d'autre) |
| Clé publique de vérification | `docs/registre/cosign.pub` (M13-E14) | `docs/registre/cosign.pub` **remplacée** par `cosign public-key --key hashivault://cosign-medisphere` ; l'ancienne est gardée sous `docs/registre/cosign-m13.pub` pour relire l'historique |
| Trace | aucune (un fichier lu ne laisse rien) | chaque signature est une requête `transit/sign/cosign-medisphere/sha2-256` du journal d'audit (M25-E21), avec le projet, la référence et le pipeline (`auth.metadata`) |

## 2. Décision : une NOUVELLE clé, pas l'import de l'ancienne

OpenBao sait importer une clé (`bao transit import`) : on garderait la même clé publique et rien ne changerait pour les vérificateurs. Refusé : l'ancienne clé a vécu des années hors du coffre (fichiers, variables de CI, Secret Kubernetes, sauvegardes), on ne peut pas prouver qu'aucune copie n'existe. « La clé ne sort jamais du coffre » n'est vrai que pour une clé **née** dans le coffre.

Conséquences, traitées dans l'ordre :
1. La nouvelle clé publique est publiée (`docs/registre/cosign.pub`) et embarquée dans une nouvelle version de l'image `outils-supply-chain` ; la porte de déploiement (`deploiement`, entrée `cosign_pub_sha256`) reçoit sa nouvelle empreinte.
2. **Re-signature** des images et charts encore utilisés (versions déployées en `recette` et `prod`, charts recopiés) par la nouvelle clé : les charts par le prochain pipeline de `plateforme/charts-miroir` (il re-signe ce que la clé actuelle ne vérifie pas), les images par un geste exceptionnel tracé (ticket CHG-2620, identité `plateforme-admins`, audit).
3. Après vérification que tout ce qui est déployé vérifie avec la nouvelle clé : suppression de `secrets/cosign-ci.yml`, du Secret `ci-jobs-protege/cosign-medisphere` et du montage du runner ; destruction des copies de l'ancienne clé privée (procès-verbal).
4. **Kyverno (M26)** ne connaîtra que la **nouvelle** clé publique. Une image signée seulement par l'ancienne clé est refusée : c'est voulu.

## 3. Rotation future de `cosign-medisphere`

Une rotation transit crée une nouvelle **version** : Cosign signe avec la dernière et `cosign public-key` rend la dernière clé publique. Les signatures existantes restent vérifiables **avec l'ancienne clé publique seulement**. Une rotation est donc un changement de clé de signature, pas une opération de fond : pas de `auto_rotate_period`.

Procédure (tous les deux ans, ou immédiatement en cas de doute sur le coffre) :
1. Vérificateurs d'abord : Kyverno (M26) et la porte de déploiement acceptent **les deux** clés publiques (ancienne et nouvelle) ; image outillée publiée avec la nouvelle.
2. `bao write -f transit/keys/cosign-medisphere/rotate` (`plateforme-admin`), publication de la nouvelle clé publique.
3. Re-signature de ce qui est déployé (§ 2, point 2).
4. Retrait de l'ancienne clé publique des vérificateurs. (Côté OpenBao, `min_decryption_version` borne aussi la version acceptée par `transit/verify` — « ciphertext or signature version is disallowed by policy (too old) » — mais nos vérificateurs ne l'appellent pas : ils vérifient hors ligne avec la clé publique. C'est donc la clé publique qu'on retire.)

## 4. Repli si `hashivault://` cesse de fonctionner avec OpenBao

Cosign utilise l'API transit de Vault, qu'OpenBao sert à l'identique (vérifié avec Cosign 3.1.4 et OpenBao 2.6.4 et 2.7.1). Si une version future cassait la compatibilité : clé Cosign classique (fichier) rangée dans `kv/plateforme/cosign/medisphere`, lue par le seul rôle `ci-signature` et écrite sur un `tmpfs` du job. Moins bon (la clé sort du coffre à chaque signature), mais tracé et révocable.
