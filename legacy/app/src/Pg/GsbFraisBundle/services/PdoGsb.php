<?php
namespace Pg\GsbFraisBundle\services;
use PDO;
class PdoGsb{   		
	private static $monPdo;
	private static $monPdoGsb=null;
/**
 * Constructeur public, crée l'instance de PDO qui sera sollicitée
 * pour toutes les méthodes de la classe
 */				

        public function __construct($serveur,$bdd,$user,$mdp){
            PdoGsb::$monPdo = new PDO($serveur.';'.$bdd, $user, $mdp); 
            PdoGsb::$monPdo->query("SET CHARACTER SET utf8");
            $this->appliqueEvolutions();
	}

/**
 * Met à niveau une base installée avant les évolutions 2026
 *
 * Chaque script de Resources/sql a son témoin : une requête qui compte ce que
 * le script crée en dernier. Tant qu'elle renvoie zéro, le script est rejoué,
 * dans l'ordre. Toutes leurs instructions sont idempotentes.
 */
        private function appliqueEvolutions(){
                $evolutions = array(
                        'evolutions-2026.sql' => "select count(*) from information_schema.tables
                                where table_schema = database() and table_name = 'justificatif'",
                        'evolutions-2026-comptable.sql' => "select count(*) from visiteur where id = 'cpt'",
                        'evolutions-2026-sujet.sql' => "select count(*) from etat where id = 'MP'",
                );
                foreach ($evolutions as $fichier => $temoin) {
                        if (PdoGsb::$monPdo->query($temoin)->fetchColumn() > 0) {
                                continue;
                        }
                        $script = file_get_contents(__DIR__.'/../Resources/sql/'.$fichier);
                        $script = preg_replace('/^\s*--.*$/m', '', $script);
                        foreach (explode(';', $script) as $instruction) {
                                if (trim($instruction) !== '') {
                                        PdoGsb::$monPdo->exec($instruction);
                                }
                        }
                }
        }
        
	public function _destruct(){
		PdoGsb::$monPdo = null;
	}
/**
 * Fonction statique qui crée l'unique instance de la classe
 
 * Appel : $instancePdoGsb = PdoGsb::getPdoGsb();
 
 * @return l'unique objet de la classe PdoGsb
 */
	public  static function getPdoGsb(){
		if(PdoGsb::$monPdoGsb==null){
			PdoGsb::$monPdoGsb= new PdoGsb();
		}
		return PdoGsb::$monPdoGsb;  
	}
        
        
/**
 * Retourne les informations d'un visiteur
 
 * @param $login 
 * @param $mdp
 * @return l'id, le nom, le prénom, le rôle et l'activation sous la forme d'un tableau associatif
*/
	public function getInfosVisiteur($login, $mdp){
                $req = "select visiteur.id as id, visiteur.nom as nom, visiteur.prenom as prenom,
                visiteur.role as role, visiteur.actif as actif from visiteur
		where visiteur.login=:log and visiteur.mdp=:md";
		$stmt = PdoGsb::$monPdo->prepare($req);
                $stmt->bindParam(':log', $login);
		$stmt->bindParam(':md', $mdp);
                $stmt->execute();
		$ligne = $stmt->fetch();
            //    var_dump($ligne);
		return $ligne;
	}

/**
 * Retourne sous forme d'un tableau associatif toutes les lignes de frais hors forfait
 * concernées par les deux arguments
 
 * La boucle foreach ne peut être utilisée ici car on procède
 * à une modification de la structure itérée - transformation du champ date-
 
 * @param $idVisiteur 
 * @param $mois sous la forme aaaamm
 * @return tous les champs des lignes de frais hors forfait sous la forme d'un tableau associatif 
*/
	public function getLesFraisHorsForfait($idVisiteur,$mois){
	    $req = "select * from lignefraishorsforfait where lignefraishorsforfait.idvisiteur = :idVisiteur 
		and lignefraishorsforfait.mois = :mois ";
                $stmt = PdoGsb::$monPdo->prepare($req);
                $stmt->bindParam(':idVisiteur', $idVisiteur);
		$stmt->bindParam(':mois', $mois);
                $stmt->execute();
		$lesLignes = $stmt->fetchAll();
		$nbLignes = count($lesLignes);
		for ($i=0; $i<$nbLignes; $i++){
			$date = $lesLignes[$i]['date'];
			$lesLignes[$i]['date'] =  dateAnglaisVersFrancais($date);
			$lesLignes[$i]['justificatifs'] = $this->getLesJustificatifs($lesLignes[$i]['id']);
		}
		return $lesLignes;
	}
/**
 * Retourne le nombre de justificatif d'un visiteur pour un mois donné
 
 * @param $idVisiteur 
 * @param $mois sous la forme aaaamm
 * @return le nombre entier de justificatifs 
*/
	public function getNbjustificatifs($idVisiteur, $mois){
		$req = "select fichefrais.nbjustificatifs as nb from  fichefrais where fichefrais.idvisiteur =:idVisiteur and fichefrais.mois = :mois";
		$stmt = PdoGsb::$monPdo->prepare($req);
                $stmt->bindParam(':idVisiteur', $idVisiteur);
		$stmt->bindParam(':mois', $mois);
                $stmt->execute();
		$laLigne = $stmt->fetch();
		return $laLigne['nb'];
	}
/**
 * Condition SQL qui retient les véhicules d'un visiteur valides pendant un mois :
 * début au plus tard le dernier jour du mois, fin nulle ou au plus tôt le premier
 * jour du mois (RG17).
 * @param $visiteur expression SQL de l'identifiant du visiteur
 * @param $premierJour expression SQL du premier jour du mois
 * @param $dernierJour expression SQL du dernier jour du mois
 */
        private static function conditionVehiculeDuMois($visiteur, $premierJour, $dernierJour){
                return "vehicule.idVisiteur = $visiteur
                        and vehicule.dateDebut <= $dernierJour
                        and (vehicule.dateFin is null or vehicule.dateFin >= $premierJour)";
        }

/**
 * Montant unitaire d'une ligne forfaitisée, en SQL, dans une requête qui joint
 * lignefraisforfait et fraisforfait.
 *
 * Pour le kilométrage : le tarif du dernier véhicule valide pendant le mois de la
 * fiche (RG16, RG17). Un mois sans véhicule déclaré date d'avant le barème : il
 * garde l'ancien taux unique du référentiel. La saisie de nouveaux km sans
 * véhicule est bloquée par le contrôleur (RG20).
 */
        private static function montantUnitaireSql(){
                $premierJour = "str_to_date(concat(lignefraisforfait.mois, '01'), '%Y%m%d')";
                $tarifVehicule = "select baremekm.tarif from vehicule
                        inner join baremekm on baremekm.id = vehicule.idBaremeKm
                        where ".self::conditionVehiculeDuMois('lignefraisforfait.idVisiteur', $premierJour, "last_day($premierJour)")."
                        order by vehicule.dateDebut desc, vehicule.id desc limit 1";
                return "(case when fraisforfait.id = 'KM'
                        then coalesce(($tarifVehicule), fraisforfait.montant)
                        else fraisforfait.montant end)";
        }

