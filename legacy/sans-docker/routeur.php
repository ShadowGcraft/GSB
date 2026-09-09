<?php
/**
 * Routeur pour le serveur web integre de PHP.
 *
 * Sans Docker, il n'y a pas d'Apache pour lire le fichier .htaccess de Symfony.
 * Ce routeur en tient lieu : il sert directement les fichiers qui existent
 * (feuilles de style, images) et confie tout le reste au controleur frontal.
 *
 * Il se passe en dernier argument au serveur integre :
 *   php -S 127.0.0.1:8089 -t chemin/vers/app/web ce-fichier.php
 *
 * La variable d'environnement GSB_ENV choisit le controleur frontal :
 *   dev  (defaut) app_dev.php, avec les messages d'erreur detailles
 *   prod           app.php
 */

$racineWeb = getenv('GSB_WEB_ROOT');
if (!$racineWeb) {
    // Par defaut, le dossier web de l'application, deux crans au-dessus.
    $racineWeb = dirname(__DIR__) . '/app/web';
}
$racineWeb = rtrim($racineWeb, '/');

$chemin = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
$chemin = urldecode($chemin);

// Un fichier reellement present est servi tel quel par le serveur integre.
//
// Le controle porte sur le chemin DEMANDE, pas sur le fichier resolu : les
// ressources du bundle sont atteintes par un lien symbolique qui sort du
// dossier web, et un controle sur la cible les rejetterait a tort.
$remontee = strpos($chemin, '..') !== false;

if ($chemin !== '/' && !$remontee && is_file($racineWeb . $chemin)) {
    return false;
}

$controleur = getenv('GSB_ENV') === 'prod' ? 'app.php' : 'app_dev.php';

// Le controleur frontal attend d'etre appele comme un script du dossier web.
$_SERVER['SCRIPT_FILENAME'] = $racineWeb . '/' . $controleur;
$_SERVER['SCRIPT_NAME']     = '/' . $controleur;
$_SERVER['PHP_SELF']        = '/' . $controleur;

require $racineWeb . '/' . $controleur;
