// Interop test: the Kotlin protocol core + Java's TLS (the same JSSE stack Android uses) against the
// real Swift BridgeServer. Runs only from scripts/interop-test.sh, which starts the Swift server.
plugins {
    alias(libs.plugins.kotlin.jvm)
}

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
    testImplementation(project(":core"))
    testImplementation(kotlin("test"))
    testImplementation(platform(libs.junit.bom))
    testImplementation(libs.junit.jupiter)
    testRuntimeOnly(libs.junit.platform.launcher)
}

tasks.test {
    useJUnitPlatform()
    onlyIf { System.getenv("MAND_INVITE") != null }
    listOf("MAND_INVITE", "MAND_PHONE_P12", "MAND_OTHER_P12").forEach { key ->
        System.getenv(key)?.let { environment(key, it) }
    }
    outputs.upToDateWhen { false }
    testLogging { events("passed", "failed"); showStandardStreams = true }
}
