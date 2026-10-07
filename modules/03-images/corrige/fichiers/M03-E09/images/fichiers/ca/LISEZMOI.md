# fichiers/ca/ — autorité de certification provisoire MédiSphère (M03-E09)

Placer ici **le certificat public** de la CA provisoire (M01), sous le nom
`medisphere-provisoire.crt` :

    cp /usr/local/share/ca-certificates/medisphere-provisoire.crt ~/src/images/fichiers/ca/

Seul le certificat (public) est versionné. La clé privée reste dans `~/pki-provisoire/`
sur `adm01`, hors de tout dépôt. Au module 06, ce fichier sera remplacé par la racine
step-ca (`medisphere-root-ca.crt`).
