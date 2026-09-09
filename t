=== Demarrage GSB sans Docker, 2026-09-09 15:46:33 ===
15:46:33  PowerShell 5.1.26100.9168  |  port web 8089  |  port base 3307
15:46:33  == 1/6  Outils portables
15:46:33     php déjà présent
15:46:33     mariadb déjà présent
15:46:33  == 2/6  Configuration de PHP
15:46:33     php.ini ecrit, 8 extensions activees : pdo_mysql, mysqli, mbstring, openssl, intl, curl, fileinfo, sodium
15:46:33     php[0] -n -r echo PHP_VERSION;
15:46:33       sortie : 7.4.33
15:46:33     PHP 7.4.33
15:46:34     php[0] -r echo extension_loaded('pdo_mysql') ? 'oui' : 'non';
15:46:34       sortie : oui
15:46:34     php[0] -r echo extension_loaded('mbstring') ? 'oui' : 'non';
15:46:34       sortie : oui
15:46:34     extensions indispensables chargees
15:46:34     7-Zip disponible pour Composer
15:46:34  == 3/6  Base de données
15:46:35  instance du projet : pid 15616, port 3309
15:46:35     mysql[0] SELECT VERSION();
15:46:35     un serveur du projet ecoute deja le port 3309, il est reutilise
15:46:35     . donnees deja initialisees
15:46:35     . test de connexion au serveur
15:46:35     mysql[0] SELECT VERSION();
15:46:35     base en marche : MariaDB 10.6.21-MariaDB
15:46:35     mysql[1] SELECT 1;
15:46:35     mysql erreur : ERROR 1045 (28000): Access denied for user 'root'@'127.0.0.1' (using password: NO)
15:46:35     mysql[0] CREATE USER IF NOT EXISTS 'root'@'127.0.0.1' IDENTIFIED BY '...
15:46:35     comptes root verifies
15:46:35  == 4/6  Schema et jeu d'essai
15:46:35     mysql[0] SELECT COUNT(*) FROM information_schema.tables WHERE table_s...
15:46:35     base deja peuplee, 6 tables
15:46:35  == 5/6  Application Symfony
15:46:35     dependances incompletes, manquent : app\vendor\autoload.php, app\vendor\composer\installed.json, app\vendor\symfony\symfony, app\vendor\doctrine\annotations, app\vendor\twig\twig
15:46:35     installation des dependances, comptez plusieurs minutes
15:46:35     . composer install dans C:\Users\admin\Documents\GitHub\GSB\legacy\app
15:48:25     php[0] -c C:\Users\admin\Documents\GitHub\GSB\legacy\local\bin\php\php.ini C:\Users\admin\Documents\GitHub\GSB\legacy\local\composer.phar install --no-interaction --no-scripts --no-autoloader --no-progress
15:48:25       erreur : Installing dependencies from lock file (including require-dev) Verifying lock file contents can be installed on current platform. Package operations: 37 installs, 0 updates, 0 removals   - Downloading doctrine/lexer (v1.0.1)   - Downloading doctrine/annotations (v1.4.0)   - Downloading symfony/polyfill-ctype (v1.10.0)   - Downloading twig/twig (v1.35.4)   - Downloading symfony/symfony (v2.8.48)   - Downloading symfony/security-acl (v3.0.1)   - Downloading symfony/polyfill-util (v1.10.0)   - Downloading paragonie/random_compat (v2.0.17)   - Downloading symfony/polyfill-php70 (v1.10.0)   - Downloading symfony/polyfill-php56 (v1.10.0)   - Downloading ircmaxell/password-compat (v1.0.4)   - Downloading symfony/polyfill-php55 (v1.10.0)   - Downloading symfony/polyfill-php54 (v1.10.0)   - Downloading symfony/polyfill-mbstring (v1.10.0)   - Downloading symfony/polyfill-intl-icu (v1.10.0)   - Downloading symfony/polyfill-apcu (v1.10.0)   - Downloading psr/log (1.1.0)   - Downloading doctrine/inflector (v1.1.0)   - Downloading doctrine/collections (v1.4.0)   - Downloading doctrine/cache (v1.6.2)   - Downloading doctrine/common (v2.7.3)   - Downloading jdorn/sql-formatter (v1.2.17)   - Downloading doctrine/doctrine-cache-bundle (1.3.5)   - Downloading doctrine/dbal (v2.5.13)   - Downloading doctrine/doctrine-bundle (1.9.1)   - Downloading doctrine/instantiator (1.0.5)   - Downloading doctrine/orm (v2.5.14)   - Downloading incenteev/composer-parameter-handler (v2.1.3)   - Downloading sensiolabs/security-checker (v3.0.7)   - Downloading sensio/distribution-bundle (v4.0.40)   - Downloading sensio/framework-extra-bundle (v3.0.29)   - Downloading sensio/generator-bundle (v3.1.7)   - Downloading monolog/monolog (1.24.0)   - Downloading symfony/monolog-bundle (v3.3.1)   - Downloading symfony/phpunit-bridge (v2.8.48)   - Downloading swiftmailer/swiftmailer (v5.4.12)   - Downloading symfony/swiftmailer-bundle (v2.6.7)   - Installing doctrine/lexer (v1.0.1): Extracting archive   - Installing doctrine/annotations (v1.4.0): Extracting archive   - Installing symfony/polyfill-ctype (v1.10.0): Extracting archive   - Installing twig/twig (v1.35.4): Extracting archive   - Installing symfony/symfony (v2.8.48): Extracting archive   - Installing symfony/security-acl (v3.0.1): Extracting archive   - Installing symfony/polyfill-util (v1.10.0): Extracting archive   - Installing paragonie/random_compat (v2.0.17): Extracting archive   - Installing symfony/polyfill-php70 (v1.10.0): Extracting archive   - Installing symfony/polyfill-php56 (v1.10.0): Extracting archive   - Installing ircmaxell/password-compat (v1.0.4): Extracting archive   - Installing symfony/polyfill-php55 (v1.10.0): Extracting archive   - Installing symfony/polyfill-php54 (v1.10.0): Extracting archive   - Installing symfony/polyfill-mbstring (v1.10.0): Extracting archive   - Installing symfony/polyfill-intl-icu (v1.10.0): Extracting archive   - Installing symfony/polyfill-apcu (v1.10.0): Extracting archive   - Installing psr/log (1.1.0): Extracting archive   - Installing doctrine/inflector (v1.1.0): Extracting archive   - Installing doctrine/collections (v1.4.0): Extracting archive   - Installing doctrine/cache (v1.6.2): Extracting archive   - Installing doctrine/common (v2.7.3): Extracting archive   - Installing jdorn/sql-formatter (v1.2.17): Extracting archive   - Installing doctrine/doctrine-cache-bundle (1.3.5): Extracting archive   - Installing doctrine/dbal (v2.5.13): Extracting archive   - Installing doctrine/doctrine-bundle (1.9.1): Extracting archive   - Installing doctrine/instantiator (1.0.5): Extracting archive   - Installing doctrine/orm (v2.5.14): Extracting archive   - Installing incenteev/composer-parameter-handler (v2.1.3): Extracting archive   - Installing sensiolabs/security-checker (v3.0.7): Extracting archive   - Installing sensio/distribution-bundle (v4.0.40): Extracting archive   - Installing sensio/framework-extra-bundle (v3.0.29): Extracting archive   - Installing sensio/generator-bundle (v3.1.7): Extracting archive   - Installing monolog/monolog (1.24.0): Extracting archive   - Installing symfony/monolog-bundle (v3.3.1): Extracting archive   - Installing symfony/phpunit-bridge (v2.8.48): Extracting archive   - Installing swiftmailer/swiftmailer (v5.4.12): Extracting archive   - Installing symfony/swiftmailer-bundle (v2.6.7): Extracting archive
15:48:25     . 
15:48:25     dependances incompletes, manquent : app\vendor\autoload.php
15:48:25  ECHEC Les dependances restent incompletes apres installation.
           Detail des paquets manquants dans C:\Users\admin\Documents\GitHub\GSB\legacy\local\log\demarrage.log
