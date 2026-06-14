package mx.criptocontrolmx.app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.work.Worker
import androidx.work.WorkerParameters
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

class AlertWorker(appContext: Context, params: WorkerParameters) : Worker(appContext, params) {
    override fun doWork(): Result {
        val prefs = applicationContext.getSharedPreferences(sharedPreferencesName, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(pref(automaticEnabledKey), false)) return Result.success()
        if (!prefs.getBoolean(pref(priceEnabledKey), false) && !prefs.getBoolean(pref(recoveryEnabledKey), false)) {
            return Result.success()
        }

        val prices = fetchPrices()
        if (prices.isEmpty()) return Result.retry()

        prefs.edit()
            .putString(pref(pricesKey), JSONObject(prices as Map<*, *>).toString())
            .putLong(pref(pricesUpdatedAtKey), System.currentTimeMillis())
            .apply()

        createChannel()
        val editor = prefs.edit()
        if (prefs.getBoolean(pref(priceEnabledKey), false)) {
            evaluateMarketAlerts(prefs, editor, prices)
        }
        if (prefs.getBoolean(pref(recoveryEnabledKey), false)) {
            evaluateRecoveryAlerts(prefs, editor, prices)
        }
        editor.apply()
        return Result.success()
    }

    private fun evaluateMarketAlerts(
        prefs: android.content.SharedPreferences,
        editor: android.content.SharedPreferences.Editor,
        prices: Map<String, Double>,
    ) {
        val threshold = max(0.01, prefs.getDoubleCompat(pref(priceThresholdKey), 2.0))
        val references = readDoubleMap(prefs.getString(pref(priceReferenceKey), null))
        val notifiedPrices = readDoubleMap(prefs.getString(pref(priceLastNotifiedPricesKey), null))
        val notifiedAt = readStringMap(prefs.getString(pref(priceLastNotifiedAtKey), null))
        var changed = false

        for (coin in coins) {
            val currentPrice = prices[coin] ?: continue
            if (currentPrice <= 0) continue
            val reference = references[coin] ?: 0.0
            if (reference <= 0) {
                references[coin] = currentPrice
                changed = true
                continue
            }
            val changePct = (currentPrice - reference) / reference * 100.0
            if (changePct >= threshold || changePct <= -threshold) {
                val up = changePct > 0
                val title = "$coin ${if (up) "subió" else "bajó"} ${signed(changePct)}%"
                val body = "Precio actual: ${formatMxn(currentPrice)}"
                if (notify(coin, title, body)) {
                    references[coin] = currentPrice
                    notifiedPrices[coin] = currentPrice
                    notifiedAt[coin] = isoNow()
                    changed = true
                }
            }
        }

        if (changed) {
            editor.putString(pref(priceReferenceKey), JSONObject(references as Map<*, *>).toString())
            editor.putString(pref(priceLastNotifiedPricesKey), JSONObject(notifiedPrices as Map<*, *>).toString())
            editor.putString(pref(priceLastNotifiedAtKey), JSONObject(notifiedAt as Map<*, *>).toString())
        }
    }

    private fun evaluateRecoveryAlerts(
        prefs: android.content.SharedPreferences,
        editor: android.content.SharedPreferences.Editor,
        prices: Map<String, Double>,
    ) {
        val stats = computeStats(prefs.getString(pref(movementsKey), null), prices)
        val references = readDoubleMap(prefs.getString(pref(recoveryReferenceKey), null))
        val notifiedAt = readStringMap(prefs.getString(pref(recoveryLastNotifiedAtKey), null))
        val threshold = max(0.01, prefs.getDoubleCompat(pref(recoveryThresholdKey), 2.0))
        val sellFeePercent = prefs.getDoubleCompat(pref(sellFeePercentKey), 0.0)
        var changed = false

        for (coin in coins) {
            val stat = stats[coin] ?: continue
            val currentPrice = prices[coin] ?: 0.0
            if (stat.quantity <= 0 || stat.costBase <= 0 || currentPrice <= 0) continue
            val multiplier = (1.0 - sellFeePercent / 100.0).coerceIn(0.0, 1.0)
            val netCurrentValue = stat.quantity * currentPrice * multiplier
            val pnl = netCurrentValue - stat.costBase
            val pnlPct = pnl / stat.costBase * 100.0
            val reference = references[coin]
            if (reference == null) {
                references[coin] = pnlPct
                changed = true
                continue
            }
            val delta = pnlPct - reference
            if (delta >= threshold || delta <= -threshold) {
                val improved = delta > 0
                val title = "$coin ${if (improved) "mejoró" else "empeoró"} ${signed(delta)} pts"
                val missing = if (pnl < 0) -pnl else 0.0
                val body = "Tu P&L pasó de ${reference.format(2)}% a ${pnlPct.format(2)}%." +
                    if (missing > 0) " Faltan ${formatMxn(missing)} para break even." else ""
                if (notify("recovery_$coin", title, body)) {
                    references[coin] = pnlPct
                    notifiedAt[coin] = isoNow()
                    changed = true
                }
            }
        }

        if (changed) {
            editor.putString(pref(recoveryReferenceKey), JSONObject(references as Map<*, *>).toString())
            editor.putString(pref(recoveryLastNotifiedAtKey), JSONObject(notifiedAt as Map<*, *>).toString())
        }
    }

