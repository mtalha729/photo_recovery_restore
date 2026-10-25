# Launcher icon handoff

The user-supplied `Photo_Recovery_Google_Play_Icon_512x512.png` artwork is
installed in the `ic_launcher` and `ic_launcher_foreground` PNGs at each Android
launcher density. The legacy icons use the full image. On Android 8.0+, the
adaptive icon centers the artwork at 75% of the foreground canvas over a white
background so common launcher masks do not crop the main subject.

The supplied logo is intentionally used without text or generated replacement
artwork. A separate approved single-color monochrome asset is still needed for
Android themed-icon support. Place that asset at
`android/app/src/main/res/drawable-nodpi/ic_launcher_monochrome.png`, then add
it as the `monochrome` layer in `mipmap-anydpi-v26/ic_launcher.xml`.
