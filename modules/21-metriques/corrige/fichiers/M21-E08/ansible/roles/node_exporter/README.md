# Rôle `node_exporter` — version 2

Exportateur de métriques système de Prometheus, **binaire amont** épinglé par empreinte, servi en **HTTPS** avec un certificat de step-ca, sous un utilisateur dédié, dans une unité systemd durcie. Remplace la version 1 (M04-E34 : paquet Debian 1.9, HTTP en clair). Rôle réécrit en M21-E08.

## Ce que fait le rôle

1. refuse une cible non prise en charge (Debian ou EL, x86_64, port et adresse valides, empreinte bien formée) ;
2. télécharge l'archive **une fois sur le contrôleur**, vérifiée par son sha256 (`get_url` refuse un fichier différent), la décompresse sur l'hôte dans `/opt/node_exporter/<version>/` et pointe `/usr/local/bin/node_exporter` vers elle (retour arrière : changer `node_exporter_version` et rejouer) ;
3. crée l'utilisateur système `node_exporter` (sans shell ni répertoire personnel) ;
4. obtient le certificat `node-exporter` par le rôle `certificats_acme` (ACME HTTP-01, puis renouvellement mTLS par `cert-renewer@node-exporter`) ;
5. écrit `/etc/node_exporter/web.yml` (TLS 1.2 minimum) ; node_exporter le relit à chaque connexion ;
6. **retire le paquet Debian** `prometheus-node-exporter` de la version 1 (même port), garde le dossier du collecteur textfile et la métrique `medisphere_info` ;
7. installe l'unité `node_exporter.service` (durcie : `systemd-analyze security node_exporter.service`) et la démarre ;
8. vérifie depuis le contrôleur : `https://<fqdn>:9100/metrics` répond avec un certificat valide pour le nom, la bonne version, et le HTTP en clair est refusé (400).

## Variables

| Variable | Défaut | Rôle |
|---|---|---|
| `node_exporter_version` / `node_exporter_sha256` | `1.12.1` / empreinte de l'archive linux-amd64 | Version amont et son empreinte (à changer ensemble) |
| `node_exporter_port` | `9100` | Port d'écoute |
| `node_exporter_adresse` | IPv4 de la route par défaut | Adresse d'écoute ; `0.0.0.0` pour les passerelles (`group_vars/role_routeur`) |
| `node_exporter_tls` | `true` | `false` seulement pour Molecule (pas d'ACME dans une instance de test) |
| `node_exporter_fqdn` | `<hôte>.par1.medisphere.internal` | Nom du certificat = nom de la cible dans Prometheus |
| `node_exporter_acme_avant_emission`, `…_apres_emission`, `…_ecoute_http` | repris du premier certificat ACME de l'hôte | Libérer le port 80 le temps du défi |
| `node_exporter_collecteurs_desactives` | `[infiniband, zfs, nfs, nfsd]` | Collecteurs coupés |
| `node_exporter_unites_systemd` | `ssh`, `chrony`, `nftables`, `node_exporter`, `cert-renewer@node-exporter` | Unités publiées par le collecteur systemd |
| `node_exporter_dossier_textfile` | `/var/lib/prometheus/node-exporter` | Collecteur textfile (inchangé depuis la version 1) |

## Prérequis réseau

- `ca01` joint le port 80 de l'hôte le temps de la **première** émission (défi HTTP-01) ; les renouvellements passent par `ca01:443` ;
- Prometheus (travailleurs de `k8s-par1`, `K8S_TRAV`) et MGMT joignent le port 9100 : bordure (`pare_feu_transit`, `pare_feu_entree` des passerelles) et pare-feu local (`pare_feu_local_communes`).

## Limites

- amd64 seulement (toutes les VMs du lab) ;
- pas d'authentification HTTP : la confidentialité vient du TLS, le contrôle d'accès du filtrage réseau (M21-E29 discute l'authentification par certificat client).
