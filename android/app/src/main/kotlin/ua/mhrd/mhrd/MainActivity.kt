package ua.mhrd.mhrd

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity, а не FlutterActivity: інакше вхід відбитком (local_auth) не працює.
class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val SAVE_REQUEST = 10
        private const val OPEN_REQUEST = 11
        private const val IMPORT_REQUEST = 12
    }

    // «Поділитися → MHRD» з іншої програми: файли — у теку обміну (на ПК — диск «Phone»).
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) acceptShared(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        acceptShared(intent)
    }

    private fun acceptShared(intent: Intent?) {
        val uris = Transfer.sharedUris(intent)
        if (uris.isEmpty()) return
        Thread {
            val n = Transfer.importUris(applicationContext, uris)
            runOnUiThread {
                val text = if (n > 0) getString(R.string.transfer_added, n) else getString(R.string.transfer_failed)
                android.widget.Toast.makeText(this, text, android.widget.Toast.LENGTH_LONG).show()
            }
        }.start()
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
                        "transferDir" to Transfer.dir(this).absolutePath,
                    )
                )
                "transferOpen", "transferShare" -> {
                    // Файл із теки обміну — у програму телефона (переглянути / надіслати далі).
                    val file = call.argument<String>("path")?.let { Transfer.resolve(this, it) }
                    if (file == null) {
                        result.success(false)
                    } else {
                        val uri = Transfer.uriFor(this, file)
                        val intent = if (call.method == "transferOpen") {
                            Intent(Intent.ACTION_VIEW).setDataAndType(uri, Transfer.mimeOf(file))
                        } else {
                            Intent.createChooser(
                                Intent(Intent.ACTION_SEND).setType(Transfer.mimeOf(file)).putExtra(Intent.EXTRA_STREAM, uri)
                                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
                                file.name,
                            )
                        }
                        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        try {
                            startActivity(intent)
                            result.success(true)
                        } catch (_: Exception) {
                            result.success(false) // немає програми для такого файлу
                        }
                    }
                }
                "transferSave" -> {
                    // «Зберегти як» для файлу з теки обміну — потоком, без завантаження в пам'ять.
                    val file = call.argument<String>("path")?.let { Transfer.resolve(this, it) }
                    if (file == null || pendingSave != null) {
                        result.success(null)
                    } else {
                        pendingSave = result
                        pendingFile = file
                        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT)
                            .addCategory(Intent.CATEGORY_OPENABLE)
                            .setType(Transfer.mimeOf(file))
                            .putExtra(Intent.EXTRA_TITLE, file.name)
                        startActivityForResult(intent, SAVE_REQUEST)
                    }
                }
                "transferImport" -> {
                    // Додати файли в теку обміну з пам'яті телефона.
                    if (pendingImport != null) {
                        result.success(0)
                    } else {
                        pendingImport = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
                            .addCategory(Intent.CATEGORY_OPENABLE)
                            .setType("*/*")
                            .putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                            .putExtra("android.content.extra.SHOW_ADVANCED", true)
                            .putExtra("android.content.extra.FANCY", true)
                        startActivityForResult(intent, IMPORT_REQUEST)
                    }
                }
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
                "keepScreenOn" -> {
                    // «Не вимикати екран», поки відкритий сеанс.
                    if (call.arguments == true) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(null)
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
    private var pendingFile: java.io.File? = null // «Зберегти як» для файлу з теки обміну
    private var pendingOpen: MethodChannel.Result? = null
    private var pendingImport: MethodChannel.Result? = null

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
        if (requestCode == IMPORT_REQUEST) {
            val result = pendingImport ?: return
            pendingImport = null
            val uris = mutableListOf<Uri>()
            if (resultCode == RESULT_OK) {
                data?.clipData?.let { clip -> for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri) }
                if (uris.isEmpty()) data?.data?.let { uris.add(it) }
            }
            if (uris.isEmpty()) {
                result.success(0)
                return
            }
            // Копіювання може бути довгим (відео) — не в головному потоці.
            Thread {
                val n = Transfer.importUris(applicationContext, uris)
                runOnUiThread { result.success(n) }
            }.start()
            return
        }
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
        val file = pendingFile
        pendingSave = null
        pendingBytes = null
        pendingFile = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null || (bytes == null && file == null)) {
            result.success(null) // скасовано
            return
        }
        if (file != null) {
            Thread {
                try {
                    contentResolver.openOutputStream(uri, "wt")?.use { out ->
                        file.inputStream().use { it.copyTo(out, 256 * 1024) }
                    }
                    runOnUiThread { result.success(uri.lastPathSegment ?: uri.toString()) }
                } catch (e: Exception) {
                    runOnUiThread { result.error("write", e.message, null) }
                }
            }.start()
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
