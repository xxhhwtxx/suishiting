allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    // JNI is plain C and supports the installed r27 toolchain. Enable both
    // Android-recommended flags for 16 KB LOAD and RELRO segment alignment.
    // https://developer.android.com/guide/practices/page-sizes
    afterEvaluate {
        extensions.findByType<com.android.build.gradle.LibraryExtension>()?.apply {
            // Some plugins conditionally set this using Groovy hasProperty,
            // which misses the namespace property on this AGP/Flutter pairing.
            if (namespace.isNullOrBlank()) namespace = project.group.toString()
            if (project.name == "jni") {
                ndkVersion = "27.0.12077973"
                defaultConfig.externalNativeBuild.cmake.arguments.add(
                    "-DCMAKE_SHARED_LINKER_FLAGS=-Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384"
                )
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
