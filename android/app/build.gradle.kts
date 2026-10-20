plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "dev.mand.android"
    compileSdk = 37

    defaultConfig {
        applicationId = "dev.mand.android"
        // The founder's phone runs Android 14+; targeting 36 (Android 16) avoids Android 17's new
        // ACCESS_LOCAL_NETWORK runtime permission until onboarding for it is built (see docs/DECISIONS.md).
        minSdk = 34
        targetSdk = 37
        versionCode = 3
        versionName = "0.3.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            // Personal distribution: signed with this Mac's local Android key (the same one the earlier
            // builds used), so it installs over the existing app and keeps the pairing. A dedicated
            // store key is needed before publishing — see docs/RELEASE_CHECKLIST.md.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
    }
}

dependencies {
    implementation(project(":core"))
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.material.icons)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.service)
    implementation(libs.androidx.datastore.preferences)
    implementation(libs.zxing.android.embedded)
}
