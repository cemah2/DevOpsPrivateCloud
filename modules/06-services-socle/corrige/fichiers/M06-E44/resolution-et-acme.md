# Analyse : une résolution DNS et une émission ACME pas à pas

> Compte rendu de référence pour M06-E44 (`docs/socle/analyses/resolution-et-acme.md`). Les extraits sont **représentatifs** : identifiants de requête, TTL, *nonces*, empreintes et horodatages diffèrent sur ton lab. Ce qui compte est la structure et les annotations.

Date des mesures : AAAA-MM-JJ. Versions : PowerDNS Recursor 5.4.x, Authoritative 5.0.x, step-ca 0.30.x, step CLI 0.31.x.

## Résolution DNS

### Schéma

```
adm01 ──UDP/53──▶ dns01 : pdns-recursor (10.10.20.10:53)
                     │  zone relayée par1.medisphere.internal (forward_zones, RD=0)
                     ├──UDP/5300 (lo)──▶ pdns (127.0.0.1:5300, gsqlite3, signature à la volée)
                     │  autres zones : résolution itérative
                     └──UDP/53──▶ racine ▶ TLD ▶ serveurs du domaine (+ DS/DNSKEY pour valider)
```

### Nom interne, à froid (`nbx01.par1.medisphere.internal`)

```
root@dns01:~# tcpdump -ni lo -vv port 5300
… 127.0.0.1.41022 > 127.0.0.1.5300: 18341 [1au] A? nbx01.par1.medisphere.internal. ar: . OPT UDPsize=1232 OK (79)
… 127.0.0.1.5300 > 127.0.0.1.41022: 18341*- 2/0/1 nbx01.par1.medisphere.internal. A 10.10.20.13, nbx01.par1.medisphere.internal. RRSIG (…)
… 127.0.0.1.38170 > 127.0.0.1.5300: 5530 [1au] DNSKEY? par1.medisphere.internal. ar: . OPT UDPsize=1232 OK (66)
… 127.0.0.1.5300 > 127.0.0.1.38170: 5530*- 2/0/1 par1.medisphere.internal. DNSKEY, par1.medisphere.internal. RRSIG (…)
```

Annotations :
- `[1au]` : un enregistrement additionnel (l'OPT d'EDNS) ; **pas de `+`** après l'identifiant : RD=0, question non récursive (zone de `forward_zones`).
- `OK` dans l'OPT : bit DO, le récurseur demande les signatures pour valider.
- `*-` dans la réponse : `*` = réponse faisant autorité (AA).
- La seconde question (DNSKEY) n'existe que parce que la validation est active : le récurseur vérifie l'ensemble DNSKEY contre son ancre (DS), puis la RRSIG du A contre ce DNSKEY.

À chaud : aucun paquet sur le port 5300 ; `dig` montre un TTL diminué (réponse du cache).

### Nom d'Internet, à froid

Trace du récurseur (`rec_control trace-regex`) : `.` (NS en cache) → serveurs du TLD (référral + DS du domaine) → serveurs du domaine (réponse + RRSIG), DNSKEY de chaque niveau validés en chaîne. Pour un nom inexistant : `NXDOMAIN` + NSEC3 (et RRSIG) prouvant l'absence ; `delv` : `; negative response, fully validated`.

### Cache négatif

`dig @10.10.20.10 nexiste-pas.par1.medisphere.internal` : SOA en autorité avec un TTL qui décroît entre deux requêtes ; valeur de départ = min(TTL du SOA, champ *minimum* du SOA), plafonnée par `recordcache.max_negative_ttl` (3600 s).

## Émission ACME

### Séquence

```
step CLI (ca01)                        step-ca (ca01:443)                 step CLI autonome (ca01:80)
  GET  /acme/acme/directory  ───────▶
  HEAD /acme/acme/new-nonce  ───────▶  Replay-Nonce
  POST /acme/acme/new-account (JWS) ─▶ compte (kid)
  POST /acme/acme/new-order   (JWS) ─▶ order: identifiers, authorizations, finalize
  POST …/authz/<id>           (JWS) ─▶ défi http-01 : token
  POST …/challenge/<id>       (JWS) ─▶ step-ca résout ca01.par1… ─▶ GET /.well-known/acme-challenge/<token> ─▶ token.empreinte_clé_compte
  POST …/order/<id>/finalize  (CSR) ─▶ certificat émis
  POST …/certificate/<id>     (JWS) ─▶ chaîne (feuille + intermédiaire)
```

### Journal de step-ca (extrait annoté)

```
… "method":"POST","path":"/acme/acme/new-order","status":201 …           ← newOrder (RFC 8555 §7.4)
… "method":"POST","path":"/acme/acme/challenge/…","status":200 …         ← le client signale qu'il est prêt (§7.5.1)
… "method":"POST","path":"/acme/acme/order/…/finalize","status":200 …    ← finalize avec la CSR (§7.4)
```

Capture du port 80 sur `lo` : `GET /.well-known/acme-challenge/<token>` venant de step-ca, réponse `200` de `step` contenant `<token>.<empreinte JWK du compte>` (§8.3).

### Certificat obtenu

`step certificate inspect --short` : sujet et SAN `ca01.par1.medisphere.internal`, émetteur « MédiSphère Intermediate CA », validité = durée par défaut du provisioner `acme` (24 h si `defaultTLSCertDuration` n'est pas fixé), EKU `serverAuth, clientAuth`. Fichiers supprimés après l'essai.

## Réponses aux questions

1. RD=0 vers un autoritaire (`forward_zones`) ; RD=1 avec `forward_zones_recurse` (relais récursif).
2. Ancre locale `dnssec.trustanchors` ; sans ancre ni NTA, la racine prouve l'absence de `internal.` et la validation échoue.
3. Environ 6 à 12 requêtes à froid, 0 à chaud ; RFC 8198 : réponses négatives synthétisées depuis des NSEC/NSEC3 validés en cache.
4. *Nonce* contre le rejeu ; JWS lie chaque requête à la clé du compte.
5. step-ca → nom résolu → port 80 ; `tls-alpn-01` sans HTTP, `dns-01` pour un générique.
6. Fenêtre d'abus courte, renouvellement comme révocation passive ; CRL/OCSP secondaires.
7. Trace du récurseur : E35 (relais 5301, question partie vers la racine), E41 (`Bogus` et raison) ; journal ACME : défi `http-01` qui échoue (origine d'une expiration, E37).
