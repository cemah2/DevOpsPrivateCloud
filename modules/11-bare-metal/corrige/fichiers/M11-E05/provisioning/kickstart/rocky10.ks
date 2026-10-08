# kickstart/rocky10.ks — plateforme/provisioning (M11-E05)
# Installation automatique de Rocky Linux 10 aux standards MédiSphère.
# Lu par Anaconda via « inst.ks=http://pxe01.par1.medisphere.internal/kickstart/rocky10.ks ».
# Servi en HTTP CLAIR sur le VLAN 60 (HTTPS en M11-E13) : empreintes et clés publiques seulement.
# Validation : ksvalidator -v RHEL10 kickstart/rocky10.ks (pipeline : outils/verifier.sh).

# Mode texte, aucune question : une commande manquante ferait s'arrêter l'installateur.
text
eula --agreed

# Sources : même version mineure que l'initrd servi par pxe01 (10.2), miroir officiel en HTTPS.
url --url=https://dl.rockylinux.org/pub/rocky/10.2/BaseOS/x86_64/os/
repo --name=AppStream --baseurl=https://dl.rockylinux.org/pub/rocky/10.2/AppStream/x86_64/os/

lang fr_FR.UTF-8
keyboard --vckeymap=fr --xlayouts=fr
timezone Europe/Paris --utc
timesource --ntp-server=10.10.60.1

# Réseau : DHCP (Kea, sous-réseau 60) sur l'interface qui a un lien.
network --bootproto=dhcp --device=link --activate --onboot=yes

# Comptes : root verrouillé ; admin dans wheel (sudo), empreinte SHA-512 pour la console seulement.
rootpw --lock
user --name=admin --groups=wheel --iscrypted --password=<EMPREINTE-SHA512-ADMIN>
sshkey --username=admin "<CLE-PUBLIQUE-SSH-ADM01>"

# Disque : le seul disque des VMs du lab (sda), tout effacé, LVM automatique.
ignoredisk --only-use=sda
zerombr
clearpart --all --initlabel --drives=sda
autopart --type=lvm
bootloader --boot-drive=sda

# Sécurité par défaut de la distribution, explicitement.
selinux --enforcing
firewall --enabled --service=ssh
services --enabled=sshd,qemu-guest-agent,chronyd

%packages
@^minimal-environment
qemu-guest-agent
curl
%end

# Racine de la PKI : acceptée SEULEMENT si son empreinte est la bonne (calculée sur adm01).
# --erroronfail : un écart arrête l'installation au lieu de livrer un serveur qui ne fait
# confiance à rien (ou, pire, à une racine substituée).
%post --erroronfail --log=/root/ks-post.log
set -eu
curl --fail --silent --show-error -o /tmp/racine.crt http://pxe01.par1.medisphere.internal/pki/medisphere-root-ca.crt
test "$(sha256sum /tmp/racine.crt | cut -d ' ' -f 1)" = "<EMPREINTE-SHA256-RACINE>"
install -m 644 /tmp/racine.crt /etc/pki/ca-trust/source/anchors/medisphere-root-ca.crt
update-ca-trust
%end

# Fin : EXTINCTION. La chaîne décide de la suite (statut NetBox, puis rallumage sur le disque).
poweroff
