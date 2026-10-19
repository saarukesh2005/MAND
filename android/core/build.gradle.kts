// Platform-independent M’AND protocol logic. Mirrors mac/Sources/MandCore and is tested
// against the same shared vectors in protocol/vectors.
plugins {
    alias(libs.plugins.kotlin.jvm)
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    implementation(libs.kotlinx.serialization.json)
    testImplementation(kotlin("test-junit"))
}

tasks.test {
    systemProperty("mand.vectors", rootProject.file("../protocol/vectors/protocol-v1.json").absolutePath)
}
