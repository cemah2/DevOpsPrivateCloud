# Matrice des flux de MédiAgenda (`mediagenda-dev`, `mediagenda-recette`)

| | |
|---|---|
| **Portée** | Flux réseau des pods de MédiAgenda ; ce qui n'est pas ici est refusé |
| **Références** | SEC-1617 (M15-E17) ; politiques : `plateforme/k8s` `espaces/politiques-mediagenda/` |
| **Revue** | à chaque nouvelle dépendance de l'application (MR qui modifie ce fichier ET les politiques) |

| # | Source | Destination | Port | Protocole / L7 | Justification | Politique |
|---|---|---|---|---|---|---|
| 1 | tous les pods de l'espace | CoreDNS (`kube-system`, `k8s-app=kube-dns`) | 53 | UDP, TCP | résolution des Services (`postgresql`, `valkey`) | `sortie-dns` |
| 2 | Gateway `gw-par1` (identité `ingress`) | `mediagenda-api` | 8000 | HTTP : `GET /sante`, `GET /pret`, `GET`/`POST /api/v1/rendez-vous`, `GET`/`DELETE /api/v1/rendez-vous/{id}`, `GET /api/v1/creneaux` | API publique de l'application | `api-entree` (CNP, L7) |
| 3 | kubelet du nœud (identité `host`) | `mediagenda-api` | 8000 | HTTP : `GET /sante`, `GET /pret` | sondes de vivacité et de disponibilité | `api-entree` |
| 4 | `mediagenda-api` | `postgresql` (même espace) | 5432 | TCP | données des rendez-vous | `api-vers-donnees`, `postgresql-depuis-api` |
| 5 | `mediagenda-api` | `valkey` (même espace) | 6379 | TCP | cache des créneaux | `api-vers-donnees`, `valkey-depuis-api` |

**Refusé explicitement (essais de la MR)** : `/metrics` depuis la Gateway (403) ; toute méthode ou tout chemin hors de la ligne 2 (403) ; tout pod d'un autre espace vers PostgreSQL, Valkey ou l'API ; toute sortie hors du cluster (aucune n'est nécessaire aujourd'hui).

**À venir** : Prometheus (M21) lira `/metrics` depuis son espace (ligne à ajouter, source par étiquette d'espace) ; sauvegardes PostgreSQL (M16, CloudNativePG) vers `s3-01` (sortie `toFQDNs` à ajouter).
