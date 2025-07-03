# Font Integration Guide

## Plus Jakarta Sans

To complete the font integration, please download Plus Jakarta Sans fonts and add them to this directory:

1. Download the font from Google Fonts: https://fonts.google.com/specimen/Plus+Jakarta+Sans
2. Extract the zip file
3. Copy the following TTF files to this directory:
   - PlusJakartaSans-Regular.ttf
   - PlusJakartaSans-Medium.ttf
   - PlusJakartaSans-SemiBold.ttf
   - PlusJakartaSans-Bold.ttf

4. Add the font files to your Xcode project:
   - Drag the TTF files into Xcode project navigator (into this Fonts folder)
   - Make sure "Copy items if needed" is checked
   - Select your target when prompted

5. Update Info.plist to include the fonts:
   - Open Info.plist
   - Add a new entry "Fonts provided by application" (UIAppFonts)
   - Add string items for each font file:
     - PlusJakartaSans-Regular.ttf
     - PlusJakartaSans-Medium.ttf
     - PlusJakartaSans-SemiBold.ttf
     - PlusJakartaSans-Bold.ttf

Once these steps are completed, the custom fonts will be available throughout the application. 