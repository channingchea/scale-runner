import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.library")
    id("kotlin-android")
}

rootProject.allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

android {
    namespace = "com.invisiblewrench.flutter_midi_command_example"
    compileSdk = 34 // use flutter.compileSdkVersion  when Flutter 3.27.0 is widely used

    defaultConfig {
        minSdk = 21
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    dependencies {
        testImplementation("org.jetbrains.kotlin:kotlin-test")
        testImplementation("org.mockito:mockito-core:5.0.0")
    }
}

kotlin {
    compilerOptions {
        jvmTarget = JvmTarget.JVM_11
    }
}

tasks.withType<Test> {
    useJUnitPlatform()

    testLogging {
        events("passed", "skipped", "failed", "standardOut", "standardError")
        outputs.upToDateWhen { false }
        showStandardStreams = true
    }
}
