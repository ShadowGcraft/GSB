#!/usr/bin/env bash
#
# Remet en marche l'application GSB de 2013 et l'ouvre sur http://localhost:8088
#
# Le script est idempotent : on peut le relancer sans rien casser. Il ne touche
# jamais au code du bundle, seulement à ce qui doit être installé ou généré.
#
set -euo pipefail
cd "$(dirname "$0")"

echo "==> 1/6  Construction de l'image PHP 7.4"
docker compose build

echo "==> 2/6  Démarrage de la base et du serveur"
docker compose up -d

echo "==> 3/6  Attente de la base"
for _ in $(seq 1 30); do
    if docker compose exec -T db mariadb -uroot -proot -e "SELECT 1" bd_gsb >/dev/null 2>&1; then
        echo "    base prête"
        break
    fi
    sleep 3
done

echo "==> 4/6  Dépendances Symfony"
if [ ! -d app/vendor ]; then
    # Le squelette Symfony 2.8 n'est pas versionné dans son intégralité : s'il
    # manque, on le réinstalle à côté puis on ne reprend que ce qui manque.
    docker compose exec -T web sh -c '
        cd /var/www/html
        if [ ! -f composer.json ]; then
            composer create-project symfony/framework-standard-edition /tmp/sf "2.8.*" \
                --no-interaction --prefer-dist --no-scripts
            cp -an /tmp/sf/. /var/www/html/
        fi
        composer install --no-interaction --no-scripts
    '
else
    echo "    déjà installées"
fi

echo "==> 5/6  Fichiers générés : paramètres, amorçage, assets"
# Composer cree les fichiers en 600 dans le conteneur. Le volume reflete ces
# permissions sur l'hote et Apache, qui tourne en www-data, ne peut plus rien
# lire : toutes les pages repondent alors 404.
chmod -R a+rX app
docker compose exec -T web sh -c '
    cd /var/www/html
    [ -f app/config/parameters.yml ] || cp app/config/parameters.yml.dist app/config/parameters.yml
    composer dump-autoload --quiet
    php vendor/sensio/distribution-bundle/Sensio/Bundle/DistributionBundle/Resources/bin/build_bootstrap.php app
    # Symfony 2.8 declenche sur PHP 7.4 un avertissement « continue targeting
    # switch » dans son propre code. Le gestionnaire d erreurs du mode debug le
    # transforme en exception fatale : on lance donc la commande sans debug.
    php app/console assets:install web --symlink --env=prod --no-debug --quiet
    # Le lien attendu par les gabarits de 2013 diffère du nom du bundle.
    [ -e web/bundles/gsbfrais ] || ln -s ../../src/Pg/GsbFraisBundle/Resources/public web/bundles/gsbfrais
    rm -rf app/cache/*
    chmod -R 777 app/cache app/logs 2>/dev/null || true
'

echo "==> 6/6  Vérification"
code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8088/accueil || echo 000)
if [ "$code" = "200" ]; then
    echo
    echo "    L'application répond : http://localhost:8088"
    echo "    Comptes de démonstration : dandre / oppg5, cbedos / gvide, pbentot / doypa"
    echo "    Mode développement, avec la barre de débogage : http://localhost:8088/app_dev.php/accueil"
else
    echo "    ÉCHEC : la page d'accueil renvoie $code"
    echo "    Journaux : docker compose logs web"
    exit 1
fi
