# RB-240 — Bris de glace : entrer quand le SSO ne répond plus

| | |
|---|---|
| Ticket | SEC-2528 (M24-E28) |
| Propriétaire | Sophie Laurent (RSSI) ; exécution : astreinte (Nadia Roussel, équipe Plateforme) |
| Essai | **trimestriel**, un compte après l'autre (§5) ; dernier essai : <AAAA-MM-JJ> (annexe A) |
| Liens | RB-243 (restauration), RB-245 (montées de version), RB-246 (SSO indisponible), ADR-0240, ADR-0241 |

## 1. Quand déclarer le bris de glace

Un compte de secours ne s'ouvre que si **les trois** conditions sont réunies :

1. un incident est ouvert (INC-…) ;
2. l'accès nominatif par le SSO est **impossible** (Keycloak arrêté, fédération en échec, MFA indisponible, service dont l'OIDC est cassé) **ou** l'action à faire n'est possible qu'avec ce compte (réparer Keycloak lui-même, restaurer l'annuaire) ;
3. la responsable d'astreinte (ou, à défaut, Claire Morel) donne son accord, par écrit dans l'incident.

Hors de ces cas, un usage est un **incident de sécurité** (§6).

## 2. Qui peut ouvrir

Les secrets sont dans le Vault `critique` (deux personnes connaissent le mot de passe du Vault : l'équipe Plateforme senior) et, pour les comptes marqués « coffre », sur papier dans l'enveloppe scellée du coffre (ouverture à deux, procès-verbal). Aucun compte de secours n'a d'OTP lié à un téléphone personnel.

## 3. Comptes, par service

| Service | Compte | Où est le secret | Ouvrir / utiliser quand le SSO est en panne | Refermer | Ce qui trace l'usage |
|---|---|---|---|---|---|
| Keycloak (royaume `master`) | `kc-secours` | Vault `critique` (`host_vars/idp01/vault-critique.yml`), coffre | `https://sso.par1.medisphere.internal/admin/` depuis MGMT ou le VPN ; si la console est inaccessible : console de `idp01`, `kc.sh bootstrap-admin user` (E04) | déconnexion ; mot de passe changé (24 caractères) et Vault mis à jour **après tout usage réel** | `BrisDeGlaceKeycloak` (Loki `audit`) ; événement `LOGIN` du royaume `master` |
| FreeIPA | `admin` | Vault `critique` (`annuaire/vault-critique.yml`, `host_vars/ipa01/vault-critique.yml`) | `ssh admin@ipa01` (clé locale), `kinit admin`, `ipa …` ; interface `https://ipa01…/ipa/ui/` | `kdestroy` ; changement du mot de passe si usage réel (puis Vault, puis job `annuaire:appliquer`) | `BrisDeGlaceAnnuaire` (KDC), `BrisDeGlaceAnnuaireLiaisonLdap` (389-ds) |
| GitLab | `root` | gestionnaire de mots de passe de l'équipe, coffre | `https://git01…/users/sign_in` : la connexion par mot de passe reste permise pour `root` seulement (palier 2) | déconnexion ; changement si usage réel | journal d'audit de GitLab (`audit_json.log`) ; pas d'alerte automatique (§7) |
| Argo CD | `admin` (désactivé) | — (mot de passe initial supprimé) | MR « bris de glace » sur les valeurs Helmfile de la release `argocd` : `configs.cm.admin.enabled: true`, puis `argocd account update-password` avec `admin.conf` ; ou `kubectl` avec `admin.conf` directement | MR inverse (`admin.enabled: false`) | MR et journal d'audit de l'API (`kubernetes-admin`) |
| Grafana | `admin` | Vault `critique` (Secret `grafana-admin`) | formulaire désactivé (`disable_login_form`) : API en authentification basique (`curl -K`), ou MR temporaire `disable_login_form: false` | MR inverse ; rotation (`outils/grafana-rotation-admin.sh`, M21-E29) | journal de Grafana (Loki, locataire `plateforme`) |
| Harbor | `admin` (base locale) | Vault `critique` | page de connexion : « LOGIN VIA LOCAL DB » (mode OIDC) | déconnexion ; changement si usage réel | journal d'audit de Harbor (`audit-logs`) |
| Proxmox VE | `root@pam` | coffre | `https://pve01:8006`, royaume « Linux PAM » ; ou console physique / SSH root | déconnexion ; changement si usage réel | `/var/log/pveproxy/access.log`, `journalctl` de `pve01` (pas dans Loki : §7) |
| PBS | `root@pam` | coffre | `https://pbs01:8007`, royaume « Linux PAM » | idem | journal de `pbs01` |
| NetBox | superutilisateur local (M06) | Vault `critique` | `https://nbx01…/login/?next=/` (formulaire local gardé à côté du SSO) | déconnexion ; changement si usage réel | journal des changements de NetBox |
| Cluster `k8s-par1` | `admin.conf` (`kubernetes-admin`, groupe `kubeadm:cluster-admins`) | Vault `critique` (`plateforme/k8s`) | `kubectl --kubeconfig <(uv run ansible-vault view …)` : jamais de fichier clair | rien à refermer côté cluster ; vider l'historique du shell | `BrisDeGlaceCluster` (audit de l'API, Loki `audit`) |
| VMs | compte local `admin` (clé SSH d'`adm01`) ; console Proxmox | clé sur `adm01` (et sauvegarde) | `ssh admin@<vm>` (SSSD, HBAC et `step ssh login` contournés) | — | journal de `sshd` des VMs (Loki, locataire `plateforme`) |
| OpenBao (M25) | jeton racine régénérable par parts Shamir | parts au coffre | RB-25x | — | journal d'audit d'OpenBao |

## 4. Procès-verbal d'usage (à joindre à l'incident)

| Champ | Valeur |
|---|---|
| Incident | INC-… |
| Compte, service | |
| Autorisé par, heure | |
| Ouvert par (deux noms si coffre) | |
| Actions faites (commandes, écrans) | |
| Refermé à (heure), secret changé ? | |
| Alerte reçue (heure) ? | |

## 5. Essai trimestriel

Un compte après l'autre, mot de passe **copié** depuis le Vault (jamais retapé), arrêt après deux échecs (un compte de secours verrouillé ne sert plus) ; noter l'heure, le résultat, l'alerte reçue ; refermer (session, ticket Kerberos, aucun fichier clair). Le procès-verbal de l'essai va en annexe A et dans l'incident de suivi (CHG-…).

## 6. Usage non déclaré

Une alerte `BrisDeGlace*` sans incident ni essai correspondant : traiter comme une compromission. Changer immédiatement le secret du compte, chercher l'origine (adresse `ipAddress` de l'événement Keycloak, connexion `conn=` de 389-ds, `sourceIPs` de l'audit de l'API), prévenir Sophie Laurent, ouvrir un SEC-….

