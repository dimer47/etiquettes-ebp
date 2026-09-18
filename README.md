# ProductLabel5890

Application iPhone native pour saisir une fiche produit, voir son étiquette et l'imprimer directement en Bluetooth Low Energy sur une Pocket Printer 5890. Aucun AirPrint, export d'image, compte ou accès Internet n'est nécessaire après installation.

## Matériel et dimensions

Le dépôt [PocketPrinter5890](https://github.com/dimer47/PocketPrinter5890) documente une machine 5890 (modèle BLE `A2Y`, firmware `V1.06LY`) testée physiquement : tête de **384 points**, **48 octets par ligne**, résolution annoncée **203 dpi**, papier d'environ 56/58 mm. Ces chiffres proviennent de cette unité ; un autre firmware pourrait différer. La tête couvre environ 48 mm, donc le modèle de 50 × 30 mm est composé dans un bitmap de **384 × 240 points**. Le contenu est centré dans la largeur imprimable. Le centrage physique de la tête dans le rouleau dépend du mécanisme.

## Architecture

- `Sources/LabelCore` : données produit, validation et encodage EAN‑13, prix français ; testable sans iOS.
- `App/LabelRenderer.swift` : composition à la résolution native, seuillage direct à 1 bit, barres EAN en modules entiers.
- `App/PrinterManager.swift` : découverte, sélection, reconnexion, densité et impression directe.
- `App/ContentView.swift` : formulaire, aperçu issu du **même bitmap** que l'impression, état BLE et réglages.
- Bibliothèque SwiftPM `PocketPrinter5890Kit` et `PocketPrinter5890BLE` : commandes de densité et d'activation, raster en bandes de 24 lignes, contrôle de flux BLE et transport CoreBluetooth. La dépendance est épinglée à la révision vérifiée dans ce projet.

L'EAN‑13 accepte 12 chiffres et calcule le contrôle, ou valide les 13 chiffres saisis. Les 95 modules sont dessinés à **3 points chacun** (sans redimensionnement), avec 10 modules blancs de chaque côté. Les barres font 70 points de haut. La composition reprend la maquette fournie : informations et nom alignés à gauche, chiffres EAN en trois groupes, référence sous le code, mention TTC à gauche et prix à droite. Le texte peut être antialiasé durant la composition, puis chaque point est converti en noir ou blanc par un seuil fixe de 160 ; aucun tramage photo n'est appliqué. Le bitmap résultant, large exactement de 384 points, part directement au protocole 5890.

## Compiler et installer

Prérequis : Xcode compatible avec le SDK iOS, iOS 17 ou plus récent et un compte de signature Apple pour déployer sur iPhone. Ouvrir `ProductLabel5890.xcodeproj`, sélectionner le schéma `ProductLabel5890`, choisir son iPhone, configurer l'équipe de signature si nécessaire, puis lancer. Le paquet SwiftPM est téléchargé lors de la première compilation. Test du cœur : `swift test`. Compilation vérifiée sans signature avec :

```sh
xcodebuild -project ProductLabel5890.xcodeproj -scheme ProductLabel5890 -configuration Debug -sdk iphoneos CODE_SIGNING_ALLOWED=NO build
```

## Utilisation

1. Allumer la 5890 et activer Bluetooth sur l'iPhone.
2. Ouvrir l'app. Appuyer sur **Connecter**, sélectionner `Mini Pocket Printer_BLE`. La dernière imprimante est recherchée au lancement suivant.
3. Saisir nom, catégorie, référence rayon, référence produit, EAN et prix (`5,95` ou `5.95`). L'aperçu se met à jour avec les données valides.
4. Appuyer sur **Imprimer**. En l'absence de connexion, l'app recherche l'imprimante avant d'envoyer le travail.
5. Dans **Réglages**, choisir la densité Faible, Moyenne ou Forte (Moyenne par défaut) et lancer l'étiquette de calibration. Éviter une densité trop forte si les barres fusionnent.

Le rouleau est continu. Une avance finale de 80 points, issue du projet d'origine, dégage l'étiquette de la tête ; la longueur totale de papier avancé dépasse donc 30 mm. Le test matériel doit vérifier le contraste, la lecture du code avec un scanner, la position horizontale sur le rouleau et la coupe réelle. Le simulateur de cet environnement n'est pas utilisable car CoreSimulator est plus ancien que Xcode ; la compilation iPhone et les tests du cœur ont été exécutés.

## Licence et attribution

Code du projet sous licence MIT, copyright 2026 Dimitri Iachi. La bibliothèque `PocketPrinter5890` est également sous MIT et conserve sa propre attribution et licence dans son dépôt. Le projet reprend la configuration Xcode et le choix de cette bibliothèque de `PocketPrinter5890App`, également annoncé MIT dans son README ; il ne modifie pas ce dépôt.
