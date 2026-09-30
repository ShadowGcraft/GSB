<?php
namespace Pg\GsbFraisBundle\Controller;
require_once("include/fct.inc.php");
use Dompdf\Dompdf;
use Dompdf\Options;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Espace de gestion, ajout 2026. Le comptable et l'administrateur traitent
 * les fiches clôturées ; seul l'administrateur gère les comptes. Toute action
 * qui modifie la base passe par un POST porteur d'un jeton CSRF.
 */
class AdminController extends GsbController
{
    const JETON = 'gsb_admin';

    private static $filtresEtat = array('CL', 'VA', 'MP', 'RB', 'CR');
    private static $roles = array(self::ROLE_VISITEUR => 'Visiteur', self::ROLE_COMPTABLE => 'Comptable',
                                  self::ROLE_ADMIN => 'Administrateur');

    /** Fiches : comptable ou administrateur. */
    private function refus(Request $request = null)
    {
        return $this->refusPour(self::$rolesGestion, $request);
    }

    /** Comptes : administrateur seul. */
    private function refusComptes(Request $request = null)
    {
        return $this->refusPour(self::ROLE_ADMIN, $request);
    }

    /** Contrôle commun : rôle attendu, et jeton valide pour un POST. */
    private function refusPour($roles, Request $request = null)
    {
        if ($refus = $this->exigeRole($roles)) return $refus;
        if ($request && !$this->isCsrfTokenValid(self::JETON, $request->request->get('_jeton'))) {
            $this->ajouteMessage('erreur', 'Le formulaire a expiré, recommencez.');
            return $this->redirect($request->headers->get('referer') ?: $this->generateUrl('pg_gsb_frais_admin_fiches'));
        }
        return null;
    }

    private function versFiche($idVisiteur, $mois)
    {
        return $this->redirectToRoute('pg_gsb_frais_admin_fiche', array('idVisiteur' => $idVisiteur, 'mois' => $mois));
    }

    private function messages()
    {
        $flash = $this->session()->getFlashBag();
        return array('leserreurs' => $flash->get('erreur'), 'lessucces' => $flash->get('succes'));
    }

    /** Le mois dont la campagne de validation est en cours : le mois écoulé. */
    private static function moisPrecedent()
    {
        return date('Ym', strtotime('first day of last month'));
    }

    /** Tout ce qu'affichent l'écran d'une fiche et son PDF, ou null si elle n'existe pas. */
    private function donneesFiche($idVisiteur, $mois)
    {
        $pdo = $this->pdo();
        $infos = $pdo->getLesInfosFicheFrais($idVisiteur, $mois);
        $visiteur = $pdo->getUnCompte($idVisiteur);
        if (!$infos || !$visiteur) {
            return null;
        }
        return array(
            'visiteur' => $visiteur,
            'mois' => $mois,
            'nummois' => substr($mois, 4, 2),
            'numannee' => substr($mois, 0, 4),
            'libmois' => self::libelleMois($mois),
            'infos' => $infos,
            'datemodif' => dateAnglaisVersFrancais($infos['dateModif']),
            'lesfraisforfait' => $pdo->getLesFraisForfait($idVisiteur, $mois),
            'lesfraishorsforfait' => $pdo->getLesFraisHorsForfait($idVisiteur, $mois),
            'vehicule' => $pdo->getVehiculeDuMois($idVisiteur, $mois),
            'montantcalcule' => $pdo->getMontantCalcule($idVisiteur, $mois),
        );
    }

    /* ----------------------------------------------------------------- fiches */

    public function fichesAction(Request $request)
    {
        if ($refus = $this->refus()) return $refus;
        $etat = $request->query->get('etat', 'CL');
        if (!in_array($etat, self::$filtresEtat)) {
            $etat = 'tous';
        }
        $pdo = $this->pdo();
        $moisPrecedent = self::moisPrecedent();
        // Le choix du mois porte sur l'année écoulée, mois courant compris.
        $lesMois = array();
        for ($i = 0; $i <= 12; $i++) {
            $unMois = date('Ym', strtotime("first day of -$i month"));
            $lesMois[$unMois] = self::libelleMois($unMois);
        }
        return $this->render('PgGsbFraisBundle:Admin:fiches.html.twig', array(
            'lesfiches' => $pdo->getLesFichesDesVisiteurs($etat === 'tous' ? null : $etat),
            'etat' => $etat,
            'lesvisiteurs' => $pdo->getLesVisiteurs(),
            'lesmois' => $lesMois,
            'visiteurchoisi' => $request->query->get('visiteur'),
            'moischoisi' => $request->query->get('mois', $moisPrecedent),
            'nbacloturer' => $pdo->compteFichesACloturer(date('Ym')),
            'moisprecedent' => self::moisCourt($moisPrecedent),
            'nbfichesmoisprecedent' => count($pdo->getLesFichesClotureesDuMois($moisPrecedent)),
        ) + $this->messages());
    }

