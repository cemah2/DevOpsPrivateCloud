<!-- EXTRAIT (M04-E12, E13) — lignes à ajouter à docs/socle/registre-secrets.md dans
     plateforme/medisphere (par MR). Aucune valeur. -->

| Identifiant | Type | Propriétaire | Portée / rôle | Stockage | Expiration | Rotation |
|---|---|---|---|---|---|---|
| `wb-ansible@pve!ansible` | jeton d'API Proxmox (privsep) | équipe Plateforme (`<MOI>`) | `WBAnsible` (VM.Audit, VM.GuestAgent.Audit, Pool.Audit) sur `/pool/lab` ; `WBAnsibleCluster` (Sys.Audit) sur `/`, sans propagation | `adm01:~/.config/workbook/pve-ansible.env` (600) ; variables CI protégées et masquées de `plateforme/ansible` (M04-E27) | ≤ 1 an (`--expire`) | créer `wb-ansible@pve!ansible2` avec les mêmes ACL, mettre à jour le fichier et les variables CI, `ansible-inventory --graph`, supprimer l'ancien |
| identité Vault `lab` | mot de passe Ansible Vault | équipe Plateforme (`<MOI>`) | déchiffre `inventories/lab/group_vars/all/vault.yml` de `plateforme/ansible` | `adm01:~/.config/workbook/ansible-vault.pass` (600) ; variable CI de type fichier, protégée et masquée (M04-E27) ; copie dans le coffre de l'équipe | aucune | `ansible-vault rekey` (M04-E30) |
| compte local `secours` | mot de passe (console) | équipe Plateforme | toutes les VMs du socle, sudo avec mot de passe, SSH refusé | empreinte chiffrée dans `vault.yml` (`vault_secours_mdp_hash`) ; mot de passe dans le coffre de l'équipe | — | nouvelle empreinte dans le Vault, `--tags base_utilisateurs` |
