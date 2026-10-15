# Durcissement de l'entrée de `k8s-par1`

| | |
|---|---|
| Ticket | SEC-1633 |
| Exercice | M15-E33 |
| Dernière revue | <DATE> |

## 1. Constat TLS de `gw-par1` (depuis `adm01`)

| Essai | Résultat |
|---|---|
| `openssl s_client -connect 10.10.41.10:443 -servername mediagenda-recette.apps.par1.medisphere.internal -tls1` | refus (`no protocols available` / alerte `protocol version`) |
| `… -tls1_1` | refus |
| `… -tls1_2` | accepté ; suites ECDHE uniquement (AES-GCM, ChaCha20-Poly1305) |
| `… -tls1_3` | accepté |
| chaîne | feuille `*.apps.par1.medisphere.internal` + intermédiaire MédiSphère ; vérifiée contre la racine |
| ALPN | `http/1.1` (h2 seulement si `gatewayAPI.enableAlpn`) |

Ces valeurs sont les **défauts d'Envoy** pour un serveur (TLS 1.2 minimum, 1.3 maximum, suites modernes) : Cilium
1.20 ne les change pas et n'expose aucun réglage par la Gateway API. La cible de la politique M06-E33 est atteinte
sans configuration ; elle devra être **revérifiée à chaque mise à jour** de Cilium (RB-153), puisqu'elle dépend d'un
défaut et non d'un réglage.

## 2. Ce que Cilium 1.20 supporte (Gateway API v1.6)

| Mécanisme | Rôle | Canal | Cilium 1.20 | Preuve |
|---|---|---|---|---|
| `listeners[].tls.options` | réglages TLS propres à l'implémentation (versions, suites…) | standard (champ libre) | **ignoré** : aucune option reconnue | essai sur `gw-essai` avec une option de version minimale : objet accepté, comportement inchangé (`openssl -tls1_2` toujours négocié avec la même suite, aucun effet visible) |
| `spec.tls.frontend` (GEP-91) | validation du certificat **client** à la Gateway (`caCertificateRefs`, `mode`) | standard en v1.6 | **non implémenté** | essai sur `gw-essai` : la Gateway est acceptée, aucun certificat client n'est demandé (`openssl s_client` sans `-cert` termine la négociation) ; la GatewayClass `cilium` ne liste pas la fonctionnalité dans `status.supportedFeatures` (à relire sur ta version) |
| `BackendTLSPolicy` | TLS **Gateway → application** (la Gateway vérifie le certificat du Service : `caCertificateRefs`, `hostname`) | standard (v1) | **implémenté** (page *BackendTLSPolicy Example* de la documentation 1.20) | non utilisé ici : ne répond pas au besoin des partenaires |
| `spec.tls.backend.clientCertificateRef` | certificat client présenté **par la Gateway** aux applications | standard en v1.6 | non implémenté (à vérifier) | — |
| `TLSRoute` en *passthrough* | relayer le flux TLS par SNI sans le terminer | standard (v1) | **implémenté** | `gw-partenaires` |

Conséquence : l'authentification mutuelle des partenaires se fait **derrière** la Gateway, par un relais qui termine
le TLS lui-même. À revoir à chaque mineure de Cilium (ADR-0150).

## 3. En-têtes de sécurité (route `mediagenda`)

Filtre `ResponseHeaderModifier` sur chaque règle de la route : `Strict-Transport-Security: max-age=31536000;
includeSubDomains`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`, `X-Frame-Options: DENY`.
Vérification : `curl -sI https://mediagenda-recette.apps.par1.medisphere.internal/sante`. La redirection HTTP → HTTPS
de `gw-par1` (E12) est inchangée (`curl -sI http://…` → 301 vers `https://…`). Pas de `preload` (domaine interne).

## 4. API des centres partenaires

```
partenaire ──TLS mutuel──> 10.10.41.11:443 gw-partenaires (Envoy, SNI, passthrough)
                                 └──flux TLS intact──> relais-mtls:443 (nginx, mediagenda-recette)
                                        vérifie le certificat client (autorité « MédiSphère Partenaires » seule)
                                        └──HTTP + X-Partenaire: <CN>──> API MédiAgenda:8000
```

- Nom : `mediagenda-partenaires.apps.par1.medisphere.internal` → 10.10.41.11 (ExternalDNS, source `service`, annotation recopiée par Cilium depuis `spec.infrastructure`).
- Certificat serveur du relais : cert-manager, `step-ca-acme`, défi DNS-01 (le nom ne pointe pas vers `gw-par1`).
- Autorité des partenaires : `outils/ca-partenaires.sh` de `plateforme/k8s` ; clé en Vault `critique` et en 600 sur `adm01`. L'autorité MédiSphère (`ca01`) n'est **pas** acceptée : un certificat serveur émis par `ca01` porte aussi l'usage `clientAuth` et ouvrirait l'API.
- Refus : nginx termine la négociation TLS puis répond **400** (pas de certificat, ou certificat non reconnu) ; aucune requête n'atteint l'API. Avec `ssl_verify_client on`, ce comportement est celui de nginx (documentation du module `ngx_http_ssl_module`).
- En-tête d'identité `X-Partenaire` **écrasé** par le relais (`proxy_set_header`) : un client ne peut pas l'imposer. L'API ne peut être jointe que par le relais et la Gateway (politiques `relais-mtls`, `relais-mtls-vers-api`, E17).
- Source vue par l'API : Envoy, puis le relais (TLS *passthrough*) : l'adresse du partenaire n'est connue que par le journal d'Envoy ; l'identité, elle, est certaine (certificat).

## 5. Procédures

**Nouveau partenaire** : ticket signé par Julien Petit (contrat) → `outils/ca-partenaires.sh emettre <centre>` →
remise du certificat et de la clé par un canal chiffré (ou mieux : le partenaire envoie une CSR, à mettre en place)
→ suppression des fichiers d'`adm01` → registre des partenaires (`docs/kubernetes/reseau/partenaires.md`).

**Retrait** : pas de liste de révocation dans nginx dans ce montage. Le certificat dure **30 jours** ; on ne le
renouvelle plus. Retrait d'urgence : nouvelle autorité, nouvelle ConfigMap `ca-partenaires`, réémission pour les
autres centres (≈ 1 h). Amélioration : liste de révocation (`ssl_crl`) produite par l'autorité, ou autorité gérée
par Vault PKI (module 25).

## 6. Vérifications (depuis `adm01`)

```
admin@adm01:~$ N=mediagenda-partenaires.apps.par1.medisphere.internal
admin@adm01:~$ curl -s -o /dev/null -w '%{http_code}\n' https://$N/sante                                  # 400 « No required SSL certificate was sent »
admin@adm01:~$ curl -s -w '%{http_code}\n' --cert ~/.config/workbook/partenaire-centre-test-01.crt \
    --key ~/.config/workbook/partenaire-centre-test-01.key https://$N/sante                                 # 200
admin@adm01:~$ curl -s -o /dev/null -w '%{http_code}\n' --cert <CERT-EMIS-PAR-CA01> --key <CLE> https://$N/sante   # 400 « The SSL certificate error » : refusé
```
