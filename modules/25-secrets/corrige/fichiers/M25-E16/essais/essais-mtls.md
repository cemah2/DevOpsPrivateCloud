# M25-E16 — Essais du TLS mutuel (modèle ; aucun fichier de clé recopié)

| Essai | Commande (résumé) | Résultat |
|---|---|---|
| Rôle : nom hors `svc` | `bao write pki-services/sign/services-k8s csr=@x.csr` (CN `evil.example.com`) | refusé : `common name evil.example.com not allowed by this role` |
| Rôle : adresse IP | CSR avec SAN `IP:10.10.41.70` | refusé : `IP Subject Alternative Names are not allowed in this role, but was provided via CSR` |
| Rôle : 100 h | `ttl=100h` | **accepté, réduit à 72 h** avec l'avertissement « TTL … is longer than permitted maxTTL … so maxTTL is being used » |
| De bout en bout | `POST /api/v1/rendez-vous/<id>/pieces-jointes` sur la recette | 201 ; journal du relais de MédiDoc : connexion de `mediagenda.mediagenda-recette.svc` |
| Sans certificat | pod d'essai dans `mediagenda-recette` (étiquette `app.kubernetes.io/name: mediagenda`, image `curlimages/curl` par Harbor) : `curl -sk https://medidoc.medidoc-recette.svc.cluster.local:8443/readyz` | échec de la poignée de main TLS (`alert certificate required` / `handshake failure`) |
| Révocation | `bao write pki-services/revoke serial_number=<série de mediagenda-mtls>` puis `bao read pki-services/crl/rotate` | la série est dans la CRL (`openssl crl -text`) ; **les appels continuent** : ghostunnel ne lit pas la CRL |
