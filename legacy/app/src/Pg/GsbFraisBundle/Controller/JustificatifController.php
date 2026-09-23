<?php
namespace Pg\GsbFraisBundle\Controller;
require_once("include/fct.inc.php");
use Symfony\Component\HttpFoundation\BinaryFileResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\ResponseHeaderBag;

/**
 * Pièces jointes des frais hors forfait.
 *
 * Consultation : le visiteur propriétaire, le comptable ou l'administrateur. Ajout et
 * suppression : le propriétaire, tant que la fiche est en cours de saisie.
 */
class JustificatifController extends GsbController
{
    /** Vrai si le visiteur connecté peut encore modifier ce frais. */
    private function estModifiable($frais)
    {
        $session = $this->session();
        if (!$frais || $session->get('role') !== self::ROLE_VISITEUR
            || $frais['idVisiteur'] !== $session->get('id')) {
            return false;
        }
        $fiche = $this->pdo()->getLesInfosFicheFrais($frais['idVisiteur'], $frais['mois']);
        return $fiche && $fiche['idEtat'] === 'CR';
    }

    public function voirAction($id)
    {
        $session = $this->session();
        $justificatif = $this->pdo()->getUnJustificatif($id);
        $autorise = $justificatif && $session->get('id') && (
            in_array($session->get('role'), self::$rolesGestion, true) || $justificatif['idVisiteur'] === $session->get('id'));
        $chemin = $justificatif ? $this->dossierJustificatifs().'/'.basename($justificatif['nomStocke']) : null;
        if (!$autorise || !is_file($chemin)) {
            throw $this->createNotFoundException('Justificatif introuvable');
        }
        $reponse = new BinaryFileResponse($chemin);
        $reponse->headers->set('Content-Type', $justificatif['typeMime']);
        $reponse->headers->set('X-Content-Type-Options', 'nosniff');
        // Symfony refuse « / », « \ » et, dans le nom de repli ASCII, « % ».
        $nom = str_replace(array('/', '\\'), '_', $justificatif['nomOriginal']);
        $reponse->setContentDisposition(ResponseHeaderBag::DISPOSITION_INLINE, $nom,
            preg_replace('/[^\x20-\x7e]|%/', '_', $nom));
        return $reponse;
    }

    public function ajouterAction(Request $request, $id)
    {
        if ($refus = $this->exigeRole(self::ROLE_VISITEUR)) return $refus;
        if ($this->envoiTropLourd($request)) {
            $this->ajouteMessage('erreurHorsForfait', 'Les pièces jointes sont trop lourdes : 5 Mo au plus par fichier.');
            return $this->redirectToRoute('pg_gsb_frais_saisirfrais');
        }
        $frais = $this->pdo()->getUnFraisHorsForfait($id);
        if (!$this->estModifiable($frais)) {
            throw $this->createNotFoundException('Frais introuvable');
        }
        $fichiers = $request->files->get('justificatifs');
        $erreurs = $this->enregistreJustificatifs($id, $fichiers);
        if (!$fichiers || $fichiers === array(null)) {
            $erreurs[] = 'Choisissez au moins un fichier à joindre.';
        } elseif (!$erreurs) {
            $this->ajouteMessage('succesHorsForfait', 'Pièce jointe ajoutée à « '.$frais['libelle'].' ».');
        }
        foreach ($erreurs as $erreur) $this->ajouteMessage('erreurHorsForfait', $erreur);
        $this->pdo()->recalculeNbJustificatifs($frais['idVisiteur'], $frais['mois']);
        return $this->redirectToRoute('pg_gsb_frais_saisirfrais');
    }

    public function supprimerAction($id)
    {
        if ($refus = $this->exigeRole(self::ROLE_VISITEUR)) return $refus;
        $justificatif = $this->pdo()->getUnJustificatif($id);
        $frais = $justificatif ? $this->pdo()->getUnFraisHorsForfait($justificatif['idFraisHorsForfait']) : false;
        if (!$this->estModifiable($frais)) {
            throw $this->createNotFoundException('Justificatif introuvable');
        }
        $this->effaceFichiers(array($justificatif));
        $this->pdo()->supprimeJustificatif($id);
        $this->pdo()->recalculeNbJustificatifs($frais['idVisiteur'], $frais['mois']);
        $this->ajouteMessage('succesHorsForfait', 'Pièce jointe « '.$justificatif['nomOriginal'].' » supprimée.');
        return $this->redirectToRoute('pg_gsb_frais_saisirfrais');
    }
}
?>
