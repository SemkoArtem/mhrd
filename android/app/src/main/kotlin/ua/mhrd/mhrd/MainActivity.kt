package ua.mhrd.mhrd

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var askedNotifications = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Канал «mhrd/android»: теки застосунку (модуль сеансу libmhrd_session.so Android дозволяє
        // запускати лише з теки бібліотек застосунку; HOME і TMPDIR для нього — власні теки MHRD)
        // і служба переднього плану, поки є активні сеанси (SessionService).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mhrd/android").setMethodCallHandler { call, result ->
            when (call.method) {
                "paths" -> result.success(
                    mapOf(
                        "nativeLibraryDir" to applicationInfo.nativeLibraryDir,
                        "filesDir" to filesDir.absolutePath,
                        "cacheDir" to cacheDir.absolutePath,
                    )
                )
                "sessions" -> {
                    val count = call.argument<Int>("count") ?: 0
                    if (count > 0) askNotifications()
                    SessionService.update(this, count, call.argument<String>("text") ?: "MHRD")
                    result.success(null)
                }
                "microphone" -> {
                    // Мікрофон на віддаленому ПК: дозвіл даний застосунку діє й для процесу сеансу.
                    if (Build.VERSION.SDK_INT >= 23 &&
                        checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED
                    ) {
                        requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 2)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Android 13+: без дозволу сповіщення служби не видно (сама служба працює й так). Питаємо раз. */
    private fun askNotifications() {
        if (Build.VERSION.SDK_INT < 33 || askedNotifications) return
        askedNotifications = true
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }
    }
}
