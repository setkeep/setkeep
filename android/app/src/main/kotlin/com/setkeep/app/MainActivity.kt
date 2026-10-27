package com.setkeep.app

import android.Manifest
import android.app.NotificationManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var notificationPermissionRequested = false
    private val channelName = "com.setkeep.app/rest_timer"
    private val imageChannelName = "com.setkeep.app/workout_image"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val restChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        RestTimerState.onChanged = { restChannel.invokeMethod("stateChanged", null) }
        restChannel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "freezeWorkoutActions" -> {
                        RestTimerState.cancel(this)
                        result.success(WorkoutNotificationState.read(this))
                    }
                    "nextWorkoutTarget" -> result.success(WorkoutNotificationState.nextTarget(this,
                        call.argument<String>("sessionId") ?: "", call.argument<String>("exerciseInstanceId") ?: "")?.let { json ->
                            json.keys().asSequence().associateWith { json.getString(it) }
                        })
                    "readWorkoutDraft" -> result.success(WorkoutNotificationState.read(this))
                    "writeWorkoutDraft" -> {
                        try { result.success(WorkoutNotificationState.write(this, call.argument<String>("draft")!!)) }
                        catch (error: Exception) { result.error("DRAFT_WRITE", "記録を保存できませんでした", null) }
                    }
                    "clearWorkoutDraft" -> {
                        WorkoutNotificationState.clear(this)
                        result.success(null)
                    }
                    "debugScreenshot" -> {
                        if (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE == 0 ||
                            Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                            result.notImplemented()
                        } else {
                            fun surface(view: android.view.View): android.view.SurfaceView? {
                                if (view is android.view.SurfaceView) return view
                                if (view is android.view.ViewGroup) {
                                    for (i in 0 until view.childCount) surface(view.getChildAt(i))?.let { return it }
                                }
                                return null
                            }
                            val target = surface(window.decorView)
                            if (target == null || target.width <= 0 || target.height <= 0) {
                                result.error("NO_SURFACE", "Flutter surface is not ready", null)
                            } else {
                                val bitmap = android.graphics.Bitmap.createBitmap(target.width, target.height, android.graphics.Bitmap.Config.ARGB_8888)
                                android.view.PixelCopy.request(target, bitmap, { status ->
                                    if (status == android.view.PixelCopy.SUCCESS) {
                                        val output = java.io.ByteArrayOutputStream()
                                        bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, output)
                                        result.success(output.toByteArray())
                                    } else result.error("PIXEL_COPY", "Could not capture Flutter surface: $status", null)
                                    bitmap.recycle()
                                }, android.os.Handler(mainLooper))
                            }
                        }
                    }
                    "debugRestAction" -> {
                        if (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE == 0) result.notImplemented()
                        else {
                            val action = call.argument<String>("action")
                            val p = getSharedPreferences("rest_timer", MODE_PRIVATE)
                            if (action == "completeNotification") {
                                val notification = (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                                    .activeNotifications.single { it.id == RestTimerState.ONGOING }.notification
                                notification.actions.single { it.title.toString() == "セット完了" }.actionIntent.send()
                                result.success(null)
                                return@setMethodCallHandler
                            }
                            val notificationAction = when (action) {
                                "pauseNotification" -> "一時停止"
                                "resumeNotification" -> "再開"
                                "extendNotification" -> "+30秒"
                                else -> null
                            }
                            if (notificationAction != null) {
                                val notification = (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                                    .activeNotifications.single { it.id == RestTimerState.ONGOING }.notification
                                notification.actions.single { it.title.toString() == notificationAction }.actionIntent.send()
                                result.success(null)
                                return@setMethodCallHandler
                            }
                            if (action == "complete") {
                                RestTimerReceiver().onReceive(this, Intent(this, RestTimerReceiver::class.java)
                                    .setAction(WorkoutNotificationState.COMPLETE)
                                    .putExtra("timerId", call.argument<String>("timerId"))
                                    .putExtra("targetSetId", call.argument<String>("targetSetId")))
                                result.success(null)
                                return@setMethodCallHandler
                            }
                            RestTimerState.action(this, Intent(this, RestTimerReceiver::class.java)
                                .setAction(when (action) {
                                    "extend" -> RestTimerState.EXTEND
                                    "resume" -> RestTimerState.RESUME
                                    else -> RestTimerState.PAUSE
                                })
                                .putExtra("timerId", p.getString("timerId", "")))
                            result.success(null)
                        }
                    }
                    "debugRestAlarm" -> {
                        if (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE == 0) result.notImplemented()
                        else {
                            RestTimerReceiver().onReceive(this, Intent(this, RestTimerReceiver::class.java)
                                .putExtra("timerId", call.argument<String>("timerId"))
                                .putExtra("deadline", call.argument<Number>("deadline")?.toLong() ?: 0))
                            result.success(null)
                        }
                    }
                    "debugStatus" -> {
                        if (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE == 0) {
                            result.notImplemented()
                        } else {
                            val p = getSharedPreferences("rest_timer", MODE_PRIVATE)
                            fun display(views: android.widget.RemoteViews?): Map<String, Any> {
                                if (views == null) return emptyMap()
                                val view = views.apply(this, android.widget.FrameLayout(this))
                                val clock = view.findViewById<android.widget.Chronometer>(R.id.rest_clock)
                                val fallback = view.findViewById<android.widget.TextView>(R.id.rest_zero)
                                return mapOf(
                                    "clockVisible" to (clock.visibility == android.view.View.VISIBLE),
                                    "clockText" to clock.text.toString(),
                                    "baseRemainingMs" to (clock.base - android.os.SystemClock.elapsedRealtime()),
                                    "countdown" to clock.isCountDown,
                                    "fallbackVisible" to (fallback.visibility == android.view.View.VISIBLE),
                                    "fallbackText" to fallback.text.toString()
                                )
                            }
                            result.success(RestTimerDiagnostics.snapshot() + RestTimerFeedback.status(this) + mapOf(
                                "keyguardLocked" to (getSystemService(Context.KEYGUARD_SERVICE) as android.app.KeyguardManager).isKeyguardLocked,
                                "ongoingDetails" to (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).activeNotifications
                                    .filter { it.id == RestTimerState.ONGOING }.map { n -> mapOf(
                                        "actions" to (n.notification.actions?.map { it.title.toString() } ?: emptyList<String>()),
                                        "when" to n.notification.`when`,
                                        "showWhen" to n.notification.extras.getBoolean(android.app.Notification.EXTRA_SHOW_WHEN),
                                        "timeoutAfter" to (if (Build.VERSION.SDK_INT >= 26) n.notification.timeoutAfter else 0L),
                                        "compact" to display(n.notification.contentView),
                                        "expanded" to display(n.notification.bigContentView),
                                        "headsUp" to display(n.notification.headsUpContentView),
                                        "chronometer" to n.notification.extras.getBoolean(android.app.Notification.EXTRA_SHOW_CHRONOMETER),
                                        "countdown" to n.notification.extras.getBoolean("android.chronometerCountDown"),
                                        "requestedPromotion" to n.notification.extras.getBoolean("android.requestPromotedOngoing"),
                                        "promoted" to (Build.VERSION.SDK_INT >= 36 && n.notification.flags and android.app.Notification.FLAG_PROMOTED_ONGOING != 0)
                                    ) },
                                "playing" to RestTimerFeedback.isPlaying, "deadline" to p.getLong("deadline", 0),
                                "paused" to p.getBoolean("paused", false),
                                "remainingSeconds" to p.getInt("remainingSeconds", 0),
                                "timerId" to (p.getString("timerId", "") ?: ""),
                                "lastCompletionTimerId" to (p.getString("lastCompletionTimerId", "") ?: ""),
                                "lastCompletionAt" to p.getLong("lastCompletionAt", 0),
                                "delivered" to (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).activeNotifications.map { it.id }))
                        }
                    }
                    "requestExactAlarmPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !RestTimerState.exactAlarmAllowed(this)) {
                            try {
                                startActivity(Intent(android.provider.Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                                    android.net.Uri.parse("package:$packageName")))
                                result.success(true)
                            } catch (_: android.content.ActivityNotFoundException) { result.success(false) }
                        } else result.success(true)
                    }
                    "schedule" -> {
                        val seconds = call.argument<Int>("seconds") ?: 1
                        requestNotificationPermission()
                        RestTimerFeedback.stop(this)
                        val deadline = call.argument<Number>("endsAtMilliseconds")?.toLong()
                            ?: (System.currentTimeMillis() + seconds.coerceAtLeast(1) * 1000L)
                        RestTimerState.schedule(this, deadline, call.argument<String>("exerciseName") ?: "",
                            call.argument<Map<String, String>>("target")?.let { org.json.JSONObject(it) },
                            call.argument<Int>("restSeconds") ?: seconds)
                        result.success(null)
                    }
                    "cancel" -> {
                        RestTimerState.cancel(this, call.argument<Int>("remainingSeconds") ?: 0)
                        result.success(null)
                    }
                    "pause" -> result.success(RestTimerState.pause(this))
                    "resume" -> result.success(RestTimerState.resume(this))
                    "extend" -> result.success(RestTimerState.extend(this))
                    "completeIfDue" -> {
                        val deadline = call.argument<Number>("endsAtMilliseconds")?.toLong() ?: 0
                        result.success(deadline > 0 && RestTimerState.completeIfDue(this,
                            expectedDeadline = deadline, source = "flutter_deadline"))
                    }
                    "state" -> result.success(RestTimerState.snapshot(this))
                    "playCompletionFeedback" -> {
                        RestTimerFeedback.play(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, imageChannelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "deviceInfo") {
                    result.success(mapOf(
                        "os" to "Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})",
                        "device" to "${Build.MANUFACTURER} ${Build.MODEL}"
                    ))
                    return@setMethodCallHandler
                }
                if (call.method != "save") return@setMethodCallHandler result.notImplemented()
                val bytes = call.argument<ByteArray>("bytes")
                val fileName = call.argument<String>("fileName")
                if (bytes == null || fileName.isNullOrBlank()) {
                    result.error("invalid_arguments", "Image bytes and file name are required", null)
                    return@setMethodCallHandler
                }
                try {
                    saveWorkoutImage(bytes, fileName)
                    result.success(null)
                } catch (error: Exception) {
                    result.error("image_save_failed", error.localizedMessage, null)
                }
            }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 7342) RestTimerState.show(this)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        RestTimerState.onChanged = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onResume() {
        super.onResume()
        RestTimerFeedback.foreground = true
        RestTimerState.refreshDeadline(this)
        RestTimerState.show(this)
    }

    override fun onPause() {
        RestTimerFeedback.foreground = false
        super.onPause()
    }

    private fun saveWorkoutImage(bytes: ByteArray, fileName: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
                put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/SETKEEP")
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
            val uri = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("Could not create image")
            try {
                contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                    ?: throw IllegalStateException("Could not open image")
                values.clear()
                values.put(MediaStore.Images.Media.IS_PENDING, 0)
                contentResolver.update(uri, values, null, null)
            } catch (error: Exception) {
                contentResolver.delete(uri, null, null)
                throw error
            }
            return
        }

        val pictures = getExternalFilesDir(Environment.DIRECTORY_PICTURES)
            ?: throw IllegalStateException("Pictures directory unavailable")
        val directory = java.io.File(pictures, "SETKEEP").apply { mkdirs() }
        val file = java.io.File(directory, fileName)
        file.writeBytes(bytes)
        android.media.MediaScannerConnection.scanFile(
            this,
            arrayOf(file.absolutePath),
            arrayOf("image/png"),
            null
        )
    }

    private fun requestNotificationPermission() {
        if (!notificationPermissionRequested && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            notificationPermissionRequested = true
            requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                7342
            )
        }
    }
}
