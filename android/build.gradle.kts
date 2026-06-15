allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Force all subproject plugins (incl. transitive Flutter plugins still applying
// their own KGP) to JVM 11, so Java/Kotlin targets stay consistent under AGP 9.
// Configure the compile TASKS directly (lazily) rather than the Android/Kotlin
// extensions: task config wins regardless of plugin evaluation order, which
// avoids the afterEvaluate race where a plugin resets Java back to 1.8.
subprojects {
    // Task-level Java forcing alone doesn't stick under AGP 9 (AGP re-derives the
    // task's compatibility from the android extension's compileOptions), so also
    // override the extension itself after the plugin's own build script has run.
    // withGroovyBuilder avoids compile-time AGP class references (BaseExtension
    // was removed in AGP 9).
    fun forceJava11(p: Project) {
        p.extensions.findByName("android")?.withGroovyBuilder {
            getProperty("compileOptions").withGroovyBuilder {
                setProperty("sourceCompatibility", JavaVersion.VERSION_11)
                setProperty("targetCompatibility", JavaVersion.VERSION_11)
            }
        }
    }
    // Skip already-evaluated projects (just :app, which sets its own targets).
    if (!state.executed) afterEvaluate { forceJava11(this) }
    tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = JavaVersion.VERSION_11.toString()
        targetCompatibility = JavaVersion.VERSION_11.toString()
    }
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