    private fun computeStats(raw: String?, prices: Map<String, Double>): MutableMap<String, NativeCoinStats> {
        val stats = coins.associateWith { NativeCoinStats(currentPrice = prices[it] ?: 0.0) }.toMutableMap()
        if (raw.isNullOrBlank()) return stats
        val movements = runCatching { JSONArray(raw) }.getOrNull() ?: return stats
        val indexed = (0 until movements.length()).mapNotNull { index ->
            val movement = movements.optJSONObject(index) ?: return@mapNotNull null
            IndexedMovement(index, movement)
        }.sortedWith(compareBy<IndexedMovement> { it.date }.thenBy { it.index })

        for (item in indexed) {
            val movement = item.json
            val coin = (movement.optString("coin", movement.optString("crypto", "BTC"))).uppercase()
            val stat = stats[coin] ?: continue
            val quantity = movement.optDoubleCompat("quantity")
            val unitPrice = movement.optDoubleCompat("unitPrice", movement.optDoubleCompat("unit_price"))
            val fee = movement.optDoubleCompat("fee", movement.optDoubleCompat("commission"))
            when (movementType(movement.optString("type"))) {
                "buy", "transferIn" -> {
                    stat.quantity += quantity
                    stat.costBase += quantity * unitPrice + fee
                }
                "sell", "transferOut" -> {
                    val average = if (stat.quantity > 0) stat.costBase / stat.quantity else 0.0
                    val quantityToRemove = min(quantity, stat.quantity)
                    val removedCost = average * quantityToRemove
                    stat.quantity -= quantityToRemove
                    stat.costBase -= removedCost
                }
            }
            if (abs(stat.quantity) < 0.0000000001) {
                stat.quantity = 0.0
                stat.costBase = 0.0
            }
            if (abs(stat.costBase) < 0.00000001) stat.costBase = 0.0
        }
        return stats
    }

    private fun fetchPrices(): Map<String, Double> {
        val url = URL("https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum,chainlink,litecoin,uniswap&vs_currencies=mxn")
        val connection = (url.openConnection() as HttpURLConnection).apply {
            connectTimeout = 10_000
            readTimeout = 10_000
            requestMethod = "GET"
            setRequestProperty("Accept", "application/json")
        }
        return try {
            if (connection.responseCode !in 200..299) return emptyMap()
            val body = connection.inputStream.bufferedReader().use { it.readText() }
            val json = JSONObject(body)
            buildMap {
                put("BTC", json.getJSONObject("bitcoin").getDouble("mxn"))
                put("ETH", json.getJSONObject("ethereum").getDouble("mxn"))
                put("LINK", json.getJSONObject("chainlink").getDouble("mxn"))
                put("LTC", json.getJSONObject("litecoin").getDouble("mxn"))
                put("UNI", json.getJSONObject("uniswap").getDouble("mxn"))
            }
        } catch (_: Exception) {
            emptyMap()
        } finally {
            connection.disconnect()
        }
    }

    private fun notify(tag: String, title: String, body: String): Boolean {
        if (!notificationsAllowed()) return false
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(applicationContext, notificationChannelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(applicationContext)
        }
        val notification = builder
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .build()
        manager().notify(abs(tag.hashCode()), notification)
        return true
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            notificationChannelId,
            "Alertas de CriptoControlMx",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply { description = "Alertas de mercado y recuperación" }
        manager().createNotificationChannel(channel)
    }

