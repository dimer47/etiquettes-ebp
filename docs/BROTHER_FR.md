# Imprimantes Brother

**Étiquettes Pocket** imprime aussi sur les imprimantes Brother, en priorité la
**TD-4550DNWB en Bluetooth Low Energy**, avec le Brother Print SDK officiel
pour iPhone. L'impression sur la Pocket 5890 (SilverCrest / Tronic) ne change
pas : elle reste le choix par défaut et passe toujours par la librairie
PocketPrinter5890.

> Le SDK n'est pas dans ce dépôt : c'est un binaire propriétaire Brother.
> L'app compile sans lui ; le choix Brother affiche alors « Brother Print SDK
> absent » et les boutons de recherche et d'impression restent inactifs.

## Utilisation

Sur l'écran **Impression**, le bouton **Connecter** / **Changer** de la carte
Imprimante ouvre l'écran **Imprimante**, dans cet ordre :

1. **Imprimante** : Pocket 5890 ou Brother, puis le modèle Brother. La liste
   reprend les 90 modèles de `BRLMPrinterModel` (SDK 4.13), groupés par série,
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
3. **Coupe et copies** (Brother).
4. **Connexion** : Bluetooth LE ou Wi-Fi selon le modèle, recherche, saisie
   d'une adresse IP, bouton **Tester la connexion et lire l'état** (ouvre le
   canal, lit l'état, referme, sans imprimer).

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

Si l'imprimante annonce un autre modèle que celui choisi (nom renvoyé par la
recherche, ou `BRLMPrinterStatus.model` lu par le test de connexion), l'app le
signale et propose **Basculer sur …**. Elle ne change pas le modèle d'elle-même.

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
- PT : seule `autoCut` est proposée.
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
   .fitPageAspect` et `halftone = .threshold`.
4. Avant l'envoi, `BRLMValidatePrintSettings.validate` contrôle les réglages :
   une erreur est affichée au lieu d'être envoyée ; les avertissements sont
   ajoutés au message.

Recherche, rendu et impression se font sur une file dédiée, jamais sur le fil
principal. L'historique n'enregistre une impression Brother que si le SDK a
accepté le travail.

Les réglages **Impression thermique (Pocket 5890)** (densité, avances,
rotation 180°) ne concernent que la 5890.

## Ajouter le SDK dans Xcode

1. Décompresser le Brother Print SDK for iPhone/iPad 4.13.2
   (`bpsdkiall4132.zip`).
2. Copier **`libs/Net/BRLMPrinterKit.xcframework`** dans `Vendor/` à la racine
   du dépôt. Ce dossier est ignoré par git : le SDK ne doit jamais être commité.
   Le framework **Net** suffit pour le BLE et le Wi-Fi, sans Product Plan ID.
   `libs/BT_Net` ne sert qu'au Bluetooth Classic MFi, que l'app ne gère pas.
3. Ouvrir `ProductLabel5890.xcodeproj`, glisser
   `Vendor/BRLMPrinterKit.xcframework` dans le projet (sans cocher « Copy items
   if needed », cible `ProductLabel5890`).
4. Cible `ProductLabel5890` → **General → Frameworks, Libraries, and Embedded
   Content** : choisir **Embed & Sign**.
5. **Build Settings → Preprocessor Macros** : `WLAN_ONLY` est déjà présent dans
   le projet, comme le demande Brother pour le framework Net. Le vérifier.
6. Compiler sur un iPhone réel. Le code Brother est entouré de
   `#if canImport(BRLMPrinterKit)` et s'active dès que le framework est lié.

Ne pas commiter le changement de `project.pbxproj` produit par l'étape 3 : il
référence un fichier absent du dépôt et casserait la compilation sans SDK.

Les clés `Info.plist` sont déjà présentes : `NSBluetoothAlwaysUsageDescription`
(BLE), `NSLocalNetworkUsageDescription` et `NSBonjourServices`
(`_pdl-datastream._tcp`, `_printer._tcp`, `_ipp._tcp`) pour le Wi-Fi.

Le simulateur n'a pas de Bluetooth : tester sur iPhone.

## Points à vérifier sur la TD-4550DNWB

Cette intégration suit les en-têtes de BRLMPrinterKit 4.13 ; elle n'a pas
encore été essayée sur l'imprimante.

- Compilation avec le SDK lié (noms Swift des modèles, `spec.xdpi`, etc.).
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
- Wi-Fi : recherche sur le réseau local (autorisation « Réseau local » d'iOS)
  et adresse IP saisie à la main.
- Retour à la Pocket 5890 : connexion, impression et réglages inchangés.
