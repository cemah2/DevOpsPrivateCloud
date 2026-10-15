# RB-151 — Certificat non délivré

| | |
|---|---|
| **Périmètre** | Certificats émis par cert-manager sur `k8s-par1` via le ClusterIssuer `step-ca-acme` (ACME de `ca01`, DNS-01 RFC 2136 sur `dns01`, HTTP-01 par `gw-par1`) |
| **Symptômes couverts** | `Certificate` à `READY False` ; renouvellement qui n'aboutit pas ; alerte d'expiration proche |
| **Voir aussi** | runbooks PKI et DNS du M06 (`docs/socle/runbooks/`), RB-150, ADR-0150 |
| **Version** | M15-E40 |

## Précautions

- **Ne supprime jamais le Secret** d'un certificat en service pour « forcer » : le service perd son certificat jusqu'à une réémission qui peut échouer pour la même raison.
- **Aucun secret** dans le ticket ou le journal : ni le Secret TSIG, ni la clé du compte ACME, ni la clé privée d'un certificat.
- Un certificat en échec de renouvellement **continue d'être servi** jusqu'à son expiration : il y a presque toujours le temps de diagnostiquer.

## La chaîne d'objets (lire de haut en bas, s'arrêter au premier étage en échec)

```
kubectl -n <espace> describe certificate <cert>          # Ready, raison, prochain renouvellement
kubectl -n <espace> get certificaterequest,order,challenge
kubectl -n <espace> describe certificaterequest <cr>     # Approved, Ready, raison
kubectl describe clusterissuer step-ca-acme              # Ready (compte ACME, confiance TLS)
kubectl -n <espace> describe order <order>               # état, raison (solveur, autorisation)
kubectl -n <espace> describe challenge <challenge>       # type, Presented, Processing, Reason
kubectl -n cert-manager logs deploy/cert-manager | grep <challenge>
```

`cmctl status certificate -n <espace> <cert>` résume tout si la CLI est installée.

## Causes, par étage

| Étage | Signe | Commande qui le prouve | Correction |
|---|---|---|---|
| `Certificate` / `CertificateRequest` | `Referenced "Issuer" not found` | `kubectl get certificate <cert> -o jsonpath='{.spec.issuerRef}'` | `kind: ClusterIssuer` (sans `kind`, c'est un `Issuer` de l'espace) |
| Émetteur | `ErrRegisterACMEAccount`, `x509: certificate signed by unknown authority` | `kubectl get clusterissuer step-ca-acme -o jsonpath='{.spec.acme.caBundle}' \| base64 -d \| openssl x509 -noout -subject -fingerprint -sha256` comparé à `/usr/local/share/ca-certificates/medisphere-root-ca.crt` | `caBundle` du dépôt (construit depuis la racine unique) |
| Émetteur | `ca01` injoignable | `kubectl -n wb-pannes exec ds/sonde -- curl -sI https://ca01.par1.medisphere.internal/health` ; flux VLAN 40 → `ca01` 443 | pare-feu de la bordure, état de step-ca (M06) |
| `Order` | `no configured challenge solvers can be used` | `kubectl get clusterissuer step-ca-acme -o json \| jq '.spec.acme.solvers[] \| .selector'` | sélecteur DNS-01 qui couvre `apps.par1.medisphere.internal` ; un joker exige DNS-01 |
| `Challenge` DNS-01 | `bad authentication`, `NOTAUTH`, `REFUSED`, `BADKEY`, `BADSIG` | sur `dns01` : `journalctl -u pdns --since -15min` ; `sudo -u pdns pdnsutil metadata get apps.par1.medisphere.internal` ; `sudo -u pdns pdnsutil tsigkey list` (noms seulement) | nom de clé `certmanager-k8s`, algorithme `HMACSHA256`, Secret `cert-manager/tsig-certmanager-k8s` recréé depuis le Vault `lab` (`outils/secret-tsig.sh`), autoritaire `10.10.20.10:5300`, `TSIG-ALLOW-DNSUPDATE`, `ALLOW-DNSUPDATE-FROM 10.10.40.0/24` |
| `Challenge` DNS-01 | `propagation check failed` | `dig +norec -p 5300 @10.10.20.10 _acme-challenge.<nom> TXT` et `@10.10.20.16` | NOTIFY/AXFR vers `dns02`, délégation et DS de `apps` dans `par1` |
| `Challenge` HTTP-01 | `wrong status code '404'` | `curl http://<nom>/.well-known/acme-challenge/<jeton>` depuis `ca01` | route temporaire acceptée par l'écouteur HTTP de `gw-par1`, nom publié |
| Horloge | `badNonce`, `unauthorized`, certificat « pas encore valide » | `timedatectl` sur les nœuds et `ca01` | chrony (synchronisation sur la passerelle) |
| Quotas | `rateLimited` dans la raison de l'`Order` | (step-ca n'en applique pas par défaut) `kubectl get certificaterequests -A \| wc -l` (boucle de redemandes) | supprimer la cause de la boucle ; prévenir l'équipe PKI |

## Relancer proprement

`cmctl renew -n <espace> <cert>` ; à défaut, supprimer la `CertificateRequest` en échec (cert-manager en recrée une). Vérifier `READY True`, puis que `_acme-challenge` a été nettoyé.

## Prévenir l'équipe PKI

Si `ca01` refuse des demandes valides (`step ca health` en erreur, journal de step-ca), si la racine ou l'intermédiaire approchent de l'expiration, ou si plus de 5 certificats sont en échec en même temps.

## Historique

| Date | Incident | Cause | Ajout |
|---|---|---|---|
| 2026-10 | INC-4246 (M15-E40) | clé TSIG, `caBundle`, sélecteur du solveur, `issuerRef` sans `kind` | création |