/**
 * Retourne sous forme d'un tableau associatif toutes les lignes de frais au forfait
 * concernées par les deux arguments

 * @param $idVisiteur
 * @param $mois sous la forme aaaamm
 * @return l'id, le libelle, la quantité, le montant unitaire et le total de la ligne,
 *         arrondi au centime (RG8), sous la forme d'un tableau associatif
*/
	public function getLesFraisForfait($idVisiteur, $mois){
		$montant = self::montantUnitaireSql();
		$req = "select fraisforfait.id as idfrais, fraisforfait.libelle as libelle,
		$montant as montant, round(lignefraisforfait.quantite * $montant, 2) as total,
		fraisforfait.description as description, fraisforfait.unite as unite,
		lignefraisforfait.quantite as quantite from lignefraisforfait inner join fraisforfait
		on fraisforfait.id = lignefraisforfait.idfraisforfait
		where lignefraisforfait.idvisiteur = :idVisiteur and lignefraisforfait.mois= :mois
		order by lignefraisforfait.idfraisforfait";
		$stmt = PdoGsb::$monPdo->prepare($req);
                $stmt->bindParam(':idVisiteur', $idVisiteur);
		$stmt->bindParam(':mois', $mois);
                $stmt->execute();
		$lesLignes = $stmt->fetchAll();
		return $lesLignes; 
	}
/**
 * Retourne tous les id de la table FraisForfait
 
 * @return un tableau associatif 
*/
	public function getLesIdFrais(){
		$req = "select fraisforfait.id as idfrais from fraisforfait order by fraisforfait.id";
		$stmt = PdoGsb::$monPdo->prepare($req);
                $stmt->execute();
		$lesLignes = $stmt->fetchAll();
		return $lesLignes;
	}
/**
 * Met à jour la table ligneFraisForfait
 
 * Met à jour la table ligneFraisForfait pour un visiteur et
 * un mois donné en enregistrant les nouveaux montants
 
 * @param $idVisiteur 
 * @param $mois sous la forme aaaamm
 * @param $lesFrais tableau associatif de clé idFrais et de valeur la quantité pour ce frais
 * @return un tableau associatif 
*/
	public function majFraisForfait($idVisiteur, $mois, $lesFrais){
		$lesCles = array_keys($lesFrais);
		foreach($lesCles as $unIdFrais){
			$req = "update lignefraisforfait set lignefraisforfait.quantite = :qte
			where lignefraisforfait.idvisiteur = :idVisiteur and lignefraisforfait.mois = :mois
			and lignefraisforfait.idfraisforfait = :unIdFrais";
                         $stmt = PdoGsb::$monPdo->prepare($req);
                        // Liée plutôt que concaténée : le comptable corrige aussi ces quantités.
                        $stmt->bindValue(':qte', (int) $lesFrais[$unIdFrais], PDO::PARAM_INT);
                        $stmt->bindParam(':idVisiteur', $idVisiteur);
                        $stmt->bindParam(':mois', $mois);
                         $stmt->bindParam(':unIdFrais', $unIdFrais);
                        $stmt->execute();
		}
		
	}
