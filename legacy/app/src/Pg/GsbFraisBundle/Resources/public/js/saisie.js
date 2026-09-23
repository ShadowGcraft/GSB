/* Saisie guidée des frais forfaitisés : le jour, puis le type, puis la quantité.
   Sans ce script, le formulaire reste utilisable : tous les champs sont actifs
   et le serveur refait chaque contrôle. */
(function () {
  // Pièce jointe sur un frais existant : envoi dès le fichier choisi, le
  // bouton « Envoyer » ne sert qu'aux navigateurs sans JavaScript.
  document.documentElement.classList.add('js');
  var ajouts = document.querySelectorAll('.ajout-pj input[type=file]');
  for (var k = 0; k < ajouts.length; k++) {
    ajouts[k].addEventListener('change', function () {
      if (this.files.length) this.form.submit();
    });
  }

  var form = document.getElementById('saisieGuidee');
  if (!form) return;

  var jour = document.getElementById('jour');
  var type = document.getElementById('idFrais');
  var quantite = document.getElementById('quantite');
  var unite = document.getElementById('unite');
  var bouton = document.getElementById('ajouterForfait');
  var aideBouton = document.getElementById('aideBouton');
  var aidePanneau = document.getElementById('aidePanneau');

  // Chaque étape ne s'ouvre qu'une fois la précédente renseignée.
  function majEtapes() {
    var jourOk = jour.value !== '' && jour.checkValidity();
    var typeOk = jourOk && type.value !== '';
    type.disabled = !jourOk;
    quantite.disabled = !typeOk;
    bouton.disabled = !(typeOk && /^[1-9][0-9]*$/.test(quantite.value));
    form.querySelector('[data-etape="type"]').classList.toggle('etape--attente', !jourOk);
    form.querySelector('[data-etape="quantite"]').classList.toggle('etape--attente', !typeOk);

    var option = type.options[type.selectedIndex];
    unite.textContent = option && option.value ? option.getAttribute('data-unite') : '';

    // Dans l'aide, le type choisi est mis en avant.
    var items = aidePanneau.querySelectorAll('.aide__item');
    for (var i = 0; i < items.length; i++) {
      items[i].classList.toggle('aide__item--choisi', items[i].getAttribute('data-frais') === type.value);
    }
  }

  aideBouton.addEventListener('click', function () {
    var ouvert = aideBouton.getAttribute('aria-expanded') === 'true';
    aideBouton.setAttribute('aria-expanded', String(!ouvert));
    aidePanneau.hidden = ouvert;
  });

  jour.addEventListener('input', majEtapes);
  jour.addEventListener('change', majEtapes);
  type.addEventListener('change', function () {
    majEtapes();
    if (!quantite.disabled) quantite.focus();
  });
  quantite.addEventListener('input', majEtapes);
  form.addEventListener('reset', function () { setTimeout(majEtapes, 0); });
  majEtapes();
})();
