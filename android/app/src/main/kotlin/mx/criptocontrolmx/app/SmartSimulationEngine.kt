package mx.criptocontrolmx.app

import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

/**
 * Motor de notificaciones inteligentes Pro (segundo plano).
 *
 * Port 1:1 de lib/smart_alerts/ (SmartSimulationEvaluator + SmartSimulationMonitor):
 * mismas claves, mismas f├│rmulas del simulador y misma l├│gica anti-duplicados.
 * Se ejecuta dentro del AlertWorker existente reutilizando la misma consulta
 * de precios (no hay un Worker adicional). Nunca ejecuta operaciones.
 */
object SmartSimulationEngine {
    const val channelId = "cripto_smart_pro"
    private const val proKey = "flutter.pro_entitlement_active_v1"
    private const val savedKey = "flutter.saved_simulations_v1_json"
    private const val monitoredKey = "flutter.smart_alerts_monitored_ids_v1_json"
    private const val stateKey = "flutter.smart_alerts_state_v1_json"
    private const val epsilon = 1e-9

    data class Evaluation(
        val status: String, // favorable | notFavorable | missingData
        val currentValue: Double = 0.0,
        val targetValue: Double = 0.0,
        val netAfterFees: Double = 0.0,
        val totalCommissions: Double = 0.0,
        val reason: String,
    )

    fun isActive(prefs: SharedPreferences): Boolean =
        prefs.getBoolean(proKey, false) && activeMonitoredIds(prefs).isNotEmpty()

    fun recordPriceFailure(prefs: SharedPreferences, diagnostic: String) {
        if (!prefs.getBoolean(proKey, false)) return
        val ids = activeMonitoredIds(prefs)
        val oldStates = readStates(prefs)
        val states = JSONObject()
        val now = isoNowUtc()
        for (id in ids) {
            val s = oldStates.optJSONObject(id) ?: JSONObject()
            s.put("lastStatus", "priceError").put("lastEvaluatedAt", now).put("diagnostic", diagnostic)
            states.put(id, s)
        }
        prefs.edit().putString(stateKey, states.toString()).commit()
    }

    /** Devuelve cu├íntas notificaciones se enviaron. */
    fun run(
        prefs: SharedPreferences,
        prices: Map<String, Double>,
        notify: (id: String, title: String, body: String) -> Boolean,
    ): Int {
        if (!prefs.getBoolean(proKey, false)) return 0
        val ids = activeMonitoredIds(prefs)
        val sims = savedSimulations(prefs).filter { it.first in ids }
        val oldStates = readStates(prefs)
        val states = JSONObject()
        val now = isoNowUtc()
        var sent = 0
        for ((id, params) in sims) {
            val prev = oldStates.optJSONObject(id) ?: JSONObject()
            val wasMet = prev.optBoolean("conditionMet", false)
            val next = JSONObject(prev.toString()).put("lastEvaluatedAt", now)
            if (params == null) {
                next.put("lastStatus", "missingData").put(
                    "diagnostic",
                    "La simulaci├│n no tiene par├ímetros econ├│micos guardados; vuelve a guardarla para supervisarla.",
                )
                states.put(id, next)
                continue
            }
            val eval = evaluate(params, prices)
            when (eval.status) {
                "missingData" -> next.put("lastStatus", "missingData").put("diagnostic", eval.reason)
                "notFavorable" -> {
                    next.put("conditionMet", false)
                        .put("lastStatus", "notFavorable")
                        .put("lastCurrentValue", eval.currentValue)
                        .put("targetValue", eval.targetValue)
                        .put("diagnostic", eval.reason)
                    next.remove("lastNotifiedAt")
                }
                else -> {
                    next.put("lastStatus", "favorable").put("lastCurrentValue", eval.currentValue)
                        .put("targetValue", eval.targetValue).put("diagnostic", eval.reason)
                    if (!wasMet) {
                        val (title, body) = message(params, eval, prices)
                        val ok = notify(id, title, body)
                        next.put("conditionMet", ok)
                        if (ok) {
                            sent += 1
                            next.put("lastNotifiedAt", now)
                        } else {
                            next.remove("lastNotifiedAt")
                            next.put("diagnostic", "Oportunidad detectada, pero Android no permitió mostrar la notificación.")
                        }
                    }
                }
            }
            states.put(id, next)
        }
        prefs.edit().putString(stateKey, states.toString()).commit()
        return sent
    }


