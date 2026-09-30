<?php
namespace Pg\GsbFraisBundle\Controller;
require_once("include/fct.inc.php");
use Symfony\Component\HttpFoundation\Request;

/**
 * Le véhicule du visiteur, ajout 2026. Le remboursement kilométrique est indexé
 * sur sa puissance fiscale et son carburant (RG16) ; le visiteur le déclare
 * lui-même (RG19) et l'historique reste consultable.
 */
class VehiculeController extends GsbController
{
    const JETON = 'gsb_vehicule';

    public function indexAction(Request $request)
    {
        if ($refus = $this->exigeRole(self::ROLE_VISITEUR)) return $refus;
        $idVisiteur = $this->session()->get('id');
        $pdo = $this->pdo();

        if ($request->isMethod('POST')) {
            $idBaremeKm = (string) $request->request->get('idBaremeKm');
            $lesTarifs = array();
            foreach ($pdo->getLeBaremeKm() as $uneLigne) {
                $lesTarifs[$uneLigne['id']] = $uneLigne;
            }
            if (!$this->isCsrfTokenValid(self::JETON, $request->request->get('_jeton'))) {
                $this->ajouteMessage('erreur', 'Le formulaire a expiré, recommencez.');
            } elseif (!isset($lesTarifs[$idBaremeKm])) {
                $this->ajouteMessage('erreur', 'Choisissez la puissance fiscale et le carburant de votre véhicule.');
            } elseif (!$pdo->declareVehicule($idVisiteur, $idBaremeKm)) {
                $this->ajouteMessage('succes', 'C\'est déjà votre véhicule actuel : rien n\'a changé.');
            } else {
                $unTarif = $lesTarifs[$idBaremeKm];
                $this->ajouteMessage('succes', sprintf('Véhicule enregistré : %s %s, remboursé %s € par km.',
                    $unTarif['puissance'], strtolower($unTarif['carburant']), number_format($unTarif['tarif'], 2, ',', ' ')));
            }
            return $this->redirectToRoute('pg_gsb_frais_vehicule');
        }

        $flash = $this->session()->getFlashBag();
        $lesVehicules = $pdo->getLesVehicules($idVisiteur);
        $actuel = ($lesVehicules && $lesVehicules[0]['dateFin'] === null) ? $lesVehicules[0] : null;
        foreach ($lesVehicules as $i => $unVehicule) {
            $lesVehicules[$i]['dateDebut'] = dateAnglaisVersFrancais($unVehicule['dateDebut']);
            $lesVehicules[$i]['dateFin'] = $unVehicule['dateFin'] ? dateAnglaisVersFrancais($unVehicule['dateFin']) : null;
        }
        return $this->render('PgGsbFraisBundle:Vehicule:vehicule.html.twig', array(
            'lebareme' => $pdo->getLeBaremeKm(),
            'lesvehicules' => $lesVehicules,
            'actuel' => $actuel ? $lesVehicules[0] : null,
            'leserreurs' => $flash->get('erreur'),
            'lessucces' => $flash->get('succes'),
        ));
    }
}
?>
