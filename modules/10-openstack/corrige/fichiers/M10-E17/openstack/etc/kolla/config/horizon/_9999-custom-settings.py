# Réglages Django propres à MédiSphère (M10-E17, DEV-1127). Copié par Kolla dans
# /etc/kolla/horizon/_9999-custom-settings.py ; chargé après _9998-kolla-settings.py.
# Module Python : vérifier avant MR avec « python3 -m py_compile » (une erreur arrête Horizon).

# Session de 30 minutes (exigence de la RSSI) : SESSION_TIMEOUT est le réglage de Horizon,
# SESSION_COOKIE_AGE celui de Django ; on aligne les deux.
SESSION_TIMEOUT = 1800
SESSION_COOKIE_AGE = 1800

# Domaine proposé par défaut sur la page de connexion.
OPENSTACK_KEYSTONE_DEFAULT_DOMAIN = "medisphere"

# Horizon est derrière le HAProxy de Kolla, en HTTPS : SECURE_PROXY_SSL_HEADER,
# SESSION_COOKIE_SECURE et CSRF_COOKIE_SECURE sont déjà posés par Kolla (TLS externe actif).
# HSTS : laissé au palier 3 (M10-E27), après vérification de tous les noms servis en HTTPS.
