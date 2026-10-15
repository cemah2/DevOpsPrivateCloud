# MR !14 de `medinotif/worker` — « chaîne de livraison + Renovate » (Lucas Martin)

> Description de la MR, écrite par Lucas :
>
> Salut ! J'ai fait la chaîne de livraison de MédiNotif en m'inspirant de ce que j'ai trouvé sur
> internet et de la doc. Tout est vert, l'image est dans Harbor et elle est signée (j'ai vérifié
> dans l'interface, il y a bien une signature). J'ai mis la clé de signature dans le dépôt pour que
> le pipeline la trouve, avec un mot de passe vide pour que ce soit plus simple. J'ai aussi proposé
> une config pour `plateforme/renovate`, avec la fusion automatique activée partout pour qu'on
> n'ait plus rien à faire.
> Le scan Trivy remonte plein de trucs sur l'image de base, je l'ai mis en non bloquant pour
> l'instant, et j'ai ignoré les CVE qui faisaient échouer le job.

Fichiers de la branche `lucas/chaine-livraison` (poussée sur `git01`) :

- `medinotif-worker/.gitlab-ci.yml`
- `medinotif-worker/.trivyignore`
- `medinotif-worker/renovate.json`
- `medinotif-worker/cosign.key`, `medinotif-worker/cosign.pub`
- `plateforme-renovate/config.js` (proposé pour `plateforme/renovate`)
- `plateforme-renovate/.gitlab-ci.yml`
