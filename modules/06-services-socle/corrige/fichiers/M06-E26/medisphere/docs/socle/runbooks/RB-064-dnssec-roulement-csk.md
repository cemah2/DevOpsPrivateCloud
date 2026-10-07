# RB-064 — DNSSEC : rouler la clé de la zone interne (CSK) avec ancres de confiance

| | |
|---|---|
| Zone | `par1.medisphere.internal` (signée sur `dns01`, pré-signée sur `dns02`) |
| Clé | une CSK ECDSA P-256 (algorithme 13), créée par `pdnsutil zone secure` (M06-E26) |
| Confiance | ancres positives (`dnssec.trustanchors`) des récurseurs de `dns01` et `dns02`, variable `powerdns_recursor_ancres` (`group_vars/role_dns/dnssec.yml`) |
| Rédigé | M06-E26 (SEC-752) — **non exécuté** ; à rejouer d'abord sur une zone d'essai |
| Durée totale | au moins 2 × (TTL du DNSKEY + durée maximale de cache des récurseurs) ≈ 1 jour avec les valeurs du lab |

## Quand rouler

- Compromission (ou suspicion) de la base de `dns01` ou de ses sauvegardes : **roulement d'urgence** (§4).
- Changement d'algorithme : procédure différente (double signature), hors de ce runbook.
- Rythme planifié : annuel, inscrit au calendrier de l'équipe (décision de M06-E33).

## Pourquoi c'est délicat ici

La zone n'a pas de parent signé : la confiance vient **uniquement** des ancres configurées dans les récurseurs. Une ancre qui ne correspond à aucune clé publiée rend toute la zone *bogus* : SERVFAIL pour `git01`, `ca01`, `nbx01`… et pour l'ACME de `ca01`. Pendant le roulement, l'ancre doit donc contenir **les deux** DS (ancien et nouveau) tant que l'une ou l'autre clé peut être vue par un récurseur.

Valeurs à relever avant de commencer :

```
admin@dns01:~$ sudo -u pdns pdnsutil zone list-keys par1.medisphere.internal
admin@adm01:~$ dig +noall +answer @10.10.20.10 -p 5300 par1.medisphere.internal DNSKEY   # TTL du DNSKEY
```

`<ATTENTE>` = TTL du DNSKEY + `max_cache_ttl` du récurseur s'il est plus petit + marge (en pratique : TTL du DNSKEY + 1 h).

## Étapes (roulement planifié, méthode « pré-publication »)

1. **Préparer** : MR prête sur `plateforme/ansible`, instantanés de `dns01` et `dns02` (`ms-snapshot 1002 1008`), supervision (`ms-verif-services`) au vert.
2. **Créer la nouvelle clé, publiée mais inactive** (elle apparaît dans le DNSKEY, ne signe rien) :
   ```
   admin@dns01:~$ sudo -u pdns pdnsutil zone add-key par1.medisphere.internal ksk inactive published ecdsa256
   admin@dns01:~$ sudo -u pdns pdnsutil zone list-keys par1.medisphere.internal      # note l'ID et le keytag de la nouvelle
   admin@dns01:~$ sudo -u pdns pdnsutil zone increase-serial par1.medisphere.internal
   ```
   (Syntaxe 5.0 : vérifie l'ordre exact des arguments avec `pdnsutil zone add-key --help` ; depuis 5.0, `add-key` crée une KSK par défaut, ce qui est le rôle d'une CSK ici.)
3. **Vérifier la publication sur les deux serveurs** (`dig … DNSKEY` sur 10.10.20.10:5300 et 10.10.20.16:5300 : deux clés).
4. **Ajouter le nouveau DS à l'ancre**, sans retirer l'ancien (MR : `powerdns_recursor_ancres` contient les deux DS), pipeline, puis `sudo rec_control get-tas` sur les deux récurseurs.
5. **Attendre `<ATTENTE>`.**
6. **Basculer la signature** : activer la nouvelle clé, désactiver l'ancienne (elle reste publiée).
   ```
   admin@dns01:~$ sudo -u pdns pdnsutil zone activate-key par1.medisphere.internal <ID-NOUVELLE>
   admin@dns01:~$ sudo -u pdns pdnsutil zone deactivate-key par1.medisphere.internal <ID-ANCIENNE>
   admin@dns01:~$ sudo -u pdns pdnsutil zone increase-serial par1.medisphere.internal
   ```
   Contrôle : `dig +dnssec git01.par1.medisphere.internal` sur les deux récurseurs → drapeau `ad` ; le *keytag* des RRSIG est celui de la nouvelle clé.
7. **Attendre `<ATTENTE>`** (les RRSIG de l'ancienne clé sortent des caches).
8. **Retirer l'ancienne clé** (`pdnsutil zone remove-key par1.medisphere.internal <ID-ANCIENNE>`, `increase-serial`), puis **l'ancien DS** de l'ancre (MR, pipeline), dans cet ordre.
9. **Clore** : supervision au vert, instantanés supprimés, date et keytag notés dans l'historique.

## 4. Roulement d'urgence (clé compromise)

Pas de pré-publication possible sans laisser la clé compromise en service : on accepte une coupure.

1. Annoncer l'incident (INC) ; prévenir que la résolution de la zone peut échouer quelques minutes.
2. Créer et **activer** immédiatement la nouvelle clé, désactiver et dépublier l'ancienne.
3. Remplacer l'ancre par le **seul** nouveau DS sur les deux récurseurs (MR en urgence ou, à chaud, `rec_control clear-ta par1.medisphere.internal` puis `rec_control add-ta par1.medisphere.internal <DS>` — non persistant : la MR doit suivre).
4. Vider les caches : `sudo rec_control wipe-cache par1.medisphere.internal$` sur les deux récurseurs.
5. Vérifier comme à l'étape 6, puis traiter la cause (accès à la base, sauvegardes : RB-061).

## Retour arrière

Tant que l'ancienne clé est publiée et que son DS est dans l'ancre, revenir en arrière = réactiver l'ancienne clé et désactiver la nouvelle. Après l'étape 8, il n'y a plus de retour arrière : on refait un roulement.

## Historique

| Date | Auteur | Changement |
|---|---|---|
| AAAA-MM-JJ | <apprenant> | Création (M06-E26) |
