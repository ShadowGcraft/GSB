<?php
namespace Pg\GsbFraisBundle\Controller;
require_once("include/fct.inc.php");
use Symfony\Component\HttpFoundation\Request;

class HomeController extends GsbController
{
    public function indexAction()
    {
        $session = $this->session();
        if (!$session->get('id')) {
            return $this->render('PgGsbFraisBundle:Home:connexion.html.twig');
        }
        if (in_array($session->get('role'), self::$rolesGestion, true)) {
            return $this->redirectToRoute('pg_gsb_frais_admin_fiches');
        }
        return $this->render('PgGsbFraisBundle::accueil.html.twig');
    }

    public function validerconnexionAction(Request $request){
        $session = $request->getSession();
        $login = $request->request->get('login');
        $mdp = $request->request->get('mdp');
        $visiteur = $this->pdo()->getInfosVisiteur($login,$mdp);
        if(!is_array($visiteur)){
            return $this->render('PgGsbFraisBundle:Home:connexion.html.twig',array(
               'message'=>'Erreur de login ou de mot de passe '));
        }
        if(!$visiteur['actif']){
            return $this->render('PgGsbFraisBundle:Home:connexion.html.twig',array(
               'message'=>'Ce compte est désactivé. Adressez-vous à l\'administrateur.'));
        }
        $session->migrate();
        $session->set('id',$visiteur['id']);
        $session->set('nom',$visiteur['nom']);
        $session->set('prenom',$visiteur['prenom']);
        $session->set('role',$visiteur['role']);
        return $this->redirectToRoute('pg_gsb_frais_home');
    }

    public function deconnexionAction(){
        $this->session()->clear();
        return $this->redirectToRoute('pg_gsb_frais_home');
   }
}
?>
