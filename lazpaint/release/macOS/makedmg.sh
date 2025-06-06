#!/bin/bash
set -e
cd `dirname $0`

if ! [ ${OSTYPE:0:6} = "darwin" ]; then
  echo "This script is for OS X only"
  exit 1
fi

appname=LazPaint
appversion=7.3
pkgversion=0
appnamenospaces=lazpaint
appbundle="$appname.app"

DMG_BACKGROUND_IMG="background.png"
VOL_NAME="$appnamenospaces${appversion}_macos"   
DMG_TMP="${VOL_NAME}-temp.dmg"
DMG_FINAL="${VOL_NAME}.dmg"         
STAGING_DIR="./staging"             # we copy all our stuff into this dir
SOURCE_DIR="$(cd ../bin; pwd)"
SCRIPT_DIR="$(cd ../../../resources/scripts; pwd)"

# Check the background image DPI and convert it if it isn't 72x72
_BACKGROUND_IMAGE_DPI_H=`sips -g dpiHeight ${DMG_BACKGROUND_IMG} | grep -Eo '[0-9]+\.[0-9]+'`
_BACKGROUND_IMAGE_DPI_W=`sips -g dpiWidth ${DMG_BACKGROUND_IMG} | grep -Eo '[0-9]+\.[0-9]+'`

if [ $(echo " $_BACKGROUND_IMAGE_DPI_H != 72.0 " | bc) -eq 1 -o $(echo " $_BACKGROUND_IMAGE_DPI_W != 72.0 " | bc) -eq 1 ]; then
   echo "WARNING: The background image's DPI is not 72.  This will result in distorted backgrounds on Mac OS X 10.7+."
   echo "         I will convert it to 72 DPI for you."
   
   _DMG_BACKGROUND_TMP="${DMG_BACKGROUND_IMG%.*}"_dpifix."${DMG_BACKGROUND_IMG##*.}"

   sips -s dpiWidth 72 -s dpiHeight 72 ${DMG_BACKGROUND_IMG} --out ${_DMG_BACKGROUND_TMP}
   
   DMG_BACKGROUND_IMG="${_DMG_BACKGROUND_TMP}"
fi

# clear out any old data
rm -rf "${STAGING_DIR}" "${DMG_TMP}" "${DMG_FINAL}"

# copy over the stuff we want in the final disk image to our staging dir
mkdir -p "${STAGING_DIR}"
cp -rpf "./$appbundle" "${STAGING_DIR}"
# ... cp anything else you want in the DMG - documentation, etc.

echo Staging files...
pushd "${STAGING_DIR}/${appbundle}" >/dev/null
 pushd Contents >/dev/null
  pushd MacOS >/dev/null
   unlink delete.me
   cp "${SOURCE_DIR}/${appnamenospaces}" .
  popd >/dev/null
  pushd Resources >/dev/null
   cp -r "${SOURCE_DIR}/i18n" .
   cp -r "${SOURCE_DIR}/models" .
   cp "${SOURCE_DIR}/readme.txt" .
   cp -r "${SCRIPT_DIR}" .
  popd >/dev/null
 popd >/dev/null
popd >/dev/null

echo Making uncompressed DMG
# figure out how big our DMG needs to be
#  assumes our contents are at least 1M!
SIZE=`du -sh "${STAGING_DIR}" | sed 's/\([0-9\.]*\)M\(.*\)/\1/'`
SIZE=`echo "${SIZE} + 1.0" | bc | awk '{print int($1+0.5)}'`

if [ $? -ne 0 ]; then
   echo "Error: Cannot compute size of staging dir"
   exit
fi

# create the temp DMG file
hdiutil create -srcfolder "${STAGING_DIR}" -volname "${VOL_NAME}" -fs HFS+ \
      -fsargs "-c c=64,a=16,e=16" -format UDRW -size ${SIZE}M "${DMG_TMP}"

echo Mounting DMG...
# mount it and save the device
DEVICE=$(hdiutil attach -readwrite -noverify "${DMG_TMP}" | \
         egrep '^/dev/' | sed 1q | awk '{print $1}')

sleep 2

# add a link to the Applications dir
echo "Adding link to Applications..."
pushd /Volumes/"${VOL_NAME}" >/dev/null
ln -s /Applications
popd >/dev/null

# add a background image
echo "Adding background image..."
mkdir /Volumes/"${VOL_NAME}"/.background
cp "${DMG_BACKGROUND_IMG}" /Volumes/"${VOL_NAME}"/.background/

# tell the Finder to resize the window, set the background,
#  change the icon size, place the icons in the right position, etc.
echo '
   tell application "Finder"
     tell disk "'${VOL_NAME}'"
           open
           set current view of container window to icon view
           set toolbar visible of container window to false
           set statusbar visible of container window to false
           set the bounds of container window to {400, 100, 920, 440}
           set viewOptions to the icon view options of container window
           set arrangement of viewOptions to not arranged
           set icon size of viewOptions to 72
           set background picture of viewOptions to file ".background:'${DMG_BACKGROUND_IMG}'"
           set position of item "'$appbundle'" of container window to {160, 205}
           set position of item "Applications" of container window to {360, 205}
           close
           open
           update without registering applications
           delay 2
     end tell
   end tell
' | osascript

sync

# unmount it
hdiutil detach "${DEVICE}"

# now make the final image a compressed disk image
echo "Creating compressed image"
hdiutil convert "${DMG_TMP}" -format UDZO -imagekey zlib-level=9 -o "${DMG_FINAL}"

# clean up
echo Cleaning up...
rm -rf "${DMG_TMP}"
rm -rf "${STAGING_DIR}"

echo 'Done.'
