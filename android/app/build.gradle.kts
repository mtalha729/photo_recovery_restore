import java.util.Properties

val releaseSigningProperties = Properties()
val releaseSigningPropertiesFile = rootProject.file("signing.properties")
val hasReleaseSigning = releaseSigningPropertiesFile.isFile
if (hasReleaseSigning) {
    releaseSigningPropertiesFile.inputStream().use(releaseSigningProperties::load)
}

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after Android and Kotlin plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.photorecoveryrestore.app"
    compileSdk = maxOf(flutter.compileSdkVersion, 36)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.photorecoveryrestore.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = maxOf(flutter.targetSdkVersion, 36)
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Do not configure static ABI APK splits here: Flutter sets default NDK
    // abiFilters during normal release configuration. Use --split-per-abi for
    // local ARM-only APKs; see the README build instructions.

    // Keep one AAB upload; Google Play serves configuration splits per device.
    bundle {
        abi {
            enableSplit = true
        }
        density {
            enableSplit = true
        }
    }

    // Do not set ndk.abiFilters or static ABI splits: a universal APK keeps
    // Flutter's supported ARM and x86_64 libraries available for device tests.
    // Modern AGP packages JNI libraries uncompressed by default, which also
    // preserves 16 KB page-size-compatible packaging when the toolchain emits
    // compatible native libraries.
    packaging {
        jniLibs {
            useLegacyPackaging = false
        }
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = releaseSigningProperties.getProperty("storeFile")?.let(::file)
                storePassword = releaseSigningProperties.getProperty("storePassword")
                keyAlias = releaseSigningProperties.getProperty("keyAlias")
                keyPassword = releaseSigningProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // A release without signing.properties stays unsigned. Never sign
            // it silently with the debug certificate: that breaks upgrades.
            signingConfig = if (hasReleaseSigning) signingConfigs.getByName("release") else null
            isDebuggable = false
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
        }
        create("internalRelease") {
            // Signed like release for local device validation, but the
            // restricted permission lives only in this variant's manifest.
            initWith(getByName("release"))
            matchingFallbacks += listOf("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
