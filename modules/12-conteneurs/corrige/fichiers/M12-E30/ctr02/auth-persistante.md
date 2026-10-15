# Identifiants du registre pour le compte app (ctr02) — M12-E30

`podman login` écrit par défaut dans `$XDG_RUNTIME_DIR/containers/auth.json` (`/run/user/1001/…`),
un tmpfs **vidé à chaque redémarrage** : après un redémarrage de `ctr02`, `podman auto-update`
échouerait sur une erreur d'authentification. On écrit donc dans un fichier persistant, que Podman
lit aussi (`$XDG_CONFIG_HOME/containers/auth.json`, voir `containers-auth.json(5)` ; à vérifier
sur ta version) :

    app@ctr02:~$ install -d -m 700 ~/.config/containers
    app@ctr02:~$ podman login --authfile ~/.config/containers/auth.json ctr01.par1.medisphere.internal:5000 \
        --username plateforme --password-stdin < <MOT-DE-PASSE-DU-COMPTE-DE-LECTURE>
    app@ctr02:~$ chmod 600 ~/.config/containers/auth.json

Le mot de passe vient du Vault (`vault_registre_travail_mdp_plateforme`, M12-E15) ; le fichier est
inscrit au registre des secrets (emplacement : `ctr02:/home/app/.config/containers/auth.json`).
En production, un compte du registre **en lecture seule** (Harbor, robot `pull`, M13).

Timer de mise à jour du compte (fourni par Podman) :

    app@ctr02:~$ systemctl --user enable --now podman-auto-update.timer
    app@ctr02:~$ systemctl --user list-timers podman-auto-update.timer
