<!-- docs/socle/registre-secrets.md (plateforme/medisphere) — lignes AJOUTÉES au palier 2 du M06 -->
| Secret | Portée | Emplacement | Détenteur | Rotation | Révocation |
|---|---|---|---|---|---|
| Jeton NetBox `svc-automatisation` « écriture » (E10) | VMs, interfaces, disques, adresses IP : lecture/écriture ; référentiel en lecture ; depuis 10.10.10.10 et 10.10.20.15 | `~/.config/workbook/netbox-auto.token` (adm01) ; `netbox-tofu.env` (E13) ; variable CI `TF_VAR_netbox_api_token` (`plateforme/infra`) | équipe Plateforme | 1 an (expiration du jeton) ou départ | *Admin > API Tokens* : désactiver puis supprimer |
| Jeton NetBox `svc-automatisation` « lecture » (E12) | lecture seule | `netbox-ansible.env` (adm01) ; variable CI `NETBOX_TOKEN` (`plateforme/ansible`) | équipe Plateforme | 1 an | idem |
| Clé d'API PowerDNS (copie de travail, E14) | toutes les zones de `dns01` | `powerdns-api.env` (adm01) ; variable CI `TF_VAR_pdns_api_key` (`plateforme/infra`) ; source : `vault_powerdns_api_cle` | équipe Plateforme | 6 mois | rotation dans Vault + rôle `powerdns_auth` |
| Mot de passe de l'API de Kea (E17) | API de `kea-dhcp4` (127.0.0.1:8004) | `vault_kea_api_mot_de_passe` ; `/etc/kea/kea-api-mdp` (dns01, 640) | équipe Plateforme | 6 mois | rotation dans Vault + rôle `kea_dhcp4` |
| Clé TSIG `ddns-kea` (E17) | mises à jour dynamiques de `par1` et `10.10.in-addr.arpa` depuis 127.0.0.1 | `vault_kea_tsig_ddns` ; `/etc/kea/tsig-ddns-kea.secret` ; base de PowerDNS | équipe Plateforme | 1 an | `pdnsutil tsigkey delete ddns-kea` + rôle `kea_ddns` |
| Clé SSH de bris de glace `admin` (E20) | compte `admin` du socle | clé privée chiffrée hors ligne (`<SUPPORT>`), publique dans `ms_cles_admin` | Claire Morel + équipe | à chaque usage | retrait de `ms_cles_admin` + rôle `base` |
