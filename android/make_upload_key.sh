#!/bin/bash
# Generates the Play upload key for Scale Runner.
# Run this yourself so the password is only ever typed by you:
#
#   bash android/make_upload_key.sh
#
# keytool will prompt for a password twice (store + key — use the same one).
# Back the resulting upload-keystore.jks up somewhere safe. If you lose it AND
# Play App Signing is off, you can never update the app again.
set -euo pipefail

cd "$(dirname "$0")"

if [ -f upload-keystore.jks ]; then
  echo "upload-keystore.jks already exists — refusing to overwrite it."
  exit 1
fi

# macOS ships a stub `keytool` with no JRE behind it. Use the JDK that Android
# Studio bundles (the same one Flutter builds with).
KEYTOOL="/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool"
if [ ! -x "$KEYTOOL" ]; then
  KEYTOOL="$(command -v keytool || true)"
fi
if [ ! -x "$KEYTOOL" ]; then
  echo "Couldn't find a working keytool. Install a JDK or Android Studio."
  exit 1
fi

"$KEYTOOL" -genkey -v \
  -keystore upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload \
  -dname "CN=Cygnus Innovations LLC, O=Cygnus Innovations LLC, C=US"

echo
read -r -s -p "Re-enter that same password to write key.properties: " PW
echo

cat > key.properties <<EOF
storePassword=$PW
keyPassword=$PW
keyAlias=upload
storeFile=upload-keystore.jks
EOF

chmod 600 key.properties
unset PW

echo "Done. Created android/upload-keystore.jks and android/key.properties (both gitignored)."
