# Durcissement des services socle — état attendu après M06-E30 (référence du corrigé)

| Service | Réglage | Valeur attendue | Où (code) |
|---|---|---|---|
| PowerDNS Authoritative | `local-address` | `127.0.0.1:5300` et l'adresse de service `:5300`, jamais `0.0.0.0` | `host_vars/dns0X/powerdns_auth.yml` |
| | `allow-axfr-ips` | `127.0.0.0/8` (dns02 transfère par TSIG) | idem |
| | `only-notify` / `also-notify` | vide / `10.10.20.16:5300` | idem |
| | API (`webserver-address`, `webserver-allow-from`) | `10.10.20.10:8081`, `127.0.0.1,10.10.10.10,10.10.20.15` ; **pas d'API sur dns02** | idem |
| | `allow-dnsupdate-from` + `ALLOW-DNSUPDATE-FROM` + `TSIG-ALLOW-DNSUPDATE` | `127.0.0.1,10.10.20.16` + clé `ddns-kea` | `host_vars/dns01/powerdns_auth.yml`, `group_vars/role_dns/kea.yml` (`kea_ddns_autorises`) |
| PowerDNS Recursor | `incoming.listen` | `127.0.0.1` et l'adresse de service | `host_vars/dns0X/powerdns_recursor.yml` |
| | `incoming.allow_from` | `127.0.0.0/8, 10.10.0.0/16, 10.20.0.0/16, 10.255.1.0/24` (pas de résolveur ouvert) | `group_vars/role_dns/powerdns_recursor.yml` |
| Kea DHCPv4 | socket de contrôle | HTTPS sur l'adresse de service `:8004`, authentification basique, pas de `0.0.0.0` | `group_vars/role_dns/kea.yml` |
| | écouteur HA | HTTPS `:8001`, `require-client-certs: true`, `restrict-commands: true` | idem |
| | fichiers de mots de passe, clé TLS | `root:_kea`, `0640` | rôle `kea_dhcp4` |
| step-ca | `address` / `insecureAddress` | `:443` / `:80` (CRL seulement) | `ca.json` (rôle `step_ca`) |
| | clé racine | **absente** de `ca01` | — |
| | confinement systemd | drop-in `20-durcissement.conf` | `roles/step_ca/files/` |
| NetBox | PostgreSQL `listen_addresses` | `localhost` (défaut Debian, vérifié) | rôle `netbox` |
| | Valkey `bind` | `127.0.0.1 -::1` (défaut Debian, vérifié), `protected-mode yes` | rôle `netbox` |
| | `ALLOWED_HOSTS` | `['nbx01.par1.medisphere.internal']` (pas `*`) | `configuration.py` (rôle `netbox`) |
| | `DEBUG` | `False` | idem |
| | `LOGIN_REQUIRED` | `True` | idem |
| | `SESSION_COOKIE_SECURE`, `CSRF_COOKIE_SECURE` | `True` (HTTPS seulement) | idem |
| | nginx | TLS 1.2 et 1.3 seulement, redirection 80 → 443 | rôle `netbox` |
| Tous (dns01, dns02, ca01, nbx01) | filtrage d'entrée local | `pare_feu_local`, politique `drop` | `host_vars/<hôte>/pare_feu_local.yml` |