    private fun notificationsAllowed(): Boolean {
        val permissionAllowed = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            applicationContext.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        val appNotificationsAllowed = Build.VERSION.SDK_INT < Build.VERSION_CODES.N || manager().areNotificationsEnabled()
        return permissionAllowed && appNotificationsAllowed
    }

    private fun manager(): NotificationManager =
        applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    companion object {
        const val notificationChannelId = "cripto_alerts"
        private const val sharedPreferencesName = "FlutterSharedPreferences"
        private val coins = listOf("BTC", "ETH", "LINK", "LTC", "UNI")
        val futureCoinGeckoIds = mapOf(
            "USDT" to "tether",
            "USDC" to "usd-coin",
            "XRP" to "ripple",
            "SOL" to "solana",
            "ATOM" to "cosmos",
        )
        private const val automaticEnabledKey = "automatic_local_alerts_enabled"
        private const val priceEnabledKey = "price_alerts_enabled"
        private const val priceThresholdKey = "price_alert_threshold_percent"
        private const val priceReferenceKey = "price_alert_reference_prices_json"
        private const val priceLastNotifiedAtKey = "price_alert_last_notified_at_json"
        private const val priceLastNotifiedPricesKey = "price_alert_last_notified_prices_json"
        private const val recoveryEnabledKey = "recovery_alerts_enabled"
        private const val recoveryThresholdKey = "recovery_alert_threshold_points"
        private const val recoveryReferenceKey = "recovery_alert_reference_pnl_json"
        private const val recoveryLastNotifiedAtKey = "recovery_alert_last_notified_at_json"
        private const val pricesKey = "prices_json"
        private const val pricesUpdatedAtKey = "prices_updated_at_ms"
        private const val movementsKey = "movements_json"
        private const val sellFeePercentKey = "sell_fee_percent"
        private fun pref(key: String) = "flutter.$key"
    }
}

private data class NativeCoinStats(var quantity: Double = 0.0, var costBase: Double = 0.0, var currentPrice: Double = 0.0)
private data class IndexedMovement(val index: Int, val json: JSONObject) { val date: String = json.optString("date") }

private fun android.content.SharedPreferences.getDoubleCompat(key: String, fallback: Double): Double {
    if (!contains(key)) return fallback
    return when (val value = all[key]) {
        is Float -> value.toDouble()
        is Double -> value
        is Long -> value.toDouble()
        is Int -> value.toDouble()
        is String -> value.toDoubleOrNull() ?: fallback
        else -> fallback
    }
}

private fun JSONObject.optDoubleCompat(key: String, fallback: Double = 0.0): Double {
    val value = opt(key) ?: return fallback
    return when (value) {
        is Number -> value.toDouble()
        is String -> value.toDoubleOrNull() ?: fallback
        else -> fallback
    }
}

private fun readDoubleMap(raw: String?): MutableMap<String, Double> {
    val result = mutableMapOf<String, Double>()
    if (raw.isNullOrBlank()) return result
    val json = runCatching { JSONObject(raw) }.getOrNull() ?: return result
    for (key in json.keys()) result[key] = json.optDoubleCompat(key)
    return result
}

private fun readStringMap(raw: String?): MutableMap<String, String> {
    val result = mutableMapOf<String, String>()
    if (raw.isNullOrBlank()) return result
    val json = runCatching { JSONObject(raw) }.getOrNull() ?: return result
    for (key in json.keys()) result[key] = json.optString(key)
    return result
}

private fun movementType(rawType: String): String {
    val raw = rawType.trim().lowercase()
    return when (raw) {
        "sell", "venta", "vender" -> "sell"
        "transferin", "transfer_in", "transferenciaentrada", "transferencia recibida", "entrada" -> "transferIn"
        "transferout", "transfer_out", "transferenciasalida", "transferencia enviada", "salida" -> "transferOut"
        else -> "buy"
    }
}

private fun signed(value: Double) = "${if (value >= 0) "+" else ""}${value.format(2)}"
private fun Double.format(decimals: Int) = "%.${decimals}f".format(this)
private fun isoNow() = java.text.SimpleDateFormat("yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'", java.util.Locale.US).apply { timeZone = java.util.TimeZone.getTimeZone("UTC") }.format(java.util.Date())
private fun formatMxn(value: Double) = "${'$'}${"%,.2f".format(value)} MXN"