    /**
     * Étapes 2 et 3 du cas « Valider fiche de frais » : le comptable choisit le
     * visiteur et le mois. Exception 4-a : aucune fiche, retour au choix.
     */
    public function rechercherAction(Request $request)
    {
        if ($refus = $this->refus()) return $refus;
        $idVisiteur = (string) $request->query->get('visiteur');
        $mois = (string) $request->query->get('mois');
        if (preg_match('/^\d{6}$/', $mois) && $this->pdo()->getLesInfosFicheFrais($idVisiteur, $mois)) {
            return $this->versFiche($idVisiteur, $mois);
        }
        $this->ajouteMessage('erreur', 'Pas de fiche de frais pour ce visiteur ce mois.');
        return $this->redirectToRoute('pg_gsb_frais_admin_fiches', array('visiteur' => $idVisiteur, 'mois' => $mois));
    }

    /** Script de début de campagne : clôture des fiches des mois écoulés (RG32). */
    public function cloturerFichesAction(Request $request)
    {
        if ($refus = $this->refus($request)) return $refus;
        $nb = $this->pdo()->clotureFichesEcoulees(date('Ym'));
        $this->ajouteMessage('succes', $nb
            ? $nb.' fiche'.($nb > 1 ? 's clôturées' : ' clôturée').' : elles sont prêtes à être validées.'
            : 'Aucune fiche à clôturer.');
        return $this->redirectToRoute('pg_gsb_frais_admin_fiches');
    }

    public function ficheAction($idVisiteur, $mois)
    {
        if ($refus = $this->refus()) return $refus;
        $donnees = $this->donneesFiche($idVisiteur, $mois);
        if (!$donnees) {
            throw $this->createNotFoundException('Fiche introuvable');
        }
        return $this->render('PgGsbFraisBundle:Admin:fiche.html.twig', $donnees + array(
            'moissuivant' => self::moisCourt(self::moisSuivant($mois)),
        ) + $this->messages());
    }

    /**
     * Étapes 5 et 6 : le comptable corrige les quantités forfaitisées d'une fiche
     * clôturée. La correction remplace la saisie du visiteur, sans trace (RG36, RG37).
     */
    public function corrigerForfaitAction(Request $request, $idVisiteur, $mois)
    {
        if ($refus = $this->refus($request)) return $refus;
        $pdo = $this->pdo();
        $fiche = $pdo->getLesInfosFicheFrais($idVisiteur, $mois);
        if (!$fiche || $fiche['idEtat'] !== 'CL') {
            $this->ajouteMessage('erreur', 'Seule une fiche clôturée, pas encore validée, peut être corrigée.');
            return $this->versFiche($idVisiteur, $mois);
        }
        $lesFrais = $request->request->get('lesFrais');
        $valides = is_array($lesFrais);
        $lesQuantites = array();
        foreach ($pdo->getLesFraisForfait($idVisiteur, $mois) as $unFrais) {
            $qte = $valides && isset($lesFrais[$unFrais['idfrais']]) ? trim((string) $lesFrais[$unFrais['idfrais']]) : '';
            // Exception 6-a : entier positif ou nul, sinon rien n'est enregistré (RG11).
            if ($qte === '' || !estEntierPositif($qte) || strlen($qte) > 5) {
                $valides = false;
                break;
            }
            $lesQuantites[$unFrais['idfrais']] = (int) $qte;
        }
        if (!$valides) {
            $this->ajouteMessage('erreur', 'Chaque quantité doit être un nombre entier positif ou nul : rien n\'a été modifié.');
        } else {
            $pdo->majFraisForfait($idVisiteur, $mois, $lesQuantites);
            $this->ajouteMessage('succes', 'Modification prise en compte : quantités et montant dû sont à jour.');
        }
        return $this->versFiche($idVisiteur, $mois);
    }

