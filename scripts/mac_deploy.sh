#!/bin/bash

set -euo pipefail

CERTIFICATE="Developer ID Application: Andrew Gilbert (${APPLE_DEV_TEAM_ID})"
FRAMEWORKS="QtCore QtGui QtNetwork QtOpenGL QtSql QtWidgets QtXml QtPrintSupport"

find_brew_prefix()
{
   local formula=$1
   if command -v brew >/dev/null 2>&1; then
      brew --prefix "$formula" 2>/dev/null || true
   fi
}

resolve_qt_prefix()
{
   if [[ -n "${QT_PREFIX:-}" ]]; then
      echo "$QT_PREFIX"
      return
   fi

   if [[ -n "${IQMOL_QT_ROOT:-}" ]]; then
      echo "$IQMOL_QT_ROOT"
      return
   fi

   local brew_qt
   brew_qt=$(find_brew_prefix qt@5)
   if [[ -n "$brew_qt" ]]; then
      echo "$brew_qt"
      return
   fi
}

QT_PREFIX=$(resolve_qt_prefix)
if [[ -z "$QT_PREFIX" ]]; then
   echo "Could not find a Qt 5 installation. Set QT_PREFIX or IQMOL_QT_ROOT."
   exit 1
fi

QT_FRAMEWORK_PATH="${QT_PREFIX}/lib"
QT_BIN_PATH="${QT_PREFIX}/bin"


# retrieve bundle name from first parameter
BUNDLE_DIRECTORY=$1
if [[ "$BUNDLE_DIRECTORY" =~ ^-no_deployqt$ ]]; then
   DEPLOYQT=0
   BUNDLE_DIRECTORY=$2
else
   DEPLOYQT=1
fi

BUNDLE_NAME=IQmol.app
DMG_NAME="${BUNDLE_DIRECTORY}.dmg"

if [[ "$BUNDLE_DIRECTORY" =~ ^IQmol-[0-9].[0-9].[0-9]$ ]]; then
   echo "Processing directory $BUNDLE_DIRECTORY"
else
   echo "Incorrect argument passed.  Should match IQmol-x.y.z"
   exit;
fi

if [[ -f "${DMG_NAME}" ]]; then
   echo "removing existing dmg file"
   rm ${DMG_NAME}
fi

if [[ ! -d "$BUNDLE_DIRECTORY/$BUNDLE_NAME" ]]; then
   echo "Could not find IQmol application  $BUNDLE_DIRECTORY/$BUNDLE_NAME"
   exit
fi

if [[ -f "$BUNDLE_DIRECTORY/$BUNDLE_NAME/Contents/MacOS/ffmpeg" ]]; then
  echo "Found ffmpeg binary"
else
  echo "Could not find ffmpeg binary in $BUNDLE_NAME/Contents/MacOS"
  exit
fi


#----------------------------------------------------------------------------------
cd $BUNDLE_DIRECTORY
#----------------------------------------------------------------------------------


if [[ $DEPLOYQT ]]; then

${QT_BIN_PATH}/macdeployqt $BUNDLE_NAME

if [[ -f "$BUNDLE_NAME/Contents/Plugins/sqldrivers/libqsqlite.dylib" ]]; then
  echo "Found SQLite plugin"
else
  DIR=${BUNDLE_NAME}/Contents/Plugins/sqldrivers
  mkdir -p $DIR
  cp -r ${QT_FRAMEWORK_PATH}/../plugins/sqldrivers/libqsqlite.dylib ${DIR}
fi


# FIX ISSUE 6
# Please note that Qt5 frameworks have incorrect layout after SDK build, so this isn't just a problem with `macdeployqt` but whole framework assembly part.
# Present
#   QtCore.framework/
#       Contents/
#           Info.plist
#       QtCore    -> Versions/Current/QtCore
#       Versions/
#           Current -> 5
#           5/
#               QtCore
# After macdeployqt
#   QtCore.framework/
#       Resources/
#       Versions/
#           5/
#               QtCore
#
# Expected
#   QtCore.framework/
#       QtCore    -> Versions/Current/QtCore
#       Resources -> Versions/Current/Resources
#       Versions/
#           Current -> 5
#           5/
#               QtCore
#               Resources/
#                   Info.plist
# So in order to comply with expected layout: https://developer.apple.com/library/mac/documentation/MacOSX/Conceptual/BPFrameworks/Concepts/FrameworkAnatomy.html

