import com.android.build.gradle.LibraryExtension
import com.google.protobuf.gradle.*
import io.gitlab.arturbosch.detekt.extensions.DetektExtension
import org.gradle.api.file.SourceDirectorySet
import org.gradle.api.plugins.ExtensionAware
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

buildscript {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://plugins.gradle.org/m2/") }
    }
    dependencies {
        classpath("com.android.tools.build:gradle:8.0.2")
        classpath("com.google.protobuf:protobuf-gradle-plugin:0.9.4")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:2.3.10")
        classpath("io.gitlab.arturbosch.detekt:detekt-gradle-plugin:1.23.0")
        classpath("de.mannodermaus.gradle.plugins:android-junit5:1.7.1.1")
    }
}

apply(plugin = "com.android.library")
apply(plugin = "com.google.protobuf")
apply(plugin = "org.jetbrains.kotlin.android")
apply(plugin = "io.gitlab.arturbosch.detekt")
apply(plugin = "de.mannodermaus.android-junit5")

group = "com.signify.hue.flutterreactiveblelib"
version = "1.0-SNAPSHOT"

val detektVersion = "1.23.0"
val kotlinVersion = "2.3.10"

allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://plugins.gradle.org/m2/") }
    }
}

configure<LibraryExtension> {
    namespace = "com.signify.hue.flutterreactiveble"
    compileSdk = 36

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
        getByName("test") {
            java.srcDirs("src/test/kotlin")
        }
    }

    defaultConfig {
        minSdk = 24
        consumerProguardFiles("proguard-rules.txt")
    }

    lint {
        disable += "InvalidPackage"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

tasks.withType<KotlinCompile>().configureEach {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

configure<DetektExtension> {
    toolVersion = detektVersion
    source.setFrom("src/main/kotlin")
}

configure<ProtobufExtension> {
    protoc {
        artifact = "com.google.protobuf:protoc:3.25.3"
    }
    generateProtoTasks {
        all().forEach { task ->
            task.builtins {
                create("java") {
                    option("lite")
                }
            }
        }
    }
}

afterEvaluate {
    val main = extensions
        .getByType(LibraryExtension::class.java)
        .sourceSets
        .getByName("main")

    val proto = (main as ExtensionAware)
        .extensions
        .getByName("proto") as SourceDirectorySet

    proto.srcDir("../protos/")
}

dependencies {
    add("implementation", "org.jetbrains.kotlin:kotlin-stdlib:$kotlinVersion")

    add("implementation", "com.polidea.rxandroidble2:rxandroidble:1.19.1")
    add("implementation", "io.reactivex.rxjava2:rxandroid:2.1.1")
    add("implementation", "io.reactivex.rxjava2:rxkotlin:2.4.0")

    add("implementation", "com.google.protobuf:protobuf-javalite:3.25.3")

    add("testImplementation", "org.junit.jupiter:junit-jupiter-api:5.7.0")
    add("testRuntimeOnly", "org.junit.jupiter:junit-jupiter-engine:5.7.0")
    add("testImplementation", "io.mockk:mockk:1.11.0")
    add("testImplementation", "com.google.truth:truth:1.1.4")

    add("detektPlugins", "io.gitlab.arturbosch.detekt:detekt-formatting:$detektVersion")
    add("detektPlugins", "io.gitlab.arturbosch.detekt:detekt-rules-libraries:$detektVersion")
}
