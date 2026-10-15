# Migration des Ingress d'InfoGér vers la Gateway API (PLAT-1618)

*Modèle de corrigé de M15-E18 — sortie réelle d'ingress2gateway 1.2.0 sur les fichiers fournis : [`sortie-brute.yaml`](sortie-brute.yaml), [`avertissements.txt`](avertissements.txt).*

## Conclusion pour Claire

- **7 Ingress, 5 applications, 32 annotations.** ingress2gateway en traduit **13 fidèlement** (41 %), **4 de travers** (délais, expressions régulières : 12 %), en **refuse 14** avec un avertissement (44 %) et en **perd 1 en silence** (délai de 3 600 s des flux gRPC).
- Ce qui passe sans effort : redirections (HTTPS, page d'accueil, ancien nom), canari par poids et par en-tête, gRPC, TLS de bout en bout.
- Ce qui demande une décision **par application** avant toute date : authentification (basique d'`admin`, SSO d'`dossier`), listes d'adresses, limites de débit, sessions collantes, extraits de configuration nginx. Aucun n'a d'équivalent dans la Gateway API v1.6 ; certains ont un équivalent **Cilium** (politiques L3/L7), d'autres doivent passer dans l'application ou disparaître.
- À demander aux équipes : (1) qui dépend de la casse des chemins (`/RDV`) ; (2) taille maximale réelle des pièces jointes du portail ; (3) pourquoi `dossier` veut à la fois le TLS de bout en bout **et** une session par cookie et un SSO devant (impossible : en *passthrough*, l'entrée ne voit ni cookie ni requête) ; (4) qui maintient le mot de passe commun d'`admin` (à supprimer : SSO au M24).
- Estimation : `portail`, `api-rdv`, `notif` migrables tout de suite (faits en essai) ; `admin` et `dossier` après le M24 (identité) ou une refonte de leur authentification.

## Annotations, Ingress par Ingress

Légende : **A** traduite fidèlement · **T** traduite de travers · **R** refusée (avertissement) · **S** perdue en silence.

| Ingress | Annotation | Rôle dans ingress-nginx | i2g | Équivalent MédiSphère |
|---|---|---|---|---|
| portail | `app-root: /accueil` | `/` exactement → 302 vers `/accueil` | A | règle `Exact /` + `RequestRedirect` `ReplaceFullPath` 302 |
| portail | `proxy-body-size: 20m` | refuse les corps > 20 Mo (413) | R | aucun champ Gateway API ; limite à porter par l'application (MédiDoc a `MEDIDOC_MAX_MB`) ; défaut de l'Envoy de Cilium à mesurer |
| portail | `ssl-redirect: "true"` | HTTP → HTTPS (308) | A | inutile par route : `redirection-https` de `gw-par1` (301) pour tout `*.apps` |
| portail | `proxy-read-timeout: "60"` | délai **entre deux lectures** du backend | T (10 min de délai **total**) | `timeouts.request` (délai total) : valeur à fixer avec l'équipe |
| portail-ancien-nom | `permanent-redirect` | renvoie une URL **fixe** (chemin perdu) | A | `RequestRedirect` `hostname` + `ReplaceFullPath` |
| portail-ancien-nom | `permanent-redirect-code: "308"` | code de la redirection | A | `statusCode: 308` |
| api-rdv | `use-regex: "true"` | chemins en expressions régulières **sans casse** | T (regex doublée `(?i)(?i)…​.*.*`) | `PathPrefix /rdv` ; différence de casse acceptée |
| api-rdv | `rewrite-target: /$2` | retire `/rdv` avant l'application | R (groupe de capture) | `URLRewrite` `ReplacePrefixMatch: /` |
| api-rdv | `limit-rps: "20"` | 20 requêtes/s par adresse source | R | pas dans la Gateway API ; Envoy (limite locale) par `CiliumEnvoyConfig` en « pour aller plus loin », ou dans l'application ; à défaut, risque accepté |
| api-rdv | `enable-cors` | répond aux pré-requêtes CORS | A (filtre `CORS`, standard en v1.6) | filtre `CORS` si Cilium 1.20 le prend en charge (**à vérifier**), sinon dans l'application (FastAPI `CORSMiddleware`) |
| api-rdv | `cors-allow-origin` | origine autorisée | A | idem |
| api-rdv | `proxy-read-timeout: "120"` | délai entre lectures | T (20 min total) | `timeouts.request: 120s` |
| api-rdv-canari | `canary: "true"` | Ingress « canari » fusionné avec celui de même nom/chemin | A | deux `backendRefs` pondérés dans la **même** règle |
| api-rdv-canari | `canary-weight: "20"` | 20 % vers v2 | A | `weight: 80` / `20` |
| api-rdv-canari | `canary-by-header` | en-tête qui force le canari | A | règle avec `headers` (plus prioritaire) |
| api-rdv-canari | `canary-by-header-value: v2` | valeur exacte | A | `type: Exact, value: v2` |
| api-rdv-canari | `use-regex` | idem api-rdv | T | idem |
| api-rdv-canari | `rewrite-target: /$2` | idem | R | idem (`URLRewrite` dans les deux règles) |
| admin | `kubernetes.io/ingress.class: nginx` | ancienne façon de choisir la classe | A (prise en compte) | sans objet (route attachée à `gw-par1`) |
| admin | `auth-type: basic` | authentification basique par nginx | R | **pas d'équivalent** dans la Gateway API ; SSO (OAuth2 Proxy, M24) ; en attendant, ne pas publier |
| admin | `auth-secret` | fichier htpasswd | R | idem (et mot de passe commun : à supprimer) |
| admin | `auth-realm` | libellé de la fenêtre | R | idem |
| admin | `whitelist-source-range` | adresses autorisées | R | `CiliumNetworkPolicy` sur le pod : `fromEntities: [ingress]` **ne voit pas** l'adresse du client (elle est dans `X-Forwarded-For`) ; filtrer avant la Gateway (non publié par `lb01`/`lb02`) ou dans l'application |
| admin | `configuration-snippet` | en-têtes `X-Frame-Options`, `X-Robots-Tag` | R | `ResponseHeaderModifier` (standard) : traduction **manuelle** facile ; et refus des *snippets* par principe (CVE-2025-1974 « IngressNightmare ») |
| notif-grpc | `backend-protocol: GRPC` | HTTP/2 vers le backend | A | `GRPCRoute` (+ `appProtocol: kubernetes.io/h2c` sur le Service) |
| notif-grpc | `proxy-read-timeout: "3600"` | flux de longue durée | S | aucun champ dans `GRPCRoute` v1 ; durée des flux selon l'Envoy de Cilium : à mesurer |
| dossier-patient | `ssl-passthrough: "true"` | TLS relayé sans déchiffrement | A (`TLSRoute` + écouteur `Passthrough`) | `TLSRoute` v1 ; Gateway ou écouteur dédié (essai E16) |
| dossier-patient | `affinity: cookie` | session collante par cookie | R | contradictoire avec le *passthrough* (cookie illisible) ; `sessionPersistence` n'existe que dans le canal **expérimental** ; à défaut, application sans état |
| dossier-patient | `session-cookie-name` | nom du cookie | R | idem |
| dossier-patient | `auth-url` | contrôle d'accès externe | R | contradictoire avec le *passthrough* ; SSO dans l'application (M24) |
| dossier-patient | `auth-signin` | page de connexion | R | idem |
| dossier-patient | `server-snippet` | `location /status { deny all; }` | R | en *passthrough*, rien n'est visible ; dans l'application |

## Ce qu'ingress2gateway produit et qu'on ne garde pas

- Une **Gateway par espace**, nommée `nginx`, classe `nginx`, avec un écouteur HTTP et un HTTPS **par nom** : MédiSphère a une Gateway partagée `gw-par1` (ADR-0150).
- Une route HTTP → HTTPS **par application** : déjà faite une fois pour toutes (`redirection-https`).
- Les références aux Secrets `*-tls` d'InfoGér, renouvelés à la main : le joker `apps-joker` (cert-manager) les remplace.
- Des délais « au mieux » (10 et 20 min) qui ne correspondent à rien dans la configuration d'origine.
- Pour `www.portail…`, un écouteur HTTP seul et l'avertissement « certificat auto-signé » : nginx servait ce nom en HTTPS avec un certificat par défaut ; chez nous, le joker le couvre (nom renommé en `www-portail-infoger.apps…`).

## Essais réalisés (wb-essais)

Routes : [`routes-migrees.yaml`](routes-migrees.yaml) ; script : [`essais-comportement.sh`](essais-comportement.sh). Résultats attendus : `portail /` → 302 `/accueil` ; ancien nom → 308 vers `https://portail-infoger.apps…/accueil` (chemin perdu, comme nginx) ; `api-rdv /rdv/hostname` → 200, répartition ≈ 80/20, 100 % v2 avec `X-Version-Rdv: v2` ; `/RDV/…` → 404 (nginx : 200) ; `notif` → `SERVING`.