for CURRENT_FRAMEWORK in ${FRAMEWORKS}; do
    echo "Processing framework: ${CURRENT_FRAMEWORK}"

    #echo "Deleting existing resource folder"
    rm -rf ${BUNDLE_NAME}/Contents/Frameworks/${CURRENT_FRAMEWORK}.framework/Resources

    #echo "create resource folder"
    mkdir -p ${BUNDLE_NAME}/Contents/Frameworks/${CURRENT_FRAMEWORK}.framework/Versions/5/Resources

    #echo "create copy resource file"
    cp -f ${QT_FRAMEWORK_PATH}/${CURRENT_FRAMEWORK}.framework/Resources/Info.plist $BUNDLE_NAME/Contents/Frameworks/${CURRENT_FRAMEWORK}.framework/Versions/5/Resources/

    #echo "create symbolic links"
    ln -nfs 5                                     ${BUNDLE_NAME}/Contents/Frameworks/${CURRENT_FRAMEWORK}.framework/Versions/Current
    ln -nfs Versions/Current/${CURRENT_FRAMEWORK} ${BUNDLE_NAME}/Contents/Frameworks/${CURRENT_FRAMEWORK}.framework/${CURRENT_FRAMEWORK}
    ln -nfs Versions/Current/Resources            ${BUNDLE_NAME}/Contents/Frameworks/${CURRENT_FRAMEWORK}.framework/Resources
done

# FIX ISSUE 7
for CURRENT_FRAMEWORK in ${BAD_FRAMEWORKS}; do
    echo "Correcting bad framework Info.plist: ${CURRENT_FRAMEWORK}"
    TMP=$(sed 's/_debug//g' ${BUNDLE_NAME}/Contents/Frameworks/${CURRENT_FRAMEWORK}.framework/Resources/Info.plist)
    echo "$TMP" > ${BUNDLE_NAME}/Contents/Frameworks/${CURRENT_FRAMEWORK}.framework/Resources/Info.plist
done

echo "Copying libgcc to Framework directory"
LIBGCC_PATH=$(otool -L "$BUNDLE_NAME/Contents/MacOS/IQmol" | awk '/libgcc_s/{print $1; exit}')
if [[ -z "$LIBGCC_PATH" && -f "$BUNDLE_NAME/Contents/MacOS/ffmpeg" ]]; then
   LIBGCC_PATH=$(otool -L "$BUNDLE_NAME/Contents/MacOS/ffmpeg" | awk '/libgcc_s/{print $1; exit}')
fi
if [[ -n "$LIBGCC_PATH" ]]; then
   cp "$LIBGCC_PATH" "$BUNDLE_NAME/Contents/Frameworks/"
fi

fi # DEPLOYQT


######################################################################################################################

# Sign nested components (e.g., libraries, binaries)
find "$BUNDLE_NAME/Contents" -type f \( -name "*.dylib" -o -name "*.so" -o -perm +111 \) | while read file; do
    echo "Signing $file"
    codesign --force --timestamp --options runtime --sign "$CERTIFICATE" "$file"
done
echo

# Sign frameworks (if any)
if [ -d "$BUNDLE_NAME/Contents/Frameworks" ]; then
    find "$BUNDLE_NAME/Contents/Frameworks" -type d -name "*.framework" | while read framework; do
        echo "Signing $framework"
        codesign --force --timestamp --options runtime --sign "$CERTIFICATE"  "$framework"
    done
fi
echo

# Sign plugins (if any)
if [ -d "$BUNDLE_NAME/Contents/PlugIns" ]; then
    find "$BUNDLE_NAME/Contents/PlugIns" -type d | while read plugin; do
        echo "Signing $plugin"
        codesign --force --timestamp --options runtime --sign "$CERTIFICATE"  "$plugin"
    done
fi
echo

# Sign the app binary
codesign --force --timestamp --options runtime --sign "$CERTIFICATE"  "${BUNDLE_NAME}/Contents/MacOS/IQmol"

# Finally, sign the app bundle
codesign --force --timestamp --options runtime --sign "$CERTIFICATE"  "$BUNDLE_NAME"

# Verify
echo "Verifing Bundle"
codesign --verify --deep --strict --verbose=4 $BUNDLE_NAME
#echo "******* Verify Bundle using dpctl ***********"
spctl --assess --type execute --verbose $BUNDLE_NAME


#----------------------------------------------------------------------------------
cd ..
#----------------------------------------------------------------------------------

echo "Creating dmg file"
hdiutil create -volname "IQmol" -srcfolder $BUNDLE_DIRECTORY  -ov -format UDZO ${DMG_NAME}
echo "Submitting to notarytool"
xcrun notarytool submit ${DMG_NAME} --apple-id ${APPLE_DEV_ID} --team-id ${APPLE_DEV_TEAM_ID} --password ${APPLE_DEV_PASSWORD} --wait
echo "Stapling certificate"
xcrun  stapler staple ${DMG_NAME}
