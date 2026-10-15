# Publier une application sur `k8s-par1`

| | |
|---|---|
| **Pour qui** | équipes de développement (MédiAgenda, MédiDoc, …) |
| **Ce que vous obtenez sans ticket** | un nom `<application>-<environnement>.apps.par1.medisphere.internal`, un certificat valide (joker de la zone), une adresse joignable depuis le réseau d'administration de MédiSphère |
| **Contact** | équipe Plateforme (ticket `PLAT-`) |

> Modèle de corrigé, vérifié sur `medidoc-dev` (M15-E34). Adapte les noms.

## Prérequis (une fois par espace, par l'équipe Plateforme)

L'espace porte l'étiquette `medisphere.internal/exposition: oui` (posée par `plateforme/k8s/espaces/`) : sans elle, la Gateway refuse vos routes (condition `NotAllowedByListeners`).

## Ce que vous écrivez

1. Une **HTTPRoute** attachée à la Gateway `passerelles/gw-par1`, écouteur HTTPS :

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: medidoc
  namespace: medidoc-dev
spec:
  parentRefs:
    - name: gw-par1
      namespace: passerelles
      sectionName: https
  hostnames:
    - medidoc-dev.apps.par1.medisphere.internal
  rules:
    - backendRefs:
        - name: medidoc
          port: 80
```

2. Une **politique d'entrée** qui autorise la Gateway (identité réservée `ingress` de Cilium) vers vos pods, sur le port de l'application (l'espace est fermé par défaut) :

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: depuis-gateway
  namespace: medidoc-dev
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: medidoc
  ingress:
    - fromEntities: [ingress]
      toPorts:
        - ports: [{port: "8080", protocol: TCP}]
```

## Ce qui se passe ensuite

- Moins d'une minute : la route est acceptée (`kubectl get httproute -o wide`, colonne et conditions `Accepted`).
- Une à deux minutes : ExternalDNS publie le nom (`dig medidoc-dev.apps.par1.medisphere.internal`).
- Aussitôt : le certificat joker de la Gateway couvre le nom (`curl -v https://…`).

## Ce qui exige un ticket

Un nom hors de `*.apps.par1.medisphere.internal` ; un certificat propre à l'application ; le passage TLS direct (`TLSRoute`) ou l'authentification mutuelle ; une exposition hors du lab par `lb01`/`lb02` ; une sortie vers Internet (`toFQDNs`) ; un Service `LoadBalancer` dédié.

## Si ça ne marche pas

`kubectl describe httproute <route>` (conditions et raisons), puis RB-150. Ne supprimez jamais la politique `refus-par-defaut` de votre espace.
