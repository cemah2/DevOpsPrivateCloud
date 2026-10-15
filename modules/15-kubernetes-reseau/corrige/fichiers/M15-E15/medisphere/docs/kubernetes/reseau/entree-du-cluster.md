# Entrée du cluster `k8s-par1` : publier une application

| | |
|---|---|
| **Portée** | Applications HTTP(S) et gRPC de `k8s-par1` publiées en `*.apps.par1.medisphere.internal` |
| **Propriétaire** | Équipe Plateforme |
| **Références** | DEV-1612, SEC-1613, PLAT-1614, DEV-1615 (M15-E12 à E15) ; RB-150, RB-151 ; ADR-0150 |

## Ce que fournit la plateforme

```
client ──DNS──▶ récurseurs dns01/dns02 ──▶ zone apps (dns01 primaire, dns02 secondaire, signée)
   │                                          ▲ ExternalDNS (RFC 2136, clé externaldns-k8s)
   │                                          ▲ cert-manager (TXT _acme-challenge, clé certmanager-k8s)
   └──HTTPS──▶ 10.10.41.10 (gw-par1, annoncée en BGP par k8s-w01..03)
                 écouteur https *.apps…  certificat joker apps-joker (ACME step-ca, 30 j)
                 écouteur http  :80      → 301 vers https (route redirection-https)
                     │
                     └──▶ HTTPRoute de l'équipe (son espace) ──▶ Service ──▶ pods
```

## Publier une application (équipe applicative)

1. **Espace autorisé** : l'espace doit porter l'étiquette `medisphere.internal/exposition: oui`. Elle est posée par la plateforme (MR sur `plateforme/k8s`, `espaces/`), pas par l'équipe.
2. **Route** dans ton espace :
   ```yaml
   apiVersion: gateway.networking.k8s.io/v1
   kind: HTTPRoute
   metadata: {name: <APPLICATION>, namespace: <ESPACE>}
   spec:
     parentRefs: [{name: gw-par1, namespace: passerelles, sectionName: https}]
     hostnames: [<APPLICATION>-<ENV>.apps.par1.medisphere.internal]
     rules:
       - backendRefs: [{name: <SERVICE>, port: <PORT>}]
   ```
3. **Nom** : publié automatiquement par ExternalDNS dans la minute (A vers 10.10.41.10 + TXT de propriété `k8s-par1`) ; retiré quand la route est supprimée.
4. **Certificat** : rien à faire, le joker couvre tout `*.apps…` (un seul niveau : `a.b.apps…` n'est pas couvert).
5. **Politiques** : autorise l'entrée depuis l'identité `ingress` de Cilium vers ton port (modèle : `espaces/mediagenda-recette/politiques/`).

## Ce qu'une équipe ne peut pas faire

- Publier un nom hors de `apps.par1.medisphere.internal` (filtre de domaine d'ExternalDNS, nom de l'écouteur).
- Créer sa propre Gateway publique (pas de droit sur `gateways` hors de `passerelles`, RBAC M14 ; pas d'adresse sans pool) ni utiliser le joker ailleurs que sur `gw-par1` (Secret dans `passerelles`, aucun `ReferenceGrant` vers lui).
- Écrire dans la zone DNS (clés TSIG détenues par la plateforme, valables pour la seule zone `apps`).

## Vérifier une publication

```
admin@adm01:~$ kubectl -n <ESPACE> get httproute <NOM> -o jsonpath='{.status.parents[*].conditions}' | jq
admin@adm01:~$ dig +short <NOM>.apps.par1.medisphere.internal                 # 10.10.41.10
admin@adm01:~$ curl -sS https://<NOM>.apps.par1.medisphere.internal/<SONDE>
admin@adm01:~$ kubectl -n external-dns logs deploy/external-dns --since=10m | jq -c 'select(.msg|test("record|Desired|Change"))'
```
