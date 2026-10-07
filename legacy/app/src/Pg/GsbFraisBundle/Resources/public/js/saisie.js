/* Page de saisie. Sans ce script, tout reste utilisable : les deux blocs de
   l'étape 3 s'affichent, l'aide est dépliée, et le serveur refait chaque contrôle. */

/* Pièce jointe sur une dépense existante : envoi dès le fichier choisi, le
   bouton « Envoyer » ne sert qu'aux navigateurs sans JavaScript. */
(function () {
  document.documentElement.classList.add('js');
  var ajouts = document.querySelectorAll('.ajout-pj input[type=file]');
  for (var i = 0; i < ajouts.length; i++) {
    ajouts[i].addEventListener('change', function () {
      if (this.files.length) this.form.submit();
    });
  }
})();

/* Formulaire « Nouvelle dépense » : la catégorie choisie décide de l'étape 3.
   Un forfait demande une quantité, au tarif fixé ; une autre dépense, le montant
   payé et la facture. Le bloc inutile est masqué et désactivé : ses champs ne
   sont ni contrôlés ni envoyés. */
(function () {
  var form = document.getElementById('nouveauFrais');
  if (!form) return;

  var jour = document.getElementById('jour');
  var filtre = document.getElementById('filtreCategories');
  var vide = document.getElementById('categoriesVide');
  var sections = form.querySelectorAll('.categories__section');
  var aideBouton = document.getElementById('aideBouton');
  var aidePanneau = document.getElementById('aidePanneau');
  var aideCategorie = document.getElementById('categorieAide');
  var attente = document.getElementById('saisieAttente');
  var groupeForfait = document.getElementById('groupeForfait');
  var groupeDepense = document.getElementById('groupeDepense');
  var quantite = document.getElementById('quantite');
  var unite = document.getElementById('unite');
  var montantCalcule = document.getElementById('montantCalcule');
  var montant = document.getElementById('montant');
  var libelle = document.getElementById('libelle');
  var facultatif = document.getElementById('libelleFacultatif');
  var euros = new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' });

  // Contrainte posée ici et non dans la page : sans ce script, le bloc forfait
  // reste affiché à côté de l'autre, et ne doit pas bloquer l'envoi d'une dépense.
  quantite.pattern = '[1-9][0-9]*';
  quantite.title = 'Un nombre entier, 1 ou plus';

  function choisie() {
    return form.querySelector('input[name=categorie]:checked');
  }

  // Forfait : l'unité s'accorde à la quantité, et le montant remboursé s'affiche.
  function majMontant() {
    var categorie = choisie();
    if (!categorie || categorie.getAttribute('data-type') !== 'forfait') return;
    var valide = /^[1-9][0-9]*$/.test(quantite.value.trim());
    var n = valide ? parseInt(quantite.value, 10) : 0;
    var tarif = parseFloat(categorie.getAttribute('data-tarif'));
    unite.textContent = (categorie.getAttribute('data-unite') || '').replace('(s)', n > 1 ? 's' : '');
    montantCalcule.textContent = valide ? 'soit ' + euros.format(Math.round(n * tarif * 100) / 100) : '';
  }

  // La catégorie choisie au dernier passage : un nouveau clic dessus la désélectionne.
  var derniere = null;

  function majEtape3() {
    var categorie = choisie();
    derniere = categorie;
    var type = categorie ? categorie.getAttribute('data-type') : '';
    var forfait = type === 'forfait';
    var depense = type === 'depense';

    attente.hidden = type !== '';
    groupeForfait.hidden = groupeForfait.disabled = !forfait;
    groupeDepense.hidden = groupeDepense.disabled = !depense;
    quantite.required = forfait;
    montant.required = depense;

    // « Autre » : le détail devient obligatoire (le serveur l'exige aussi).
    var autre = depense && categorie.value === 'horsforfait-AUT';
    libelle.required = autre;
    facultatif.hidden = autre;
    libelle.placeholder = depense ? (autre ? 'Précisez la dépense' : categorie.getAttribute('data-exemple') || '') : '';

    // Un forfait est daté du mois en cours ; une dépense, de moins d'un an (RG4).
    jour.min = jour.getAttribute(forfait ? 'data-min-forfait' : 'data-min-depense');

    aideCategorie.textContent = forfait ? categorie.getAttribute('data-description') : '';
    aideCategorie.hidden = !forfait;
    majMontant();
  }

  // Aide « Forfait ou prix payé » : repliée derrière le bouton « ? ».
  aideBouton.hidden = false;
  aidePanneau.hidden = true;
  aideBouton.addEventListener('click', function () {
    var ouvert = aideBouton.getAttribute('aria-expanded') === 'true';
    aideBouton.setAttribute('aria-expanded', String(!ouvert));
    aidePanneau.hidden = ouvert;
  });

  // Recherche, sans accents ni majuscules : « hotel » trouve « Hôtel ».
  function simplifie(texte) {
    return texte.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');
  }
  function filtrer() {
    var cherche = simplifie(filtre.value.trim());
    var total = 0;
    for (var i = 0; i < sections.length; i++) {
      var blocs = sections[i].querySelectorAll('.categories__bloc'), dansSection = 0;
      for (var j = 0; j < blocs.length; j++) {
        var tuiles = blocs[j].querySelectorAll('.categorie'), dansBloc = 0;
        for (var k = 0; k < tuiles.length; k++) {
          // La catégorie choisie reste visible, pour ne pas perdre le choix de vue.
          var ok = !cherche || tuiles[k].querySelector('input').checked
                || simplifie(tuiles[k].getAttribute('data-recherche')).indexOf(cherche) !== -1;
          tuiles[k].hidden = !ok;
          if (ok) dansBloc++;
        }
        blocs[j].hidden = dansBloc === 0;
        dansSection += dansBloc;
      }
      sections[i].hidden = dansSection === 0;
      total += dansSection;
    }
    vide.hidden = total > 0;
  }
  filtre.hidden = false;
  filtre.addEventListener('input', filtrer);
  // Entrée dans la recherche ne soumet pas le formulaire.
  filtre.addEventListener('keydown', function (e) {
    if (e.key === 'Enter') e.preventDefault();
  });

  form.addEventListener('change', function (e) {
    if (e.target.name === 'categorie') majEtape3();
  });
  // Un bouton radio ne se décoche pas seul : un nouveau clic sur la catégorie
  // déjà choisie la retire, et l'étape 3 revient en attente.
  // Sinon, au clic, le curseur passe au champ suivant. Pas avec les flèches du
  // clavier : chaque flèche change de catégorie (e.detail vaut 0).
  // Le clic précède l'événement « change » : l'étape 3 est mise à jour ici d'abord.
  form.addEventListener('click', function (e) {
    if (e.target.name !== 'categorie') return;
    if (e.target === derniere) {
      e.target.checked = false;
      majEtape3();
      return;
    }
    if (e.detail === 0) return;
    majEtape3();
    if (!jour.value || !jour.checkValidity()) jour.focus();
    else (e.target.getAttribute('data-type') === 'forfait' ? quantite : montant).focus();
  });
  // Au clavier, Espace sur la catégorie choisie la retire de même. Chrome n'envoie
  // pas de clic sur un bouton radio déjà coché : la touche est traitée ici, et
  // preventDefault évite qu'il soit recoché au relâchement.
  form.addEventListener('keydown', function (e) {
    if (e.target.name !== 'categorie' || e.key !== ' ' || !e.target.checked) return;
    e.preventDefault();
    e.target.checked = false;
    majEtape3();
  });
  quantite.addEventListener('input', majMontant);

  // « Effacer » vide le formulaire, même revenu rempli après une erreur.
  form.addEventListener('reset', function () {
    setTimeout(function () {
      var categorie = choisie();
      if (categorie) categorie.checked = false;
      jour.value = jour.getAttribute('data-aujourdhui');
      quantite.value = montant.value = libelle.value = '';
      filtre.value = '';
      filtrer();
      majEtape3();
    }, 0);
  });

  majEtape3();
})();