    /** Refuse un frais hors forfait, ou le réintègre : il sort ou rentre dans le montant dû. */
    public function refuserFraisAction(Request $request, $id)
    {
        if ($refus = $this->refus($request)) return $refus;
        $frais = $this->pdo()->getUnFraisHorsForfait($id);
        if (!$frais) {
            throw $this->createNotFoundException('Frais introuvable');
        }
        $fiche = $this->pdo()->getLesInfosFicheFrais($frais['idVisiteur'], $frais['mois']);
        if ($fiche['idEtat'] !== 'CL') {
            $this->ajouteMessage('erreur', 'Seule une fiche clôturée, pas encore validée, peut être modifiée.');
        } else {
            $refuse = !$frais['refuse'];
            $this->pdo()->majRefusFraisHorsForfait($id, $refuse);
            $this->pdo()->recalculeNbJustificatifs($frais['idVisiteur'], $frais['mois']);
            $this->ajouteMessage('succes', ($refuse ? 'Frais refusé : ' : 'Frais réintégré : ').$frais['libelle']);
        }
        return $this->versFiche($frais['idVisiteur'], $frais['mois']);
    }

    /**
     * Reporte un frais hors forfait sur la fiche du mois suivant, créée au besoin :
     * sa facture est arrivée après le 10 (RG28). La ligne garde sa date et son
     * mois d'origine (RG29).
     */
    public function reporterFraisAction(Request $request, $id)
    {
        if ($refus = $this->refus($request)) return $refus;
        $pdo = $this->pdo();
        $frais = $pdo->getUnFraisHorsForfait($id);
        if (!$frais) {
            throw $this->createNotFoundException('Frais introuvable');
        }
        $fiche = $pdo->getLesInfosFicheFrais($frais['idVisiteur'], $frais['mois']);
        $cible = self::moisSuivant($frais['mois']);
        $ficheCible = $pdo->getLesInfosFicheFrais($frais['idVisiteur'], $cible);
        if ($fiche['idEtat'] !== 'CL') {
            $this->ajouteMessage('erreur', 'Seule une fiche clôturée, pas encore validée, peut être modifiée.');
        } elseif ($frais['refuse']) {
            $this->ajouteMessage('erreur', 'Un frais refusé ne se reporte pas : réintégrez-le d\'abord.');
        } elseif ($cible > date('Ym')) {
            $this->ajouteMessage('erreur', 'Le mois '.self::moisCourt($cible).' n\'a pas encore commencé : le report attendra.');
        } elseif ($ficheCible && !in_array($ficheCible['idEtat'], array('CR', 'CL'), true)) {
            $this->ajouteMessage('erreur', 'La fiche '.self::moisCourt($cible).' est déjà validée : le report est impossible.');
        } else {
            if (!$ficheCible) {
                $pdo->creeFicheFrais($frais['idVisiteur'], $cible);
            }
            $pdo->reporteFraisHorsForfait($id, $cible);
            $pdo->recalculeNbJustificatifs($frais['idVisiteur'], $frais['mois']);
            $pdo->recalculeNbJustificatifs($frais['idVisiteur'], $cible);
            $this->ajouteMessage('succes', 'Frais reporté sur la fiche '.self::moisCourt($cible).' : '.$frais['libelle']);
        }
        return $this->versFiche($frais['idVisiteur'], $frais['mois']);
    }

    public function validerFicheAction(Request $request, $idVisiteur, $mois)
    {
        if ($refus = $this->refus($request)) return $refus;
        $fiche = $this->pdo()->getLesInfosFicheFrais($idVisiteur, $mois);
        $montant = str_replace(',', '.', trim((string) $request->request->get('montantValide')));
        if (!$fiche || $fiche['idEtat'] !== 'CL') {
            $this->ajouteMessage('erreur', 'Seule une fiche clôturée peut être validée.');
        } elseif (!is_numeric($montant) || $montant < 0 || $montant >= 100000000) {
            $this->ajouteMessage('erreur', 'Le montant validé doit être un nombre positif.');
        } else {
            $this->pdo()->majMontantValide($idVisiteur, $mois, number_format((float) $montant, 2, '.', ''));
            $this->pdo()->majEtatFicheFrais($idVisiteur, $mois, 'VA');
            $this->ajouteMessage('succes', 'Fiche validée.');
        }
        return $this->versFiche($idVisiteur, $mois);
    }

    /** Validée → Mise en paiement, au 20 du mois suivant la saisie (RG44). */
    public function mettreEnPaiementAction(Request $request, $idVisiteur, $mois)
    {
        if ($refus = $this->refus($request)) return $refus;
        $fiche = $this->pdo()->getLesInfosFicheFrais($idVisiteur, $mois);
        if (!$fiche || $fiche['idEtat'] !== 'VA') {
            $this->ajouteMessage('erreur', 'Seule une fiche validée peut être mise en paiement.');
        } else {
            $this->pdo()->majEtatFicheFrais($idVisiteur, $mois, 'MP');
            $this->ajouteMessage('succes', 'Fiche mise en paiement.');
        }
        return $this->versFiche($idVisiteur, $mois);
    }

