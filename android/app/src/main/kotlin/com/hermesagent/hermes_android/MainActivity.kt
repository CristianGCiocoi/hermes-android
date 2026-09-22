package com.hermesagent.hermes_android

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    private val methodChannelName = "hermes.notification/local"
    private val notificationChannelId = "hermes_gateway_notifications"
    private val notificationPermissionRequestCode = 48031
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestPermission" -> requestNotificationPermission(result)
                    "show" -> {
                        val notificationId = call.argument<String>("notification_id")
                        val version = call.argument<Int>("version")
                        val title = call.argument<String>("title")
                        val body = call.argument<String>("body")
                        if (notificationId == null || version == null || title == null || body == null) {
                            result.error(
                                "invalid_notification",
                                "Missing Hermes notification presentation data",
                                null,
                            )
                            return@setMethodCallHandler
                        }
                        result.success(showLocalNotification(notificationId, version, title, body))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33 ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (pendingPermissionResult != null) {
            result.error(
                "permission_request_in_progress",
                "A notification permission request is already active",
                null,
            )
            return
        }
        pendingPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            notificationPermissionRequestCode,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != notificationPermissionRequestCode) return
        val result = pendingPermissionResult ?: return
        pendingPermissionResult = null
        result.success(
            grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED,
        )
    }

    private fun showLocalNotification(
        notificationId: String,
        version: Int,
        title: String,
        body: String,
    ): Map<String, String> {
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return deliveryResult(
                notificationId,
                version,
                "PERMISSION_DENIED",
            )
        }
        return try {
            val manager = getSystemService(NotificationManager::class.java)
            if (Build.VERSION.SDK_INT >= 26) {
                manager.createNotificationChannel(
                    NotificationChannel(
                        notificationChannelId,
                        "Hermes notifications",
                        NotificationManager.IMPORTANCE_DEFAULT,
                    ),
                )
            }
            val launch = packageManager.getLaunchIntentForPackage(packageName)
                ?: Intent(this, MainActivity::class.java)
            val pending = PendingIntent.getActivity(
                this,
                0,
                launch,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val builder = if (Build.VERSION.SDK_INT >= 26) {
                android.app.Notification.Builder(this, notificationChannelId)
            } else {
                @Suppress("DEPRECATION")
                android.app.Notification.Builder(this)
            }
            manager.notify(
                notificationId.hashCode(),
                builder
                    .setSmallIcon(applicationInfo.icon)
                    .setContentTitle(title.take(80))
                    .setContentText(body.take(240))
                    .setContentIntent(pending)
                    .setAutoCancel(true)
                    .build(),
            )
            deliveryResult(notificationId, version, "DELIVERED")
        } catch (_: RuntimeException) {
            deliveryResult(notificationId, version, "DELIVERY_FAILED")
        }
    }

    private fun deliveryResult(
        notificationId: String,
        version: Int,
        outcome: String,
    ): Map<String, String> {
        val bytes = MessageDigest.getInstance("SHA-256")
            .digest("$notificationId|$version|$packageName|$outcome".toByteArray(Charsets.UTF_8))
        val resultRef = "urn:hermes:android-delivery:" +
            bytes.joinToString("") { "%02x".format(it) }
        return mapOf("outcome" to outcome, "result_ref" to resultRef)
    }
}