/**
 * met à jour le nombre de justificatifs de la table ficheFrais
 * pour le mois et le visiteur concerné
 
 * @param $idVisiteur 
 * @param $mois sous la forme aaaamm
*/
        public function majNbJustificatifs($idVisiteur, $mois, $nbJustificatifs){
                $req = "update fichefrais set nbjustificatifs = :nbJustificatifs 
                where fichefrais.idvisiteur = :idVisiteur and fichefrais.mois = :mois";
                $stmt = PdoGsb::$monPdo->prepare($req);
                $stmt->bindParam(':idVisiteur', $idVisiteur);
                $stmt->bindParam(':mois', $mois);
                $stmt->bindParam(':nbJustificatifs', $nbJustificatifs);
                $stmt->execute();
        }
/**
 * Teste si un visiteur possède une fiche de frais pour le mois passé en argument
 
 * @param $idVisiteur 
 * @param $mois sous la forme aaaamm
 * @return vrai ou faux 
*/	
        public function estPremierFraisMois($idVisiteur,$mois)
        {
                $ok = false;
                $req = "select count(*) as nblignesfrais from fichefrais 
                where fichefrais.mois = :mois and fichefrais.idvisiteur = :idVisiteur";
                $stmt = PdoGsb::$monPdo->prepare($req);
                $stmt->bindParam(':idVisiteur', $idVisiteur);
                $stmt->bindParam(':mois', $mois);
                $stmt->execute();
                $laLigne = $stmt->fetch();
                if($laLigne['nblignesfrais'] == 0){
                        $ok = true;
                }
                return $ok;
        }
/**
 * Retourne le dernier mois en cours d'un visiteur
 
 * @param $idVisiteur 
 * @return le mois sous la forme aaaamm
*/	
        public function dernierMoisSaisi($idVisiteur){
                $req = "select max(mois) as dernierMois from fichefrais where fichefrais.idvisiteur = :idVisiteur";
                $stmt = PdoGsb::$monPdo->prepare($req);
                $stmt->bindParam(':idVisiteur', $idVisiteur);
                $stmt->execute();
                $laLigne = $stmt->fetch();
                $dernierMois = $laLigne['dernierMois'];
                return $dernierMois;
        }
	
/**
 * Crée une nouvelle fiche de frais et les lignes de frais au forfait pour un visiteur et un mois donnés
 
 * récupère le dernier mois en cours de traitement, met à 'CL' son champs idEtat, crée une nouvelle fiche de frais
 * avec un idEtat à 'CR' et crée les lignes de frais forfait de quantités nulles 
 * @param $idVisiteur 
 * @param $mois sous la forme aaaamm
*/
        public function creeNouvellesLignesFrais($idVisiteur,$mois){
                $dernierMois = $this->dernierMoisSaisi($idVisiteur);
                $laDerniereFiche = $this->getLesInfosFicheFrais($idVisiteur,$dernierMois);
                // Un visiteur tout juste créé n'a encore aucune fiche à clôturer.
                if($laDerniereFiche && $laDerniereFiche['idEtat']=='CR'){
                                $this->majEtatFicheFrais($idVisiteur, $dernierMois,'CL');

                }
                $this->creeFicheFrais($idVisiteur, $mois);
        }
/**
 * Crée une fiche de frais à l'état 'CR' et ses lignes de frais au forfait à zéro,
 * sans clôturer aucune autre fiche
 *
 * Sert aussi au report d'un frais hors forfait sur un mois dont la fiche
 * n'existe pas encore (RG28).
 * @param $idVisiteur
 * @param $mois sous la forme aaaamm
*/
        public function creeFicheFrais($idVisiteur,$mois){
                $req = "insert into fichefrais(idvisiteur,mois,nbJustificatifs,montantValide,dateModif,idEtat)
                values(:idVisiteur,:mois,0,0,now(),'CR')";
                $stmt = PdoGsb::$monPdo->prepare($req);
                $stmt->bindParam(':idVisiteur', $idVisiteur);
                 $stmt->bindParam(':mois', $mois);
                $stmt->execute();
                $lesIdFrais = $this->getLesIdFrais();
                foreach($lesIdFrais as $uneLigneIdFrais){
                        $unIdFrais = $uneLigneIdFrais['idfrais'];
                        $req = "insert into lignefraisforfait(idvisiteur,mois,idFraisForfait,quantite) 
                        values(:idVisiteur,:mois,:unIdFrais,0)";
                        $stmt = PdoGsb::$monPdo->prepare($req);
                        $stmt->bindParam(':idVisiteur', $idVisiteur);
                        $stmt->bindParam(':mois', $mois);
                        $stmt->bindParam(':unIdFrais', $unIdFrais);
                        $stmt->execute();
                 }
        }
/**
 * Crée un nouveau frais hors forfait pour un visiteur un mois donné
 * à partir des informations fournies en paramètre
 
 * @param $idVisiteur 
 * @param $mois sous la forme aaaamm
 * @param $libelle : le libelle du frais
 * @param $date : la date du frais au format français jj//mm/aaaa
 * @param $montant : le montant
 * @return l'id du frais créé
*/
        public function creeNouveauFraisHorsForfait($idVisiteur,$mois,$libelle,$date,$montant){
                $dateFr = dateFrancaisVersAnglais($date);
                $req = "insert into lignefraishorsforfait (idVisiteur, mois, libelle, date, montant)
                values(:idVisiteur,:mois,:libelle,:date,:montant)";
                $stmt = PdoGsb::$monPdo->prepare($req);
                $stmt->bindParam(':idVisiteur', $idVisiteur);
                $stmt->bindParam(':mois', $mois);
                $stmt->bindParam(':libelle', $libelle);
                $stmt->bindParam(':date', $dateFr);
                $stmt->bindParam(':montant', $montant);
                $stmt->execute();
                return (int) PdoGsb::$monPdo->lastInsertId();
        }
