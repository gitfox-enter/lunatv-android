import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "org.moontechlab.selene"
compileSdk = flutter.compileSdkVersion
    // No native sources are compiled here (media_kit ships prebuilt .so), so a
    // 1GB NDK download buys nothing; drop it to keep builds offline-friendly.

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "org.moontechlab.selene"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val keystorePropertiesFile = rootProject.file("key.properties")
    val hasSigningConfig = keystorePropertiesFile.exists()

    signingConfigs {
        if (hasSigningConfig) {
            create("release") {
                val properties = Properties()
                properties.load(FileInputStream(keystorePropertiesFile))
                
                storeFile = file(properties.getProperty("storeFile")!!)
                storePassword = properties.getProperty("storePassword")
                keyAlias = properties.getProperty("keyAlias")
                keyPassword = properties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (hasSigningConfig) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                // Fallback to debug signing for local development
                signingConfig = signingConfigs.getByName("debug")
            }
            
            // R8 OFF for the Android port: with it on, R8 judged
            // LunaGateway/LunaPrefs — reached only through our Service and
            // MethodChannel wiring, never through Flutter's own code — unused
            // and stripped them, so LunaService.start() called into nothing,
            // the bundled server never came up, and the splash screen waited
            // in vain. The APK's bulk is the 68MB payload zip, which shrinking
            // cannot touch anyway.
            isMinifyEnabled = false
            isShrinkResources = false
        }
        
        debug {
            // Keep debug builds fast
            isMinifyEnabled = false
        }
    }
}

flutter {
    source = "../.."
}

android {
    packaging {
        jniLibs {
            // REQUIRED: libbun.so is not a JNI library but an executable
            // (the Android build of Bun). The shell execs it from the app's
            // native library directory, which only holds the .so files if
            // they were extracted to disk. AGP defaults to
            // extractNativeLibs=false (keep them inside the APK), which left
            // nativeLibraryDir without libbun.so — the server then logged
            // "Bun 二进制缺失" and never started.
            useLegacyPackaging = true
        }
    }
}

android {
    // Self-use build: debuggable stays on so `run-as` can read the bundled
    // server's log, and release lint gates are off — SetDebuggable is fatal.
    lint {
        checkReleaseBuilds = false
        abortOnError = false
    }
}
