plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

// Se leen de gradle.properties para no incrustar literales en el código y para
// que un build de CI pueda sobreescribirlas con -P.
fun prop(name: String): String = (project.findProperty(name) as String?).orEmpty()

android {
    namespace = "mx.portgo.app"
    compileSdk = 35

    defaultConfig {
        applicationId = "mx.portgo.app"
        // 24 = Android 7.0.
        //
        // Se eligió por el usuario real, no por comodidad de desarrollo: PortGo
        // se usa en patio y en puerto, y en ese entorno abundan los teléfonos
        // baratos y viejos. Dejar fuera Android 7 excluiría justamente a los
        // operadores, que son quienes más usan el seguimiento y las evidencias.
        //
        // El costo es `java.time`, que no existe antes de API 26: se resuelve
        // con desugaring (ver isCoreLibraryDesugaringEnabled más abajo).
        // EncryptedSharedPreferences y BiometricPrompt funcionan desde API 23.
        minSdk = 24
        targetSdk = 35
        versionCode = 1
        versionName = "1.0.0"

        buildConfigField("String", "SUPABASE_URL", "\"${prop("PORTGO_SUPABASE_URL")}\"")
        buildConfigField("String", "SUPABASE_ANON_KEY", "\"${prop("PORTGO_SUPABASE_ANON_KEY")}\"")
        buildConfigField("String", "WEB_URL", "\"${prop("PORTGO_WEB_URL")}\"")

        // Esquema del deep link de recuperación de contraseña. Tiene que estar
        // dado de alta en Supabase → Authentication → URL Configuration
        // (Redirect URLs) o el enlace del correo no regresa a la app.
        manifestPlaceholders["authScheme"] = "portgo"
        manifestPlaceholders["authHost"] = "auth"
    }

    signingConfigs {
        getByName("debug") {
            // AGP omite la firma v1 cuando minSdk >= 24, porque a partir de
            // ahí Android usa v2. Pero varios emuladores de terceros
            // (BlueStacks, LDPlayer, MEmu) traen instaladores no estándar que
            // siguen exigiendo v1 y rechazan el APK con un genérico
            // "revisa la aplicación". Firmar con las tres no cuesta nada y
            // hace que el APK de depuración se instale en cualquier parte.
            enableV1Signing = true
            enableV2Signing = true
            enableV3Signing = true
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("debug")
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Hace que java.time (Instant, LocalDate, ZoneId…) funcione en API 24 y
        // 25, donde no existe en la plataforma. Sin esto, la app compila pero
        // revienta al primer formateo de fecha en un Android 7.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    packaging {
        resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
    }
}

dependencies {
    coreLibraryDesugaring(libs.desugar.jdk.libs)

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.activity.compose)

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.material.icons.extended)
    implementation(libs.androidx.navigation.compose)
    debugImplementation(libs.androidx.compose.ui.tooling)

    implementation(libs.androidx.security.crypto)
    implementation(libs.androidx.biometric)
    implementation(libs.coil.compose)

    implementation(platform(libs.supabase.bom))
    implementation(libs.supabase.postgrest)
    implementation(libs.supabase.auth)
    implementation(libs.supabase.realtime)
    implementation(libs.supabase.storage)
    implementation(libs.supabase.functions)
    implementation(libs.ktor.client.okhttp)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.kotlinx.datetime)
}
