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
        return $this->tableauDeBord($session->get('id'));
    }

    /**
     * Accueil du visiteur : la fiche du mois, ce qui reste à faire, et ses
     * remboursements de l'année écoulée (RG46). Simple lecture : la fiche du
     * mois n'est pas créée ici, mais à la première saisie.
     */
    private function tableauDeBord($idVisiteur)
    {
        $pdo = $this->pdo();
        $mois = date('Ym');
        $moisPrecedent = date('Ym', strtotime('first day of last month'));
        $fiche = $pdo->getLesInfosFicheFrais($idVisiteur, $mois);
        $horsForfait = $fiche ? $pdo->getLesFraisHorsForfait($idVisiteur, $mois) : array();
        $vehicule = $pdo->getVehiculeDuMois($idVisiteur, $mois);
        $saisie = $this->generateUrl('pg_gsb_frais_saisirfrais');

        // Ce qui attend le visiteur, du plus bloquant au simple avis.
        $aFaire = array();
        if (!$vehicule) {
            $aFaire[] = array('type' => 'alerte', 'lien' => $this->generateUrl('pg_gsb_frais_vehicule'),
                'action' => 'Déclarer mon véhicule',
                'texte' => 'Aucun véhicule déclaré : la saisie des kilomètres est bloquée.');
        }
        $sansPiece = count(array_filter($horsForfait, function ($l) { return !$l['justificatifs']; }));
        if ($sansPiece) {
            $aFaire[] = array('type' => 'alerte', 'lien' => $saisie, 'action' => 'Joindre les factures',
                'texte' => $sansPiece > 1 ? "$sansPiece frais hors forfait de ce mois n'ont pas de justificatif."
                                          : "Un frais hors forfait de ce mois n'a pas de justificatif.");
        }
        // Jusqu'au 10, le service comptable attend les factures du mois écoulé (RG2).
        $fichePrecedente = $pdo->getLesInfosFicheFrais($idVisiteur, $moisPrecedent);
        if ($fichePrecedente && $fichePrecedente['idEtat'] === 'CL' && (int) date('j') <= 10) {
            $manquantes = count(array_filter($pdo->getLesFraisHorsForfait($idVisiteur, $moisPrecedent),
                function ($l) { return !$l['refuse'] && !$l['justificatifs']; }));
            if ($manquantes) {
                $aFaire[] = array('type' => 'alerte', 'lien' => null, 'action' => null,
                    'texte' => sprintf('%d frais de %s sans justificatif : remettez les factures au service comptable avant le 10/%s.',
                        $manquantes, self::moisCourt($moisPrecedent), date('m')));
            }
        }
        foreach ($horsForfait as $ligne) {
            if ($ligne['moisOrigine']) {
                $aFaire[] = array('type' => 'info', 'lien' => null, 'action' => null,
                    'texte' => sprintf('« %s » a été reporté de %s sur ce mois par le service comptable.',
                        $ligne['libelle'], self::moisCourt($ligne['moisOrigine'])));
            }
        }
        foreach ($pdo->getLesFraisRefuses($idVisiteur, date('Ym', strtotime('first day of -2 month'))) as $ligne) {
            $aFaire[] = array('type' => 'refus', 'lien' => null, 'action' => null,
                'texte' => sprintf('« %s » (%s, %s €) a été refusé par le service comptable.',
                    $ligne['libelle'], self::moisCourt($ligne['mois']), number_format($ligne['montant'], 2, ',', ' ')));
        }

        // Les douze mois écoulés, hors mois courant.
        $synthese = $pdo->getSyntheseFiches($idVisiteur, date('Ym', strtotime('first day of -12 month')), $mois);
        $rembourse = $enPaiement = 0;
        foreach ($synthese as $i => $ligne) {
            $synthese[$i]['libMois'] = self::libelleMois($ligne['mois']);
            if ($ligne['idEtat'] === 'RB') $rembourse += $ligne['montantValide'];
            if (in_array($ligne['idEtat'], array('VA', 'MP'), true)) $enPaiement += $ligne['montantValide'];
        }

        $joursRestants = (int) date('t') - (int) date('j');
        return $this->render('PgGsbFraisBundle:Accueil:tableau.html.twig', array(
            'libmois' => self::libelleMois($mois),
            'fiche' => $fiche,
            'lesfraisforfait' => $fiche ? $pdo->getLesFraisForfait($idVisiteur, $mois) : array(),
            'nbhorsforfait' => count($horsForfait),
            'montantestime' => $fiche ? $pdo->getMontantCalcule($idVisiteur, $mois) : 0,
            'vehicule' => $vehicule,
            'cloture' => $joursRestants === 0 ? 'ce soir' : ($joursRestants === 1 ? 'demain' : "dans $joursRestants jours"),
            'afaire' => $aFaire,
            'synthese' => $synthese,
            'rembourse' => $rembourse,
            'enpaiement' => $enPaiement,
        ));
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
