# Dépendances de la reprise à PAR2

| | |
|---|---|
| Ticket | PLAT-3502 |
| Entrées | `bia.md`, `objectifs.md`, ADR-0350 |
| Relecture | Karim Benali, Sophie Laurent |
| Révision | à chaque changement d'architecture de PAR1 ou de PAR2, et après chaque exercice |

Méthode : on a suivi une requête de patient (`https://mediagenda.medisphere.internal`) et le travail de l'opérateur (se connecter, déchiffrer, déployer) jusqu'à leurs racines, en se demandant à chaque fois « où est-ce que ça vit le jour où PAR1 n'existe plus ? ».

## 1. Inventaire

Colonnes : **source à PAR1** ; **forme à PAR2** ; **mécanisme** (fréquence) ; **retard maximal** visé ; **contrôle** qui prouve que c'est à jour ; **pour s'en servir** (secret ou personne).

| # | Dépendance | Source PAR1 | Forme à PAR2 | Mécanisme | Retard max. | Contrôle | Pour s'en servir |
|---|---|---|---|---|---|---|---|
| D1 | Noms internes (zones `medisphere.internal`, `par1`, `par2`, inverses) | `dns01` (primaire), `dns02` | `dns03` secondaire, **promu primaire** en PRA | AXFR/NOTIFY signés TSIG `axfr-par1` | secondes (NOTIFY) ; expiration de la zone secondaire : 14 j (SOA `expire`) | même numéro de série (`check F5 3`) | clé d'API locale de `dns03` (Ansible Vault `critique`) |
| D2 | Noms globaux | zone `medisphere.internal` (rôle `powerdns_auth`) | CNAME TTL 60 s, réécrits sur `dns03` en PRA | AXFR (D1) | idem D1 | `dig` des trois noms | idem D1 |
| D3 | Signature DNSSEC de `par1.medisphere.internal` | clés sur `dns01` | zone **signée** copiée, sans les clés | AXFR | — | — | ⚠️ les signatures expirent (≈ 2 à 3 semaines) ; pendant un PRA long : retirer l'ancre de confiance des récurseurs de PAR2 ou ne plus résoudre `par1` |
| D4 | Temps | `gw01`/`gw02` (chrony) | `hp01` (chrony) sert PAR2 INFRA | source Internet propre à `hp01` | — | `chronyc sources` (`check F5 3`) | — |
| D5 | Confiance (racine) | `~/pki-racine` de `adm01` (clé chiffrée) | certificat de la racine dans les images et les VMs ; **clé** : archive `gpg` hors site + sauvegarde PBS de `adm01` | cérémonie | — | `ceremonie-pki.sh verifier` (M06) | phrase de passe de la racine **et** de l'archive (enveloppe) |
| D6 | Certificats de PAR2 (Gateway, services du cluster) | `ca01` (ACME, 30 jours) | **autorité intermédiaire PAR2** dans `k8s-par2` (`ClusterIssuer` CA) | cérémonie (S05), une fois | — | émetteur du certificat de `gw-par2` (`check F5 6`) | clé de l'intermédiaire (Ansible Vault `critique`) |
| D7 | Certificats des VMs de PAR2 (`s3-02`, `reg02`, `dns03`, `adm02`) | `ca01` ACME | certificats en place (≤ 30 jours, renouvelés à 15) | ACME par `wg0` en temps normal | — | date d'expiration (supervision) | ⚠️ au plus **15 jours** d'autonomie en PRA ; au-delà : certificats émis à la main par l'intermédiaire PAR2 (RB-350, annexe) |
| D8 | Certificat de `kms01` restauré | ACME (`kms01.par1.medisphere.internal`) | celui de la sauvegarde PBS | PBS | âge de la sauvegarde | expiration lue à la restauration (RB-355) | rien : il doit être **encore valide** (≤ 30 jours) |
| D9 | Coffre (OpenBao) | `vault01-03` | `bao-par2` restauré depuis le dernier instantané | instantané horaire (`openbao-instantanes`) + `filer.sync` | 1 h + retard de copie | âge du dernier instantané sur `s3-02` (`check F5 4`) | clé `age` **privée** de restauration (Ansible Vault `critique`) ; descellement par D10 |
| D10 | Descellement (`kms01`) | `kms01` (1024) | `kms01` restauré (3501, 10.20.20.24) | PBS (`par1/secrets`, quotidien) | 24 h (sa clé de transit ne change pas) | sauvegarde du jour vérifiée (PBS) | **3 parts Shamir sur 5** (gardiens), **clé de chiffrement PBS** ; jeton de seal périodique 168 h (valable si la sauvegarde a moins de 7 jours) |
| D11 | Base de MédiAgenda | `mediagenda-prod/mediagenda-db` | `mediagenda-db-par2` en réplica (topologie distribuée) | archive des WAL (`cnpg-k8s-par1`) + `filer.sync` | ≈ 7 min (RPO 15 min) | âge du dernier WAL sur `s3-02` ; témoin `PRA-TEMOIN` | promotion (jeton si PAR1 vivant, sinon sans jeton) |
| D12 | Identifiants de base de MédiAgenda | OpenBao `db-mediagenda` (rôles dynamiques, TTL 1 h) | Secrets créés en veille par ESO ; en PRA, moteur `db-mediagenda` de `bao-par2` **repointé** vers la base de PAR2 | ESO (30 min) | — | ExternalSecrets `Ready` (`check F5 6`) | jeton administrateur de `bao-par2` ; mot de passe du rôle `openbao` (dans la base, répliqué) |
| D13 | Autres secrets des applications (S3, AMQP, racine, clés d'API) | OpenBao `kv/<application>/<env>/…` | Secrets en veille (ESO, source PAR1) ; en PRA, ESO pointé sur `bao-par2` | ESO | ≤ `refreshInterval` | idem D12 | identité ESO de `k8s-par2` (méthode `k8s-par2` déclarée dans le coffre de PAR1, donc dans l'instantané) |
| D14 | Documents MédiDoc | RGW `medidoc-documents` | `s3-02` `medidoc-documents` | `rclone` (15 min) | 30 min | âge de la dernière copie (`check F5 4`) | identité S3 de MédiDoc à PAR2 (D13) |
| D15 | Legacy-RDV : base et pièces jointes | MariaDB (`legacy-rdv-prod`), CephFS | sauvegardes `mariadb-legacy-rdv` et Velero sur `s3-02` | quotidien + `filer.sync` | 24 h | dernier objet de `mariadb-legacy-rdv/prod/` | phrase Kopia de Velero (enveloppe) ; identité S3 (D13) |
| D16 | MédiNotif : topologie RabbitMQ | `plateforme/donnees` (Topology Operator) | code sur les miroirs | *push mirror* | 1 h | miroir à jour (`check F5 4`) | identifiants AMQP (D13) |
| D17 | Images des applications | Harbor `medisphere/*` | `reg02` | `cosign copy` planifié (runner protégé), toutes les heures et à chaque promotion en prod | 1 h | *digest* de prod présent sur `reg02` (`check F5 4`) | compte de lecture de `reg02` (Secret du nœud, amorçage) |
| D18 | Images de la plateforme (Cilium, cert-manager, CNPG, ESO, Argo CD…) | caches de Harbor | images déjà présentes sur le nœud + Internet par `hp01` | `containerd` | — | pods de la couche de base `Running` | — |
| D19 | Charts | Harbor `charts/` | `reg02` `charts/` | `cosign copy` | 1 h | — | idem D17 |
| D20 | Code et documentation | GitLab | miroirs nus sur `adm02` | *push mirrors* (à chaque poussée) | minutes | `check F5 4` | clé SSH de lecture (Argo CD) ; compte `admin` de `adm02` |
| D21 | État OpenTofu de PAR2 | — | `s3://tofu-par2` sur `s3-02` | — | — | `check F5 3` | identité `tofu-par2` (Ansible Vault `critique`) ; jeton `wb-tofu@pve!par2` |
| D22 | Configuration Ansible et ses secrets | `plateforme/ansible` (Vault `lab` et `critique`) | miroir sur `adm02` | D20 | D20 | — | ⚠️ mots de passe des Vault : **dans OpenBao depuis le M25** (`vault-pass-client.sh`) → copie dans l'enveloppe |
| D23 | Accès de l'opérateur au site | `wg1` de PAR1, SSO, certificats SSH de 16 h (step-ca) | `wg1` de `hp01` ; clés SSH `admin` (cloud-init) des VMs de PAR2 ; `root@pam` de `hp01` | — | — | essai trimestriel (calendrier des tests) | clé privée WireGuard du poste ; clé SSH de bris de glace ; mot de passe `root@pam` de `hp01` (enveloppe) |
| D24 | Accès au cluster de secours | OIDC de Keycloak (PAR1) | `admin.conf` de `k8s-par2` | — | — | — | `admin.conf` (enveloppe, chiffré) |
| D25 | Sauvegardes des VMs de PAR1 (restauration de `kms01`, éventuellement `adm01`, `ca01`) | `pve01` → PBS | datastore `ds-lab` sur `hp01` | PBS (nuit) | 24 h | tâches de vérification de PBS | clé de chiffrement PBS (enveloppe) ; stockage PBS déclaré dans le PVE de `hp01` |
| D26 | Communication de crise | Mailpit (PAR1), messagerie interne | téléphones, SMS, messagerie hors MédiSphère | — | — | annuaire de crise à jour (S07) | numéros de l'annuaire de crise (papier) |

