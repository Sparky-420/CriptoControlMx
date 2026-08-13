package mx.criptocontrolmx.app

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.security.MessageDigest
import kotlin.math.max

internal class WalletImageChannel(messenger: BinaryMessenger) {
    init {
        MethodChannel(messenger, channelName).setMethodCallHandler { call, result ->
            if (call.method != "process") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            try {
                val source = call.argument<ByteArray>("bytes")
                    ?: throw IllegalArgumentException("bytes is required")
                val preserveAlpha = call.argument<Boolean>("preserveAlpha") ?: false
                val maxLongEdge = call.argument<Int>("maxLongEdge") ?: 1024
                val jpegQuality = call.argument<Int>("jpegQuality") ?: 82
                result.success(process(source, preserveAlpha, maxLongEdge, jpegQuality))
            } catch (error: IllegalArgumentException) {
                result.error("invalid_image", error.message, null)
            } catch (error: Exception) {
                result.error("image_processing_failed", error.message, null)
            }
        }
    }

    private fun process(
        source: ByteArray,
        preserveAlpha: Boolean,
        maxLongEdge: Int,
        jpegQuality: Int,
    ): Map<String, Any> {
        require(source.isNotEmpty()) { "bytes is required" }
        require(maxLongEdge > 0) { "maxLongEdge must be positive" }
        val decoded = BitmapFactory.decodeByteArray(source, 0, source.size)
            ?: throw IllegalArgumentException("Invalid image bytes")
        val bitmap = scaleIfNeeded(decoded, maxLongEdge)
        if (bitmap !== decoded) decoded.recycle()
        val width = bitmap.width
        val height = bitmap.height
        val usePng = preserveAlpha && bitmap.hasAlpha()
        val bytes = ByteArrayOutputStream().use { output ->
            val format = if (usePng) Bitmap.CompressFormat.PNG else Bitmap.CompressFormat.JPEG
            if (!bitmap.compress(format, jpegQuality.coerceIn(0, 100), output)) {
                throw IllegalStateException("Unable to encode image")
            }
            output.toByteArray()
        }
        bitmap.recycle()
        val mimeType = if (usePng) "image/png" else "image/jpeg"
        return mapOf(
            "bytes" to bytes,
            "width" to width,
            "height" to height,
            "mimeType" to mimeType,
            "sha256" to MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) },
        )
    }

    private fun scaleIfNeeded(bitmap: Bitmap, maxLongEdge: Int): Bitmap {
        val longEdge = max(bitmap.width, bitmap.height)
        if (longEdge <= maxLongEdge) return bitmap
        val ratio = maxLongEdge.toDouble() / longEdge.toDouble()
        return Bitmap.createScaledBitmap(
            bitmap,
            (bitmap.width * ratio).toInt().coerceAtLeast(1),
            (bitmap.height * ratio).toInt().coerceAtLeast(1),
            true,
        )
    }

    private companion object {
        const val channelName = "mx.criptocontrolmx.app/wallet_images"
    }
}