    /** Mise en paiement → Remboursée, une fois le paiement effectué (RG45). */
    public function rembourserFicheAction(Request $request, $idVisiteur, $mois)
    {
        if ($refus = $this->refus($request)) return $refus;
        $fiche = $this->pdo()->getLesInfosFicheFrais($idVisiteur, $mois);
        if (!$fiche || $fiche['idEtat'] !== 'MP') {
            $this->ajouteMessage('erreur', 'Seule une fiche mise en paiement peut être marquée remboursée.');
        } else {
            $this->pdo()->majEtatFicheFrais($idVisiteur, $mois, 'RB');
            $this->ajouteMessage('succes', 'Fiche marquée remboursée.');
        }
        return $this->versFiche($idVisiteur, $mois);
    }

    /* -------------------------------------------------------------------- PDF */

    /** Une fiche au format de l'annexe 1, pour l'archive papier. */
    public function pdfAction($idVisiteur, $mois)
    {
        if ($refus = $this->refus()) return $refus;
        $donnees = $this->donneesFiche($idVisiteur, $mois);
        if (!$donnees) {
            throw $this->createNotFoundException('Fiche introuvable');
        }
        if ($donnees['infos']['idEtat'] === 'CR') {
            $this->ajouteMessage('erreur', 'Cette fiche est encore en cours de saisie : elle s\'imprimera une fois clôturée.');
            return $this->versFiche($idVisiteur, $mois);
        }
        return $this->reponsePdf(array($donnees), 'fiche-frais-'.$idVisiteur.'-'.$mois.'.pdf');
    }

    /** D'un seul clic, toutes les fiches clôturées du mois précédent, une par page. */
    public function pdfLotAction()
    {
        if ($refus = $this->refus()) return $refus;
        $mois = self::moisPrecedent();
        $lesFiches = array();
        foreach ($this->pdo()->getLesFichesClotureesDuMois($mois) as $uneFiche) {
            $lesFiches[] = $this->donneesFiche($uneFiche['idVisiteur'], $mois);
        }
        if (!$lesFiches) {
            $this->ajouteMessage('erreur', 'Aucune fiche clôturée pour '.self::moisCourt($mois)
                .' : lancez d\'abord la clôture des fiches.');
            return $this->redirectToRoute('pg_gsb_frais_admin_fiches');
        }
        return $this->reponsePdf($lesFiches, 'fiches-frais-'.$mois.'.pdf');
    }

    private function reponsePdf(array $lesFiches, $nomFichier)
    {
        $logo = $this->get('kernel')->locateResource('@PgGsbFraisBundle/Resources/public/images/logo.jpg');
        $html = $this->renderView('PgGsbFraisBundle:Pdf:fiches.html.twig', array(
            'lesfiches' => $lesFiches,
            // En JPEG et en ligne : dompdf n'a ainsi besoin ni de GD ni d'accès aux fichiers.
            'logo' => base64_encode(file_get_contents($logo)),
            'datejour' => self::dateEnLettres(new \DateTime()),
        ));
        $options = new Options();
        $options->setIsRemoteEnabled(false);
        $options->setIsJavascriptEnabled(false);
        $options->setDefaultFont('DejaVu Serif');
        $options->setFontCache($this->getParameter('kernel.cache_dir'));
        $dompdf = new Dompdf($options);
        $dompdf->loadHtml($html, 'UTF-8');
        $dompdf->setPaper('A4', 'portrait');
        $dompdf->render();
        return new Response($dompdf->output(), 200, array(
            'Content-Type' => 'application/pdf',
            'Content-Disposition' => 'inline; filename="'.$nomFichier.'"',
        ));
    }

    /* ----------------------------------------------------------------- comptes */

