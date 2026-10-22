# Sous-politique MédiSphère (rôle durcissement, M26-E11) : pour l'ÉCHANGE DE CLÉS SSH, ni courbes NIST
# (seules ou hybrides) ni groupe Diffie-Hellman de 2048 bits. Les SIGNATURES ne sont pas touchées :
# la CA SSH de step-ca (M06) peut signer en ECDSA P-256, et ses certificats doivent rester acceptés.
group@SSH = -SECP256R1 -SECP384R1 -SECP521R1 -FFDHE-2048 -P256-MLKEM768 -P384-MLKEM1024
