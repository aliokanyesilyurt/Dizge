import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Yayın imzası `android/key.properties`ten okunuyor. Dosya **git'te değil**:
// içinde anahtar deposunun parolası var ve o parola sızarsa herkes senin
// adına güncelleme yayımlayabilir.
//
// Dosya yoksa derleme durmuyor, hata ayıklama anahtarına düşüyor (aşağıdaki
// `release` bloğu) — ama sesli bir uyarıyla. Sessizce düşseydi, mağazaya
// gitmeyen ama "yayın" diye dağıtılan bir APK üretilirdi.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasReleaseKey = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "com.aliokan.dizge"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Kurulduktan sonra **değiştirilemez**: paket kimliği cihazda
        // uygulamanın kim olduğu. Değiştirmek yeni bir uygulama demek —
        // eskisi güncellenmez, yan yana kurulur.
        applicationId = "com.aliokan.dizge"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                // Hata ayıklama anahtarıyla imzalanan APK **kurulur ve
                // çalışır**, ama güncellenemez: gerçek anahtarla imzalanmış
                // bir sürüm sonradan gelince Android onu "başka bir
                // uygulama" sayar ve kullanıcı eskisini silmek zorunda kalır.
                logger.warn(
                    "\n  UYARI · Yayın APK'sı hata ayıklama anahtarıyla imzalanıyor." +
                    "\n  Gerçek anahtar için: android/key.properties " +
                    "(bkz. android/key.properties.example)\n"
                )
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