## 2. Boucles et leur amorçage

1. **Le coffre et son descellement.** `bao-par2` ne se descelle que par `kms01` ; `kms01` ne se descelle que par 3 parts Shamir ; les parts sont… chez des personnes. **Amorçage** : gardiens désignés (au moins 5, dont 3 joignables en 1 h, deux hors de l'équipe Plateforme), procédure dans RB-355, vérification semestrielle **sans ouvrir** (le gardien confirme qu'il a sa part et son enveloppe scellée intacte, `enveloppe.md`).
2. **L'état OpenTofu de PAR2 sur `s3-02`.** `envs/par2` décrit `s3-02`, qui porte l'état de `envs/par2`. **Amorçage** : premier `apply` avec un état local (sur `adm01`), ciblé sur `adm02`, `dns03`, `s3-02` ; configuration de `s3-02` (compartiment `tofu-par2`) ; migration de l'état ; suppression de l'état local. En cas de perte de `s3-02` : versions précédentes de l'objet (versionnage), sinon reconstruction par `tofu import` des VMs (VMID connus) — RB-353.
3. **Les mots de passe d'Ansible Vault dans OpenBao.** Depuis le M25, `outils/vault-pass-client.sh` lit les mots de passe dans `kv/plateforme/ansible-vault` ; or la clé `age` de restauration du coffre, l'identité `tofu-par2` et la clé de l'autorité de PAR2 sont dans Ansible Vault « critique ». **Amorçage** : les deux mots de passe dans l'enveloppe ; `vault-pass-client.sh` accepte un repli explicite (variable d'environnement pointant vers un fichier en mémoire, jamais sur disque).
4. **La confiance.** Les certificats ACME viennent de `ca01`, à PAR1. **Amorçage** : autorité intermédiaire propre à PAR2, signée **avant** (S05), clé hors de PAR1.
5. **ESO et le coffre de secours.** Les applications de PAR2 ont besoin de Secrets, ESO a besoin d'un coffre, le coffre de secours n'est démarré qu'en PRA. **Amorçage** : en veille, ESO de `k8s-par2` lit le coffre de **PAR1** (méthode `k8s-par2`) : les Secrets existent déjà le jour J et ESO ne les efface pas si sa source disparaît ; en PRA, on le repointe vers `bao-par2` (la méthode `k8s-par2` y est, puisqu'elle est dans l'instantané).
6. **Argo CD et Git.** Argo CD de `k8s-par2` ne peut pas lire GitLab (PAR1) ; ses identifiants de dépôts sont des Secrets que… Argo CD ne crée pas. **Amorçage** : sources sur les miroirs de `adm02` ; clé SSH de lecture créée par le script d'amorçage (modèle F1 `outils/amorcer-secrets.sh`, lu depuis Ansible Vault « critique ») avant la première synchronisation.
7. **La délégation `par1`.** La zone parente délègue `par1.medisphere.internal` à `dns01`/`dns02` : à PAR2, un récurseur qui suit la délégation interroge des serveurs morts. **Amorçage** : le récurseur de `dns03` transfère les zones internes à l'autoritaire **local** d'abord (comme `dns02`, M06-E24), il ne suit pas la délégation.
8. **Restaurer `kms01` depuis PBS demande… la clé de chiffrement des sauvegardes**, qui est sur `pve01` (`/etc/pve/priv/storage/…`). **Amorçage** : copie de la clé (et de sa version papier, `proxmox-backup-client key paperkey`) dans l'enveloppe.

## 3. Ordre de redémarrage (PRA)

Chaque vague a une condition de passage **observable**. Les temps de référence sont ceux de la répétition (S08) ; ils seront remplacés par les mesures de l'exercice.

| Vague | Contenu | Condition de passage | Réf. |
|---|---|---|---|
| **0. Déclarer et isoler** | décision de Claire ; cellule de crise ; accès par `wg1` de `hp01` ; vérification que PAR1 ne répond plus **et ne peut plus écrire** (ou neutralisé) ; arrêt de `filer.sync` et des copies (sources mortes) | main courante ouverte ; `ping` vers PAR1 en échec depuis `adm02` ; décision tracée | 15 min |
| **1. Socle de PAR2** | heure de `hp01` sur une source Internet ; `dns03` promu primaire des zones internes ; `adm02` devient la forge (miroirs en écriture) | `dig @10.20.20.11 SOA medisphere.internal` répond, zone **native/primaire** ; `chronyc tracking` synchronisé | 20 min |
| **2. Secrets** | restauration de `kms01` (3501, 10.20.20.24) ; descellement Shamir ; démarrage de `bao-par2`, restauration de l'instantané ; moteur `db-mediagenda` repointé vers la base de PAR2 ; ESO repointé vers `bao-par2` | `bao status` : descellé ; lecture d'un secret de `kv/mediagenda/prod/` ; ExternalSecrets `Ready` | 45 min |
| **3. Données** | promotion de `mediagenda-db-par2` ; relevé du dernier témoin (RPO) ; restauration de la base de Legacy-RDV (sauvegarde du jour) et de ses pièces jointes (Velero) | `kubectl cnpg status` : primaire ; témoin lu et noté ; `SELECT count(*)` de contrôle | 30 min (MédiAgenda), + 1 h (Legacy-RDV) |
| **4. Applications** | MédiAgenda (migrations, API), puis MédiNotif (RabbitMQ, worker), MédiDoc, Legacy-RDV : réplicas > 0 par Argo CD de `k8s-par2` | `/pret` 200 sur `….apps.par2…` ; une création de rendez-vous en direct sur `mediagenda.apps.par2…` | 30 min |
| **5. Noms** | CNAME globaux vers `….apps.par2.medisphere.internal` sur `dns03` ; vidage des caches des récurseurs | sonde `ms-sonde-pra` : création réussie par le nom global, `X-MediSphere-Site: par2` → **T reprise** | 10 min (+ TTL 60 s) |
| **6. Mode dégradé** | supervision minimale de PAR2 mise en service (`objectifs.md` §4) ; rejeu des rappels du jour ; communication aux cabinets ; sauvegardes de ce qui tourne à PAR2 | alertes reçues dans Mailpit de secours ; messages d'état envoyés ; rappels partis | — |

Chemin critique (MédiAgenda) : vagues 0 → 1 → 2 → 3 → 4 → 5 ≈ **2 h 30** de référence, sous le RTO de 4 h avec ≈ 1 h 30 de marge pour la décision et les imprévus.

## 4. Impossible ou dégradé sans PAR1

| Élément | Situation à PAR2 | Combien de temps on tient |
|---|---|---|
| Livraisons (CI, Harbor, signature par `transit` de PAR1) | gelées ; correctif d'urgence à la main (RB-350, annexe) | toute la durée du PRA |
| SSO (Keycloak, FreeIPA), certificats SSH de 16 h | comptes de bris de glace | toute la durée, avec revue des accès au retour |
| Certificats ACME des VMs de PAR2 | plus de renouvellement | **15 jours** (puis émission manuelle par l'intermédiaire PAR2) |
| DNSSEC de `par1` | signatures non renouvelées | ≈ 2 semaines |
| Observabilité, alertes par courriel | sonde de `adm02` ; supervision minimale (Prometheus, Alertmanager, Mailpit de secours sur `adm02`) mise en service en vague 6 ; contrôle humain par vacations en attendant | jours (pas de journaux centralisés, pas de tableaux de bord) |
| Sauvegardes de ce qui tourne à PAR2 | la base de PAR2 archive dans `cnpg-k8s-par2` (`s3-02`), **sur la même machine** que tout le reste ; pas de copie hors site | jours : au-delà, exporter vers un support externe (RB-350, annexe) |
| Haute disponibilité | aucune (un nœud, une instance de base) | le temps du PRA |

## 5. Flux réseau nouveaux (matrice des flux)

| Source | Destination | Port | Motif | Scénario |
|---|---|---|---|---|
| PAR2 INFRA (10.20.20.0/24) | `dns01`, `dns02` | 53 TCP/UDP | résolution (déjà ouvert pour `NETS_PAR2`) | S03 |
| `dns03` (10.20.20.11) | `dns01` | 5300 TCP/UDP | AXFR (TSIG) | S03 |
| `dns01` | `dns03` | 5300 UDP/TCP | NOTIFY | S03 |
| MGMT (`adm01`), `runner01` | PAR2 INFRA | 22 | administration, Ansible (déjà : « bastion vers tout le lab et PAR2 » pour MGMT) | S03 |
| PAR2 INFRA | `ca01` | 443 | ACME | S03 |
| `ca01` | PAR2 INFRA | 80 | défi HTTP-01 | S03 |
| `s3-02` | `s3-01` | 8888, 18888 | filer HTTP et gRPC (`filer.sync`, `-a.filerProxy`) | S04 |
| `s3-02` | RGW 10.10.30.200 | 443 | copie de MédiDoc | S04 |
| `git01` | `adm02` | 22 | *push mirrors* | S04 |
| pods de `ci-jobs-protege` (VLAN 40) | `reg02` | 443 | `cosign copy` | S04 |
| `mon01` | PAR2 INFRA | 9100 | node_exporter (retards de réplication) | S04 |
| `k8s-par2-n01` | `openbao` 10.10.20.200 | 8200 | ESO en veille | S06 |
| `vault01-03` | `k8s-par2-n01` | 6443 | TokenReview de la méthode `k8s-par2` | S06 |
| PAR2 INFRA | Internet (NAT `inet par2` de `hp01`) | 80, 443, 123 | paquets, images publiques, temps | S03 |
| poste de l'apprenant (10.255.3.2) | PAR2 (10.20.0.0/16) | tous (filtrés sur `hp01`) | VPN de secours `wg1` | S03 |
