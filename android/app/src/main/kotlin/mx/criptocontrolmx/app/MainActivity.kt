package mx.criptocontrolmx.app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs

class MainActivity : FlutterActivity() {
    private val channelName = "mx.criptocontrolmx.app/price_alerts"
    private val notificationChannelId = AlertWorker.notificationChannelId
    private val automaticWorkName = "cripto_alerts_periodic"
    private val notificationPermissionRequestCode = 4202
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> {
                    createPriceAlertChannel()
                    result.success(null)
                }
                "areNotificationsAllowed" -> result.success(areNotificationsAllowed())
                "requestNotificationPermission" -> requestNotificationPermission(result)
                "configureAutomaticAlerts" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    val intervalMinutes = call.argument<Int>("intervalMinutes") ?: 30
                    configureAutomaticAlerts(enabled, intervalMinutes)
                    result.success(null)
                }
                "runAutomaticAlertCheckNow" -> {
                    enqueueImmediateAlertCheck()
                    result.success(null)
                }
                "showPriceAlert" -> {
                    val coin = call.argument<String>("coin") ?: "CRIPTO"
                    val title = call.argument<String>("title") ?: "Alerta de precio"
                    val body = call.argument<String>("body") ?: "Precio actualizado"
                    result.success(showPriceAlert(coin, title, body))
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        if (requestCode == notificationPermissionRequestCode) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        }
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU || areNotificationsAllowed()) {
            result.success(true)
            return
        }

        if (pendingPermissionResult != null) {
            result.success(false)
            return
        }

        pendingPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            notificationPermissionRequestCode,
        )
    }

    private fun configureAutomaticAlerts(enabled: Boolean, intervalMinutes: Int) {
        val workManager = WorkManager.getInstance(applicationContext)
        if (!enabled) {
            workManager.cancelUniqueWork(automaticWorkName)
            return
        }

        val safeMinutes = maxOf(15, intervalMinutes.toLong())
        val request = PeriodicWorkRequestBuilder<AlertWorker>(
            safeMinutes,
            TimeUnit.MINUTES,
        ).build()
        workManager.enqueueUniquePeriodicWork(
            automaticWorkName,
            ExistingPeriodicWorkPolicy.UPDATE,
            request,
        )
    }

    private fun enqueueImmediateAlertCheck() {
        val request = OneTimeWorkRequestBuilder<AlertWorker>().build()
        WorkManager.getInstance(applicationContext).enqueueUniqueWork(
            "cripto_alerts_now",
            ExistingWorkPolicy.REPLACE,
            request,
        )
    }

    private fun showPriceAlert(coin: String, title: String, body: String): Boolean {
        createPriceAlertChannel()
        if (!areNotificationsAllowed()) return false

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, notificationChannelId)
        } else {
            legacyNotificationBuilder()
        }

        val notification = builder
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .build()

        notificationManager().notify(abs(coin.hashCode()), notification)
        return true
    }

    @Suppress("DEPRECATION")
    private fun legacyNotificationBuilder(): Notification.Builder = Notification.Builder(this)

    private fun areNotificationsAllowed(): Boolean {
        val permissionAllowed = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        val appNotificationsAllowed = Build.VERSION.SDK_INT < Build.VERSION_CODES.N ||
            notificationManager().areNotificationsEnabled()

        return permissionAllowed && appNotificationsAllowed
    }

    private fun createPriceAlertChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val channel = NotificationChannel(
            notificationChannelId,
            "Alertas de CriptoControlMx",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "Alertas de mercado y recuperación"
        }

        notificationManager().createNotificationChannel(channel)
    }

    private fun notificationManager(): NotificationManager =
        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
}
