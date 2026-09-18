# ProductLabel5890

**Étiquettes Pocket** (nom anglais : **Pocket Labels**) est une application iPhone native pour saisir une fiche produit, voir son étiquette et l'imprimer directement en Bluetooth Low Energy sur une Pocket Printer 5890. Aucun AirPrint, export d'image, compte ou accès Internet n'est nécessaire après installation.

## Matériel et dimensions

Le dépôt [PocketPrinter5890](https://github.com/dimer47/PocketPrinter5890) documente une machine 5890 (modèle BLE `A2Y`, firmware `V1.06LY`) testée physiquement : tête de **384 points**, **48 octets par ligne**, résolution annoncée **203 dpi**, papier d'environ 56/58 mm. Ces chiffres proviennent de cette unité ; un autre firmware pourrait différer. La tête couvre environ 48 mm. Les quatre hauteurs proposées sont **208, 240, 312 et 416 points** (environ 26, 30, 39 et 52 mm de zone imprimée). Le contenu est centré dans la largeur imprimable. Le centrage physique de la tête dans le rouleau dépend du mécanisme.

## Architecture

- `Sources/LabelCore` : données produit, choix de présentation, validation et encodage EAN‑13, prix français, rotation exacte du bitmap 1 bit ; testable sans iOS.
- `App/LabelRenderer.swift` : composition à la résolution native, seuillage direct à 1 bit, barres EAN en modules entiers.
- `App/PrinterManager.swift` : découverte, sélection, reconnexion, densité et impression directe.
- `App/LabelHistoryStore.swift` : historique local des impressions et restauration des paramètres associés.
- `App/ContentView.swift` : formulaire, aperçu à l'endroit issu du **bitmap source** de l'impression, état BLE et réglages.
- Bibliothèque SwiftPM `PocketPrinter5890Kit` et `PocketPrinter5890BLE` : commandes de densité et d'activation, raster en bandes de 24 lignes, contrôle de flux BLE et transport CoreBluetooth. La dépendance est épinglée à la révision vérifiée dans ce projet.

L'EAN‑13 accepte 12 chiffres et calcule le contrôle, ou valide les 13 chiffres saisis. Les 95 modules sont dessinés à **3 points chacun** (sans redimensionnement), avec au moins 10 modules blancs de chaque côté. La hauteur des barres varie selon la présentation choisie. Le texte peut être antialiasé durant la composition, puis chaque point est converti en noir ou blanc par un seuil fixe de 160 ; aucun tramage photo n'est appliqué. Le bitmap résultant, large exactement de 384 points, part directement au protocole 5890.

## Compiler et installer

Prérequis : Xcode compatible avec le SDK iOS, iOS 17 ou plus récent et un compte de signature Apple pour déployer sur iPhone. Ouvrir `ProductLabel5890.xcodeproj`, sélectionner le schéma `ProductLabel5890`, choisir son iPhone, configurer l'équipe de signature si nécessaire, puis lancer. Le paquet SwiftPM est téléchargé lors de la première compilation. Test du cœur : `swift test`. Compilation vérifiée sans signature avec :

```sh
xcodebuild -project ProductLabel5890.xcodeproj -scheme ProductLabel5890 -configuration Debug -sdk iphoneos CODE_SIGNING_ALLOWED=NO build
```

## Utilisation

1. Allumer la 5890 et activer Bluetooth sur l'iPhone.
2. Ouvrir l'app. Appuyer sur **Connecter**, sélectionner `Mini Pocket Printer_BLE`. La dernière imprimante est recherchée au lancement suivant.
3. Dans **Produit**, saisir les champs identifiés par leur libellé permanent. Le sélecteur iOS natif **Produit / Impression** dispose de plus de hauteur ; le formulaire utilise de grands champs dans un panneau Glass sur iOS 26 et un matériau système sur les versions antérieures. Le bouton **Scanner un code** sous l'EAN ouvre la caméra et remplit automatiquement un EAN‑13 valide ; l'accès à la caméra est demandé au premier scan. La catégorie reste libre : **Choisir** ouvre les catégories enregistrées et **Enregistrer** mémorise celle qui est saisie. Les catégories se gèrent aussi dans **Réglages**, avec suppression par balayage. Le texte « Prix de vente TTC » est modifiable dans **Libellé du prix** ; la référence rayon est également libre. Le prix accepte `5,95` ou `5.95` ; choisir la devise EUR, USD, GBP ou CHF à côté. Les fiches enregistrées avant ces ajouts conservent EUR et « Prix de vente TTC ».
4. Passer à **Aperçu et impression** : l'état de l'imprimante est affiché en premier. Appuyer ensuite sur **Présentation de l’étiquette** pour choisir visuellement une des quatre hauteurs et une des six dispositions (le modèle actuel et cinq nouveautés). Les quatre formats sont montrés un par ligne à largeur constante pour comparer leurs hauteurs. Le choix est mémorisé sur l'iPhone.
   La fenêtre s'ouvre aussitôt avec des indicateurs de chargement ; les miniatures sont calculées progressivement en arrière-plan à partir des données du produit. Le bouton donne un retour visuel dès l'appui.
5. Une fois la 5890 connectée, appuyer sur **Imprimer**. Le bouton est désactivé sans connexion, tout comme **Réimprimer** dans l'historique et l'impression de test. Le bitmap affiché est celui envoyé au protocole, mais l'affichage à l'écran est lissé pour éviter le crénelage lié à l'agrandissement ; les points imprimés restent strictement noirs ou blancs.
6. Dans **Réglages**, choisir la densité Faible, Moyenne ou Forte (Moyenne par défaut), ajuster les avances avant et après impression, activer éventuellement **Tourner l'impression de 180°**, et lancer l'étiquette de calibration. Éviter une densité trop forte si les barres fusionnent.

Le bloc **Imprimante** affiche le nom du périphérique connecté et son niveau de batterie lorsque la 5890 le transmet. Le bouton **Changer** permet de choisir un autre périphérique compatible. Dans **Réglages**, un nom personnalisé peut être enregistré pour l'imprimante connectée ; il reste associé à son identifiant Bluetooth sur cet iPhone. Le nom BLE d'origine demeure visible dans la liste de sélection.

La fiche en cours est enregistrée après chaque modification et réapparaît à la prochaine ouverture. Le format, la disposition, la densité, les avances papier et la rotation restent aussi mémorisés. Le bouton **Historique** dans la barre supérieure ouvre les 100 dernières impressions soumises au transport Bluetooth, conservées localement dans `UserDefaults`. Chaque entrée contient la fiche, l'heure, le format, la disposition, la densité, les avances et la rotation. **Restaurer** remet ces valeurs dans l'éditeur ; **Réimprimer** recharge les mêmes paramètres et soumet une nouvelle impression, ajoutée à l'historique. Les entrées se suppriment par balayage. L'historique n'est pas une preuve que le papier est sorti : le protocole ne fournit pas d'accusé de fin physique.

La rotation est désactivée par défaut et mémorisée sur l'iPhone. Elle retourne **tout le bitmap final** de 180° par permutation exacte des points, sans nouveau rendu de texte ni redimensionnement. L'aperçu reste toujours à l'endroit pour faciliter la saisie ; seul le bitmap transmis à l'imprimante est tourné. Une fois le ticket découpé, le retourner physiquement pour lire l'étiquette : le blanc mécanique initial se retrouve alors sous le contenu. L'avance finale du papier reste identique.

Le rouleau est continu. L'avance avant impression est réglable de 0 à 10 mm et vaut **0 mm par défaut** ; elle est envoyée après la séquence d'activation de la 5890 et avant le bitmap. L'avance finale vaut désormais **104 points**, soit environ **13 mm** selon la résolution documentée : 3 mm de plus que le réglage initial de 80 points, et 3 mm de moins que l'essai de 128 points jugé excessif. Le réglage propose 10, 12, 13, 14, 15, 16 et 20 mm. Une ancienne valeur de 16 mm est ramenée automatiquement à 13 mm. Ce réglage ajoute du papier blanc après le prix avant la découpe ; il ne change pas la composition du bitmap de 30 mm. Le blanc en tête visible sur les impressions semble lié à la distance mécanique entre tête thermique et bord de découpe ; sa valeur exacte reste à mesurer sur le papier. Mesurer la hauteur totale du ticket découpé avant de choisir un porte-étiquette : les produits du commerce existent notamment pour des insertions de 30, 39/40 et 52 mm. Voir par exemple les [porte-étiquettes Provost 30 × 50 mm](https://www.provost.fr/fr/rayonnage-pour-magasins/569-porte-etiquette/) et les [réglettes VKF Renzel 26, 39 et 52 mm](https://www.vkf-renzel.com/no-shelf-edge-strip-26-mm-transparent-standard-adhesive-12-mm-20-0026-40.html).

Le test matériel doit vérifier le contraste, la lecture du code avec un scanner, la position horizontale sur le rouleau et la hauteur réelle du ticket après découpe. La compilation iPhone, le lancement sur iPhone et le rendu sur simulateur ont été vérifiés ; l'impression physique dépend de l'imprimante connectée.

Le scan caméra demande un iPhone réel avec autorisation caméra ; il n'est pas vérifiable sur le simulateur. Le numéro lu est validé comme EAN‑13 avant de remplacer le champ. Le scanner choisit une caméra arrière virtuelle triple ou double large lorsqu'elle existe, puis une caméra simple en repli. Sur les appareils compatibles, AVFoundation peut alors passer de l'objectif principal à l'ultra grand-angle pour une mise au point rapprochée selon la distance et la lumière. L'image démarre au champ de vision de l'objectif principal. Le scanner utilise l'autofocus continu ; toucher l'image déclenche une nouvelle mise au point à cet endroit, puis réactive le suivi continu. Le changement d'objectif réel et la lisibilité d'un code très proche restent à vérifier sur chaque modèle d'iPhone. Les catégories sont stockées localement dans `UserDefaults` sur l'appareil, sans synchronisation réseau.

## Langues

L'interface est disponible en **français** (langue de développement) et en **anglais**. Les textes des écrans, états Bluetooth, noms de présentations et autorisations système se trouvent dans `Resources/fr.lproj` et `Resources/en.lproj` (`Localizable.strings` et `InfoPlist.strings`). La devise et la ponctuation du prix imprimé suivent les réglages régionaux de l'iPhone ; la saisie accepte toujours la virgule et le point. Les champs produit et noms de catégories déjà enregistrés restent tels que saisis : changer la langue de l'iPhone ne traduit pas les données personnelles existantes. Les langues autres que le français et l'anglais utilisent le français en repli.

Dans **Réglages → Application**, le bouton de langue ouvre la page de l'application dans les réglages iOS. Le choix de langue par application y est géré par le système : il permet de choisir l'anglais ou le français sans maintenir deux mécanismes de traduction concurrents dans l'app.

Le projet Xcode ne contient plus les références inactives aux anciens écrans de prévisualisation, à une extension de partage ou à App Intents. La bibliothèque `PocketPrinter5890` reste une dépendance volontaire pour le protocole et le transport BLE ; le nom interne du projet et son identifiant de paquet ne changent pas, afin de préserver l'installation et les préférences de l'app.

La documentation du protocole ne décrit aucune commande permettant d'éteindre immédiatement la 5890 par Bluetooth. Une commande de réglage du délai d'extinction automatique existe dans la bibliothèque, mais son fonctionnement sur l'A2Y n'a pas été vérifié ; l'application n'affiche donc pas de bouton « Éteindre ».

## Présentations disponibles

Les quatre hauteurs et les limites de largeur sont décrites dans [docs/FORMATS_PROPOSES.md](docs/FORMATS_PROPOSES.md). La largeur reste de **384 points** pour cette imprimante : choisir un papier de 80 mm nécessiterait une autre imprimante et un profil matériel distinct.

Les cinq nouvelles dispositions sont présentées dans [docs/DISPOSITIONS_PROPOSEES.md](docs/DISPOSITIONS_PROPOSEES.md). Les maquettes Python de ce document ont servi au choix visuel ; l'app utilise son propre moteur natif pour produire le bitmap imprimé. Le contraste et la lecture de chaque combinaison doivent encore être vérifiés sur papier.

## Licence et attribution

Code du projet sous licence MIT, copyright 2026 Dimitri Iachi. La bibliothèque `PocketPrinter5890` est également sous MIT et conserve sa propre attribution et licence dans son dépôt. Le projet reprend la configuration Xcode et le choix de cette bibliothèque de `PocketPrinter5890App`, également annoncé MIT dans son README ; il ne modifie pas ce dépôt.
