<!-- À INTÉGRER dans le registre des secrets (plateforme/medisphere, M06) — M15-E14. -->
| Secret | Usage | Où (source de vérité) | Copies | Accès | Rotation | Réf. |
|---|---|---|---|---|---|---|
| TSIG `certmanager-k8s` (hmac-sha256) | défis DNS-01 de cert-manager, zone `apps` seulement, depuis 10.10.40.0/24 | Vault `lab` : `group_vars/role_dns/vault-lab.yml` (`vault_powerdns_tsig_certmanager_k8s`) | base de PowerDNS de `dns01` ; Secret `cert-manager/tsig-certmanager-k8s` | équipe Plateforme | annuelle ou sur incident : `outils/ajouter-tsig.sh`, pipeline, `outils/secret-tsig.sh` | M15-E14 |
| TSIG `externaldns-k8s` (hmac-sha256) | ExternalDNS (mises à jour et AXFR de la zone `apps`), depuis 10.10.40.0/24 | Vault `lab` : `vault_powerdns_tsig_externaldns_k8s` | base de PowerDNS de `dns01` ; Secret `external-dns/tsig-externaldns-k8s` | équipe Plateforme | idem | M15-E14, E15 |
