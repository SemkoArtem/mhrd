package ua.mhrd.mhrd

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Канал «mhrd/android»: теки застосунку. Модуль сеансу (libmhrd_session.so) Android дозволяє
        // запускати лише з теки бібліотек застосунку; HOME і TMPDIR для нього — власні теки MHRD.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mhrd/android").setMethodCallHandler { call, result ->
            when (call.method) {
                "paths" -> result.success(
                    mapOf(
                        "nativeLibraryDir" to applicationInfo.nativeLibraryDir,
                        "filesDir" to filesDir.absolutePath,
                        "cacheDir" to cacheDir.absolutePath,
                    )
                )
                else -> result.notImplemented()
            }
        }
    }
}
