#!/bin/bash
#
# Auto-incrémente le numéro de build (CFBundleVersion) à CHAQUE compilation.
#
# But : distinguer les builds installés successivement (l'app restait bloquée à « 8 »,
# figé par CURRENT_PROJECT_VERSION dans le projet).
#
# Principe :
#   - Un compteur persistant est stocké HORS du binaire, dans "$SRCROOT/.build-number"
#     (fichier ignoré par git, voir .gitignore). À chaque build il est lu, incrémenté,
#     réécrit, puis injecté dans l'Info.plist du .app PRODUIT — jamais dans la source.
#   - On ne touche donc NI le project.pbxproj NI Resources/Info.plist : le dépôt n'est
#     pas pollué à chaque compilation, et chaque build porte un CFBundleVersion
#     strictement supérieur au précédent.
#   - Le compteur démarre au moins à CURRENT_PROJECT_VERSION + 1 (ici 9), pour rester
#     au-dessus du dernier build « 8 » déjà distribué.
#
# Cible : $BUILT_PRODUCTS_DIR/$INFOPLIST_PATH (l'Info.plist à l'intérieur du .app).
# Doit s'exécuter APRÈS la phase « Copy Bundle Resources » (qui génère l'Info.plist).

set -euo pipefail

# Hors d'un build Xcode (lancement manuel), on ne fait rien de destructif.
if [ -z "${BUILT_PRODUCTS_DIR:-}" ] || [ -z "${INFOPLIST_PATH:-}" ]; then
  echo "bump_build_number : variables Xcode absentes, rien à faire." >&2
  exit 0
fi

PLIST="${BUILT_PRODUCTS_DIR}/${INFOPLIST_PATH}"
if [ ! -f "$PLIST" ]; then
  echo "bump_build_number : Info.plist produit introuvable ($PLIST)." >&2
  exit 0
fi

COUNTER_FILE="${SRCROOT:-$(pwd)}/.build-number"

# Plancher : au-dessus du dernier build distribué (CURRENT_PROJECT_VERSION = 8).
FLOOR=9

# Lit le compteur courant (0 si absent/illisible), applique le plancher, incrémente.
current=0
if [ -f "$COUNTER_FILE" ]; then
  current=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
fi
case "$current" in
  ''|*[!0-9]*) current=0 ;;
esac
if [ "$current" -lt "$FLOOR" ]; then
  current=$FLOOR
else
  current=$((current + 1))
fi

echo "$current" > "$COUNTER_FILE"

# Injecte le nouveau build number dans l'Info.plist du .app produit.
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $current" "$PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $current" "$PLIST"

echo "bump_build_number : CFBundleVersion = $current (dans le .app produit)."
