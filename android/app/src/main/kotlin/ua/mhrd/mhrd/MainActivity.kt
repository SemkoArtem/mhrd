package ua.mhrd.mhrd

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val SAVE_REQUEST = 10
    }

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
                "saveFile" -> {
                    // «Зберегти як» системним вікном Android (Завантаження, Google Drive…): бекап, експорт.
                    val name = call.argument<String>("name") ?: "mhrd"
                    val bytes = call.argument<ByteArray>("bytes")
                    if (bytes == null || pendingSave != null) {
                        result.success(null)
                    } else {
                        pendingSave = result
                        pendingBytes = bytes
                        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT)
                            .addCategory(Intent.CATEGORY_OPENABLE)
                            .setType("application/octet-stream")
                            .putExtra(Intent.EXTRA_TITLE, name)
                        startActivityForResult(intent, SAVE_REQUEST)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private var pendingSave: MethodChannel.Result? = null
    private var pendingBytes: ByteArray? = null

    @Deprecated("startActivityForResult — найпростіше, що працює з Android 7")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != SAVE_REQUEST) return
        val result = pendingSave ?: return
        val bytes = pendingBytes
        pendingSave = null
        pendingBytes = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null || bytes == null) {
            result.success(null) // скасовано
            return
        }
        try {
            contentResolver.openOutputStream(uri, "wt")?.use { it.write(bytes) }
            result.success(uri.lastPathSegment ?: uri.toString())
        } catch (e: Exception) {
            result.error("write", e.message, null)
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