/**
 * Supprime le frais hors forfait dont l'id est passé en argument
 
 * @param $idFrais 
*/
        public function supprimerFraisHorsForfait($idFrais){
                $req = "delete from lignefraishorsforfait where lignefraishorsforfait.id =:idFrais ";
                $stmt = PdoGsb::$monPdo->prepare($req);
                $stmt->bindParam(':idFrais', $idFrais);
                $stmt->execute();
        }
/**
 * Retourne les dernieres fiches d'un visiteur, avec leur etat, du mois le plus
 * recent au plus ancien. Ajout 2026 pour l'ecran en cartes de la maquette.

 * @param $idVisiteur
 * @param $nombre nombre de fiches a retourner
 * @return un tableau associatif : mois (aaaamm), idEtat, libEtat
*/
        public function getLesDernieresFiches($idVisiteur, $nombre = 6){
                $req = "select fichefrais.mois as mois, fichefrais.idEtat as idEtat, etat.libelle as libEtat
                        from fichefrais inner join etat on fichefrais.idEtat = etat.id
                        where fichefrais.idvisiteur = :idVisiteur
                        order by fichefrais.mois desc limit " . (int) $nombre;
                $stmt = PdoGsb::$monPdo->prepare($req);
                $stmt->bindParam(':idVisiteur', $idVisiteur);
                $stmt->execute();
                return $stmt->fetchAll(PDO::FETCH_ASSOC);
        }
/**
 * Retourne les mois pour lesquel un visiteur a une fiche de frais
 
 * @param $idVisiteur 
 * @return un tableau associatif de clé un mois -aaaamm- et de valeurs l'année et le mois correspondant 
*/
        public function getLesMoisDisponibles($idVisiteur){
                $req = "select fichefrais.mois as mois from  fichefrais where fichefrais.idvisiteur =:idVisiteur 
                order by fichefrais.mois desc ";
                $stmt = PdoGsb::$monPdo->prepare($req);
                $stmt->bindParam(':idVisiteur', $idVisiteur);
                $stmt->execute();
                $laLigne = $stmt->fetch();
                $lesMois =array();
                while($laLigne != null)	{
                        $mois = $laLigne['mois'];
                        $numAnnee =substr( $mois,0,4);
                        $numMois =substr( $mois,4,2);
                        $lesMois["$mois"]=array(
                        "mois"=>"$mois",
                        "numAnnee"  => "$numAnnee",
                        "numMois"  => "$numMois"
                        );
                        $laLigne = $stmt->fetch(); 		
                }
                return $lesMois;
        }
/**
 * Retourne les informations d'une fiche de frais d'un visiteur pour un mois donné
 
 * @param $idVisiteur 
 * @param $mois sous la forme aaaamm
 * @return un tableau avec des champs de jointure entre une fiche de frais et la ligne d'état 
*/	
        public function getLesInfosFicheFrais($idVisiteur,$mois){
                $req = "select ficheFrais.idEtat as idEtat, ficheFrais.dateModif as dateModif, ficheFrais.nbJustificatifs as nbJustificatifs, 
                        ficheFrais.montantValide as montantValide, etat.libelle as libEtat from  fichefrais inner join Etat on ficheFrais.idEtat = Etat.id 
                        where fichefrais.idvisiteur = :idVisiteur and fichefrais.mois = :mois";
                $stmt = PdoGsb::$monPdo->prepare($req);
                $stmt->bindParam(':idVisiteur', $idVisiteur);
                $stmt->bindParam(':mois', $mois);
                $stmt->execute();
                $laLigne = $stmt->fetch();
                return $laLigne;
        }
/**
 * Modifie l'état et la date de modification d'une fiche de frais
 
 * Modifie le champ idEtat et met la date de modif à aujourd'hui
 * @param $idVisiteur 
 * @param $mois sous la forme aaaamm
 */
 
        public function majEtatFicheFrais($idVisiteur,$mois,$etat){
                $req = "update ficheFrais set idEtat = :etat, dateModif = now() 
                where fichefrais.idvisiteur = :idVisiteur and fichefrais.mois = :mois";
                $stmt = PdoGsb::$monPdo->prepare($req);
                $stmt->bindParam(':idVisiteur', $idVisiteur);
                $stmt->bindParam(':mois', $mois);
                $stmt->bindParam(':etat', $etat);
                $stmt->execute();

        }
/**
 * Retourne toutes les fiches de frais dont l'état est à validé
 * @return type
 */
        public function getLesFichesValidees()
        {
            $req = "select * from fichefrais
                    inner join etat on fichefrais.idetat = etat.id
                    inner join visiteur on visiteur.id = fichefrais.idVisiteur
                    where idetat = 'VA'";	
            $stmt = PdoGsb::$monPdo->prepare($req);
            $stmt->execute();
            $lesLignes = $stmt->fetchAll();
            return $lesLignes; 
        }
