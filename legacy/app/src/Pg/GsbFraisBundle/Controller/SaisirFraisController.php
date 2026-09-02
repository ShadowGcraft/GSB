<?php
namespace Pg\GsbFraisBundle\Controller;
require_once("include/fct.inc.php");
//require_once ("include/class.pdogsb.inc.php");
use Symfony\Bundle\FrameworkBundle\Controller\Controller;
use Symfony\Component\HttpFoundation\Session\Session;
use Symfony\Component\HttpFoundation\Response;
//use PdoGsb;
class SaisirFraisController extends Controller
{
    public function indexAction()
    {
        $session= $this->get('request')->getSession();
        $idVisiteur =  $session->get('id');
        $mois = getMois(date("d/m/Y"));
        $numAnnee =substr( $mois,0,4);
        $numMois =substr( $mois,4,2);
//        $pdo = PdoGsb::getPdoGsb();
        $pdo = $this->get('pg_gsb_frais.pdo');
        if($pdo->estPremierFraisMois($idVisiteur,$mois)){
                                $pdo->creeNouvellesLignesFrais($idVisiteur,$mois);
        }
        $request = $this->get('request');
        $lesErreursForfaits = array();
        if($this->get('request')->getMethod() == 'POST'){
                $lesFrais = $request->request->get('lesFrais');
                if(lesQteFraisValides($lesFrais)){
                     $pdo->majFraisForfait($idVisiteur,$mois,$lesFrais);
                }
                else{
                     $lesErreursForfaits[]="Les valeurs des frais doivent être numériques";
                }
         }
        $lesFraisForfait = $pdo->getLesFraisForfait($idVisiteur,$mois);
        $lesFraisHorsForfait = $pdo->getLesFraisHorsForfait($idVisiteur,$mois);
        return $this->render('PgGsbFraisBundle:SaisirFrais:saisirtouslesfrais.html.twig',
                array('lesfraisforfait'=>$lesFraisForfait,'lesfraishorsforfait'=>$lesFraisHorsForfait,'nummois'=>$numMois,
                    'numannee'=>$numAnnee,'leserreursforfait'=> $lesErreursForfaits,'leserreurshorsforfait'=>null));
     }
     public function validerfraishorsforfaitAction(){
                $session= $this->get('request')->getSession();
                $idVisiteur =  $session->get('id');
                $mois = getMois(date("d/m/Y"));
                $numAnnee =substr( $mois,0,4);
                $numMois =substr( $mois,4,2);
//                $pdo = PdoGsb::getPdoGsb();
                $pdo = $this->get('pg_gsb_frais.pdo');
                $request = $this->get('request');
                $dateFrais = $request->request->get('dateFrais');
		$libelle = $request->request->get('libelle');
                $montant = $request->request->get('montant');
		$lesErreursHorsForfait = valideInfosFrais($dateFrais,$libelle,$montant);
              	if (count($lesErreursHorsForfait)==0){
			$pdo->creeNouveauFraisHorsForfait($idVisiteur,$mois,$libelle,$dateFrais,$montant);
		}
                $lesFraisForfait= $pdo->getLesFraisForfait($idVisiteur,$mois);
                $lesFraisHorsForfait = $pdo->getLesFraisHorsForfait($idVisiteur,$mois);
                return $this->render('PgGsbFraisBundle:SaisirFrais:saisirtouslesfrais.html.twig',
                array('lesfraisforfait'=>$lesFraisForfait,'lesfraishorsforfait'=>$lesFraisHorsForfait,'nummois'=>$numMois,
                    'numannee'=>$numAnnee,'leserreursforfait'=>null,'leserreurshorsforfait'=> $lesErreursHorsForfait));
     
     }
     
     
     public function supprimerfraishorsforfaitAction($id){
                $session= $this->get('request')->getSession();
                $idVisiteur =  $session->get('id');
                $mois = getMois(date("d/m/Y"));
                $numAnnee =substr( $mois,0,4);
                $numMois =substr( $mois,4,2);
//                $pdo = PdoGsb::getPdoGsb();
               $pdo = $this->get('pg_gsb_frais.pdo');
                if( $pdo->estValideSuppressionFrais($idVisiteur,$mois,$id))
                            $pdo->supprimerFraisHorsForfait($id);
                else {
                     $response = new Response;
                     $response->setContent("<h2>Page introuvable erreur 404 ");
                     $response->setStatusCode(404);
                     return $response;
                }
                $lesFraisForfait= $pdo->getLesFraisForfait($idVisiteur,$mois);
                $lesFraisHorsForfait = $pdo->getLesFraisHorsForfait($idVisiteur,$mois);
                return $this->render('PgGsbFraisBundle:SaisirFrais:saisirtouslesfrais.html.twig',
                array('lesfraisforfait'=>$lesFraisForfait,'lesfraishorsforfait'=>$lesFraisHorsForfait,'nummois'=>$numMois,
                    'numannee'=>$numAnnee,'leserreursforfait'=>null,'leserreurshorsforfait'=>null));
     }
    
}
?>
