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

// Yayın APK'sına hangi işlemci mimarilerinin gireceği.
//
// Flutter'ın `--target-platform` bayrağı yalnız **kendi** kitaplıklarını
// kırpıyor (`libflutter.so`, `libapp.so`); eklentilerden gelen yerel
// kitaplıklar üç ABI için de paketlenmeye devam ediyor. Ölçüm: arm64
// istenen APK 43,9 MiB çıktı ve bunun 12,7'si ML Kit'in hiç
// çalıştırılmayacak `libdigitalink.so` kopyalarıydı.
//
// Süzgeç bu yüzden burada, gradle tarafında — ve **yalnız `release`**:
// hata ayıklama derlemesi x86_64 emülatörde açılabilmeli.
val abiOfPlatform = mapOf(
    "android-arm" to "armeabi-v7a",
    "android-arm64" to "arm64-v8a",
    "android-x64" to "x86_64",
)
val requestedPlatforms = (project.findProperty("target-platform") as String?)
    ?.split(",")
    ?.map { it.trim() }
    ?.filter { it.isNotEmpty() }
    .orEmpty()

// Tanınmayan bir platform gelirse süzgeç **hiç** kurulmuyor. Yanlış tarafa
// düşmenin bedeli asimetrik: eksik süzgeç yalnız büyük bir APK üretir,
// fazla süzgeç ise Flutter'ın kitaplığını koyup eklentininkini atarak
// açılışta çöken bir APK üretir.
val releaseAbis =
    if (requestedPlatforms.isNotEmpty() && requestedPlatforms.all { abiOfPlatform.containsKey(it) }) {
        requestedPlatforms.map { abiOfPlatform.getValue(it) }
    } else {
        if (requestedPlatforms.isNotEmpty()) {
            logger.warn(
                "  UYARI · Tanınmayan target-platform ($requestedPlatforms): " +
                    "ABI süzgeci uygulanmadı, APK tüm mimarileri taşıyacak."
            )
        }
        emptyList()
    }

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
            if (releaseAbis.isNotEmpty()) {
                ndk {
                    abiFilters.clear()
                    abiFilters.addAll(releaseAbis)
                }
            }

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
