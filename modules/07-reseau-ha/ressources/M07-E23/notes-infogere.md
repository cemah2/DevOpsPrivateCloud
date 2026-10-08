# Routeur de bordure « rt-bord-01 » — notes de passation (InfoGér)

Document transmis par InfoGér avec la configuration `frr-infogere.conf` (export du 12 du mois).

## Contexte chez InfoGér

- Un routeur Debian + FRR en bordure de la baie MédiSphère, AS **65000** (le même que le vôtre,
  pratique pour la reprise).
- Voisins :
  - **opérateur de transit** « NetCo » (AS 64600) en 192.0.2.1, lien direct ;
  - **agence de Lyon** (AS 65030), 10.255.2.2, à travers un tunnel IPsec ;
  - les **serveurs clients** hébergés dans la baie (AS 65100 à 65199 selon le client), qui
    annoncent leurs adresses de service ; ils se connectent depuis 10.10.0.0/16.
- Le routeur fait aussi le NAT et le pare-feu (iptables, hors de ce document).

## Ce qu'on vous conseille

- Reprendre la configuration telle quelle sur `gw01` et `gw02` : elle tourne sans incident depuis
  cinq ans.
- Les temporisateurs ont été réduits pour que la bascule vers l'agence soit rapide.
- La politique eBGP « obligatoire » des versions récentes de FRR a été désactivée, car elle
  bloquait tout après une mise à jour : « on ne touche plus à ça ».
- Le mot de passe des sessions est le même partout, c'est plus simple pour les techniciens.
- Les débogages sont activés pour l'astreinte, qui lit les journaux en cas de souci.
