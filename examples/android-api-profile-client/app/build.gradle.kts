plugins {
    id("com.android.application")
}

android {
    namespace = "com.apilot.exampleclient"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.apilot.exampleclient"
        minSdk = 24
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }
}

dependencies {
    implementation("androidx.activity:activity-ktx:1.10.1")
    implementation("androidx.core:core-ktx:1.15.0")
}
