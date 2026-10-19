plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.kotlin.compose) apply false
}

// Gradle's test runner can't load classes from a path containing an apostrophe, and this project
// lives in a folder named "M'AND". When that's the case, put build output under ~/.mand-build instead.
if ('\'' in rootDir.absolutePath) {
    allprojects {
        layout.buildDirectory.set(file("${System.getProperty("user.home")}/.mand-build/${path.replace(':', '_').ifEmpty { "root" }}"))
    }
}
