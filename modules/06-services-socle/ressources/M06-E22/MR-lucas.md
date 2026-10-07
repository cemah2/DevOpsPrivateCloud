# MR !12 — feat(dns): maquette du DNS de PAR2 (dns21)

**Auteur** : Lucas Martin · **Relecteurs demandés** : Karim Benali, toi

Bonjour,

Voici la config de `dns21`, le DNS de PAR2 en attendant la réplication. J'ai tout mis sur la même
VM pour faire simple : PowerDNS Authoritative pour `par2.medisphere.internal` et le Recursor pour les
clients de PAR2. Testé sur ma VM de la sandbox (`dig` OK sur la zone et sur Internet), **ça marche** !

Fichiers :
- `pdns.conf` → `/etc/powerdns/pdns.conf`
- `recursor.yml` → `/etc/powerdns/recursor.yml`
- `zone-par2.txt` : la zone telle que je l'ai créée (`pdnsutil zone list par2.medisphere.internal`)
- `ajouter-enregistrement.sh` : pour que la CI (runner01) ajoute des noms par l'API

Notes :
- J'ai mis l'API et l'écoute sur `0.0.0.0` parce qu'avec l'adresse précise ça ne démarrait pas sur
  ma VM de test (elle n'a pas 10.20.20.10, évidemment).
- J'ai désactivé la validation DNSSEC dans le récurseur : avec, `medisphere.internal` ne répondait plus
  (SERVFAIL). Sans, tout marche.
- J'ai mis un TTL de 60 s partout pour que les changements soient vus tout de suite.
- Pour Internet, j'ai mis 8.8.8.8 en amont : c'est plus rapide que la récursion depuis la racine.
- Le joker `*.par2` évite les erreurs quand quelqu'un se trompe dans un nom.
- Les logs de requêtes sont activés pour le debug, je les couperai plus tard.

Merci pour la relecture !
