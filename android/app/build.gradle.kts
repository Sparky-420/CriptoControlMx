import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "mx.criptocontrolmx.app"
    compileSdk = 35
    // Pin a stable NDK version instead of using flutter.ndkVersion. This avoids builds
    // failing when a locally cached Flutter-selected NDK folder is malformed/corrupt.
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "mx.criptocontrolmx.app"
        minSdk = flutter.minSdkVersion
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val storeFilePath = keystoreProperties["storeFile"]?.toString().orEmpty()
            if (storeFilePath.isNotBlank()) {
                storeFile = file(storeFilePath)
            }
            storePassword = keystoreProperties["storePassword"]?.toString().orEmpty()
            keyAlias = keystoreProperties["keyAlias"]?.toString().orEmpty()
            keyPassword = keystoreProperties["keyPassword"]?.toString().orEmpty()
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}


dependencies {
    implementation("androidx.work:work-runtime-ktx:2.9.1")
}
