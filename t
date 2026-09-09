
  +------------------------------------------------+
  |   GSB - application de 2013, sans Docker       |
  +------------------------------------------------+

  Premiere execution : telechargement de PHP et MariaDB,
  comptez une dizaine de minutes selon le reseau.

    journal : C:\Users\admin\Documents\GitHub\GSB\legacy\local\log\demarrage.log

==> 1/6  Outils portables
    php déjà présent
    mariadb déjà présent

==> 2/6  Configuration de PHP
    php.ini ecrit, 8 extensions activees : pdo_mysql, mysqli, mbstring, openssl, intl, curl, fileinfo, sodium
    PHP 7.4.33
    extensions indispensables chargees
    7-Zip disponible pour Composer

==> 3/6  Base de données
    un serveur du projet ecoute deja le port 3309, il est reutilise
    base en marche : MariaDB 10.6.21-MariaDB
    comptes root verifies

==> 4/6  Schema et jeu d'essai
    base deja peuplee, 6 tables

==> 5/6  Application Symfony
    dependances deja installees
    connexion dirigée vers 127.0.0.1:3309

    L autoloader ne trouve pas les classes de Doctrine.
    vendor\doctrine\annotations est absent.
    Le dossier vendor est incomplet. Supprimez-le et relancez :
      Remove-Item -Recurse -Force 'C:\Users\admin\Documents\GitHub\GSB\legacy\app\vendor'
    Dependances incompletes.

    Journal complet : C:\Users\admin\Documents\GitHub\GSB\legacy\local\log\demarrage.log

  ECHEC : les messages ci-dessus indiquent a quelle etape.

Appuyez sur une touche pour continuer...

