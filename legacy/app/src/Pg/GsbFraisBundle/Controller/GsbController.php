<?php
namespace Pg\GsbFraisBundle\Controller;
require_once("include/fct.inc.php");
use Symfony\Bundle\FrameworkBundle\Controller\Controller;
use Symfony\Component\HttpFoundation\File\UploadedFile;
use Symfony\Component\HttpFoundation\Request;

/**
 * Socle commun des contrôleurs : contrôle d'accès par rôle et rangement des
 * pièces jointes. Ajout 2026 : le code de 2013 ne vérifiait pas la connexion.
 */
abstract class GsbController extends Controller
{
    const ROLE_VISITEUR = 'visiteur';
    const ROLE_COMPTABLE = 'comptable';
    const ROLE_ADMIN = 'admin';

    /** Rôles de l'espace de gestion : fiches pour les deux, comptes pour l'administrateur seul. */
    protected static $rolesGestion = array(self::ROLE_COMPTABLE, self::ROLE_ADMIN);

    /** Taille maximale d'une pièce jointe, en octets. */
    const TAILLE_MAX_JUSTIFICATIF = 5242880;

    /** Types acceptés, contrôlés sur le contenu du fichier et non sur son nom. */
    private static $typesJustificatif = array(
        'application/pdf' => 'pdf',
        'image/jpeg' => 'jpg',
        'image/png' => 'png',
    );

    protected function pdo()
    {
        return $this->get('pg_gsb_frais.pdo');
    }

    protected function session()
    {
        return $this->get('request_stack')->getCurrentRequest()->getSession();
    }

    /**
     * Retourne une redirection vers l'accueil si l'utilisateur n'a pas le rôle
     * demandé, ou l'un des rôles demandés, null sinon.
     * Usage : if ($refus = $this->exigeRole(...)) return $refus;
     */
    protected function exigeRole($roles)
    {
        $session = $this->session();
        if (!$session->get('id') || !in_array($session->get('role'), (array) $roles, true)) {
            return $this->redirectToRoute('pg_gsb_frais_home');
        }
        return null;
    }

    protected function ajouteMessage($type, $message)
    {
        $this->session()->getFlashBag()->add($type, $message);
    }

    private static $nomsMois = array('janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet',
                                     'août', 'septembre', 'octobre', 'novembre', 'décembre');

    /** « Septembre 2026 » pour 202609. */
    protected static function libelleMois($mois)
    {
        return ucfirst(self::$nomsMois[(int) substr($mois, 4, 2) - 1]).' '.substr($mois, 0, 4);
    }

    /** « 09/2026 » pour 202609 : dans une phrase, évite « de août ». */
    protected static function moisCourt($mois)
    {
        return substr($mois, 4, 2).'/'.substr($mois, 0, 4);
    }

    /** « 30 septembre 2026 ». */
    protected static function dateEnLettres(\DateTime $date)
    {
        return $date->format('j').' '.self::$nomsMois[$date->format('n') - 1].' '.$date->format('Y');
    }

    /** 202610 pour 202609, 202701 pour 202612. */
    protected static function moisSuivant($mois)
    {
        $date = \DateTime::createFromFormat('!Ym', $mois);
        return $date->modify('+1 month')->format('Ym');
    }

    protected function dossierJustificatifs()
    {
        $dossier = $this->getParameter('kernel.root_dir').'/justificatifs';
        if (!is_dir($dossier)) {
            mkdir($dossier, 0775, true);
        }
        return $dossier;
    }

    /**
     * Vrai si la requête a dépassé post_max_size : PHP vide alors $_POST et
     * $_FILES sans rien signaler.
     */
    protected function envoiTropLourd(Request $request)
    {
        return $request->isMethod('POST') && $request->request->count() === 0
            && $request->files->count() === 0 && $request->server->get('CONTENT_LENGTH') > 0;
    }

    /**
     * Range les fichiers envoyés et les rattache au frais hors forfait
     * @param $idFrais
     * @param $fichiers tableau d'UploadedFile, éventuellement null ou vide
     * @return les messages d'erreur, un par fichier refusé
     */
    protected function enregistreJustificatifs($idFrais, $fichiers)
    {
        $erreurs = array();
        if (!is_array($fichiers)) {
            $fichiers = $fichiers ? array($fichiers) : array();
        }
        foreach ($fichiers as $fichier) {
            if (!$fichier instanceof UploadedFile) {
                continue;
            }
            $nom = $fichier->getClientOriginalName();
            if (!$fichier->isValid()) {
                $trop = in_array($fichier->getError(), array(UPLOAD_ERR_INI_SIZE, UPLOAD_ERR_FORM_SIZE));
                $erreurs[] = $trop ? "« $nom » dépasse la taille autorisée."
                                   : "« $nom » n'a pas pu être reçu.";
                continue;
            }
            if ($fichier->getSize() > self::TAILLE_MAX_JUSTIFICATIF) {
                $erreurs[] = "« $nom » dépasse 5 Mo.";
                continue;
            }
            $finfo = new \finfo(FILEINFO_MIME_TYPE);
            $type = $finfo->file($fichier->getPathname());
            if (!isset(self::$typesJustificatif[$type])) {
                $erreurs[] = "« $nom » n'est ni un PDF, ni une image JPEG ou PNG.";
                continue;
            }
            $taille = $fichier->getSize();
            $nomStocke = bin2hex(random_bytes(16)).'.'.self::$typesJustificatif[$type];
            $fichier->move($this->dossierJustificatifs(), $nomStocke);
            $this->pdo()->ajouteJustificatif($idFrais, mb_substr($nom, 0, 255), $nomStocke, $type, $taille);
        }
        return $erreurs;
    }

    /** Supprime du disque les fichiers d'un frais, avant ou après sa suppression en base. */
    protected function effaceFichiers(array $justificatifs)
    {
        foreach ($justificatifs as $justificatif) {
            $chemin = $this->dossierJustificatifs().'/'.basename($justificatif['nomStocke']);
            if (is_file($chemin)) {
                unlink($chemin);
            }
        }
    }
}
