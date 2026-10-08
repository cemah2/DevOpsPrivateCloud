# MédiDoc — documents patients

Service Go qui reçoit et restitue les documents des patients (comptes rendus, ordonnances, images). Les documents sont rangés dans un compartiment S3 compatible : SeaweedFS du socle (`s3-01`) ou Ceph RGW (module 08, compartiment `medidoc-documents`).

Projet GitLab cible : `medidoc/medidoc` (chemin du module Go : `git01.par1.medisphere.internal/medidoc/medidoc`).

## Points d'accès (port 8080)

| Méthode et chemin | Rôle |
|---|---|
| `GET /healthz` | Vivacité : `{"statut":"ok","version":"…"}`, sans contacter S3. |
| `GET /readyz` | Disponibilité : `HeadBucket` sur le compartiment (2 s au plus) ; 200 ou 503. |
| `GET /metrics` | Prometheus : `medidoc_http_requests_total{methode,route,code}`, `medidoc_http_request_duration_seconds`, métriques Go et processus. |
| `POST /documents` | `multipart/form-data` : champ `patient` (identifiant, `[A-Za-z0-9-]`, 64 caractères au plus) et champ `fichier`. 201 avec la description du document et un en-tête `Location`. 413 au-delà de `MEDIDOC_MAX_MB`. |
| `GET /documents/{id}` | Contenu du document (`Content-Disposition: attachment`). 404 si absent, 400 si l'identifiant n'a pas la forme attendue (32 caractères hexadécimaux). |
| `GET /documents?limite=100` | Liste (identifiant, taille, date), 1000 au plus. |

Les erreurs du stockage donnent 502 (le service dont on dépend a échoué), jamais un 500 muet. Chaque requête produit une ligne de journal JSON (`log/slog`) ; ni nom de fichier ni identifiant patient n'y figurent.

Les objets sont écrits sous la clé `documents/<id>`, avec le patient et le nom de fichier d'origine en métadonnées S3 (encodés façon URL : les métadonnées S3 n'acceptent que l'ASCII).

```
admin@adm01:~$ curl -F patient=PAT-000123 -F fichier=@compte-rendu.pdf http://127.0.0.1:8080/documents
admin@adm01:~$ curl -OJ http://127.0.0.1:8080/documents/<ID>
```

## Configuration (variables d'environnement)

| Variable | Défaut | Rôle |
|---|---|---|
| `MEDIDOC_S3_ENDPOINT` | *(obligatoire)* | URL du service S3, ex. `https://s3-01.par1.medisphere.internal:8333` |
| `MEDIDOC_S3_BUCKET` | *(obligatoire)* | Compartiment, ex. `medidoc-documents` |
| `MEDIDOC_S3_REGION` | `us-east-1` | Région annoncée dans la signature SigV4 ; `us-east-1` convient à SeaweedFS et à Ceph RGW avec son *zonegroup* par défaut |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | *(obligatoires)* | Identifiants S3, lus directement par le SDK AWS |
| `MEDIDOC_CA_FILE` | *(vide)* | Fichier PEM d'une autorité **ajoutée** à celles du système (ex. `/usr/local/share/ca-certificates/medisphere-root-ca.crt`) |
| `MEDIDOC_MAX_MB` | `10` | Taille maximale d'un document, en Mio (1 à 1024) |
| `MEDIDOC_PORT` | `8080` | Port d'écoute |
| `MEDIDOC_LOG_LEVEL` | `info` | `debug`, `info`, `warn`, `error` (les sondes sont journalisées en `debug`) |
| `MEDIDOC_VERSION` | version compilée | Remplace la version fixée par `-ldflags` |

Deux réglages du client S3 méritent d'être connus :

- **style « chemin »** (`UsePathStyle`) : les requêtes visent `https://s3-01…:8333/<compartiment>/<clé>` et non `https://<compartiment>.s3-01…`, qui demanderait un DNS et un certificat joker ;
- **sommes de contrôle « quand c'est requis »** : depuis début 2025, le SDK AWS ajoute par défaut des sommes CRC en en-têtes de fin de requête, que tous les services compatibles S3 ne comprennent pas. MédiDoc ne les envoie que lorsque l'opération l'exige.

Chaque document est lu en mémoire avant l'envoi (au plus `MEDIDOC_MAX_MB`) : le SDK peut ainsi signer le contenu et réessayer. Prévois la mémoire en conséquence (requêtes simultanées × taille maximale).

## Compiler et lancer

Go 1.26 :

```
admin@adm01:~/src/medidoc$ go test ./...
admin@adm01:~/src/medidoc$ go vet ./...
admin@adm01:~/src/medidoc$ CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X main.version=1.0.0" -o medidoc ./cmd/medidoc
admin@adm01:~/src/medidoc$ file medidoc        # « statically linked » : aucune dépendance à la libc
admin@adm01:~/src/medidoc$ set -a; . ~/.config/workbook/s3-medidoc-app.env; set +a   # clés du compte medidoc-app (M08-E12), hors dépôt
admin@adm01:~/src/medidoc$ MEDIDOC_S3_ENDPOINT=https://rgw.par1.medisphere.internal \
  MEDIDOC_S3_BUCKET=medidoc-documents ./medidoc
```

Arrêt propre : sur SIGTERM ou SIGINT, le serveur cesse d'accepter des connexions et laisse 20 secondes au plus aux requêtes en cours ; un second signal l'arrête immédiatement.

## Tests

`go test ./...` n'a besoin d'aucun service : le code ne dépend que de l'interface `stockage.ClientS3`, que le faux client en mémoire `internal/stockage/stockagetest` implémente aussi bien que `*s3.Client`.

## Structure

```
cmd/medidoc/                 main : configuration, client S3, serveur HTTP, signaux
internal/config/             variables d'environnement
internal/stockage/           interface ClientS3, Depot (Enregistrer, Lire, Lister, Verifier), client S3
internal/stockage/stockagetest/  faux S3 en mémoire
internal/serveur/            routes HTTP, mesure, journal d'accès
```
