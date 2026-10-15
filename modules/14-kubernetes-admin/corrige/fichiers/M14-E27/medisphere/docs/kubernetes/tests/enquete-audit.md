# Enquête SEC-1527 — suppression de `mediagenda-dev/rdv-essai-audit`

> Modèle de réponse (M14-E27). Les valeurs entre chevrons viennent de **tes** journaux.

## Réponse au ticket

Le Deployment `mediagenda-dev/rdv-essai-audit` a été supprimé le <AAAA-MM-JJ> à <HH:MM:SS> UTC par l'identité **`<julien.petit | MOI>`** (groupes `<medisphere:mediagenda-devs, system:authenticated>`), avec `kubectl` (`userAgent` : `<kubectl/v1.36.5 (linux/amd64) kubernetes/…>`), requête reçue par le serveur d'API de **`<k8s-cp0N>`**, réponse `200`. Identifiant d'audit : `<auditID>`.

## Preuve

```
admin@adm01:~$ for n in k8s-cp01 k8s-cp02 k8s-cp03; do
>   ssh $n "sudo zcat -f /var/log/kubernetes/audit/audit*.log*" \
>   | jq -c --arg n "$n" 'select(.verb == "delete" and .objectRef.resource == "deployments"
>        and .objectRef.namespace == "mediagenda-dev" and .objectRef.name == "rdv-essai-audit")
>        | {noeud: $n, heure: .requestReceivedTimestamp, qui: .user.username, groupes: .user.groups,
>           via: .impersonatedUser, ip: .sourceIPs, client: .userAgent, code: .responseStatus.code, id: .auditID}'
> done
```

Résultat : un seul événement, sur un seul des trois nœuds (la VIP envoie chaque requête à un serveur d'API).

Création par les deux identités (contexte) : même filtre avec `.verb == "create"`.

## Vérification du niveau des Secrets

```
admin@adm01:~$ ssh k8s-cp01 "sudo zcat -f /var/log/kubernetes/audit/audit*.log*" \
>   | jq -c 'select(.objectRef.resource == "secrets" and .objectRef.name == "temoin-audit")
>            | {verb, level, a_requete: has("requestObject"), a_reponse: has("responseObject")}'
{"verb":"create","level":"Metadata","a_requete":false,"a_reponse":false}
```

## Ce que cette preuve ne dit pas

- **Qui est derrière l'identité** : un certificat client se copie. Si la clé privée de `julien.petit` a été copiée, l'audit montre « julien.petit ». D'où les certificats courts (E12) et la fédération d'identité au module 24 (Keycloak, MFA).
- **`admin.conf` et `super-admin.conf`** : une suppression par ces kubeconfigs apparaît sous `kubernetes-admin` (groupe `kubeadm:cluster-admins`, ou `system:masters`) : personne en particulier. Leur usage est un bris de glace, tracé à part (registre, ticket).
- **L'adresse source** : HAProxy relaie en mode TCP et ouvre sa propre connexion vers le serveur d'API ; le serveur d'API ne parle pas le protocole PROXY. `sourceIPs` montre donc l'adresse du nœud de contrôle qui porte la VIP (10.10.40.5x), pas celle du poste. Pour retrouver le poste, il faut croiser avec le journal de HAProxy (adresse client, heure, port) — ou se connecter directement au port 6443 d'un nœud, ce que la matrice des flux ne permet qu'à `adm01`.
- **Les actions hors API** : un administrateur root d'un nœud de contrôle peut écrire directement dans etcd (avec les certificats d'etcd) sans passer par l'audit.
- **Au-delà de la rétention locale** (30 jours au plus, moins si le volume est fort) : les journaux sont perdus jusqu'à la centralisation (module 22).

## Mesure du volume (30 minutes)

| Nœud | Taille produite | Événements | Premier émetteur |
|---|---|---|---|
| k8s-cp01 | <… Mo> | <…> | <ex. system:serviceaccount:kube-system:cilium-operator> |
| k8s-cp02 | | | |
| k8s-cp03 | | | |

Répartition : `jq -r '.user.username' | sort | uniq -c | sort -rn | head` et `jq -r '.objectRef.resource // .requestURI' | sort | uniq -c | sort -rn | head`.
