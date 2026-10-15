# Hubble : observer les flux de `k8s-par1`

> Aide-mémoire de l'équipe Plateforme et de l'astreinte — SEC-1605 (M15-E05). Hubble 1.20 (relay activé, interface web en M15-E26).

## Se connecter

```
admin@adm01:~$ cilium hubble port-forward &          # relay → localhost:4245 (laisser tourner)
admin@adm01:~$ hubble status                          # « Healthcheck (via localhost:4245): Ok », nœuds connectés 6/6
admin@adm01:~$ hubble list nodes
```

Chaque agent garde en mémoire les **derniers** flux de son nœud (4095 par défaut, tampon circulaire) : Hubble montre ce qui vient de se passer, ce n'est pas une archive. Pour un incident, observer **pendant** qu'on reproduit (`-f`), ou tout de suite après (`--last`).

## Filtres utiles

| Je cherche | Commande |
|---|---|
| Ce qui se passe dans un espace | `hubble observe -n wb-essais -f` |
| Ce qu'un pod émet / reçoit | `hubble observe --from-pod wb-essais/sonde-w01a` · `--to-pod wb-essais/echo-…` · `--pod wb-essais/sonde-w01a` (les deux sens) |
| Les refus | `hubble observe -n wb-essais --verdict DROPPED` |
| Les refus dus à une politique, avec le sens | `hubble observe -n wb-essais --type policy-verdict --verdict DROPPED` |
| Un port, un protocole | `--port 53` · `--to-port 8080` · `--protocol udp` · `--protocol http` |
| Le trafic vers l'extérieur du cluster | `hubble observe --to-label reserved:world` |
| Un nœud | `--node-name k8s-w01` |
| Les 50 derniers, en JSON | `--last 50 -o json` (puis `jq`) |
| Le nom du nœud qui a vu le flux | `--print-node-name` |

Lire une ligne : `horodatage`, `source (identité) -> destination (identité)`, `type` (`to-endpoint`, `to-stack`, `to-overlay`, `policy-verdict:…`, `drop`), verdict (`FORWARDED`, `DROPPED`, `ERROR`, `AUDIT`), et pour un refus la **raison** (`Policy denied`, `Service backend not found`…). Une même connexion apparaît plusieurs fois : une ligne par point d'observation (sortie du pod, tunnel, entrée du pod de destination).

## Ce que Hubble voit, et ce qu'il ne voit pas

- **Toujours** : L3/L4 (adresses, identités, ports, drapeaux TCP), verdicts des politiques, refus du plan de données.
- **Seulement si une politique L7 s'applique** : requêtes HTTP (méthode, URL, code, latence), questions et réponses DNS (politique avec `rules.dns`), Kafka. Sans politique L7, une requête HTTP n'est qu'un flux TCP vers le port 8080.
- **Jamais** : le contenu des corps de requête, le trafic du réseau des nœuds qui n'implique aucun pod.

## Rédaction des champs sensibles (HDS)

Réglée dans `composants/cilium/values.yaml` de `plateforme/k8s` (`hubble.redact`) : paramètres d'URL (`?patient=…` : la chaîne de requête est retirée de l'URL), mot de passe des informations d'utilisateur (`user:mot-de-passe@`) et valeur des en-têtes `Authorization`, `Proxy-Authorization`, `Cookie`, `Set-Cookie`, `X-Api-Key` remplacés par `HUBBLE_REDACTED` dans les flux L7. Vérification : `hubble observe --protocol http -o json | jq '.flow.l7.http'` sur une requête de test portant ces champs.

Limites : les **chemins** d'URL ne sont pas rédigés (une API qui met un identifiant de patient dans le chemin le laisse voir) ; l'adresse source des clients reste visible. Règle MédiSphère : pas d'identifiant de patient dans les chemins des API (à vérifier en revue d'API) ; les flux ne quittent pas le cluster tant que l'export vers la supervision (M21-M22) n'a pas été validé par la RSSI.

## Pièges

- `hubble observe` sans `-n` ni filtre : des milliers de lignes de santé (`lxc_health`, sondes du kubelet). Filtrer d'abord.
- « Je ne vois pas mon flux » : le pod est-il sur un nœud dont l'agent est sain (`hubble list nodes`) ? Le flux est-il plus ancien que le tampon ?
- Un `DROPPED` avec `Policy denied` en **sortie** du client et rien côté serveur : c'est la politique de sortie du client, pas celle du serveur.
