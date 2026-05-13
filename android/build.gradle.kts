plugins {
    id("com.android.application") version "8.9.1" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
}

subprojects {
    afterEvaluate {
        if (hasProperty("android")) {
            val android = extensions.getByName<com.android.build.gradle.BaseExtension>("android")
            android.compileSdkVersion(36)
        }
    }
}