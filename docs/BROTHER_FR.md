# Imprimantes Brother

**Étiquettes Produit** imprime aussi sur les imprimantes Brother, en priorité la
**TD-4550DNWB en Bluetooth Low Energy**, avec le Brother Print SDK officiel
pour iPhone. L'impression sur la Pocket 5890 (SilverCrest / Tronic) ne change
pas : elle reste le choix par défaut et passe toujours par la librairie
PocketPrinter5890.

Le volet Brother reprend [TD Print Studio](https://github.com/dimer47/BrotherTDPrintStudio),
testé sur une TD-4550DNWB en BLE depuis un iPhone 16 Pro : même SDK, mêmes
appels, mêmes réglages, mêmes contournements.

> Le SDK 4.13.2 est livré dans `Vendor/`, avec sa licence
> (`Brother-SDK-EULA.pdf`) et l'autorisation de Brother de redistribuer les
> fichiers du dossier `libs` (`Brother-SDK-Redist.txt`). Le code reste
> entouré de `#if canImport(BRLMPrinterKit)` : si le framework est retiré,
> l'app compile et affiche « Brother Print SDK absent ».

## Utilisation

Sur l'écran **Impression**, le bouton **Connecter** / **Changer** de la carte
Imprimante ouvre l'écran **Imprimante**, dans cet ordre :

1. **Imprimante** : Pocket 5890 ou Brother, puis le modèle Brother. La liste
   reprend les 93 modèles de `BRLMPrinterModel` (SDK 4.13.2), groupés par série,
   avec les connexions possibles. Un filtre « Bluetooth LE seulement » existe.
2. **Papier**, selon le modèle :

   | Imprimante | Papier proposé |
   |---|---|
   | Pocket 5890 | rouleau ticket 58 mm (inchangé) |
   | TD-4xxx | continu 102/76/58 mm, prédécoupé 102×152, 102×51, 51×26 mm, marque noire 102×152 mm, ou personnalisé jusqu'à 118 mm |
   | TD-2xxx | continu 58/51 mm, prédécoupé 40×40, 51×26 mm, marque noire 58×40 mm, ou personnalisé |
   | RJ-4 / RJ-3 / RJ-2 | formats à la largeur de la série, dans les trois types, ou personnalisé |
   | QL | étiquettes DK de `BRLMPrinterModelSpec.supportedQLLabels` |
   | PT | rubans de `BRLMPrinterModelSpec.supportedPTLabels` |
   | PJ | A4, Letter, Legal, A5 |
   | MW | format imposé par le modèle (A6 ou A7) |

   Pour les TD et RJ, trois types, comme `BRLMCustomPaperSize` :

   | Type | Réglages | Appel SDK |
   |---|---|---|
   | Continu | largeur | `rollWithTapeWidth` |
   | Prédécoupé | largeur, longueur, espace entre étiquettes | `dieCutWithTapeWidth` (`gapLength`) |
   | Marque noire | largeur, longueur, position et hauteur de la marque | `markRollWithTapeWidth` (`markPosition`, `markHeight`) |

   Plus une marge commune (1,5 mm par défaut). Si on change de modèle et que
   le papier ne convient plus, un papier compatible est remis.
3. **Coupe et copies** : coupe, décolleur et marge haut/bas (TD), copies.
4. **Qualité d'impression** : densité (TD), qualité, tramage, seuil.
5. **Connexion** : Bluetooth LE ou Wi-Fi selon le modèle, recherche, saisie
   d'une adresse IP, puis pour l'imprimante choisie :
   - **Tester la connexion et lire l'état** : ouvre le canal, lit l'état,
     referme, sans imprimer ;
   - **Infos de l'imprimante** : n° de série, firmware, version média,
     firmware Bluetooth, batterie (charge et santé) ;
   - **Rapport système** : rapport complet en rubriques (résumé, erreurs
     enregistrées, détail), avec un bouton Copier ;
   - **Journal Brother** : messages horodatés du SDK, étiquetés `SCAN`
     recherche, `LINK` connexion, `PRT` impression, `INFO` infos, `ERR`
     erreur (200 au plus, en mémoire seulement).

Pendant une impression, **Annuler** apparaît sur la carte Imprimante et dans
l'écran Imprimante. Le SDK ne s'arrête qu'entre deux pages : la page en cours
sort quand même.

La coupe, la qualité et le journal sont aussi dans **Réglages** quand une
Brother est choisie.

Tous ces choix sont conservés entre deux lancements (`UserDefaults`, comme les
autres réglages de l'app). La carte **Présentation de l'étiquette** affiche la
taille imprimée estimée sur le papier Brother.

## Connexion

- **Bluetooth LE** : `BRLMPrinterSearcher.startBLESearch`, puis
  `BRLMChannel(bleLocalName:)` avec le nom local annoncé.
- **Wi-Fi** : `BRLMPrinterSearcher.startNetworkSearch`, ou adresse IP saisie
  (`BRLMChannel(wifiIPAddress:)`).
- **Bluetooth Classic (MFi)** : non géré (autre framework `BT_Net`,
  Product Plan ID Brother, accessoire externe).

D'après le manuel du SDK, **les TD-4410D, TD-4420DN et TD-4520DN n'ont pas de
BLE** : l'app ne le leur propose pas. Le TD-4420DN et le TD-4520DN passent par
le Wi-Fi ; le TD-4410D n'existe pas dans le SDK iOS.

Toucher une imprimante trouvée par la recherche la choisit et règle le modèle
sur celui qu'elle annonce, comme TD Print Studio. Si le modèle diffère ensuite
(changé à la main, ou `BRLMPrinterStatus.model` lu par le test de connexion),
l'app le signale et propose **Basculer sur …**.

Le nom Bluetooth de l'imprimante n'est jamais lu : sur une TD-4550DNWB en BLE,
`requestBluetoothLocalName` reste bloqué plusieurs minutes et bloque les
requêtes suivantes.

## Coupe

| Réglage SDK | Option | Effet |
|---|---|---|
| `autoCut` | Coupe après chaque page | coupe après chaque page |
| `autoCutForEachPageCount` | Couper toutes les N pages (1 à 255) | coupe toutes les N pages, seulement avec `autoCut` |
| `cutAtEnd` | Coupe après la dernière page | coupe une fois à la fin du travail |

- TD et QL : les trois réglages. **Tout est désactivé par défaut** : sur la
  TD-4550DNWB, le massicot est une option matérielle. Sans massicot, rien
  n'est coupé. Si l'imprimante répond
  `printerStatusErrorIncompatibleOptionalEquipment`, l'app affiche : « La coupe
  est demandée mais le massicot n'est pas installé ou n'est pas reconnu… ».
- PT : `autoCut` et coupe toutes les N pages, pas de coupe en fin ;
  certaines P-touch n'ont qu'une coupe manuelle.
- RJ, PJ, MW : pas de coupe pilotable, l'option n'est pas affichée.

## Impression

Les étiquettes de l'app sortent sur Brother avec la même mise en page que sur
la 5890 :

1. La taille finale est estimée à partir du papier (`fitPageAspect` garde les
   proportions ; sur une étiquette prédécoupée, la longueur peut limiter).
2. L'étiquette est redessinée à cette taille, à la résolution de la tête
   (`BRLMPrinterModelSpec.xdpi`, 300 dpi sur la TD-4550DNWB). Le texte est
   composé à cette résolution. Les modules du code-barres gardent un nombre
   entier de points (9 points sur un rouleau 102 mm à 300 dpi), sans lissage.
3. Le résultat, strictement noir et blanc, part en `CGImage` sans
   interpolation vers `printImage(with:settings:)`, avec `scaleMode =
   .fitPageAspect`. Le tramage par défaut est le seuil (`.threshold`) ; la
   diffusion d'erreur et le motif sont proposés mais dégradent les codes-barres.
4. Avant l'envoi, `BRLMValidatePrintSettings.validate` contrôle les réglages :
   une erreur est affichée au lieu d'être envoyée ; les avertissements sont
   ajoutés au message.

Recherche, rendu et impression se font sur une file dédiée, jamais sur le fil
principal. L'historique n'enregistre une impression Brother que si le SDK a
accepté le travail.

Les réglages **Impression thermique (Pocket 5890)** (densité, avances,
rotation 180°) ne concernent que la 5890.

## Le SDK dans le projet

| | |
|---|---|
| Version | **4.13.2** (`bpsdkiall4132`) |
| Variante | `libs/Net` : Bluetooth LE et Wi-Fi, sans Product Plan ID |
| Emplacement | `Vendor/BRLMPrinterKit.xcframework` (iPhone et simulateur) |
| Projet | lié et intégré (*Embed & Sign*), macro `WLAN_ONLY`, `LD_RUNPATH_SEARCH_PATHS = @executable_path/Frameworks` |

Rien à faire dans Xcode : ouvrir `ProductLabel5890.xcodeproj`, choisir son
équipe de signature et lancer sur un iPhone.

- `.gitattributes` (`Vendor/** -text -diff`) interdit à Git de toucher aux
  fichiers du SDK : la conversion des fins de ligne casserait la signature
  du framework.
- Le chemin `@executable_path/Frameworks` est indispensable : avec celui de
  macOS (`@executable_path/../Frameworks`), l'app plante au lancement dès
  qu'elle embarque le SDK.
- Les 4.13.0 et 4.13.1 n'ont ni RJ-2031, ni RJ-2131, ni PT-P750Wc. Pour mettre
  à jour le SDK, vérifier le numéro dans le nom du zip et remplacer tout le
  dossier `Vendor/BRLMPrinterKit.xcframework`.
- La variante `BT_Net` (Bluetooth Classic MFi) n'est pas utilisée : elle
  demande une autorisation MFi d'Apple.

Les clés `Info.plist` sont présentes : `NSBluetoothAlwaysUsageDescription` et
`NSBluetoothPeripheralUsageDescription` (BLE), `NSLocalNetworkUsageDescription`
et `NSBonjourServices` (`_pdl-datastream._tcp`, `_printer._tcp`, `_ipp._tcp`)
pour le Wi-Fi.

Le simulateur n'a pas de Bluetooth : il ne sert qu'à vérifier l'interface.

## Points à vérifier sur la TD-4550DNWB

Les appels au SDK sont ceux de TD Print Studio. Dans TD Print Studio, sur
TD-4550DNWB : recherche BLE, test de connexion, infos de l'imprimante et
impression (texte, QR code) sont testés ; densité, qualité, tramage, PDF,
rapport système, annulation, coupe, décolleur, marge et Wi-Fi sont codés mais
pas vérifiés sur papier. Dans ProductLabel5890, rien n'a encore été lancé.

- Compilation sur Mac et lancement sur iPhone (le framework se charge).
- Bluetooth activé sur l'imprimante, qui n'est connectée à aucun autre
  appareil pendant la recherche. La recherche BLE renvoie « TD-4550DNWB » et un
  nom local ; la première connexion déclenche la demande d'autorisation
  Bluetooth.
- **Tester la connexion et lire l'état** : « Prête », le modèle, la largeur du
  papier ; capot ouvert et papier absent donnent un message clair.
- Le papier choisi correspond au rouleau chargé, et l'imprimante a été
  calibrée pour lui (capteur d'espace en prédécoupé, capteur de marque en
  marque noire).
- Marque noire : l'impression démarre au bon endroit de chaque étiquette ;
  sinon, ajuster la position de la marque.
- Taille et position de l'étiquette sur rouleau 102 mm et sur étiquette
  102×51 mm ; ajuster les marges si besoin.
- **Lecture du code-barres au scanner** sur chaque format : si le SDK
  redimensionne légèrement l'image, la largeur des barres peut varier d'un point.
- Massicot installé : coupe après chaque page, toutes les N pages et après la
  dernière, avec 1 puis 3 copies.
- Massicot absent avec coupe activée : noter la réponse (aucune coupe, ou
  message « massicot non installé »).
- **Infos de l'imprimante**, **Rapport système** (peut prendre une minute en
  BLE) et **Annuler** pendant une impression de plusieurs copies.
- Densité −5 / 0 / +5 et seuil : effet sur le contraste et sur la lecture du
  code-barres.
- Wi-Fi : recherche sur le réseau local (autorisation « Réseau local » d'iOS)
  et adresse IP saisie à la main.
- Retour à la Pocket 5890 : connexion, impression et réglages inchangés.
