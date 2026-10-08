# etc/kolla/config/horizon/_9999-custom-settings.py — M10-E27 (SEC-1153)
# Réglages Django/Horizon ajoutés après ceux de Kolla (_9998-kolla-settings.py, qui pose déjà
# SESSION_COOKIE_SECURE et CSRF_COOKIE_SECURE quand la VIP externe est en TLS).
# Appliquer : reconfigure -t horizon.

# Durée maximale d'une session Horizon (secondes) : 30 minutes, quelle que soit l'activité.
SESSION_TIMEOUT = 1800
# Cookie de session supprimé à la fermeture du navigateur.
SESSION_EXPIRE_AT_BROWSER_CLOSE = True
