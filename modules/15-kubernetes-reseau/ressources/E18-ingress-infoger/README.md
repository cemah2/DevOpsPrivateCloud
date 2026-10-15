# Exposition des applications — clusters InfoGér (export du 12/02/2026)

Export des objets `Ingress` des clusters « prod-a » et « prod-b » gérés par InfoGér pour MédiSphère.
Contrôleur : ingress-nginx (classe `nginx`), version « récente ».

| Fichier | Application | Remarques InfoGér |
|---|---|---|
| `01-portail.yaml` | portail patients | page d'accueil sur /accueil, envoi de pièces jointes |
| `02-portail-ancien-nom.yaml` | ancien nom du portail | à garder « quelque temps » |
| `03-api-rdv.yaml` | API rendez-vous (v1) | préfixe /rdv retiré avant l'application |
| `04-api-rdv-canari.yaml` | API rendez-vous (v2) | 20 % du trafic, ou en-tête pour les testeurs |
| `05-admin.yaml` | console d'administration | mot de passe commun de l'équipe, réseau interne seulement |
| `06-notif-grpc.yaml` | notifications (gRPC) | |
| `07-dossier-patient.yaml` | dossier patient | TLS jusqu'à l'application (exigence client), session collante, SSO |

Les certificats sont dans les Secrets `*-tls` de chaque espace (renouvelés à la main, voir procédure interne).
Le Secret `admin-htpasswd` est généré par le script `gen-htpasswd.sh` (non fourni).