    /** Contrôle les champs d'un compte ; le mot de passe n'est exigé qu'à la création. */
    private function valideCompte(array $compte, $idModifie = null)
    {
        $erreurs = array();
        if ($compte['nom'] === '' || mb_strlen($compte['nom']) > 30) $erreurs[] = 'Le nom est obligatoire (30 caractères au plus).';
        if ($compte['prenom'] === '' || mb_strlen($compte['prenom']) > 30) $erreurs[] = 'Le prénom est obligatoire (30 caractères au plus).';
        if (!preg_match('/^[A-Za-z0-9._-]{3,45}$/', $compte['login'])) {
            $erreurs[] = 'Le login fait de 3 à 45 caractères : lettres sans accent, chiffres, point, tiret.';
        } elseif ($this->pdo()->existeLogin($compte['login'], $idModifie)) {
            $erreurs[] = 'Ce login est déjà utilisé.';
        }
        if (($idModifie === null || $compte['mdp'] !== '') && (mb_strlen($compte['mdp']) < 5 || mb_strlen($compte['mdp']) > 45)) {
            $erreurs[] = 'Le mot de passe fait de 5 à 45 caractères.';
        }
        if (!isset(self::$roles[$compte['role']])) $erreurs[] = 'Rôle inconnu.';
        return $erreurs;
    }

    private function lireCompte(Request $request)
    {
        $compte = array();
        foreach (array('nom', 'prenom', 'login', 'mdp', 'role') as $champ) {
            $compte[$champ] = trim((string) $request->request->get($champ));
        }
        return $compte;
    }

    public function comptesAction(Request $request)
    {
        if ($refus = $this->refusComptes()) return $refus;
        $compte = array('nom' => '', 'prenom' => '', 'login' => '', 'role' => self::ROLE_VISITEUR);
        $erreursCreation = array();
        if ($request->isMethod('POST')) {
            if ($refus = $this->refusComptes($request)) return $refus;
            $compte = $this->lireCompte($request);
            $erreursCreation = $this->valideCompte($compte);
            if (!$erreursCreation) {
                $id = $this->pdo()->creeCompte($compte['nom'], $compte['prenom'], $compte['login'], $compte['mdp'], $compte['role']);
                $this->ajouteMessage('succes', "Compte créé pour {$compte['prenom']} {$compte['nom']} (identifiant $id).");
                return $this->redirectToRoute('pg_gsb_frais_admin_comptes');
            }
        }
        return $this->render('PgGsbFraisBundle:Admin:comptes.html.twig', array(
            'lescomptes' => $this->pdo()->getLesComptes(),
            'roles' => self::$roles,
            'nouveau' => $compte,
            'erreurscreation' => $erreursCreation,
        ) + $this->messages());
    }

    public function modifierCompteAction(Request $request, $id)
    {
        if ($refus = $this->refusComptes()) return $refus;
        $existant = $this->pdo()->getUnCompte($id);
        if (!$existant) {
            throw $this->createNotFoundException('Compte introuvable');
        }
        $compte = $existant;
        $erreurs = array();
        if ($request->isMethod('POST')) {
            if ($refus = $this->refusComptes($request)) return $refus;
            $compte = $this->lireCompte($request) + array('id' => $id, 'actif' => $existant['actif']);
            $erreurs = $this->valideCompte($compte, $id);
            if ($id === $this->session()->get('id') && $compte['role'] !== self::ROLE_ADMIN) {
                $erreurs[] = 'Vous ne pouvez pas retirer votre propre rôle administrateur.';
            }
            if (!$erreurs) {
                $this->pdo()->majCompte($id, $compte['nom'], $compte['prenom'], $compte['login'], $compte['mdp'], $compte['role']);
                if ($id === $this->session()->get('id')) {
                    $this->session()->set('nom', $compte['nom']);
                    $this->session()->set('prenom', $compte['prenom']);
                }
                $this->ajouteMessage('succes', "Compte de {$compte['prenom']} {$compte['nom']} modifié.");
                return $this->redirectToRoute('pg_gsb_frais_admin_comptes');
            }
        }
        return $this->render('PgGsbFraisBundle:Admin:compte.html.twig', array(
            'compte' => $compte, 'roles' => self::$roles, 'leserreurs' => $erreurs, 'lessucces' => array()));
    }

    public function activerCompteAction(Request $request, $id)
    {
        if ($refus = $this->refusComptes($request)) return $refus;
        $compte = $this->pdo()->getUnCompte($id);
        if (!$compte) {
            throw $this->createNotFoundException('Compte introuvable');
        }
        if ($id === $this->session()->get('id')) {
            $this->ajouteMessage('erreur', 'Vous ne pouvez pas désactiver votre propre compte.');
        } else {
            $this->pdo()->majActivationCompte($id, !$compte['actif']);
            $this->ajouteMessage('succes', ($compte['actif'] ? 'Compte désactivé : ' : 'Compte réactivé : ')
                ."{$compte['prenom']} {$compte['nom']}");
        }
        return $this->redirectToRoute('pg_gsb_frais_admin_comptes');
    }
}
?>