    fun evaluate(p: JSONObject, prices: Map<String, Double>): Evaluation {
        val kind = p.optString("kind")

        if (kind !in setOf("buy", "sell", "rotation")) {
            return Evaluation("missingData", reason = "Tipo de simulación desconocido.")
        }

        val coins = when (kind) {
            "rotation" -> listOf(
                p.optString("originCoin").uppercase(),
                p.optString("targetCoin").uppercase()
            )
            else -> listOf(p.optString("coin").uppercase())
        }

        if (coins.any { it.isBlank() }) {
            return Evaluation("missingData", reason = "Faltan activos de la simulación.")
        }

        if (kind == "rotation" && coins[0] == coins[1]) {
            return Evaluation(
                "missingData",
                reason = "Parámetros de rotación incompletos o inválidos."
            )
        }

        for (coin in coins) {
            val price = prices[coin]
            if (price == null || !price.isFinite() || price <= 0.0) {
                return Evaluation(
                    "missingData",
                    reason = "Falta cotización actual válida de $coin."
                )
            }
        }

        fun d(key: String): Double? =
            if (p.has(key)) {
                p.optDouble(key, Double.NaN).takeIf { it.isFinite() }
            } else {
                null
            }

        fun positiveFinite(value: Double?) =
            value != null && value.isFinite() && value > 0.0

        fun nonNegativeFinite(value: Double?) =
            value != null && value.isFinite() && value >= 0.0

        fun validFee(fee: Double?) =
            fee != null && fee.isFinite() && fee >= 0.0 && fee < 100.0

        fun meets(current: Double, target: Double) =
            current >= target * (1.0 - epsilon)

        return when (kind) {
            "buy" -> {
                val gross = d("grossAmount")
                val fee = d("buyFeePercent")
                val simPrice = d("simPrice")
                val target = d("targetQuantity")

                if (!positiveFinite(gross) ||
                    !validFee(fee) ||
                    !positiveFinite(simPrice) ||
                    !positiveFinite(target)
                ) {
                    return Evaluation(
                        "missingData",
                        reason = "Parámetros de compra incompletos o inválidos."
                    )
                }

                val coin = coins[0]
                val price = prices.getValue(coin)
                val commission = gross!! * fee!! / 100.0
                val net = gross - commission
                val quantity = net / price

                if (!nonNegativeFinite(commission) ||
                    !positiveFinite(net) ||
                    !positiveFinite(quantity)
                ) {
                    return Evaluation(
                        "missingData",
                        reason = "Resultado de compra fuera de rango numérico."
                    )
                }

                val ok = meets(quantity, target!!)

                Evaluation(
                    if (ok) "favorable" else "notFavorable",
                    quantity,
                    target,
                    net,
                    commission,
                    if (ok) {
                        "Con el mismo capital obtienes igual o más $coin que en tu simulación."
                    } else {
                        "Hoy obtendrías menos $coin que el objetivo de la simulación."
                    }
                )
            }

            "sell" -> {
                val quantity = d("quantity")
                val fee = d("sellFeePercent")
                val simPrice = d("simPrice")
                val target = d("targetNetReceived")

                if (!positiveFinite(quantity) ||
                    !validFee(fee) ||
                    !positiveFinite(simPrice) ||
                    !positiveFinite(target)
                ) {
                    return Evaluation(
                        "missingData",
                        reason = "Parámetros de venta incompletos o inválidos."
                    )
                }

                val coin = coins[0]
                val price = prices.getValue(coin)
                val gross = quantity!! * price
                val commission = gross * fee!! / 100.0
                val net = gross - commission

                if (!positiveFinite(gross) ||
                    !nonNegativeFinite(commission) ||
                    !positiveFinite(net)
                ) {
                    return Evaluation(
                        "missingData",
                        reason = "Resultado de venta fuera de rango numérico."
                    )
                }

                val ok = meets(net, target!!)

                Evaluation(
                    if (ok) "favorable" else "notFavorable",
                    net,
                    target,
                    net,
                    commission,
                    if (ok) {
                        "Vender la misma cantidad hoy deja igual o más MXN netos que tu simulación."
                    } else {
                        "Hoy recibirías menos MXN netos que el objetivo de la simulación."
                    }
                )
            }

            "rotation" -> {
                val origin = coins[0]
                val destination = coins[1]
                val quantity = d("originQuantity")
                val sellFee = d("sellFeePercent")
                val buyFee = d("buyFeePercent")
                val simOriginPrice = d("simOriginPrice")
                val simTargetPrice = d("simTargetPrice")
                val target = d("targetQuantity")

                if (!positiveFinite(quantity) ||
                    !validFee(sellFee) ||
                    !validFee(buyFee) ||
                    !positiveFinite(simOriginPrice) ||
                    !positiveFinite(simTargetPrice) ||
                    !positiveFinite(target)
                ) {
                    return Evaluation(
                        "missingData",
                        reason = "Parámetros de rotación incompletos o inválidos."
                    )
                }

                val originPrice = prices.getValue(origin)
                val destinationPrice = prices.getValue(destination)

                val originGross = quantity!! * originPrice
                val sellCommission = originGross * sellFee!! / 100.0
                val netAvailable = originGross - sellCommission
                val buyCommission = netAvailable * buyFee!! / 100.0
                val converted = netAvailable - buyCommission
                val bought = converted / destinationPrice
                val totalCommissions = sellCommission + buyCommission

                if (!positiveFinite(originGross) ||
                    !nonNegativeFinite(sellCommission) ||
                    !positiveFinite(netAvailable) ||
                    !nonNegativeFinite(buyCommission) ||
                    !positiveFinite(converted) ||
                    !positiveFinite(bought) ||
                    !nonNegativeFinite(totalCommissions)
                ) {
                    return Evaluation(
                        "missingData",
                        reason = "Resultado de rotación fuera de rango numérico."
                    )
                }

                val ok = meets(bought, target!!)

                Evaluation(
                    if (ok) "favorable" else "notFavorable",
                    bought,
                    target,
                    converted,
                    totalCommissions,
                    if (ok) {
                        "La relación $origin/$destination permite obtener igual o más $destination que tu simulación."
                    } else {
                        "La relación $origin/$destination hoy da menos $destination que el objetivo."
                    }
                )
            }

            else -> Evaluation("missingData", reason = "Tipo de simulación desconocido.")
        }
    }

