# Sécurité de la pile de supervision

| | |
|---|---|
| Ticket | SEC-2229 (M21-E29), demandé par Sophie Laurent |
| Périmètre | espace `supervision` (Prometheus, Alertmanager, Grafana, Thanos, Pyrra, opérateur), cibles hors cluster (node_exporter), témoin `mon01` |
| Revue | à chaque montée de version de kube-prometheus-stack, et au M24 (SSO) |

## Pourquoi c'est sensible

Les métriques ne contiennent pas de données de patients (règle des applications : jamais d'identifiant en étiquette), mais elles décrivent **toute** l'infrastructure : adresses, versions, charges, noms d'espaces et de pods, heures de sauvegarde. C'est une carte pour un attaquant. Grafana et Prometheus ont aussi des **pouvoirs** : l'API d'administration de Prometheus supprime des séries ; Grafana peut interroger toutes les sources ; Alertmanager peut taire une alerte (silence).

## Mesures

| Risque | Mesure | Où |
|---|---|---|
| Comptes créés par n'importe qui, accès anonyme | `users.allow_sign_up=false`, `auth.anonymous.enabled=false`, `allow_org_create=false`, nouveau compte en `Viewer` | `kps/values.yaml` (`grafana.ini`) |
| Vol de session | `cookie_secure`, `cookie_samesite=lax` (compatible avec l'OIDC du M24), sessions de 8 h d'inactivité / 24 h au plus, HSTS sur `grafana.apps…` | idem |
| Mots de passe faibles | `auth.basic.password_policy=true` | idem |
| Fuite par instantané public | `snapshots.external_enabled=false` | idem |
| Mot de passe `admin` éternel | rotation trimestrielle par `outils/grafana-rotation-admin.sh` (API, puis Vault et Secret) ; usage d'`admin` réservé au dépannage ; comptes nominatifs et équipes (E17) | `plateforme/k8s` |
| Suppression de séries, instantanés de la TSDB | API d'administration désactivée dans le cluster (`enableAdminAPI: false`) ; activée seulement sur le témoin de `mon01` (E44) | `kps/values.yaml` |
| Une équipe lit ou se fait passer pour une autre | `PrometheusRule` des équipes dans LEURS espaces, lus seulement s'ils portent `medisphere.internal/supervision-regles=oui` ; `enforcedNamespaceLabel: namespace` (sélecteurs et alertes forcés sur l'espace d'origine) ; plateforme exemptée (`excludedFromEnforcement`) ; écriture par Git seulement, lecture par RoleBinding | `kps/values.yaml`, `plateforme/k8s` |
| Accès réseau aux API sans authentification (Prometheus, Thanos Query, Alertmanager n'ont **pas** d'authentification) | Services `LoadBalancer` filtrés (MGMT et `mon01` seulement) ; espace `supervision` en refus par défaut en entrée **et** en sortie, flux listés | `kps/values.yaml`, `thanos/`, `pyrra/`, `reseau/` |
| Collecte des VMs en clair | node_exporter en TLS (certificat step-ca, E08), vérifié par Prometheus (`scheme: https`, autorité MédiSphère) | rôle `node_exporter`, ScrapeConfig `vms` |
| Interface Pyrra | lecture seule par nature, publiée par la Gateway ; pas d'authentification avant le M24 | `pyrra/` |

## Limites connues (acceptées jusqu'au M24)

- Prometheus, Thanos Query et Alertmanager restent **sans authentification** : toute machine de MGMT peut lire toutes les métriques et poser un silence. Mesure compensatoire : MGMT est le réseau d'administration (accès VPN nominatif). Au M24 : proxy d'authentification (OIDC) devant les trois interfaces.
- Authentification de node_exporter (basique ou certificat client) : non mise en place ; le TLS protège la confidentialité et l'intégrité, le pare-feu local limite les clients aux travailleurs.
- `sortie-commune` autorise tout l'espace `supervision` vers lui-même : le contrôle fin est fait à l'**entrée** de chaque composant.
