<?php
namespace Pg\GsbFraisBundle\Controller;
require_once("include/fct.inc.php");
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Saisie de la fiche du mois courant.
 *
 * Chaque envoi de formulaire se termine par une redirection vers la page de
 * saisie : recharger la page ne rejoue pas l'ajout d'une quantité. Les messages
 * de la page passent par deux clés, « erreur » et « succes ».
 */
class SaisirFraisController extends GsbController
{
    /** Sans véhicule déclaré, pas de saisie kilométrique (RG20). */
    const MESSAGE_SANS_VEHICULE = 'Déclarez d\'abord votre véhicule, menu « Mon véhicule » : le remboursement des km dépend de sa puissance fiscale.';

    /** Le mois courant, après création de sa fiche si besoin. */
    private function moisCourant()
    {
        $idVisiteur = $this->session()->get('id');
        $mois = getMois(date("d/m/Y"));
        if($this->pdo()->estPremierFraisMois($idVisiteur,$mois)){
            $this->pdo()->creeNouvellesLignesFrais($idVisiteur,$mois);
        } else {
            // Une fiche ouverte avant l'ajout d'un forfait au référentiel reçoit sa ligne.
            $this->pdo()->completeLignesFraisForfait($idVisiteur,$mois);
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
        $vehicule = $pdo->getVehiculeDuMois($idVisiteur, $mois);

        // Correction directe des totaux du mois, formulaire d'origine.
        if($request->isMethod('POST')){
            $lesFrais = $request->request->get('lesFrais');
            if(is_array($lesFrais) && lesQteFraisValides($lesFrais)){
                $lesFrais = array_map('intval', $lesFrais);
                $kmEnregistres = 0;
                foreach ($pdo->getLesFraisForfait($idVisiteur,$mois) as $unFrais) {
                    if ($unFrais['idfrais'] === 'KM') $kmEnregistres = (int) $unFrais['quantite'];
                }
                // Sans véhicule, aucun nouveau km (RG20) ; les autres totaux restent modifiables.
                if (!$vehicule && isset($lesFrais['KM']) && $lesFrais['KM'] > 0 && $lesFrais['KM'] !== $kmEnregistres) {
                    $this->ajouteMessage('erreur', self::MESSAGE_SANS_VEHICULE);
                } else {
                    $pdo->majFraisForfait($idVisiteur,$mois,$lesFrais);
                    $this->ajouteMessage('succes', 'Quantités du mois enregistrées.');
                }
            }
            else{
                $this->ajouteMessage('erreur', 'Les quantités doivent être des nombres entiers.');
            }
            return $this->versSaisie();
        }

        // Après une erreur, le formulaire revient rempli avec la saisie refusée.
        $flash = $this->session()->getFlashBag();
        $saisie = $flash->get('saisie');
        $aujourdhui = new \DateTime('today');
        return $this->render('PgGsbFraisBundle:SaisirFrais:saisirtouslesfrais.html.twig', array(
            'lesfraisforfait' => $pdo->getLesFraisForfait($idVisiteur,$mois),
            'lesfraishorsforfait' => $pdo->getLesFraisHorsForfait($idVisiteur,$mois),
            'lescategories' => array_values($pdo->getLesCategoriesHorsForfait()),
            'vehicule' => $vehicule,
            'libmois' => self::libelleMois($mois),
            'montantestime' => $pdo->getMontantCalcule($idVisiteur,$mois),
            'cloture' => self::delaiCloture(),
            'premierjour' => $aujourdhui->format('Y-m-01'),
            'aujourdhui' => $aujourdhui->format('Y-m-d'),
            'dernierjour' => $aujourdhui->format('Y-m-t'),
            'ilyaunan' => $aujourdhui->modify('-1 year')->format('Y-m-d'),
            'leserreurs' => $flash->get('erreur'),
            'lessucces' => $flash->get('succes'),
            'saisie' => $saisie ? $saisie[0] : array(),
        ));
    }

    /**
     * Formulaire unique « Nouvelle dépense ». La catégorie choisie dit de quoi il
     * s'agit : « forfait-REP » ajoute une quantité à un frais forfaitisé, au prix
     * fixé par le laboratoire ; « horsforfait-TRA » enregistre une dépense au prix
     * payé, avec sa facture. Les deux restent rangés à part en base.
     */
    public function ajouterfraisAction(Request $request)
    {
        if ($refus = $this->exigeRole(self::ROLE_VISITEUR)) return $refus;
        if ($this->envoiTropLourd($request)) {
            $this->ajouteMessage('erreur', 'Les pièces jointes sont trop lourdes : 5 Mo au plus par fichier.');
            return $this->versSaisie();
        }
        $mois = $this->moisCourant();
        $categorie = (string) $request->request->get('categorie');

        if (preg_match('/^forfait-([A-Z]{2,3})$/', $categorie, $m)) {
            $erreurs = $this->ajouteFraisForfait($request, $mois, $m[1]);
        } elseif (preg_match('/^horsforfait-([A-Z]{3})$/', $categorie, $m)) {
            $erreurs = $this->ajouteFraisHorsForfait($request, $mois, $m[1]);
        } else {
            $erreurs = array('Choisissez la catégorie de la dépense.');
        }

        if ($erreurs) {
            foreach ($erreurs as $erreur) $this->ajouteMessage('erreur', $erreur);
            // Seule la facture est à rechoisir : un navigateur ne remplit pas un champ fichier.
            $this->session()->getFlashBag()->add('saisie', array(
                'jour' => (string) $request->request->get('jour'),
                'categorie' => $categorie,
                'quantite' => (string) $request->request->get('quantite'),
                'montant' => (string) $request->request->get('montant'),
                'libelle' => (string) $request->request->get('libelle'),
            ));
        }
        return $this->versSaisie();
    }

    /**
     * Ajoute une quantité à un frais forfaitisé du mois (RG9, RG11, RG20). Le jour
     * sert aux contrôles et au message : la fiche reste mensuelle.
     * @return les messages d'erreur, vide si l'ajout est fait
     */
    private function ajouteFraisForfait(Request $request, $mois, $idFrais)
    {
        $idVisiteur = $this->session()->get('id');
        $jour = \DateTime::createFromFormat('!Y-m-d', (string) $request->request->get('jour'));
        $quantite = trim((string) $request->request->get('quantite'));

        $lesFrais = array();
        foreach ($this->pdo()->getLesFraisForfait($idVisiteur, $mois) as $unFrais) {
            $lesFrais[$unFrais['idfrais']] = $unFrais;
        }

        $erreurs = array();
        // Tout jour du mois de la fiche, passé ou à venir.
        if (!$jour) {
            $erreurs[] = 'Choisissez le jour du frais.';
        } elseif ($jour->format('Ym') !== $mois) {
            $erreurs[] = 'Un frais forfaitisé doit être daté du mois en cours.';
        }
        if (!isset($lesFrais[$idFrais])) {
            $erreurs[] = 'Ce frais forfaitisé n\'existe pas.';
        } elseif ($idFrais === 'KM' && !$this->pdo()->getVehiculeDuMois($idVisiteur, $mois)) {
            $erreurs[] = self::MESSAGE_SANS_VEHICULE;
        }
        if ($quantite === '' || !estEntierPositif($quantite) || (int) $quantite === 0) {
            $erreurs[] = 'La quantité doit être un nombre entier supérieur à zéro.';
        } elseif ((int) $quantite > 99999) {
            $erreurs[] = 'La quantité est trop grande.';
        }
        if ($erreurs) {
            return $erreurs;
        }

        $this->pdo()->ajouteQuantiteFraisForfait($idVisiteur, $mois, $idFrais, (int) $quantite);
        $unFrais = $lesFrais[$idFrais];
        $unite = str_replace('(s)', (int) $quantite > 1 ? 's' : '', (string) $unFrais['unite']);
        $this->ajouteMessage('succes', sprintf('Ajouté le %s : %s, %d %s.',
            $jour->format('d/m/Y'), $unFrais['libelle'], $quantite, $unite));
        return array();
    }

    /**
     * Enregistre une dépense hors forfait au prix payé, avec ses factures (RG23, RG25).
     * Le détail est facultatif, sauf pour « Autre » : sans lui, le libellé
     * enregistré est celui de la catégorie.
     * @return les messages d'erreur, vide si la dépense est enregistrée
     */
    private function ajouteFraisHorsForfait(Request $request, $mois, $idCategorie)
    {
        $idVisiteur = $this->session()->get('id');
        $detail = trim((string) $request->request->get('libelle'));
        $montant = str_replace(',', '.', trim((string) $request->request->get('montant')));

        $lesCategories = $this->pdo()->getLesCategoriesHorsForfait();
        $erreurs = array();
        if (!isset($lesCategories[$idCategorie])) {
            $erreurs[] = 'Choisissez la catégorie de la dépense.';
        } elseif ($detail === '' && $idCategorie === 'AUT') {
            $erreurs[] = 'Précisez la dépense : la catégorie « Autre » demande un détail.';
        }
        $libelle = $detail !== '' ? $detail
                 : (isset($lesCategories[$idCategorie]) ? $lesCategories[$idCategorie]['libelle'] : '');

        // Le calendrier envoie aaaa-mm-jj ; les contrôles de 2013 attendent jj/mm/aaaa.
        $dateFrais = (string) $request->request->get('jour');
        if (preg_match('/^(\d{4})-(\d{2})-(\d{2})$/', $dateFrais, $m)) {
            $dateFrais = "$m[3]/$m[2]/$m[1]";
        }
        // Un libellé manquant est déjà signalé par la catégorie : pas de second message.
        $erreurs = array_merge($erreurs, valideInfosFrais($dateFrais, $libelle !== '' ? $libelle : '-', $montant));
        if (!$erreurs && $montant <= 0) {
            $erreurs[] = 'Le montant doit être supérieur à zéro.';
        }
        // Jusqu'à un an en arrière (RG4), et au plus tard le dernier jour du mois en cours.
        if (!$erreurs && dateFrancaisVersAnglais($dateFrais) > date('Y-m-t')) {
            $erreurs[] = 'La date ne peut pas dépasser la fin du mois en cours.';
        }
        if ($erreurs) {
            return $erreurs;
        }

        $idFrais = $this->pdo()->creeNouveauFraisHorsForfait($idVisiteur, $mois, $libelle, $dateFrais, $montant, $idCategorie);
        // La dépense est enregistrée même si une facture est refusée : on la joindra depuis la liste.
        $erreursFactures = $this->enregistreJustificatifs($idFrais, $request->files->get('justificatifs'));
        $this->pdo()->recalculeNbJustificatifs($idVisiteur, $mois);
        $this->ajouteMessage('succes', sprintf('Dépense ajoutée : %s, %s €.',
            $libelle, number_format((float) $montant, 2, ',', ' ')));
        foreach ($erreursFactures as $erreur) {
            $this->ajouteMessage('erreur', $erreur);
        }
        return array();
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
        $this->ajouteMessage('succes', 'Dépense supprimée.');
        return $this->versSaisie();
    }
}
?>
