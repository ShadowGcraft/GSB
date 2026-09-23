<?php
namespace Pg\GsbFraisBundle\Controller;
require_once("include/fct.inc.php");
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Saisie de la fiche du mois courant.
 *
 * Chaque envoi de formulaire se termine par une redirection vers la page de
 * saisie : recharger la page ne rejoue pas l'ajout d'une quantité.
 */
class SaisirFraisController extends GsbController
{
    /** Le mois courant, après création de sa fiche si besoin. */
    private function moisCourant()
    {
        $idVisiteur = $this->session()->get('id');
        $mois = getMois(date("d/m/Y"));
        if($this->pdo()->estPremierFraisMois($idVisiteur,$mois)){
            $this->pdo()->creeNouvellesLignesFrais($idVisiteur,$mois);
        }
        return $mois;
    }

    private function versSaisie()
    {
        return $this->redirectToRoute('pg_gsb_frais_saisirfrais');
    }

    public function indexAction(Request $request)
    {
        if ($refus = $this->exigeRole(self::ROLE_VISITEUR)) return $refus;
        $idVisiteur = $this->session()->get('id');
        $mois = $this->moisCourant();
        $pdo = $this->pdo();

        // Correction directe des totaux du mois, formulaire d'origine.
        if($request->isMethod('POST')){
            $lesFrais = $request->request->get('lesFrais');
            if(is_array($lesFrais) && lesQteFraisValides($lesFrais)){
                $pdo->majFraisForfait($idVisiteur,$mois,array_map('intval', $lesFrais));
                $this->ajouteMessage('succesForfait', 'Totaux du mois enregistrés.');
            }
            else{
                $this->ajouteMessage('erreurForfait', 'Les valeurs des frais doivent être numériques');
            }
            return $this->versSaisie();
        }

        $flash = $this->session()->getFlashBag();
        $aujourdhui = new \DateTime('today');
        return $this->render('PgGsbFraisBundle:SaisirFrais:saisirtouslesfrais.html.twig', array(
            'lesfraisforfait' => $pdo->getLesFraisForfait($idVisiteur,$mois),
            'lesfraishorsforfait' => $pdo->getLesFraisHorsForfait($idVisiteur,$mois),
            'nummois' => substr($mois,4,2),
            'numannee' => substr($mois,0,4),
            'premierjour' => $aujourdhui->format('Y-m-01'),
            'aujourdhui' => $aujourdhui->format('Y-m-d'),
            'ilyaunan' => $aujourdhui->modify('-1 year')->format('Y-m-d'),
            'leserreursforfait' => $flash->get('erreurForfait'),
            'lessuccesforfait' => $flash->get('succesForfait'),
            'leserreurshorsforfait' => $flash->get('erreurHorsForfait'),
            'lessucceshorsforfait' => $flash->get('succesHorsForfait'),
        ));
    }

