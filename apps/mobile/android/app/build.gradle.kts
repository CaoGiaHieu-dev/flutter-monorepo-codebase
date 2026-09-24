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

// Signing material, one properties file per flavor, read from android/.
//
// dev    -> key-dev.properties (committed, public: see keystore-dev.jks)
// staging-> key-stg.properties (gitignored, you supply it)
// prod   -> key.properties     (gitignored, you supply it)
//
// When a staging/prod file is missing, the flavor's signing config falls back
// to the dev key so that debug/profile builds of every flavor keep working
// from a fresh clone. A *release* build of staging/prod never does: the guard
// at the bottom of this file fails it before anything is packaged or signed,
// because the dev key is public and a store listing's signature can never
// change.
// See docs/en/operations/02_fastlane_release.md section 4.
fun loadProperties(file: File): Properties {
    val properties = Properties()
    if (file.exists()) {
        FileInputStream(file).use { fis -> properties.load(fis) }
    }
    return properties
}

val keystoreDevPropertiesFile: File = rootProject.file("key-dev.properties")
val keystoreDevProperties = loadProperties(keystoreDevPropertiesFile)

val keystoreStagingPropertiesFile: File = rootProject.file("key-stg.properties")
val keystoreStagingProperties = loadProperties(keystoreStagingPropertiesFile)
    .takeIf { keystoreStagingPropertiesFile.exists() } ?: keystoreDevProperties

val keystorePropertiesFile: File = rootProject.file("key.properties")
val keystoreProperties = loadProperties(keystorePropertiesFile)
    .takeIf { keystorePropertiesFile.exists() } ?: keystoreDevProperties

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
    // Pinned above Flutter 3.47's default (36). AGP requires the app's
    // compileSdk to be at least as high as any plugin's; this was raised for a
    // plugin compiled against API 37. Lower it only after a clean
    // `flutter build apk` confirms no remaining plugin needs 37.
    compileSdk = 37
    // API 37 is only published as a minor-versioned platform (android-37.0,
    // android-37.1, ...); AGP 9 needs compileSdkMinor to resolve it.
    compileSdkMinor = 0
    ndkVersion = "28.2.13676358"

    buildFeatures {
        // AGP 9 turns resValues off by default; defaultConfig below declares
        // resValue entries for the web-domain/app-name/app-id strings.
        resValues = true
    }

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

        // Host of the verified App Links intent-filter in AndroidManifest.xml.
        // An empty host would turn that filter into "every https link", so an
        // env file without WEB_DOMAIN gets a reserved, never-resolving domain
        // (RFC 2606 `.invalid`) instead. See docs/en/guides/04_routing.md §9.
        resValue(
            "string",
            "WEB_DOMAIN",
            envs["WEB_DOMAIN"]?.takeIf { it.isNotBlank() } ?: "example.invalid",
        )
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
            // Drops resources nothing references. Anything looked up only by
            // name at runtime (e.g. a notification icon passed from Dart)
            // must be listed in src/main/res/raw/keep.xml.
            isShrinkResources = true
            // Every flavor's release build gets the same R8 rules — staging
            // included, so it tests what prod ships.
            proguardFiles(
                // AGP 9 dropped support for "proguard-android.txt" because it
                // carries `-dontoptimize` and blocks most R8 optimizations.
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            // No signingConfig here: each flavor sets its own, and the guard
            // at the bottom of this file refuses a staging/prod release that
            // would be signed with the public dev key.
        }
    }

    // AGP 9 removed the `flavorDimensions(...)` method form.
    flavorDimensions += "environment"

    productFlavors {
        // DEEP_LINK_SCHEME is the custom URL scheme of the deep-link
        // intent-filter in AndroidManifest.xml (`<scheme>://settings?tab=2`).
        // One per flavor, so dev/staging/prod installed side by side never
        // compete for a link. Rename them with the app, and keep each equal
        // to DEEP_LINK_SCHEME in the iOS build settings of the same flavor.
        create("dev") {
            dimension = "environment"
            applicationIdSuffix = ".dev"
            signingConfig = signingConfigs.getByName("dev")
            resValue("string", "DEEP_LINK_SCHEME", "codebase-dev")
            // Optionally set version name suffix
            // versionNameSuffix = "-dev"
        }
        create("staging") {
            dimension = "environment"
            applicationIdSuffix = ".stg"
            signingConfig = signingConfigs.getByName("staging")
            resValue("string", "DEEP_LINK_SCHEME", "codebase-stg")
            // Optionally set version name suffix
            // versionNameSuffix = "-stg"
        }
        create("prod") {
            dimension = "environment"
            // No suffix for prod
            signingConfig = signingConfigs.getByName("prod")
            resValue("string", "DEEP_LINK_SCHEME", "codebase")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

// Release-signing guard: a staging/prod *release* build must be signed with
// its own key, never the committed (public) dev keystore. The check hangs off
// `pre<Flavor>ReleaseBuild`, which every release entry point runs first
// (`flutter build apk|appbundle`, `assemble*`, `bundle*`), so debug and
// profile builds of every flavor, and IDE sync, are unaffected.
//
// Escape hatch for staging only, for pipelines that deliberately distribute
// staging to testers with the dev key: pass the Gradle property
// `allowDevKeystoreForStaging=true`, e.g.
//   flutter build apk --flavor staging -PallowDevKeystoreForStaging=true
//   ORG_GRADLE_PROJECT_allowDevKeystoreForStaging=true flutter build apk --flavor staging
// There is none for prod.
val allowDevKeystoreForStaging =
    (findProperty("allowDevKeystoreForStaging") as String?)?.toBoolean() == true
val releaseKeyFiles = buildMap {
    if (!keystoreStagingPropertiesFile.exists() && !allowDevKeystoreForStaging) {
        put("Staging", keystoreStagingPropertiesFile)
    }
    if (!keystorePropertiesFile.exists()) {
        put("Prod", keystorePropertiesFile)
    }
}
releaseKeyFiles.forEach { (flavor, file) ->
    val message = """
        |Refusing to build the ${flavor.lowercase()} release: ${file.path} is missing.
        |Without it this build would be signed with the committed, public dev keystore
        |(keystore-dev.jks), and a Play listing's signing key can never change afterwards.
        |Create ${file.name} pointing at your release keystore - see
        |docs/en/operations/02_fastlane_release.md section 4 ("Signing").
        """.trimMargin()
    tasks.matching { it.name == "pre${flavor}ReleaseBuild" }.configureEach {
        doFirst { throw GradleException(message) }
    }
}