/**
 * Vérifie si un frais existe pour un visiteur et un mois donné
 * @param type $idVisiteur
 * @param type $mois
 * @param type $idFrais
 * @return 1 ou 0
 */
        public function estValideSuppressionFrais($idVisiteur,$mois,$idFrais){
            $req = "select count(*) as nb from lignefraishorsforfait 
            where lignefraishorsforfait.id=:idfrais and lignefraishorsforfait.mois=:mois
            and lignefraishorsforfait.idvisiteur=:idvisiteur";
            $stmt = PdoGsb::$monPdo->prepare($req);
            $stmt->bindParam(':idfrais', $idFrais);
            $stmt->bindParam(':mois', $mois);
            $stmt->bindParam(':idvisiteur', $idVisiteur);
            $stmt->execute();
            $ligne = $stmt->fetch();
            return $ligne['nb'];

        }

/* ---------------------------------------------------------------------------
 * Ajouts 2026 : saisie par jour, pièces jointes, administration.
 * ------------------------------------------------------------------------ */

/**
 * Ajoute une quantité au total mensuel d'un frais forfaitisé
 *
 * Le jour choisi à la saisie n'est pas conservé : la fiche reste mensuelle.
 * @param $idVisiteur
 * @param $mois sous la forme aaaamm
 * @param $idFrais
 * @param $quantite entier positif
 */
        public function ajouteQuantiteFraisForfait($idVisiteur, $mois, $idFrais, $quantite){
                $req = "update lignefraisforfait set quantite = quantite + :quantite
                        where idvisiteur = :idVisiteur and mois = :mois and idfraisforfait = :idFrais";
                $stmt = PdoGsb::$monPdo->prepare($req);
                $stmt->bindValue(':quantite', (int) $quantite, PDO::PARAM_INT);
                $stmt->bindParam(':idVisiteur', $idVisiteur);
                $stmt->bindParam(':mois', $mois);
                $stmt->bindParam(':idFrais', $idFrais);
                $stmt->execute();
                return $stmt->rowCount() > 0;
        }

/**
 * Retourne un frais hors forfait, avec le visiteur et le mois de sa fiche
 * @param $idFrais
 * @return la ligne, ou false
 */
        public function getUnFraisHorsForfait($idFrais){
                $req = "select * from lignefraishorsforfait where id = :idFrais";
                $stmt = PdoGsb::$monPdo->prepare($req);
                $stmt->bindParam(':idFrais', $idFrais);
                $stmt->execute();
                return $stmt->fetch(PDO::FETCH_ASSOC);
        }

/**
 * Retourne les pièces jointes d'un frais hors forfait
 * @param $idFrais
 * @return un tableau associatif : id, nomOriginal, nomStocke, typeMime, taille, dateAjout
 */
        public function getLesJustificatifs($idFrais){
                $req = "select * from justificatif where idFraisHorsForfait = :idFrais order by id";
                $stmt = PdoGsb::$monPdo->prepare($req);
                $stmt->bindParam(':idFrais', $idFrais);
                $stmt->execute();
                return $stmt->fetchAll(PDO::FETCH_ASSOC);
        }

/**
 * Retourne une pièce jointe, avec le visiteur et le mois du frais qui la porte
 * @param $idJustificatif
 * @return la ligne, ou false
 */
        public function getUnJustificatif($idJustificatif){
                $req = "select justificatif.*, lignefraishorsforfait.idVisiteur as idVisiteur,
                        lignefraishorsforfait.mois as mois
                        from justificatif inner join lignefraishorsforfait
                        on lignefraishorsforfait.id = justificatif.idFraisHorsForfait
                        where justificatif.id = :id";
                $stmt = PdoGsb::$monPdo->prepare($req);
                $stmt->bindParam(':id', $idJustificatif);
                $stmt->execute();
                return $stmt->fetch(PDO::FETCH_ASSOC);
        }

/**
 * Enregistre une pièce jointe déjà rangée sur le disque
 */
        public function ajouteJustificatif($idFrais, $nomOriginal, $nomStocke, $typeMime, $taille){
                $req = "insert into justificatif (idFraisHorsForfait, nomOriginal, nomStocke, typeMime, taille, dateAjout)
                        values (:idFrais, :nomOriginal, :nomStocke, :typeMime, :taille, now())";
                $stmt = PdoGsb::$monPdo->prepare($req);
                $stmt->bindParam(':idFrais', $idFrais);
                $stmt->bindParam(':nomOriginal', $nomOriginal);
                $stmt->bindParam(':nomStocke', $nomStocke);
                $stmt->bindParam(':typeMime', $typeMime);
                $stmt->bindValue(':taille', (int) $taille, PDO::PARAM_INT);
                $stmt->execute();
        }

        public function supprimeJustificatif($idJustificatif){
                $stmt = PdoGsb::$monPdo->prepare("delete from justificatif where id = :id");
                $stmt->bindParam(':id', $idJustificatif);
                $stmt->execute();
        }

