import java.util.Properties
import java.io.FileInputStream
import java.util.Base64
import org.gradle.api.JavaVersion
import java.io.File 

// Extension function to decode Base64 strings
fun String.decodeBase64(): ByteArray = Base64.getDecoder().decode(this)

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("dev.flutter.flutter-gradle-plugin")
}

//keystore dev properties
val keystoreDevProperties = Properties()
val keystoreDevPropertiesFile: File = rootProject.file("key-dev.properties") // Explicitly typed as File
if (keystoreDevPropertiesFile.exists()) {
    FileInputStream(keystoreDevPropertiesFile).use { fis -> // Use try-with-resources
        keystoreDevProperties.load(fis)
    }
}

//keystore staging properties
val keystoreStagingProperties = Properties()
val keystoreStagingPropertiesFile: File = rootProject.file("key-stg.properties") // Explicitly typed as File
if (keystoreStagingPropertiesFile.exists()) {
     FileInputStream(keystoreStagingPropertiesFile).use { fis -> // Use try-with-resources
        keystoreStagingProperties.load(fis)
    }
} else {
    keystoreStagingProperties.putAll(keystoreDevProperties)
}

//keystore properties
val keystoreProperties = Properties()
val keystorePropertiesFile: File = rootProject.file("key.properties") // Explicitly typed as File
if (keystorePropertiesFile.exists()) {
     FileInputStream(keystorePropertiesFile).use { fis -> // Use try-with-resources
        keystoreProperties.load(fis)
    }
} else {
    keystoreProperties.putAll(keystoreDevProperties)
}

// dart-define
var envs: Map<String, String> = mapOf()
if (project.hasProperty("dart-defines")) {
    envs = project.property("dart-defines")
        .toString()
        .split(",")
        .mapNotNull { entry -> // Use mapNotNull to handle potential decoding errors gracefully
            try {
                val decoded = String(entry.decodeBase64(), Charsets.UTF_8)
                val pair = decoded.split("=", limit = 2) // Limit split to 2 parts
                if (pair.size == 2) pair.first() to pair.last() else null
            } catch (e: IllegalArgumentException) {
                // Handle potential Base64 decoding errors if needed
                println("Warning: Could not decode dart-define entry: $entry")
                null
            }
        }
        .toMap()
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}


android {
    namespace = "com.example.codebase"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main").java.srcDirs("src/main/kotlin")
    }

    signingConfigs {
        create("dev") {
            // Use keystoreDevProperties, not keystoreDevPropertiesFile
            storeFile = file(keystoreDevProperties.getProperty("storeFile") ?: "") // Use getProperty and provide default
            storePassword = keystoreDevProperties.getProperty("storePassword") ?: ""
            keyAlias = keystoreDevProperties.getProperty("keyAlias") ?: ""
            keyPassword = keystoreDevProperties.getProperty("keyPassword") ?: ""
        }
        create("staging") {
            // Use keystoreStagingProperties, not keystoreStagingPropertiesFile
            storeFile = file(keystoreStagingProperties.getProperty("storeFile") ?: "")
            storePassword = keystoreStagingProperties.getProperty("storePassword") ?: ""
            keyAlias = keystoreStagingProperties.getProperty("keyAlias") ?: ""
            keyPassword = keystoreStagingProperties.getProperty("keyPassword") ?: ""
        }
        create("prod") {
            // Use keystoreProperties, not keystorePropertiesFile
            storeFile = file(keystoreProperties.getProperty("storeFile") ?: "")
            storePassword = keystoreProperties.getProperty("storePassword") ?: ""
            keyAlias = keystoreProperties.getProperty("keyAlias") ?: ""
            keyPassword = keystoreProperties.getProperty("keyPassword") ?: ""
        }
    }

    defaultConfig {
        applicationId = "com.example.codebase"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true

        resValue("string", "FACEBOOK_APP_ID", envs["FACEBOOK_APP_ID"] ?: "")
        resValue("string", "FACEBOOK_TOKEN", envs["FACEBOOK_TOKEN"] ?: "")
        resValue("string", "APP_SCHEMA", envs["APP_SCHEMA"] ?: "")
        resValue("string", "WEB_DOMAIN", envs["WEB_DOMAIN"] ?: "")
        resValue("string", "app_name", envs["APP_NAME"] ?: "Codebase") 
        resValue("string", "APP_ID", "${applicationId}${applicationIdSuffix ?: ""}") 
    }

    buildTypes {
        getByName("debug") {
            // Debug should ideally not be signed with release keys,
            // but can use the dev key if needed for specific scenarios.
            // Setting signingConfig = null is usually correct for debug.
            signingConfig = null // Or signingConfigs.getByName("dev") if required
        }
        getByName("profile") {
            // Profile builds are often similar to release but with debugging symbols.
            // They might use release keys or dev keys depending on the use case.
            // Setting signingConfig = null is common if not distributing profile builds.
             signingConfig = null // Or signingConfigs.getByName("prod") or signingConfigs.getByName("dev")
             // Consider adding matchingFallbacks = listOf("release") if needed
        }
        getByName("release") {
            isMinifyEnabled = true
            isShrinkResources = false // Keep false unless you test thoroughly
            // Release builds MUST have a signing config for distribution.
            // This will be overridden by the flavor's signingConfig.
            // Setting it here is redundant if flavors always define it.
            // signingConfig = signingConfigs.getByName("prod") // Can be set as a default
        }
    }

    flavorDimensions("environment")

    productFlavors {
        create("dev") {
            dimension = "environment"
            applicationIdSuffix = ".dev"
            signingConfig = signingConfigs.getByName("dev")
            // Optionally set version name suffix
            // versionNameSuffix = "-dev"
        }
        create("staging") {
            dimension = "environment"
            applicationIdSuffix = ".stg"
            signingConfig = signingConfigs.getByName("staging")
            // Optionally set version name suffix
            // versionNameSuffix = "-stg"
        }
        create("prod") {
            dimension = "environment"
            // No suffix for prod
            // applicationIdSuffix = "" // Default is empty
            signingConfig = signingConfigs.getByName("prod")
            proguardFiles(
                // Includes the default ProGuard rules files that are packaged with
                // the Android Gradle plugin. To learn more, go to the section about
                // R8 configuration files.
                getDefaultProguardFile("proguard-android.txt"),

                // Includes a local, custom Proguard rules file
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Consider updating play-services-auth if needed, 16.0.1 is quite old.
    // Check for the latest version compatible with your project.
    // Example: implementation("com.google.android.gms:play-services-auth:20.7.0")
    implementation("com.google.android.gms:play-services-auth:16.0.1")

    // Check for the latest desugar_jdk_libs version
    // Example: coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // Check for latest window manager versions
    // Example: implementation("androidx.window:window:1.2.0")
    // Example: implementation("androidx.window:window-java:1.2.0")
    implementation("androidx.window:window:1.0.0")
    implementation("androidx.window:window-java:1.0.0")

    // Add other dependencies here
    // implementation(kotlin("stdlib-jdk8")) // Already included via kotlin-android plugin usually
}
