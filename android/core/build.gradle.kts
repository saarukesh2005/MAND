// Platform-independent M’AND protocol logic. Mirrors mac/Sources/MandCore and is tested
// against the same shared vectors in protocol/vectors.
plugins {
    alias(libs.plugins.kotlin.jvm)
}

// Target Java 17 bytecode with whatever JDK runs Gradle (Android Studio bundles JDK 21),
// so no separate JDK 17 download is needed and :app (Java 17) can consume this module.
java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation(libs.kotlinx.serialization.json)
    testImplementation(kotlin("test"))
    testImplementation(platform(libs.junit.bom))
    testImplementation(libs.junit.jupiter)
    testRuntimeOnly(libs.junit.platform.launcher)
}

tasks.test {
    useJUnitPlatform()
    val vectors = rootProject.file("../protocol/vectors/protocol-v1.json")
    inputs.file(vectors) // re-run whenever the shared vectors change
    systemProperty("mand.vectors", vectors.absolutePath)
}