/**
 * Recalcule le nombre de justificatifs d'une fiche : celui des pièces jointes
 * pris en compte dans le remboursement, donc hors frais refusés (RG26)
 * @param $idVisiteur
 * @param $mois sous la forme aaaamm
 */
        public function recalculeNbJustificatifs($idVisiteur, $mois){
                $req = "select count(*) from justificatif inner join lignefraishorsforfait
                        on lignefraishorsforfait.id = justificatif.idFraisHorsForfait
                        where lignefraishorsforfait.idvisiteur = :idVisiteur and lignefraishorsforfait.mois = :mois
                        and lignefraishorsforfait.refuse = 0";
                $stmt = PdoGsb::$monPdo->prepare($req);
                $stmt->bindParam(':idVisiteur', $idVisiteur);
                $stmt->bindParam(':mois', $mois);
                $stmt->execute();
                $this->majNbJustificatifs($idVisiteur, $mois, (int) $stmt->fetchColumn());
        }

/**
 * Retourne les fiches de tous les visiteurs, les plus récentes d'abord
 * @param $idEtat filtre facultatif sur l'état
 * @return un tableau associatif : idVisiteur, nom, prenom, mois, idEtat, libEtat,
 *         nbJustificatifs, montantValide, dateModif
 */
        public function getLesFichesDesVisiteurs($idEtat = null){
                $req = "select fichefrais.idVisiteur as idVisiteur, visiteur.nom as nom, visiteur.prenom as prenom,
                        fichefrais.mois as mois, fichefrais.idEtat as idEtat, etat.libelle as libEtat,
                        fichefrais.nbJustificatifs as nbJustificatifs, fichefrais.montantValide as montantValide,
                        fichefrais.dateModif as dateModif
                        from fichefrais
                        inner join visiteur on visiteur.id = fichefrais.idVisiteur
                        inner join etat on etat.id = fichefrais.idEtat";
                if ($idEtat !== null) {
                        $req .= " where fichefrais.idEtat = :idEtat";
                }
                $req .= " order by fichefrais.mois desc, visiteur.nom, visiteur.prenom";
                $stmt = PdoGsb::$monPdo->prepare($req);
                if ($idEtat !== null) {
                        $stmt->bindParam(':idEtat', $idEtat);
                }
                $stmt->execute();
                return $stmt->fetchAll(PDO::FETCH_ASSOC);
        }

/**
 * Montant dû pour une fiche : forfaits au tarif du référentiel, kilométrage au
 * tarif du véhicule, chaque ligne arrondie au centime, plus les frais hors
 * forfait non refusés (RG7, RG8)
 */
        public function getMontantCalcule($idVisiteur, $mois){
                $montant = self::montantUnitaireSql();
                $req = "select
                          (select coalesce(sum(round(lignefraisforfait.quantite * $montant, 2)), 0)
                           from lignefraisforfait inner join fraisforfait on fraisforfait.id = lignefraisforfait.idfraisforfait
                           where lignefraisforfait.idvisiteur = :v1 and lignefraisforfait.mois = :m1)
                        + (select coalesce(sum(montant), 0) from lignefraishorsforfait
                           where idvisiteur = :v2 and mois = :m2 and refuse = 0)";
                $stmt = PdoGsb::$monPdo->prepare($req);
                $stmt->bindParam(':v1', $idVisiteur);
                $stmt->bindParam(':m1', $mois);
                $stmt->bindParam(':v2', $idVisiteur);
                $stmt->bindParam(':m2', $mois);
                $stmt->execute();
                return number_format((float) $stmt->fetchColumn(), 2, '.', '');
        }

        public function majMontantValide($idVisiteur, $mois, $montant){
                $req = "update fichefrais set montantValide = :montant
                        where idvisiteur = :idVisiteur and mois = :mois";
                $stmt = PdoGsb::$monPdo->prepare($req);
                $stmt->bindParam(':montant', $montant);
                $stmt->bindParam(':idVisiteur', $idVisiteur);
                $stmt->bindParam(':mois', $mois);
                $stmt->execute();
        }

        public function majRefusFraisHorsForfait($idFrais, $refuse){
                $stmt = PdoGsb::$monPdo->prepare("update lignefraishorsforfait set refuse = :refuse where id = :id");
                $stmt->bindValue(':refuse', $refuse ? 1 : 0, PDO::PARAM_INT);
                $stmt->bindParam(':id', $idFrais);
                $stmt->execute();
        }

/**
 * Gestion des comptes, réservée à l'administrateur
 */
        public function getLesComptes(){
                $req = "select id, nom, prenom, login, role, actif from visiteur order by role, nom, prenom";
                return PdoGsb::$monPdo->query($req)->fetchAll(PDO::FETCH_ASSOC);
        }

        public function getUnCompte($id){
                $stmt = PdoGsb::$monPdo->prepare("select id, nom, prenom, login, role, actif from visiteur where id = :id");
                $stmt->bindParam(':id', $id);
                $stmt->execute();
                return $stmt->fetch(PDO::FETCH_ASSOC);
        }

        public function existeLogin($login, $saufId = null){
                $stmt = PdoGsb::$monPdo->prepare("select count(*) from visiteur where login = :login and id <> :saufId");
                $stmt->bindParam(':login', $login);
                $stmt->bindValue(':saufId', (string) $saufId);
                $stmt->execute();
                return $stmt->fetchColumn() > 0;
        }