    private fun message(p: JSONObject, e: Evaluation, prices: Map<String, Double>): Pair<String, String> {
        val intro = "Las condiciones actuales cumplen los objetivos de tu simulaci├│n guardada."
        val outro = "Motivo: se alcanzaron las condiciones configuradas en tu estrategia. CriptoControlMx no ejecuta operaciones."
        return when (p.optString("kind")) {
            "rotation" -> {
                val o = p.optString("originCoin").uppercase(); val t = p.optString("targetCoin").uppercase()
                "Oportunidad de rotaci├│n $o ΓåÆ $t" to listOf(
                    intro,
                    "Activo de origen: $o (${mxn(prices[o] ?: 0.0)}).",
                    "Activo de destino: $t (${mxn(prices[t] ?: 0.0)}).",
                    "Cantidad estimada actual: ${qty(e.currentValue)} $t.",
                    "Cantidad objetivo de la simulaci├│n: ${qty(e.targetValue)} $t.",
                    "Resultado estimado despu├⌐s de comisiones: ${mxn(e.netAfterFees)} convertidos (comisiones ${mxn(e.totalCommissions)}).",
                    outro,
                ).joinToString("\n")
            }
            "buy" -> {
                val c = p.optString("coin").uppercase()
                "Oportunidad de compra $c" to listOf(
                    intro,
                    "Precio actual $c: ${mxn(prices[c] ?: 0.0)} (simulado ${mxn(p.optDouble("simPrice"))}).",
                    "Cantidad estimada actual: ${qty(e.currentValue)} $c.",
                    "Cantidad objetivo de la simulaci├│n: ${qty(e.targetValue)} $c.",
                    "Capital neto despu├⌐s de comisiones: ${mxn(e.netAfterFees)}.",
                    outro,
                ).joinToString("\n")
            }
            else -> {
                val c = p.optString("coin").uppercase()
                "Oportunidad de venta $c" to listOf(
                    intro,
                    "Precio actual $c: ${mxn(prices[c] ?: 0.0)} (simulado ${mxn(p.optDouble("simPrice"))}).",
                    "Cantidad a vender: ${qty(p.optDouble("quantity"))} $c.",
                    "Resultado estimado despu├⌐s de comisiones: ${mxn(e.currentValue)}.",
                    "Objetivo de la simulaci├│n: ${mxn(e.targetValue)}.",
                    outro,
                ).joinToString("\n")
            }
        }
    }

    private fun monitoredIds(prefs: SharedPreferences): Set<String> {
        val raw = prefs.getString(monitoredKey, null) ?: return emptySet()
        val arr = runCatching { JSONArray(raw) }.getOrNull() ?: return emptySet()
        return (0 until arr.length()).map { arr.optString(it) }.filter { it.isNotBlank() }.toSet()
    }
    private fun activeMonitoredIds(prefs: SharedPreferences): Set<String> {
        val existingIds = savedSimulations(prefs).map { it.first }.toSet()
        val storedIds = monitoredIds(prefs)
        val validIds = storedIds.intersect(existingIds)

        if (validIds != storedIds) {
            prefs.edit()
                .putString(monitoredKey, JSONArray(validIds.sorted()).toString())
                .commit()
        }

        return validIds
    }

    private fun savedSimulations(prefs: SharedPreferences): List<Pair<String, JSONObject?>> {
        val raw = prefs.getString(savedKey, null) ?: return emptyList()
        val arr = runCatching { JSONArray(raw) }.getOrNull() ?: return emptyList()
        val seen = mutableSetOf<String>()
        return (0 until arr.length()).mapNotNull { i ->
            val item = arr.optJSONObject(i) ?: return@mapNotNull null
            val id = item.optString("id")
            if (id.isBlank() || !seen.add(id)) return@mapNotNull null
            id to item.optJSONObject("smartParams")
        }
    }

    private fun readStates(prefs: SharedPreferences): JSONObject =
        runCatching { JSONObject(prefs.getString(stateKey, null) ?: "{}") }.getOrDefault(JSONObject())

    private fun qty(v: Double) = if (kotlin.math.abs(v) >= 1) "%.4f".format(java.util.Locale.US, v) else "%.8f".format(java.util.Locale.US, v)
    private fun mxn(v: Double) = "${'$'}${"%,.2f".format(java.util.Locale.US, v)} MXN"
    private fun isoNowUtc() = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", java.util.Locale.US)
        .apply { timeZone = java.util.TimeZone.getTimeZone("UTC") }.format(java.util.Date())
}