## 7. Comptes partagés restant sans alerte (actions prévues)

| Compte | Pourquoi il reste | Action | Module |
|---|---|---|---|
| `root` de GitLab | bris de glace de GitLab | envoyer `audit_json.log` à Loki `audit`, alerte sur `root` | M26 (journalisation des hôtes) |
| `root@pam` de `pve01` et `pbs01` | hors du lab supervisé (hyperviseur) | journal de `pveproxy` vers Loki, ou revue mensuelle (E30) | M26 / F6 |
| `admin` de Grafana | bris de glace et automatisation (OpenTofu) | séparer : compte de service pour OpenTofu, `admin` au coffre | M25 |
| `admin` de FreeIPA | bris de glace **et** automatisation de l'annuaire | compte de service à rôle limité pour le pipeline (pour aller plus loin d'E03) | M25 |
| compte local `admin` des VMs | automatisation Ansible et bris de glace | certificats SSH courts pour Ansible aussi ; clé de secours au coffre | M26 |

## Annexe A — Procès-verbal de l'essai du <AAAA-MM-JJ>

| Heure | Compte | Résultat | Alerte reçue (heure) | Refermé |
|---|---|---|---|---|
| <HH:MM> | `kc-secours` | <connexion OK, écran *Realm settings* lu, déconnexion> | <HH:MM> `BrisDeGlaceKeycloak` | oui |
| <HH:MM> | `admin` (FreeIPA) | <`kinit admin`, `ipa user-show lucas.martin`, `kdestroy`> | <HH:MM> `BrisDeGlaceAnnuaire` | oui |
| <HH:MM> | `root` (GitLab) | | — (pas d'alerte, §7) | oui |
| <HH:MM> | `admin` (Harbor) | | — | oui |
| <HH:MM> | superutilisateur NetBox | | — | oui |
| <HH:MM> | `root@pam` (pve01) | | — | oui |
| <HH:MM> | `root@pam` (pbs01) | | — | oui |
| <HH:MM> | `admin` (Grafana, API) | <`GET /api/org` → 200> | — | oui |
| <HH:MM> | `admin.conf` | <`kubectl auth whoami` → kubernetes-admin> | <HH:MM> `BrisDeGlaceCluster` | oui |
| <HH:MM> | Argo CD `admin` | procédure relue, non jouée (E43) | — | — |
