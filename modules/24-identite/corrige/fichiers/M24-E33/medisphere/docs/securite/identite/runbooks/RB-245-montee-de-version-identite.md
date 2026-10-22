# RB-245 — Monter de version Keycloak et FreeIPA

| | |
|---|---|
| Ticket | CHG-2533 (M24-E33) |
| Dernière montée | Keycloak 26.7.5 → 26.8.1 le <AAAA-MM-JJ> (coupure mesurée : <N> s, migration du schéma : <N> s) ; FreeIPA <VERSION> → <VERSION> |
| Fenêtre type | mardi 7 h – 8 h, annoncée la veille (astreinte, équipes) |

## 1. Préparer (J-7 à J-1)

1. Lire les notes de version et le guide de montée de version de **chaque** version entre l'actuelle et la cible (`https://www.keycloak.org/docs/latest/upgrading/`), et `annexes/versions-bloc-F.md`.
2. Pour chaque rupture : chercher si elle nous touche (code `plateforme/identite`, politiques d'autorisation, rôles des comptes de service, fournisseur OpenTofu) ; résultat dans le plan de changement.
   Relevé pour 26.8 : lecture du secret d'un client réservée à `manage-clients` (nos comptes de service : `wb-checks` et `revue-acces` ne lisent pas les secrets → sans effet) ; nom de groupe nu = groupe de premier niveau (nos groupes sont tous de premier niveau → sans effet) ; client désactivé absent de `aud` (aucun) ; jeton de rafraîchissement plafonné par l'inactivité de session (30 min : kubelogin et la CLI d'Argo CD se reconnectent plus souvent après une pause, sans effet de sécurité) ; échecs de connexion stockés en base (compteurs de force brute conservés au redémarrage) ; rotation des secrets clients active par défaut (nos secrets restent imposés par OpenTofu).
3. **Essai sur une copie** (`idp-resto`, RB-243 §4) : restauration de la sauvegarde de la nuit en version actuelle, puis montée de la copie ; noter la durée de la migration (journal : `Updating database`, `migrated realm … to 26.8.0`), contrôler découverte, `kid`, comptes, droits de `wb-checks` ; détruire la copie.
4. Plan de changement : étapes, durées, **critères d'arrêt** (migration de plus de 10 min, `/health/ready` absent 5 min après le démarrage, une connexion de personnage refusée), retour arrière (§5), communication.

## 2. Le jour J — Keycloak

1. Annonce de début ; `kc-secours` essayé ; session `<MOI>-admin` ouverte ; `admin@idp01` en SSH.
2. Sauvegarde **juste avant** : `sudo systemctl start identite-sauvegarde.service` puis `cat /var/lib/identite-sauvegarde/dernier-succes` (noter l'objet : c'est le point de retour).
3. MR `host_vars/idp01/keycloak.yml` (version, empreinte) fusionnée ; `uv run ansible-playbook playbooks/identite.yml --limit idp01` (téléchargement vérifié, construction, bascule du lien, redémarrage).
4. Suivre `sudo journalctl -u keycloak -f` : migration du schéma, puis `Keycloak … started`.

## 3. Contrôles après le changement

`/health/ready` (9000) ; version (`/opt/keycloak` → `/opt/keycloak-26.8.1`) ; alertes d'E26 muettes ; connexion de `lucas.martin` et de toi (OTP) ; `kubectl` (kubelogin, après `kubectl oidc-login clean`) ; `argocd login --sso` ; `step ssh login` ; `tofu -chdir=tofu plan` vide dans `plateforme/identite` ; `lab/bin/check 24 05`, `24 27`, `24 33`.

## 4. Le jour J — FreeIPA (correctifs de la mineure)

1. Sauvegarde : `sudo systemctl start identite-sauvegarde.service` **et** sauvegarde complète (`sudo ipa-backup`, services arrêtés ≈ 2 min ; RB-243 §5).
2. `sudo dnf check-update` : lire la liste ; n'appliquer que les paquets de la mineure en cours (`ipa-*`, `389-ds-base`, `pki-*`, `krb5-*`, `sssd-*` et leurs dépendances), jamais un changement de version de Rocky dans la même fenêtre.
3. `sudo dnf upgrade --refresh <paquets>` : le paquet `ipa-server` lance `ipa-server-upgrade` (journal `/var/log/ipaupgrade.log`, se termine par « The ipa-server-upgrade command was successful »).
4. Contrôles : `ipactl status` (tout `RUNNING`), `sudo ipa-healthcheck --failures-only`, `kinit lucas.martin` (puis `kdestroy`), connexion d'un personnage à Keycloak (LDAPS), `ssh` sur une VM inscrite, `FederationLdapEnEchec` muette.

## 5. Retour arrière

- **Keycloak** : la base a été **migrée** au premier démarrage ; l'ancienne version ne sait pas lire un schéma plus récent. Retour = `sudo systemctl stop keycloak`, restauration de la sauvegarde du §2.2 (RB-243 §4, « sur `idp01` »), `keycloak_version`/`keycloak_sha256` de l'ancienne version (MR), playbook (le lien revient sur `/opt/keycloak-26.7.5`, déjà construit), démarrage, contrôles. Tout ce qui a été fait entre la sauvegarde et le retour est perdu (OTP enregistrés, sessions).
- **FreeIPA** : pas de retour arrière de paquets (`dnf history undo` ne défait pas `ipa-server-upgrade`) ; retour = restauration de la VM depuis PBS (`pbs-par2-identite`) ou `ipa-restore` de la sauvegarde complète du §4.1.

## 6. Clôture

Après une semaine sans incident : supprimer `/opt/keycloak-26.7.5` (`sudo rm -rf` noté au changement, ou variable de nettoyage du rôle) ; mettre à jour PLAN §6 si la version de référence change ; journal du changement (durées réelles) dans `docs/socle/journal/`.
