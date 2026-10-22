# PKI de services

| | |
|---|---|
| Ticket | SEC-2616 (M25-E16) |
| Propriétaire | Équipe Plateforme ; relecture : Sophie Laurent (RSSI) |
| Configuration | `plateforme/secrets` : `tofu/pki-services.tf`, `politiques/cert-manager-services.hcl` ; `plateforme/k8s` : `composants/cert-manager/openbao-services.yaml` ; procès-verbal : `docs/securite/identite/ceremonie-ca.md` |

## 1. Chaîne

```
MédiSphère Root CA (hors ligne, adm01, 10 ans)
  └── MédiSphère Services CA (OpenBao pki-services/, clé EC P-256 non exportable, 3 ans, pathlen:0)
        └── certificats de service (rôle services-k8s : *.svc, *.svc.cluster.local, 24 h par défaut, 72 h au plus)
```

Points publiés (sans authentification) : `…/v1/pki-services/ca` (AIA), `…/crl` (CDP), `…/ocsp`.

## 2. Émission

cert-manager, ClusterIssuer `openbao-services` (méthode `k8s-par1`, compte `cert-manager/openbao-emetteur`, chemin `pki-services/sign/services-k8s`) : la clé privée est générée dans le cluster, seule la CSR va à OpenBao. Certificats en service : `medidoc-mtls` (`medidoc-recette`), `mediagenda-mtls` (`mediagenda-recette`), 48 h, renouvelés 16 h avant l'échéance, nouvelle clé à chaque fois.

Limite connue : tout espace qui peut créer un `Certificate` sur cette ClusterIssuer obtient un certificat pour **n'importe quel** nom en `.svc` (y compris celui d'un autre espace). Compensation actuelle : les relais vérifient un nom précis, et seuls les dépôts de déploiement relus créent des `Certificate`. Correction prévue : `approver-policy` de cert-manager (un espace ne demande que ses propres Services), ou un rôle OpenBao par espace avec `allowed_domains_template`.

## 3. TLS mutuel MédiAgenda → MédiDoc (recette)

| Côté | Relais | Écoute | Vers | Vérifie |
|---|---|---|---|---|
| MédiAgenda | ghostunnel `client` (conteneur annexe natif) | `127.0.0.1:8081` | `medidoc.medidoc-recette.svc.cluster.local:8443` | certificat serveur signé par la Services CA, nom `medidoc.medidoc-recette.svc` |
| MédiDoc | ghostunnel `server` | `0.0.0.0:8443` | `127.0.0.1:8080` | certificat client signé par la Services CA, nom `mediagenda.mediagenda-recette.svc` |

Réseau : MédiAgenda n'atteint MédiDoc que sur 8443 (CiliumNetworkPolicy des deux côtés) ; la Gateway garde 8080. Certificats relus toutes les 5 min par les relais (`--timed-reload`).

## 4. Révocation

- `bao write pki-services/revoke serial_number=<SÉRIE>` (ou `revoke-with-key`) : le certificat entre dans la CRL **à sa prochaine reconstruction** (automatique, au plus tard `auto_rebuild_grace_period` = 12 h ; immédiate avec `bao read pki-services/crl/rotate`).
- **Les relais ghostunnel ne lisent pas la CRL** (ni OCSP) : un certificat révoqué reste accepté jusqu'à son expiration. La protection réelle contre un certificat volé est donc sa **durée** (48 h émis, 72 h au plus) et la rotation de la clé à chaque renouvellement.
- Révocation effective, si un jour nécessaire : un relais qui vérifie la CRL ou OCSP (Envoy avec `crl`, nginx `ssl_crl`), ou bien des durées encore plus courtes (quelques heures), ou retirer le nom autorisé du relais (`--allow-dns`) le temps de l'incident.
- La CRL sert aux consommateurs qui la lisent (navigateurs, outils `openssl verify -crl_check`) et à la **preuve** (registre daté de ce qui a été révoqué, pour l'auditeur HDS).

## 5. Exploitation

- Supervision : expiration de la Services CA (alerte à un an), âge de la CRL, échecs d'émission de cert-manager (`certmanager_certificate_ready_status`), `CertificatServicesExpireBientot` (E27).
- Renouvellement de la CA : voir le procès-verbal (nouvel émetteur, bascule, ancien gardé 72 h).
