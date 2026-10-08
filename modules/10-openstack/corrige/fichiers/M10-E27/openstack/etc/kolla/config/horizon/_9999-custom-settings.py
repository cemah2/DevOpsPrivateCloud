# etc/kolla/config/horizon/_9999-custom-settings.py — M10-E17 (DEV-1127), complété en M10-E27 (SEC-1153)
# Réglages Django/Horizon propres à MédiSphère, copiés par Kolla dans
# /etc/kolla/horizon/_9999-custom-settings.py et chargés après _9998-kolla-settings.py (qui pose
# déjà SESSION_COOKIE_SECURE et CSRF_COOKIE_SECURE quand la VIP externe est en TLS).
# Module Python : vérifier avant MR avec « python3 -m py_compile » (une erreur arrête Horizon).
# Appliquer : kolla-ansible reconfigure -t horizon.

# --- M10-E17 -------------------------------------------------------------------------------------
# Session de 30 minutes : SESSION_TIMEOUT est le réglage de Horizon, SESSION_COOKIE_AGE celui de
# Django ; on aligne les deux.
SESSION_TIMEOUT = 1800
SESSION_COOKIE_AGE = 1800

# Domaine proposé par défaut sur la page de connexion.
OPENSTACK_KEYSTONE_DEFAULT_DOMAIN = "medisphere"

# --- M10-E27 -------------------------------------------------------------------------------------
# Par défaut (SESSION_REFRESH = True), SESSION_TIMEOUT est un délai d'INACTIVITÉ : une session
# active dure jusqu'à l'expiration du jeton. False en fait une limite absolue de 30 minutes.
SESSION_REFRESH = False
# Cookie de session supprimé à la fermeture du navigateur.
SESSION_EXPIRE_AT_BROWSER_CLOSE = True
