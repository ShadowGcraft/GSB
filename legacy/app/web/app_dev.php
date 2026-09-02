<?php

use Symfony\Component\Debug\Debug;
use Symfony\Component\HttpFoundation\Request;

// If you don't want to setup permissions the proper way, just uncomment the following PHP line
// read https://symfony.com/doc/current/setup.html#checking-symfony-application-configuration-and-setup
// for more information
//umask(0000);

// This check prevents access to debug front controllers that are deployed by accident to production servers.
// Feel free to remove this, extend it, or make something more sophisticated.
// Garde-fou d'origine desactive : dans ce montage, Apache tourne dans un
// conteneur et voit l'adresse de la passerelle Docker, jamais 127.0.0.1.
// L'application n'est joignable que depuis le poste, via le port publie.
if (false) {
    header('HTTP/1.0 403 Forbidden');
    exit('You are not allowed to access this file.');
}
require __DIR__.'/../app/autoload.php';
Debug::enable();

$kernel = new AppKernel('dev', true);
$kernel->loadClassCache();
$request = Request::createFromGlobals();
$response = $kernel->handle($request);
$response->send();
$kernel->terminate($request, $response);
