#!/usr/bin/env bash
#
# Génère les captures d'écran App Store de l'app (fastlane snapshot).
# Un seul point d'entrée : ./captures.sh
#
#   ./captures.sh              # génère tout (devices x langues du Snapfile)
#   ./captures.sh "iPhone Duo" # restreint à un device
#   ./captures.sh "iPhone Duo" "fr-FR"   # device + langue
#
# Le script choisit un Ruby récent (le système est trop vieux pour fastlane),
# installe fastlane au premier lancement, puis lance la génération.
# Les captures arrivent dans fastlane/screenshots/ (+ aperçu screenshots.html).

set -euo pipefail
cd "$(dirname "$0")"

# 1) Ruby récent (Homebrew) : le Ruby système 2.6 ne compile pas fastlane.
for ruby_bin in /opt/homebrew/opt/ruby/bin /usr/local/opt/ruby/bin; do
  [ -x "$ruby_bin/ruby" ] && export PATH="$ruby_bin:$PATH" && break
done
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

if ! ruby -e 'exit(RUBY_VERSION.split(".").first.to_i >= 3)' 2>/dev/null; then
  echo "❌ Ruby >= 3 introuvable. Installez-le : brew install ruby" >&2
  exit 1
fi

# 2) fastlane installé localement (vendor/bundle) au premier lancement.
if ! bundle check >/dev/null 2>&1; then
  echo "📦 Installation de fastlane (première fois)…"
  bundle config set --local path 'vendor/bundle' >/dev/null
  bundle install
fi

# 3) Génération. Les arguments éventuels restreignent device/langue.
echo "📸 Génération des captures…"
if [ "$#" -ge 2 ]; then
  bundle exec fastlane snapshot --devices "$1" --languages "$2"
elif [ "$#" -eq 1 ]; then
  bundle exec fastlane snapshot --devices "$1"
else
  bundle exec fastlane screenshots
fi

echo ""
echo "✅ Terminé. Aperçu : open fastlane/screenshots/screenshots.html"
