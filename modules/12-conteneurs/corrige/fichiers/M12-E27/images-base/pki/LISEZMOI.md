# pki/

`medisphere-root-ca.crt` : copie du certificat **public** de la racine « MédiSphère Root CA »
(M06), identique à `/usr/local/share/ca-certificates/medisphere-root-ca.crt` des hôtes. Ce n'est
pas un secret. À remplacer par MR si la racine change (procédure de renouvellement de M06).
Vérification : `openssl x509 -in pki/medisphere-root-ca.crt -noout -subject -fingerprint -sha256`.
