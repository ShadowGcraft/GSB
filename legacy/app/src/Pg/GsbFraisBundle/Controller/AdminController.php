<?php
namespace Pg\GsbFraisBundle\Controller;
require_once("include/fct.inc.php");
use Symfony\Component\HttpFoundation\Request;

/**
 * Espace administrateur, ajout 2026 : traitement des fiches clôturées et
 * gestion des comptes. Toute action qui modifie la base passe par un POST
 * porteur d'un jeton CSRF.
 */
class AdminController extends GsbController
{
    const JETON = 'gsb_admin';

    private static $filtresEtat = array('CL', 'VA', 'RB', 'CR');
    private static $roles = array(self::ROLE_VISITEUR => 'Visiteur', self::ROLE_ADMIN => 'Administrateur');

    /** Contrôle commun : rôle administrateur, et jeton valide pour un POST. */
    private function refus(Request $request = null)
    {
        if ($refus = $this->exigeRole(self::ROLE_ADMIN)) return $refus;
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

    /* ----------------------------------------------------------------- fiches */

    public function fichesAction(Request $request)
    {
        if ($refus = $this->refus()) return $refus;
        $etat = $request->query->get('etat', 'CL');
        if (!in_array($etat, self::$filtresEtat)) {
            $etat = 'tous';
        }
        $lesFiches = $this->pdo()->getLesFichesDesVisiteurs($etat === 'tous' ? null : $etat);
        return $this->render('PgGsbFraisBundle:Admin:fiches.html.twig', array(
            'lesfiches' => $lesFiches, 'etat' => $etat) + $this->messages());
    }

    public function ficheAction($idVisiteur, $mois)
    {
        if ($refus = $this->refus()) return $refus;
        $pdo = $this->pdo();
        $infos = $pdo->getLesInfosFicheFrais($idVisiteur, $mois);
        $visiteur = $pdo->getUnCompte($idVisiteur);
        if (!$infos || !$visiteur) {
            throw $this->createNotFoundException('Fiche introuvable');
        }
        return $this->render('PgGsbFraisBundle:Admin:fiche.html.twig', array(
            'visiteur' => $visiteur,
            'mois' => $mois,
            'nummois' => substr($mois, 4, 2),
            'numannee' => substr($mois, 0, 4),
            'infos' => $infos,
            'datemodif' => dateAnglaisVersFrancais($infos['dateModif']),
            'lesfraisforfait' => $pdo->getLesFraisForfait($idVisiteur, $mois),
            'lesfraishorsforfait' => $pdo->getLesFraisHorsForfait($idVisiteur, $mois),
            'montantcalcule' => $pdo->getMontantCalcule($idVisiteur, $mois),
        ) + $this->messages());
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
            $this->ajouteMessage('succes', ($refuse ? 'Frais refusé : ' : 'Frais réintégré : ').$frais['libelle']);
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
            $this->ajouteMessage('succes', 'Fiche validée et mise en paiement.');
        }
        return $this->versFiche($idVisiteur, $mois);
    }

    public function rembourserFicheAction(Request $request, $idVisiteur, $mois)
    {
        if ($refus = $this->refus($request)) return $refus;
        $fiche = $this->pdo()->getLesInfosFicheFrais($idVisiteur, $mois);
        if (!$fiche || $fiche['idEtat'] !== 'VA') {
            $this->ajouteMessage('erreur', 'Seule une fiche validée peut être marquée remboursée.');
        } else {
            $this->pdo()->majEtatFicheFrais($idVisiteur, $mois, 'RB');
            $this->ajouteMessage('succes', 'Fiche marquée remboursée.');
        }
        return $this->versFiche($idVisiteur, $mois);
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
        if ($refus = $this->refus()) return $refus;
        $compte = array('nom' => '', 'prenom' => '', 'login' => '', 'role' => self::ROLE_VISITEUR);
        $erreursCreation = array();
        if ($request->isMethod('POST')) {
            if ($refus = $this->refus($request)) return $refus;
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
        if ($refus = $this->refus()) return $refus;
        $existant = $this->pdo()->getUnCompte($id);
        if (!$existant) {
            throw $this->createNotFoundException('Compte introuvable');
        }
        $compte = $existant;
        $erreurs = array();
        if ($request->isMethod('POST')) {
            if ($refus = $this->refus($request)) return $refus;
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
        if ($refus = $this->refus($request)) return $refus;
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
