# Segmentation du cluster `k8s-par1` entre équipes

| | |
|---|---|
| Ticket | SEC-1628 |
| Exercice | M15-E28 |
| Dernière revue | <DATE> |

## Règles (Sophie Laurent)

1. Aucun pod d'un espace d'équipe ne reçoit de connexion d'un pod d'un **autre** espace d'équipe, ni n'en ouvre vers lui, même entre deux espaces de la même équipe.
2. Cette règle ne peut pas être levée depuis un espace d'équipe.
3. Sortie Internet de MédiAgenda limitée à `calendrier.api.gouv.fr` (HTTPS) ; MédiDoc ne sort pas sur Internet.
4. Les espaces de plateforme ne sont pas concernés par la règle 1.

## Politiques qui les portent (`plateforme/k8s`, `composants/reseau/politiques/`)

| Politique (cluster) | Règle | Mécanisme |
|---|---|---|
| `base-dns` | prérequis de 3 | DNS de tous les pods (hors `kube-system`) par le proxy DNS, `enableDefaultDeny` à `false` |
| `isolement-mediagenda-dev`, `isolement-mediagenda-recette`, `isolement-medidoc-dev` | 1, 2 | `ingressDeny` et `egressDeny` vers les pods d'espaces portant `medisphere.fr/equipe`, sauf le sien ; un refus l'emporte sur toute autorisation |
| `sortie-mediagenda` | 3 | `toFQDNs` `calendrier.api.gouv.fr`, port 443 ; le reste d'Internet reste refusé par le refus par défaut de M15-E17 |
| (aucune pour MédiDoc) | 3 | refus par défaut de l'espace (M15-E34) : aucune règle vers `world` |

Label d'appartenance : `medisphere.fr/equipe: <équipe>` sur les Namespace, posé par `espaces/` de `plateforme/k8s`.
Les équipes ne créent ni ne modifient de politique Cilium ni de Namespace (RBAC du M14 :
`kubectl auth can-i create ciliumnetworkpolicies -n mediagenda-dev --as julien.petit --as-group medisphere:mediagenda-devs` → `no`).

## Matrice de tests (sondes `netshoot`, M15-E28)

| # | Source | Destination | Attendu | Obtenu | Raison lue dans Hubble |
|---|---|---|---|---|---|
| 1 | `mediagenda-dev/sonde` | PostgreSQL de `mediagenda-recette` (5432) | refus | refus | `Policy denied by denylist` |
| 2 | `medidoc-dev/sonde` | API de `mediagenda-recette` (8000) | refus | refus | `Policy denied by denylist` |
| 3 | API de `mediagenda-recette` | son PostgreSQL | accepté | accepté | — |
| 4 | Gateway (`ingress`) | API de `mediagenda-recette` | accepté | accepté | — |
| 5 | `wb-essais` | API de `mediagenda-recette` | refus | refus | `Policy denied` (refus par défaut, pas la cloison : `wb-essais` n'est pas un espace d'équipe) |
| 6 | `mediagenda-dev/sonde` → recette **avec** `tout-autoriser-test` posée | API de recette | refus | refus | `Policy denied by denylist` : la cloison tient (règle 2) |
| 7 | `mediagenda-recette/sonde` (label `app=sonde`) | `https://calendrier.api.gouv.fr` | selon E17 : les sondes n'ont que le DNS | refus | `Policy denied` |
| 8 | API de `mediagenda-recette` | `https://calendrier.api.gouv.fr/jours-feries/metropole.json` | accepté | 200 | — |
| 9 | API de `mediagenda-recette` | `https://example.com` | refus | délai dépassé | `Policy denied` |
| 10 | API de `mediagenda-recette` | IP en dur de `calendrier.api.gouv.fr` sans résolution préalable par le pod | refus si l'IP n'est pas apprise | refus après expiration de l'entrée | `Policy denied` |

Note sur 7-10 : `toFQDNs` n'autorise une adresse que pour le pod qui l'a **résolue** à travers le proxy. Le
test 10 passe si le pod a résolu le nom juste avant (l'adresse est alors dans son cache FQDN) : ce n'est pas
une faille, c'est le fonctionnement documenté.

## Changement d'adresse de l'API publique

Les adresses apprises suivent le TTL des réponses DNS (avec un minimum réglable, `dnsProxy.minTtl` du chart,
à vérifier sur ta version). Une connexion ouverte n'est pas coupée à l'expiration de l'entrée : elle se termine
normalement. Une application qui garde une résolution plus longtemps que le TTL se verra refuser la
connexion suivante : il faut qu'elle respecte le TTL (ou passe par le résolveur à chaque connexion).

## Ajouter une équipe

Une MR sur `plateforme/k8s` : Namespace avec le label `medisphere.fr/equipe`, fichier
`isolement-<espace>.yaml` (copie du modèle), éventuellement une politique de sortie par noms. Revue par
l'équipe Plateforme et la RSSI.

## Limites

- Pods en réseau de l'hôte (`hostNetwork`) : identité `host`, non couverts (interdits par le PSA `restricted` dans les espaces d'équipe).
- Flux vers la bordure et le reste du lab (`s3-01`, `reg01`…) : régis par les politiques de chaque espace et la matrice de la bordure, pas par la cloison.
- Un administrateur du cluster peut supprimer une politique de cluster : traçabilité par l'audit de l'API (M14-E27) et par Git.
- L'adresse source vers Internet est celle du nœud (masquage) : un partenaire ne peut pas filtrer « MédiAgenda » ; c'est l'objet de l'Egress Gateway (pour aller plus loin).