/**
 * Crée un compte. L'identifiant suit le modèle de 2013 : l'initiale du nom
 * suivie d'un numéro, sur quatre caractères au plus.
 * @return l'identifiant attribué
 */
        public function creeCompte($nom, $prenom, $login, $mdp, $role){
                $initiale = strtolower(substr(preg_replace('/[^A-Za-z]/', '', iconv('UTF-8', 'ASCII//TRANSLIT', $nom)), 0, 1));
                if ($initiale === '') {
                        $initiale = 'v';
                }
                $verif = PdoGsb::$monPdo->prepare("select count(*) from visiteur where id = :id");
                for ($n = 1; $n <= 999; $n++) {
                        $id = $initiale.$n;
                        $verif->bindParam(':id', $id);
                        $verif->execute();
                        if ($verif->fetchColumn() == 0) {
                                break;
                        }
                }
                $req = "insert into visiteur (id, nom, prenom, login, mdp, role, actif)
                        values (:id, :nom, :prenom, :login, :mdp, :role, 1)";
                $stmt = PdoGsb::$monPdo->prepare($req);
                $stmt->bindParam(':id', $id);
                $stmt->bindParam(':nom', $nom);
                $stmt->bindParam(':prenom', $prenom);
                $stmt->bindParam(':login', $login);
                $stmt->bindParam(':mdp', $mdp);
                $stmt->bindParam(':role', $role);
                $stmt->execute();
                return $id;
        }

/**
 * Modifie un compte. Un mot de passe vide laisse l'ancien en place.
 */
        public function majCompte($id, $nom, $prenom, $login, $mdp, $role){
                $req = "update visiteur set nom = :nom, prenom = :prenom, login = :login, role = :role"
                     . ($mdp !== '' ? ", mdp = :mdp" : "")
                     . " where id = :id";
                $stmt = PdoGsb::$monPdo->prepare($req);
                $stmt->bindParam(':nom', $nom);
                $stmt->bindParam(':prenom', $prenom);
                $stmt->bindParam(':login', $login);
                $stmt->bindParam(':role', $role);
                if ($mdp !== '') {
                        $stmt->bindParam(':mdp', $mdp);
                }
                $stmt->bindParam(':id', $id);
                $stmt->execute();
        }

        public function majActivationCompte($id, $actif){
                $stmt = PdoGsb::$monPdo->prepare("update visiteur set actif = :actif where id = :id");
                $stmt->bindValue(':actif', $actif ? 1 : 0, PDO::PARAM_INT);
                $stmt->bindParam(':id', $id);
                $stmt->execute();
        }

/* ---------------------------------------------------------------------------
 * Ajouts 2026, demandes du sujet : campagne de validation, report, véhicule.
 * ------------------------------------------------------------------------ */

/**
 * Les visiteurs médicaux, pour le choix du visiteur par le comptable
 * @return un tableau associatif : id, nom, prenom
 */
        public function getLesVisiteurs(){
                $req = "select id, nom, prenom from visiteur where role = 'visiteur' order by nom, prenom";
                return PdoGsb::$monPdo->query($req)->fetchAll(PDO::FETCH_ASSOC);
        }

/**
 * Nombre de fiches encore en cours de saisie pour un mois écoulé
 * @param $moisCourant sous la forme aaaamm
 */
        public function compteFichesACloturer($moisCourant){
                $stmt = PdoGsb::$monPdo->prepare("select count(*) from fichefrais where idEtat = 'CR' and mois < :mois");
                $stmt->bindParam(':mois', $moisCourant);
                $stmt->execute();
                return (int) $stmt->fetchColumn();
        }

