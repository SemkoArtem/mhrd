package ua.mhrd.mhrd

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import java.io.File

/**
 * Тека обміну файлами з ПК: під час сеансу вона — диск «Phone» на віддаленому ПК (канал rdpdr).
 * Сюди потрапляє те, що надіслали в MHRD «Поділитися» чи «Додати файли», і те, що на ПК скопіювали
 * на цей диск. Лише внутрішня пам'ять MHRD; назовні — через FileProvider (відкрити, поділитися).
 */
object Transfer {
    const val AUTHORITY = "ua.mhrd.mhrd.files"

    fun dir(context: Context): File = File(context.filesDir, "transfer").apply { mkdirs() }

    /** Файл усередині теки обміну (шлях від Dart); поза текою — null. */
    fun resolve(context: Context, path: String): File? {
        val root = dir(context).canonicalFile
        val f = File(path).canonicalFile
        return if (f.path.startsWith(root.path + File.separator) && f.isFile) f else null
    }

    fun uriFor(context: Context, file: File): Uri = FileProvider.getUriForFile(context, AUTHORITY, file)

    fun mimeOf(file: File): String =
        MimeTypeMap.getSingleton().getMimeTypeFromExtension(file.extension.lowercase()) ?: "application/octet-stream"

    /** Ім'я від іншої програми → безпечне ім'я файлу: без шляхів, «..» і порожнього. */
    private fun safeName(raw: String?): String {
        val name = (raw ?: "").substringAfterLast('/').substringAfterLast('\\').trim().trimStart('.')
        return name.ifEmpty { "file" }.take(200)
    }

    /** «назва (2).ext», якщо таке ім'я вже є. */
    private fun unique(dir: File, name: String): File {
        var f = File(dir, name)
        if (!f.exists()) return f
        val base = name.substringBeforeLast('.', name)
        val ext = if (name.contains('.')) "." + name.substringAfterLast('.') else ""
        var i = 2
        while (f.exists()) f = File(dir, "$base ($i)$ext").also { i++ }
        return f
    }

    /** Копіює вміст [uris] у теку обміну. Повертає кількість скопійованих файлів. */
    fun importUris(context: Context, uris: List<Uri>): Int {
        val target = dir(context)
        var count = 0
        for (uri in uris) {
            var name: String? = null
            try {
                context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                    if (c.moveToFirst() && !c.isNull(0)) name = c.getString(0)
                }
            } catch (_: Exception) {
                // без назви — візьмемо з адреси
            }
            val out = unique(target, safeName(name ?: uri.lastPathSegment))
            try {
                context.contentResolver.openInputStream(uri)?.use { input ->
                    out.outputStream().use { input.copyTo(it, 256 * 1024) }
                    count++
                }
            } catch (_: Exception) {
                out.delete() // недокопійований — не лишаємо
            }
        }
        return count
    }

    /** Адреси файлів з наміру «Поділитися» (один чи кілька). */
    @Suppress("DEPRECATION")
    fun sharedUris(intent: Intent?): List<Uri> = when (intent?.action) {
        Intent.ACTION_SEND -> listOfNotNull(intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri)
        Intent.ACTION_SEND_MULTIPLE ->
            intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.filterNotNull() ?: emptyList()
        else -> emptyList()
    }
}
