allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = "17"
        targetCompatibility = "17"
    }
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}

// Guava / Firebase expose Checker Framework annotations (e.g.
// @UnknownInitialization) on inferred types, but declare checker-qual as
// `compileOnly` so it never reaches a consumer's compile classpath. Kotlin 2.x
// rejects an inferred type carrying an inaccessible annotation class, which
// breaks :firebase_auth:compileDebugKotlin. Putting checker-qual on every
// Android subproject's compile classpath makes those annotations resolvable.
// Compile-time only — nothing is added to the shipped APK.
subprojects {
    plugins.withId("com.android.library") {
        dependencies.add("compileOnly", "org.checkerframework:checker-qual:3.51.1")
    }
    plugins.withId("com.android.application") {
        dependencies.add("compileOnly", "org.checkerframework:checker-qual:3.51.1")
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
