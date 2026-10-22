# Sous-politique MédiSphère (rôle durcissement, M26-E11) : pour SSH, ni HMAC-SHA1 ni UMAC-64, et
# seulement des MAC « encrypt-then-MAC » (-etm@openssh.com).
mac@SSH = -HMAC-SHA1 -UMAC-64
etm@SSH = DISABLE_NON_ETM
