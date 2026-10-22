# Politique de rotation des secrets

> `docs/securite/secrets/politique-rotation.md` — M25-E33 (SEC-2633). Propriétaire : Sophie Laurent (RSSI). Revue : annuelle et après chaque fuite (RB-250). Exécution : RB-254.

## Principes

1. **Le plus court possible** : ce qui peut être dynamique l'est (identifiants PostgreSQL, certificats, jetons de CI) ; ce qui est statique a une période écrite.
2. **Sans coupure** : chaque méthode chevauche ancien et nouveau secret le temps que les consommateurs suivent (secret « tourné » de Keycloak, jeton GitLab neuf avant révocation de l'ancien, nouvelle version KV reprise par ESO puis Reloader).
3. **Observable** : chaque secret de `kv/plateforme/` porte `proprietaire` et `rotation` (métadonnées personnalisées) ; le pipeline planifié de `plateforme/secrets` contrôle chaque semaine l'âge de la version courante et échoue (courriel à `plateforme@`) en cas de retard ou de métadonnées manquantes.
4. **Prouvée** : toute rotation laisse une trace dans l'audit d'OpenBao (Loki, locataire `audit`) : chemin, identité (rôle JWT `ci-secrets-rotation` ou personne OIDC), heure ; les preuves de §3 sont des requêtes LogQL rangées dans `audit-openbao.md`.
5. **Après une fuite**, la période ne compte plus : rotation immédiate (RB-250, puis RB-254).

## Tableau

| Type | Exemples réels | Période | Méthode | Auto. | Propriétaire | Preuve | Alerte avant échéance |
|---|---|---|---|---|---|---|---|
| Identifiants PostgreSQL des applications | `db-mediagenda/creds/mediagenda-api` | 1 h (max 24 h) | dynamiques (moteur `database`) | oui | Julien Petit | baux (`sys/leases`), audit | — (expiration) |
| Mot de passe racine des connexions de bases | rôle PostgreSQL `openbao` | 30 jours | `rotate-root` par le pipeline | oui | Plateforme | audit `db-mediagenda/rotate-root/*` | contrôle des âges |
| Certificats de service | ClusterIssuer `openbao-services` | 72 h | `pki-services`, cert-manager | oui | Plateforme | `CertificatServicesExpireBientot` | 12 h |
| Jetons de CI | rôles `ci-<projet>` | 10 min | JWT de GitLab (`id_tokens`) | oui | équipes | audit `auth/gitlab/login` | — |
| Secrets des clients Keycloak de la plateforme | `grafana`, `argocd`, `oauth2-proxy`, `harbor`, `netbox`, `openbao` | 90 jours | pipeline (`client-keycloak.sh`), secret tourné puis invalidé | oui | Plateforme | audit `kv/data/plateforme/<client>/oidc` + événements d'administration Keycloak | contrôle des âges (15 j) |
| Jetons d'accès GitLab de service | jeton de dépôt d'Argo CD, jetons de promotion (M19) | 90 jours (durée GitLab : 120 j) | pipeline (`jeton-gitlab.sh`), nouveau puis révocation | oui | Plateforme | audit + journal d'audit de GitLab | contrôle des âges ; GitLab prévient 7 j avant expiration |
| Secrets KV des applications | `kv/mediagenda/recette/valkey` | 180 jours | rotation par l'équipe (KV puis ESO puis Reloader) | non (rappel) | équipe propriétaire | audit | contrôle des âges (étendu à `kv/<application>/`) |
| Clé de transit de chiffrement | `sops-plateforme`, `medictl-donnees` | 1 an (+ `rewrap` des données) | `transit/keys/<clé>/rotate`, puis `rewrap`, puis `min_decryption_version` | non (cérémonie légère, plateforme-admin) | Plateforme | audit `transit/keys/*/rotate` | rappel calendrier |
| Clé de signature Cosign | `cosign-medisphere` | 2 ans | nouvelle version de clé + clé publique dans Kyverno (M26) avant usage | non | Sophie Laurent | audit | rappel |
| Trousseau de la barrière | `bao operator rotate` | 1 an (et après départ d'un dépositaire) | jeton racine régénéré (cérémonie, `procedure-jeton-racine.md`) | non | Sophie Laurent | audit `sys/rotate` | rappel |
| Clés de récupération / parts de `kms01` | `secrets/openbao-init.yml`, `secrets/kms01-init.yml` | à chaque départ d'un dépositaire, sinon 2 ans | `bao operator rekey` (`-target=recovery` pour la grappe), nouvelles parts chiffrées `age` | non | Sophie Laurent | audit + décision écrite des dépositaires | rappel |
| Jeton du seal transit | `vault_openbao_kms_jeton` | 1 an | nouveau jeton sur `kms01`, rôle `openbao`, redémarrages en roulement (RB-251 § 6) | non | Plateforme | audit de `kms01` | rappel |
| `secret_id` AppRole de machines | `wb-checks`, `medictl`, `openbao-instantanes` | 90 jours | nouveau `secret_id` **enveloppé**, puis destruction de l'ancien (`secret-id/destroy`) | non (rappel) | Plateforme | audit `auth/approle/role/*/secret-id` | rappel |
| Identités S3 | `openbao-instantanes`, `etcd-k8s`, `thanos` | 1 an | nouvelle paire, Vault `critique`, rôle `seaweedfs`, puis retrait de l'ancienne | non | Plateforme | journal de SeaweedFS | rappel |
| Clés `age` de sauvegarde | restauration OpenBao, etcd, identité | 2 ans (ou fuite) | nouvelle paire ; l'ancienne privée gardée tant que des sauvegardes chiffrées pour elle existent (30 j à 35 j) | non | Sophie Laurent | registre | rappel |
| Clé `secretbox` d'etcd | `EncryptionConfiguration` | 1 an | procédure M14-E28 (nouvelle clé en tête, réécriture, retrait) | non | Plateforme | registre | rappel |
| Clés WireGuard des passerelles | `gw01`/`gw02`, `hp01` | 1 an | rôle `wireguard`, une passerelle à la fois (ADR-0070) | non | Plateforme | registre | rappel |
| Jetons d'API Proxmox | `wb-automation@pve!lab`, jetons des exportateurs | 1 an | nouveau jeton, Vault `critique`, retrait de l'ancien | non | Plateforme | journal de tâches de Proxmox | rappel |
| Clés cephx | `client.k8s`, `client.rgw…` | 1 an | `ceph auth` (nouvelle clé), Secrets de ceph-csi, retrait | non | Plateforme | journal Ceph | rappel |
| Racine hors ligne, CA intermédiaires | « MédiSphère Root CA », « MédiSphère Services CA » | à l'échéance (cérémonie) | cérémonie (M24, `ceremonie-ca.md`) | non | Sophie Laurent | procès-verbal | 6 mois avant |

« Rappel » : ticket créé automatiquement chaque trimestre par le pipeline planifié pour les types non automatisés dont l'échéance tombe dans les 45 jours (liste tenue dans ce tableau et dans les métadonnées quand le secret est dans le coffre).

## Ce qui reste à automatiser (et pourquoi pas encore)

Valkey de MédiAgenda (le serveur doit accepter deux mots de passe le temps de la bascule : `ACL` à deux utilisateurs, à concevoir avec Julien) ; `secret_id` des machines (livraison enveloppée par Ansible faite, pipeline à écrire) ; clés cephx et identités S3 (pas d'API de chevauchement simple).

## Preuves

Requêtes LogQL (locataire `audit`) : rotation par le pipeline `{service="openbao"} | json qui="auth.metadata.role", chemin="request.path" | qui="ci-secrets-rotation"` ; rotations de clés `… | chemin=~"transit/keys/.+/rotate|sys/rotate"`. Rapport hebdomadaire : artefact `rapport-ages.tsv` du pipeline planifié (90 jours).
