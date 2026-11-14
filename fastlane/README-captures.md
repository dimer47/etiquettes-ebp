# Captures d'écran automatiques (fastlane snapshot)

Génère les captures App Store de l'app **en mode démonstration** (données factices,
hors ligne, sans gateway ni compte), sur plusieurs simulateurs et langues, en une
commande. À lancer **à la montée de version**, pas à chaque build.

## Ce qui est déjà en place

- `fastlane/Snapfile` — simulateurs, langues, dossier de sortie.
- `fastlane/Fastfile` — lanes `screenshots` (génération locale) et `upload_screenshots`.
- `fastlane/.env.example` — modèle des secrets d'upload (le vrai `.env` n'est jamais commité).
- `Gemfile` — dépendance fastlane.
- `ProductLabelsUITests/SnapshotHelper.swift` — helper officiel fastlane.
- `ProductLabelsUITests/ScreenshotUITests.swift` — parcours de capture.
- Argument de lancement `--uitest-demo` géré par l'app (`GatewaySettings`) : démarre
  directement sur le catalogue en mode démo.

## Étape à faire UNE FOIS dans Xcode : créer la cible de tests UI

fastlane a besoin d'une cible **UI Testing Bundle**. Les deux fichiers Swift ci-dessus
existent déjà dans `ProductLabelsUITests/`, il reste à créer la cible qui les compile :

1. Ouvrir `ProductLabels.xcodeproj` dans Xcode.
2. Menu **File → New → Target…**
3. Choisir **UI Testing Bundle** (section iOS), puis **Next**.
4. Réglages :
   - **Product Name** : `ProductLabelsUITests`
   - **Target to be Tested** : `ProductLabels`
   - Langue : Swift
   - **Finish**.
5. Xcode crée un dossier/target `ProductLabelsUITests` avec un fichier d'exemple.
   - **Supprimer** le fichier d'exemple généré (ex. `ProductLabelsUITestsLaunchTests.swift`
     et le `...UITests.swift` vide) **de la cible** (Move to Trash).
   - **Ajouter à la cible** les deux fichiers déjà présents sur le disque :
     clic droit sur le groupe `ProductLabelsUITests` → **Add Files to "ProductLabels"…**
     → sélectionner `SnapshotHelper.swift` et `ScreenshotUITests.swift`
     (déjà dans `ProductLabelsUITests/`), cocher la cible `ProductLabelsUITests`.
6. Vérifier que le **schéma `ProductLabels`** inclut la cible de test :
   **Product → Scheme → Edit Scheme… → Test → +** → ajouter `ProductLabelsUITests` si absent.
7. Lancer une fois les tests (**Cmd+U**) pour valider que le parcours se déroule.

> Astuce : si un écran n'est pas trouvé par le test, ajouter un
> `.accessibilityIdentifier("…")` sur l'élément concerné dans l'app et viser cet
> identifiant dans `ScreenshotUITests.swift` (plus robuste que le libellé).

## Générer les captures

```sh
bundle install            # une fois, installe fastlane
bundle exec fastlane screenshots
```

Les PNG arrivent dans `fastlane/screenshots/` (ignoré par git), avec un aperçu
`screenshots.html`. **Relire les captures** avant tout envoi.

## Envoyer sur App Store Connect (optionnel, manuel)

Ne jamais faire pendant qu'une version est **en cours de vérification**.

1. `cp fastlane/.env.example fastlane/.env` puis renseigner les 3 variables
   (Key ID, Issuer ID, chemin du `.p8`). Le `.p8` reste **hors du dépôt**.
2. `bundle exec fastlane upload_screenshots`
   — envoie **uniquement les captures**, en brouillon, **sans** soumettre à la vérification.

## Sécurité (dépôt public)

- Aucun identifiant de compte Apple n'est commité : clés, certificats, profils et `.env`
  sont exclus par `.gitignore`.
- Le `Team ID` présent dans le projet n'est pas un secret (il figure déjà dans toute app
  publiée et n'ouvre aucun accès sans l'Apple ID, le mot de passe et les clés privées).
