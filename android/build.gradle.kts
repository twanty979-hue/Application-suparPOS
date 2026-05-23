// android/build.gradle.kts (ไฟล์นอกสุด)

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir = File(rootProject.projectDir, "../build")
rootProject.layout.buildDirectory.set(newBuildDir)

subprojects {
    project.layout.buildDirectory.set(File(newBuildDir, project.name))
}

// ✅ ตัวแก้เรื่อง Namespace สำหรับ Plugin เก่า (เวอร์ชัน Kotlin DSL ที่ไม่พ่น Error)
subprojects {
    // ใช้สถาปัตยกรรมแบบดักจับทุก Plugin ที่โหลดขึ้นมา
    afterEvaluate {
        if (hasProperty("android")) {
            val android = extensions.getByName("android") as com.android.build.gradle.BaseExtension
            if (android.namespace == null) {
                // ฉีดชื่อ namespace เข้าไปให้ Plugin ที่ไม่มีชื่อครับนาย
                android.namespace = "com.foodscan.${project.name.replace("-", ".")}"
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}