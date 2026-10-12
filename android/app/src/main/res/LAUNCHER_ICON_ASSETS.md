# Launcher icon assets

The current Photo Recovery Google Play artwork is kept as the 512x512 master at
`assets/photo_recovery_google_play_icon.png`. The same artwork is resized into
the Android legacy launcher densities, the adaptive foreground resource, and
the other platform icon sets so the project has one consistent app identity.

Android 7–8.0 uses the density-specific legacy fallbacks; Android 8.0+ uses the
adaptive launcher resource in `mipmap-anydpi-v26/ic_launcher.xml`. The artwork
includes its own rounded-square background and is intentionally used without
text or a generated wordmark.

A separate approved single-color monochrome asset is still needed for Android
themed-icon support. Place that asset at
`android/app/src/main/res/drawable-nodpi/ic_launcher_monochrome.png`, then add
it as the `monochrome` layer in `mipmap-anydpi-v26/ic_launcher.xml`.