    /**
     * Ajout guidé : le jour, puis le type de frais, puis la quantité.
     * Le jour sert à la vérification et au message ; la fiche reste mensuelle.
     */
    public function ajouterfraisforfaitAction(Request $request)
    {
        if ($refus = $this->exigeRole(self::ROLE_VISITEUR)) return $refus;
        $idVisiteur = $this->session()->get('id');
        $mois = $this->moisCourant();

        $jour = \DateTime::createFromFormat('!Y-m-d', (string) $request->request->get('jour'));
        $idFrais = (string) $request->request->get('idFrais');
        $quantite = trim((string) $request->request->get('quantite'));

        $lesFrais = array();
        foreach ($this->pdo()->getLesFraisForfait($idVisiteur,$mois) as $unFrais) {
            $lesFrais[$unFrais['idfrais']] = $unFrais;
        }

        $erreurs = array();
        if (!$jour) {
            $erreurs[] = 'Choisissez d\'abord le jour du frais.';
        } elseif ($jour->format('Ym') !== $mois) {
            $erreurs[] = 'Le jour doit appartenir au mois de la fiche en cours.';
        } elseif ($jour > new \DateTime('today')) {
            $erreurs[] = 'Le jour ne peut pas être dans le futur.';
        }
        if (!isset($lesFrais[$idFrais])) {
            $erreurs[] = 'Choisissez le type de frais à renseigner.';
        }
        if ($quantite === '' || !estEntierPositif($quantite) || (int) $quantite === 0) {
            $erreurs[] = 'La quantité doit être un nombre entier supérieur à zéro.';
        } elseif ((int) $quantite > 99999) {
            $erreurs[] = 'La quantité est trop grande.';
        }

        if ($erreurs) {
            foreach ($erreurs as $erreur) $this->ajouteMessage('erreurForfait', $erreur);
        } else {
            $this->pdo()->ajouteQuantiteFraisForfait($idVisiteur, $mois, $idFrais, (int) $quantite);
            $unFrais = $lesFrais[$idFrais];
            $this->ajouteMessage('succesForfait', sprintf('Ajouté : %d %s (%s) le %s.',
                $quantite, $unFrais['unite'] ?: '', $unFrais['libelle'], $jour->format('d/m/Y')));
        }
        return $this->versSaisie();
    }

    public function validerfraishorsforfaitAction(Request $request){
        if ($refus = $this->exigeRole(self::ROLE_VISITEUR)) return $refus;
        if ($this->envoiTropLourd($request)) {
            $this->ajouteMessage('erreurHorsForfait', 'Les pièces jointes sont trop lourdes : 5 Mo au plus par fichier.');
            return $this->versSaisie();
        }
        $idVisiteur = $this->session()->get('id');
        $mois = $this->moisCourant();
        $dateFrais = (string) $request->request->get('dateFrais');
        $libelle = trim((string) $request->request->get('libelle'));
        $montant = str_replace(',', '.', trim((string) $request->request->get('montant')));

        // Le calendrier envoie aaaa-mm-jj ; les contrôles de 2013 attendent jj/mm/aaaa.
        if (preg_match('/^(\d{4})-(\d{2})-(\d{2})$/', $dateFrais, $m)) {
            $dateFrais = "$m[3]/$m[2]/$m[1]";
        }
        $lesErreurs = valideInfosFrais($dateFrais,$libelle,$montant);
        if (!$lesErreurs && dateFrancaisVersAnglais($dateFrais) > date('Y-m-d')) {
            $lesErreurs[] = 'La date du frais ne peut pas être dans le futur.';
        }
        if (!$lesErreurs) {
            $idFrais = $this->pdo()->creeNouveauFraisHorsForfait($idVisiteur,$mois,$libelle,$dateFrais,$montant);
            $lesErreurs = $this->enregistreJustificatifs($idFrais, $request->files->get('justificatifs'));
            $this->pdo()->recalculeNbJustificatifs($idVisiteur, $mois);
            $this->ajouteMessage('succesHorsForfait', 'Frais hors forfait ajouté.');
        }
        foreach ($lesErreurs as $erreur) $this->ajouteMessage('erreurHorsForfait', $erreur);
        return $this->versSaisie();
    }

    public function supprimerfraishorsforfaitAction($id){
        if ($refus = $this->exigeRole(self::ROLE_VISITEUR)) return $refus;
        $idVisiteur = $this->session()->get('id');
        $mois = $this->moisCourant();
        $pdo = $this->pdo();
        if(!$pdo->estValideSuppressionFrais($idVisiteur,$mois,$id)){
            return new Response("<h2>Page introuvable erreur 404", 404);
        }
        $this->effaceFichiers($pdo->getLesJustificatifs($id));
        $pdo->supprimerFraisHorsForfait($id);
        $pdo->recalculeNbJustificatifs($idVisiteur, $mois);
        $this->ajouteMessage('succesHorsForfait', 'Frais hors forfait supprimé.');
        return $this->versSaisie();
    }
}
?>
