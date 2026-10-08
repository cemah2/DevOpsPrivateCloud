# pki/hv-par1-root-ca.crt (M09-E18)

Certificat **public** de l'autorité du cluster `hv-par1` : copie de `/etc/pve/pve-root-ca.pem`
(identique sur les trois nœuds, pmxcfs). Il n'est pas fourni ici : il est propre à TON cluster.

```
admin@adm01:~/src/ansible$ ssh root@hv01 cat /etc/pve/pve-root-ca.pem > pki/hv-par1-root-ca.crt
admin@adm01:~/src/ansible$ openssl x509 -in pki/hv-par1-root-ca.crt -noout -subject -enddate -fingerprint -sha256
```

Compare l'empreinte avec celle lue **sur la console** d'un nœud (`qm terminal 2091` depuis
`pve01`) avant de le versionner : c'est ce fichier qui décide à qui `adm01` et `runner01` font
confiance. Le playbook `hv-cluster.yml` refuse de s'exécuter si le fichier versionné et
l'autorité réelle diffèrent (cluster reconstruit : nouvelle autorité, nouvelle MR).
