# talos/secrets/

Une seule chose ici : `talos-secrets.yaml.vault`, le bundle `talosctl gen secrets` de
`talos-essai` **chiffré** avec l'identité Ansible Vault `lab` (M18-E05). Il permet de régénérer
exactement les mêmes configurations machine (mêmes autorités, mêmes jetons) si
`~/.config/workbook/m18/talos-secrets.yaml` est perdu :

    admin@adm01:~/src/distributions$ uv --project ~/src/ansible run ansible-vault encrypt \
        --vault-id lab@$HOME/src/ansible/outils/vault-pass-client.sh \
        --output talos/secrets/talos-secrets.yaml.vault ~/.config/workbook/m18/talos-secrets.yaml

Jamais le fichier en clair (le `.gitignore` le refuse, Gitleaks aussi).