/**
 * Script de début de campagne : clôture toutes les fiches des mois écoulés encore
 * en cours de saisie, tous visiteurs confondus. Sans effet sur les fiches plus
 * avancées, il peut être relancé (RG32).
 * @param $moisCourant sous la forme aaaamm
 * @return le nombre de fiches clôturées
 */
        public function clotureFichesEcoulees($moisCourant){
                $stmt = PdoGsb::$monPdo->prepare("update fichefrais set idEtat = 'CL', dateModif = now()
                        where idEtat = 'CR' and mois < :mois");
                $stmt->bindParam(':mois', $moisCourant);
                $stmt->execute();
                return $stmt->rowCount();
        }

/**
 * Les fiches d'un mois dont la saisie est terminée, pour l'impression en lot
 * @param $mois sous la forme aaaamm
 * @return un tableau associatif : idVisiteur, nom, prenom
 */
        public function getLesFichesClotureesDuMois($mois){
                $req = "select fichefrais.idVisiteur as idVisiteur, visiteur.nom as nom, visiteur.prenom as prenom
                        from fichefrais inner join visiteur on visiteur.id = fichefrais.idVisiteur
                        where fichefrais.mois = :mois and fichefrais.idEtat <> 'CR'
                        order by visiteur.nom, visiteur.prenom";
                $stmt = PdoGsb::$monPdo->prepare($req);
                $stmt->bindParam(':mois', $mois);
                $stmt->execute();
                return $stmt->fetchAll(PDO::FETCH_ASSOC);
        }

/**
 * Bascule un frais hors forfait sur une autre fiche du même visiteur. La ligne
 * garde sa date d'engagement et retient le mois de sa fiche d'origine (RG28, RG29).
 * @param $idFrais
 * @param $moisCible sous la forme aaaamm
 */
        public function reporteFraisHorsForfait($idFrais, $moisCible){
                // moisOrigine est affecté avant mois : MySQL évalue le SET de gauche à droite.
                $req = "update lignefraishorsforfait set moisOrigine = coalesce(moisOrigine, mois), mois = :cible
                        where id = :id";
                $stmt = PdoGsb::$monPdo->prepare($req);
                $stmt->bindParam(':cible', $moisCible);
                $stmt->bindParam(':id', $idFrais);
                $stmt->execute();
        }

/**
 * Le barème kilométrique, du taux le plus bas au plus haut par carburant
 * @return un tableau associatif : id, puissance, carburant, tarif
 */
        public function getLeBaremeKm(){
                $req = "select id, puissance, carburant, tarif from baremekm order by carburant, tarif";
                return PdoGsb::$monPdo->query($req)->fetchAll(PDO::FETCH_ASSOC);
        }

/**
 * Les véhicules déclarés par un visiteur, le plus récent d'abord
 * @return un tableau associatif : id, idBaremeKm, dateDebut, dateFin, puissance, carburant, tarif
 */
        public function getLesVehicules($idVisiteur){
                $req = "select vehicule.id, vehicule.idBaremeKm, vehicule.dateDebut, vehicule.dateFin,
                        baremekm.puissance, baremekm.carburant, baremekm.tarif
                        from vehicule inner join baremekm on baremekm.id = vehicule.idBaremeKm
                        where vehicule.idVisiteur = :idVisiteur
                        order by vehicule.dateDebut desc, vehicule.id desc";
                $stmt = PdoGsb::$monPdo->prepare($req);
                $stmt->bindParam(':idVisiteur', $idVisiteur);
                $stmt->execute();
                return $stmt->fetchAll(PDO::FETCH_ASSOC);
        }

/**
 * Le véhicule dont le tarif s'applique au kilométrage d'un mois : le dernier
 * déclaré parmi ceux valides pendant ce mois (RG17)
 * @param $idVisiteur
 * @param $mois sous la forme aaaamm
 * @return la ligne, ou false si aucun véhicule n'était déclaré ce mois-là
 */
        public function getVehiculeDuMois($idVisiteur, $mois){
                $req = "select vehicule.id, vehicule.idBaremeKm, vehicule.dateDebut, vehicule.dateFin,
                        baremekm.puissance, baremekm.carburant, baremekm.tarif
                        from vehicule inner join baremekm on baremekm.id = vehicule.idBaremeKm
                        where ".self::conditionVehiculeDuMois(':idVisiteur', ':premierJour', ':dernierJour')."
                        order by vehicule.dateDebut desc, vehicule.id desc limit 1";
                $premierJour = substr($mois, 0, 4).'-'.substr($mois, 4, 2).'-01';
                $stmt = PdoGsb::$monPdo->prepare($req);
                $stmt->bindParam(':idVisiteur', $idVisiteur);
                $stmt->bindValue(':premierJour', $premierJour);
                $stmt->bindValue(':dernierJour', date('Y-m-t', strtotime($premierJour)));
                $stmt->execute();
                return $stmt->fetch(PDO::FETCH_ASSOC);
        }

/**
 * Déclare le véhicule actuel d'un visiteur, à compter d'aujourd'hui (RG18, RG19).
 *
 * Le véhicule précédent prend fin la veille : les mois déjà écoulés gardent
 * leur taux. Une seconde déclaration le même jour corrige la première.
 * @param $idVisiteur
 * @param $idBaremeKm ligne du barème : puissance fiscale et carburant
 * @return faux si ce véhicule est déjà le véhicule actuel
 */
        public function declareVehicule($idVisiteur, $idBaremeKm){
                $lesVehicules = $this->getLesVehicules($idVisiteur);
                $actuel = null;
                foreach ($lesVehicules as $unVehicule) {
                        if ($unVehicule['dateFin'] === null) {
                                $actuel = $unVehicule;
                                break;
                        }
                }
                if ($actuel && $actuel['idBaremeKm'] === $idBaremeKm) {
                        return false;
                }
                $aujourdhui = date('Y-m-d');
                PdoGsb::$monPdo->beginTransaction();
                if ($actuel && $actuel['dateDebut'] === $aujourdhui) {
                        $stmt = PdoGsb::$monPdo->prepare("update vehicule set idBaremeKm = :bareme where id = :id");
                        $stmt->bindParam(':bareme', $idBaremeKm);
                        $stmt->bindParam(':id', $actuel['id']);
                        $stmt->execute();
                } else {
                        if ($actuel) {
                                $stmt = PdoGsb::$monPdo->prepare("update vehicule set dateFin = :hier where id = :id");
                                $stmt->bindValue(':hier', date('Y-m-d', strtotime('-1 day')));
                                $stmt->bindParam(':id', $actuel['id']);
                                $stmt->execute();
                        }
                        $stmt = PdoGsb::$monPdo->prepare("insert into vehicule (idVisiteur, idBaremeKm, dateDebut)
                                values (:idVisiteur, :bareme, :debut)");
                        $stmt->bindParam(':idVisiteur', $idVisiteur);
                        $stmt->bindParam(':bareme', $idBaremeKm);
                        $stmt->bindParam(':debut', $aujourdhui);
                        $stmt->execute();
                }
                PdoGsb::$monPdo->commit();
                return true;
        }
}
?>