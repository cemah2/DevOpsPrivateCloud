# etc/kolla/certificates/ca/

Copie du certificat **public** de la racine MédiSphère : `medisphere-root-ca.crt`
(identique à `/usr/local/share/ca-certificates/medisphere-root-ca.crt` de `adm01`).
Kolla le copie dans chaque conteneur quand `kolla_copy_ca_into_containers` vaut `yes` (M10-E27).
Aucune clé privée dans ce dossier ni dans `certificates/` : les certificats des VIP sont obtenus
par ACME (rôle letsencrypt de Kolla) et ne sont plus versionnés.
