## 1.2.0 (M08-E02)

### Ajouts
- `ca_lab` : prise en charge de la famille Red Hat (Rocky Linux 10) : ancres dans
  `/etc/pki/ca-trust/source/anchors/`, magasin reconstruit par `update-ca-trust extract`,
  vérification dans `/etc/pki/tls/certs/ca-bundle.crt`. Le comportement sur Debian ne change pas.
- `ca_lab` : refus explicite d'une famille inconnue.

### Changements internes
- Variables de famille dans `vars/Debian.yml` et `vars/RedHat.yml`.
