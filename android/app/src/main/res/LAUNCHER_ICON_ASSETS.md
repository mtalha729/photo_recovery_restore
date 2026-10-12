# Launcher icon handoff

The approved Photo Recovery & Restore artwork supplied as
`codex-clipboard-15e799be-9963-4a21-8410-f3c435251990.png` is installed in the
`ic_launcher` and `ic_launcher_foreground` PNGs at each
Android launcher density. Android 7–8.0 uses the standard legacy fallbacks;
Android 8.0+ uses the larger density-correct adaptive foreground resource over
the existing navy background. Only the source image's pure-black outer corners
were converted to transparency for correct launcher masking.

The supplied logo is intentionally used without text or generated replacement
artwork. A separate approved single-color monochrome asset is still needed for
Android themed-icon support. Place that asset at
`android/app/src/main/res/drawable-nodpi/ic_launcher_monochrome.png`, then add
it as the `monochrome` layer in `mipmap-anydpi-v26/ic_launcher.xml`.
