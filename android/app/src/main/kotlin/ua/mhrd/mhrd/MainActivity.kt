package ua.mhrd.mhrd

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val SAVE_REQUEST = 10
        private const val OPEN_REQUEST = 11
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
                "openFiles" -> {
                    // Вибір файлів системним вікном. SHOW_ADVANCED — одразу з пам'яттю телефона: без нього
                    // старі Android (7) показують у «Завантаженнях» лише завантажене браузером, а решту
                    // ховають, поки в меню ⋮ не ввімкнути «Показати внутрішню пам'ять».
                    if (pendingOpen != null) {
                        result.success(null)
                    } else {
                        pendingOpen = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
                            .addCategory(Intent.CATEGORY_OPENABLE)
                            .setType(call.argument<String>("mime") ?: "*/*")
                            .putExtra(Intent.EXTRA_ALLOW_MULTIPLE, call.argument<Boolean>("multiple") ?: false)
                            .putExtra("android.content.extra.SHOW_ADVANCED", true)
                            .putExtra("android.content.extra.FANCY", true)
                        startActivityForResult(intent, OPEN_REQUEST)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private var pendingSave: MethodChannel.Result? = null
    private var pendingBytes: ByteArray? = null
    private var pendingOpen: MethodChannel.Result? = null

    /** Вибрані файли → [{name, bytes}] (до 64 МБ кожен — бекап, конфіг, .rdp, картинка). */
    private fun readPicked(data: Intent?): List<Map<String, Any>> {
        val uris = mutableListOf<Uri>()
        data?.clipData?.let { clip -> for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri) }
        if (uris.isEmpty()) data?.data?.let { uris.add(it) }
        return uris.mapNotNull { uri ->
            var name = uri.lastPathSegment ?: "file"
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst() && !c.isNull(0)) name = c.getString(0)
            }
            val bytes = contentResolver.openInputStream(uri)?.use { input ->
                val out = java.io.ByteArrayOutputStream()
                val buf = ByteArray(64 * 1024)
                while (true) {
                    val n = input.read(buf)
                    if (n < 0) break
                    if (out.size() + n > 64 * 1024 * 1024) return@mapNotNull null
                    out.write(buf, 0, n)
                }
                out.toByteArray()
            } ?: return@mapNotNull null
            mapOf("name" to name, "bytes" to bytes)
        }
    }

    @Deprecated("startActivityForResult — найпростіше, що працює з Android 7")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == OPEN_REQUEST) {
            val result = pendingOpen ?: return
            pendingOpen = null
            if (resultCode != RESULT_OK) {
                result.success(emptyList<Any>()) // скасовано
                return
            }
            try {
                result.success(readPicked(data))
            } catch (e: Exception) {
                result.error("read", e.message, null)
            }
            return
        }
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
