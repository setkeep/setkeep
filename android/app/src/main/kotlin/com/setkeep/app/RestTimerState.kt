package com.setkeep.app

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.widget.RemoteViews
import android.view.View
import java.util.UUID
import org.json.JSONObject

/** One persisted wall-clock deadline, shared by Flutter and notification actions. */
object RestTimerState {
    const val ONGOING = 7340
    const val CHANNEL = "rest_timer_running"
    const val PAUSE = "setkeep.rest.PAUSE"
    const val RESUME = "setkeep.rest.RESUME"
    // Old notifications may still deliver STOP after an app update.
    const val STOP = "setkeep.rest.STOP"
    const val EXTEND = "setkeep.rest.EXTEND"
    var onChanged: (() -> Unit)? = null
    private fun prefs(c: Context) = c.getSharedPreferences("rest_timer", Context.MODE_PRIVATE)
    private fun manager(c: Context) = c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    private fun alarm(c: Context) = c.getSystemService(Context.ALARM_SERVICE) as AlarmManager
    private val handler = Handler(Looper.getMainLooper())
    private var deadlineTask: Runnable? = null
    private fun alarmIntent(c: Context, id: String? = null, deadline: Long = 0) = PendingIntent.getBroadcast(c, 7341,
        Intent(c, RestTimerReceiver::class.java).putExtra("timerId", id).putExtra("deadline", deadline),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    private fun clearDeadlineTask() {
        deadlineTask?.let { handler.removeCallbacks(it) }
        deadlineTask = null
    }

    fun exactAlarmAllowed(c: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarm(c).canScheduleExactAlarms()

    fun refreshDeadline(c: Context) {
        val p = prefs(c)
        val id = p.getString("timerId", null) ?: return
        val deadline = p.getLong("deadline", 0)
        if (deadline > 0) armDeadline(c, id, deadline)
    }

    private fun armDeadline(c: Context, id: String, deadline: Long) {
        clearDeadlineTask()
        if (deadline <= System.currentTimeMillis()) {
            completeIfDue(c, id, deadline, "schedule_due")
            return
        }
        val pending = alarmIntent(c, id, deadline)
        var exact = exactAlarmAllowed(c)
        if (exact) {
            try {
                alarm(c).setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, deadline, pending)
            } catch (_: SecurityException) {
                // Permission can be revoked between the check and scheduling.
                exact = false
            }
        }
        if (!exact) alarm(c).setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, deadline, pending)
        RestTimerDiagnostics.set("alarmSchedulingMode", if (exact) "exact" else "inexact_permission_required")
        // One deadline callback, not a per-second notification update. AlarmManager
        // remains the background/process-death fallback; both enter the same claim.
        deadlineTask = object : Runnable {
            override fun run() {
                val current = prefs(c)
                if (current.getString("timerId", null) != id || current.getLong("deadline", 0) != deadline) return
                val remaining = deadline - System.currentTimeMillis()
                if (remaining > 0) {
                    // Handler uses uptime, deadline uses wall time. Millisecond
                    // rounding/clock adjustment must not drop an early callback.
                    handler.postDelayed(this, remaining.coerceAtLeast(10))
                } else completeIfDue(c.applicationContext, id, deadline, "native_deadline")
            }
        }
        handler.postDelayed(deadlineTask!!, (deadline - System.currentTimeMillis()).coerceAtLeast(1))
    }

    fun schedule(c: Context, deadline: Long, name: String = "", target: JSONObject? = null, restSeconds: Int = 90) {
        clearDeadlineTask()
        RestTimerFeedback.stop(c)
        val id = UUID.randomUUID().toString()
        check(prefs(c).edit().putLong("deadline", deadline).putInt("remainingSeconds", 0)
            .putBoolean("paused", false).putString("exerciseName", name).putString("timerId", id).commit())
        manager(c).cancel(7341)
        WorkoutNotificationState.arm(c, target, id, restSeconds)
        armDeadline(c, id, deadline)
        RestTimerDiagnostics.log(c, id, "scheduled deadline=$deadline")
        show(c)
    }

    fun cancel(c: Context, remaining: Int = 0) {
        WorkoutNotificationState.invalidate(c)
        clearDeadlineTask()
        RestTimerDiagnostics.log(c, prefs(c).getString("timerId", null), "cancelled")
        RestTimerDiagnostics.set("lastCancellationAt", System.currentTimeMillis())
        prefs(c).edit().remove("deadline").remove("timerId").remove("paused")
            .putInt("remainingSeconds", remaining.coerceAtLeast(0)).apply()
        alarm(c).cancel(alarmIntent(c))
        RestTimerFeedback.stop(c)
        manager(c).cancel(ONGOING)
        manager(c).cancel(7341)
    }

    @Synchronized
    fun pause(c: Context, expectedId: String? = null): Boolean {
        val p = prefs(c)
        val id = p.getString("timerId", null) ?: return false
        if (expectedId != null && expectedId != id) return false
        val deadline = p.getLong("deadline", 0)
        if (deadline <= 0) return false
        if (deadline <= System.currentTimeMillis()) {
            completeIfDue(c, id, deadline, "pause_due")
            return false
        }
        val remaining = ((deadline - System.currentTimeMillis() + 999) / 1000).toInt()
        if (!p.edit().remove("deadline").putBoolean("paused", true)
            .putInt("remainingSeconds", remaining).commit()) return false
        clearDeadlineTask()
        alarm(c).cancel(alarmIntent(c))
        show(c)
        onChanged?.invoke()
        return true
    }

    @Synchronized
    fun resume(c: Context, expectedId: String? = null): Boolean {
        val p = prefs(c)
        val id = p.getString("timerId", null) ?: return false
        if (expectedId != null && expectedId != id || !p.getBoolean("paused", false)) return false
        val remaining = p.getInt("remainingSeconds", 0)
        if (remaining <= 0) return false
        val deadline = System.currentTimeMillis() + remaining * 1000L
        if (!p.edit().putLong("deadline", deadline).putBoolean("paused", false)
            .putInt("remainingSeconds", 0).commit()) return false
        armDeadline(c, id, deadline)
        show(c)
        onChanged?.invoke()
        return true
    }

    @Synchronized
    fun extend(c: Context, expectedId: String? = null): Boolean {
        val p = prefs(c)
        val id = p.getString("timerId", null) ?: return false
        if (expectedId != null && expectedId != id) return false
        if (p.getBoolean("paused", false)) {
            val remaining = p.getInt("remainingSeconds", 0)
            if (remaining <= 0 || !p.edit().putInt("remainingSeconds", remaining + 30).commit()) return false
        } else {
            val deadline = p.getLong("deadline", 0)
            if (deadline <= System.currentTimeMillis()) {
                completeIfDue(c, id, deadline, "extend_due")
                return false
            }
            val extended = deadline + 30_000
            if (!p.edit().putLong("deadline", extended).commit()) return false
            alarm(c).cancel(alarmIntent(c))
            armDeadline(c, id, extended)
        }
        show(c)
        onChanged?.invoke()
        return true
    }

    /** All callers run on the main looper; persisted claim also survives recreation. */
    @Synchronized
    fun completeIfDue(c: Context, expectedId: String? = null, expectedDeadline: Long = 0,
                      source: String = "state_sync"): Boolean {
        val p = prefs(c)
        val id = p.getString("timerId", null)
        val deadline = p.getLong("deadline", 0)
        if (id == null || deadline == 0L ||
            (expectedId != null && expectedId != id) ||
            (expectedDeadline != 0L && expectedDeadline != deadline)) {
            RestTimerDiagnostics.log(c, expectedId, "stale alarm ignored source=$source")
            RestTimerDiagnostics.set("lastIgnoredEvent", "stale_alarm:$source")
            return false
        }
        if (System.currentTimeMillis() < deadline) return false
        RestTimerDiagnostics.log(c, id, "deadline valid source=$source")
        if (p.getString("lastCompletionTimerId", null) == id) return false
        val at = System.currentTimeMillis()
        // Claim before output. Duplicate Alarm/Dart/resume events cannot replay it.
        if (!p.edit().remove("deadline").remove("timerId").remove("paused").putInt("remainingSeconds", 0)
            .putString("lastCompletionTimerId", id).putLong("lastCompletionAt", at)
            .putLong("lastCompletionDeadline", deadline).commit()) {
            RestTimerDiagnostics.set("lastSoundError", "completion claim persistence failed")
            return false
        }
        clearDeadlineTask()
        alarm(c).cancel(alarmIntent(c))
        if (WorkoutNotificationState.valid(c, id) == null) manager(c).cancel(ONGOING)
        RestTimerDiagnostics.increment("completionCount")
        RestTimerDiagnostics.log(c, id, "completion claimed")
        RestTimerReceiver.deliverCompletion(c, id)
        onChanged?.invoke()
        return true
    }

    fun snapshot(c: Context): Map<String, Any> {
        completeIfDue(c)
        val p = prefs(c)
        val deadline = p.getLong("deadline", 0)
        val pending = WorkoutNotificationState.pending(c)
        val target = listOf("sessionId", "exerciseInstanceId", "previousSetId", "targetSetId", "exerciseName", "setNumber")
            .associateWith { pending?.optString(it) ?: "" }
        return mapOf("exactAlarmAllowed" to exactAlarmAllowed(c), "target" to target, "timerId" to (p.getString("timerId", "") ?: ""),
            "phase" to (if (p.getBoolean("paused", false) && p.getString("timerId", null) != null) "paused"
                        else if (deadline > 0) "running" else "finished"),
            "lastCompletionTimerId" to (p.getString("lastCompletionTimerId", "") ?: ""),
            "lastCompletionAt" to p.getLong("lastCompletionAt", 0),
            "lastCompletionDeadline" to p.getLong("lastCompletionDeadline", 0), "endsAtMilliseconds" to deadline, "remainingSeconds" to p.getInt("remainingSeconds", 0),
            "exerciseName" to (p.getString("exerciseName", "") ?: ""))
    }

    fun action(c: Context, intent: Intent): Boolean {
        if (intent.action != PAUSE && intent.action != STOP && intent.action != RESUME && intent.action != EXTEND) return false
        val p = prefs(c)
        if (intent.getStringExtra("timerId") != p.getString("timerId", null)) return true
        when (intent.action) {
            PAUSE, STOP -> pause(c, p.getString("timerId", null))
            RESUME -> resume(c, p.getString("timerId", null))
            EXTEND -> extend(c, p.getString("timerId", null))
        }
        return true
    }

    private fun completeIntent(c: Context, id: String, target: JSONObject) = PendingIntent.getBroadcast(c, 7345,
        Intent(c, RestTimerReceiver::class.java).setAction(WorkoutNotificationState.COMPLETE)
            .setData(android.net.Uri.parse("setkeep://rest-action/$id"))
            .putExtra("timerId", id).putExtra("targetSetId", target.getString("targetSetId")),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    /** System Chronometer ticks in SystemUI; Flutter never posts once per second.
     * Custom layout intentionally prioritizes legibility over promoted-chip eligibility. */
    private fun timerLayout(c: Context, builder: Notification.Builder, deadline: Long,
                            target: JSONObject?, complete: PendingIntent?, name: String,
                            pausedRemaining: Int = 0) {
        if (Build.VERSION.SDK_INT < 24) return
        fun view(expanded: Boolean): RemoteViews {
            val layout = RemoteViews(c.packageName, if (expanded) R.layout.rest_notification_expanded else R.layout.rest_notification_compact)
            val paused = pausedRemaining > 0
            val running = !paused && deadline > System.currentTimeMillis()
            val countdown = running && exactAlarmAllowed(c)
            layout.setViewVisibility(R.id.rest_clock, if (countdown) View.VISIBLE else View.GONE)
            layout.setViewVisibility(R.id.rest_zero, if (countdown) View.GONE else View.VISIBLE)
            if (running && !countdown) layout.setTextViewText(R.id.rest_zero,
                android.text.format.DateFormat.format("HH:mm:ss", deadline))
            if (paused) layout.setTextViewText(R.id.rest_zero,
                "%02d:%02d".format(pausedRemaining / 60, pausedRemaining % 60))
            layout.setChronometer(R.id.rest_clock,
                SystemClock.elapsedRealtime() + (deadline - System.currentTimeMillis()).coerceAtLeast(0), null, countdown)
            layout.setChronometerCountDown(R.id.rest_clock, true)
            val detail = target?.optString("exerciseName")?.takeIf { it.isNotBlank() } ?: name
            val number = target?.optString("setNumber")?.takeIf { it.isNotBlank() }
            layout.setTextViewText(R.id.rest_detail, detail)
            layout.setTextViewText(R.id.rest_next, number?.let { if (expanded) "次：${it}セット目" else "次：$it" } ?: "休憩")
            if (expanded) layout.setTextViewText(R.id.rest_label,
                if (paused) "一時停止中" else if (running && !countdown) "終了予定（通知が遅れる場合があります）" else if (running) "休憩タイマー" else "休憩終了")
            else {
                layout.setViewVisibility(R.id.rest_complete, if (complete == null) View.GONE else View.VISIBLE)
                if (complete != null) layout.setOnClickPendingIntent(R.id.rest_complete, complete)
            }
            return layout
        }
        builder.setStyle(Notification.DecoratedCustomViewStyle())
            .setCustomContentView(view(false)).setCustomBigContentView(view(true))
            .setCustomHeadsUpContentView(view(false))
    }

    fun show(c: Context) {
        val p = prefs(c)
        val deadline = p.getLong("deadline", 0)
        val paused = p.getBoolean("paused", false) && p.getString("timerId", null) != null
        val pausedRemaining = if (paused) p.getInt("remainingSeconds", 0) else 0
        if (!paused && deadline <= System.currentTimeMillis()) {
            if (deadline > 0) completeIfDue(c, source = "display_resume")
            val id = p.getString("lastCompletionTimerId", "") ?: ""
            if (WorkoutNotificationState.valid(c, id) != null) {
                if (manager(c).activeNotifications.none { it.id == ONGOING }) showReady(c, id)
            } else manager(c).cancel(ONGOING)
            return
        }
        if (Build.VERSION.SDK_INT >= 26) {
            manager(c).createNotificationChannel(NotificationChannel(CHANNEL, "休憩タイマー実行中", NotificationManager.IMPORTANCE_LOW).apply {
                setSound(null, null); enableVibration(false); lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            })
        }
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(c, CHANNEL) else Notification.Builder(c)
        val open = PendingIntent.getActivity(c, ONGOING, Intent(c, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        fun actionIntent(action: String, code: Int) = PendingIntent.getBroadcast(c, code,
            Intent(c, RestTimerReceiver::class.java).setAction(action)
                .setData(android.net.Uri.parse("setkeep://rest-action/${p.getString("timerId", "")}/$action"))
                .putExtra("timerId", p.getString("timerId", "")),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        builder.setSmallIcon(R.mipmap.ic_launcher).setContentTitle(if (paused) "休憩タイマー（一時停止中）" else "休憩タイマー")
            .setContentText("${if (paused) "残り" else "残り時間"} · ${p.getString("exerciseName", "")}").setContentIntent(open)
            .setStyle(Notification.BigTextStyle().bigText("休憩タイマー — 残り時間\n${p.getString("exerciseName", "")}"))
            .setCategory(Notification.CATEGORY_STATUS).setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true).setOnlyAlertOnce(true).setWhen(deadline).setShowWhen(!paused).setUsesChronometer(!paused && exactAlarmAllowed(c))
            .addAction(Notification.Action.Builder(null, if (paused) "再開" else "一時停止",
                actionIntent(if (paused) RESUME else PAUSE, 7343)).build())
            .addAction(Notification.Action.Builder(null, "+30秒", actionIntent(EXTEND, 7344)).build())
        val id = p.getString("timerId", "") ?: ""
        val target = WorkoutNotificationState.valid(c, id)
        val complete = target?.let { completeIntent(c, id, it) }
        if (complete != null) builder.addAction(Notification.Action.Builder(null, "セット完了", complete).build())
        timerLayout(c, builder, deadline, target, complete, p.getString("exerciseName", "") ?: "", pausedRemaining)
        if (Build.VERSION.SDK_INT >= 24 && !paused && exactAlarmAllowed(c)) builder.setChronometerCountDown(true)
        // SystemUI must never continue through zero into a negative timer.
        // Completion independently posts the ready/action notification.
        if (Build.VERSION.SDK_INT >= 26 && !paused) {
            builder.setTimeoutAfter((deadline - System.currentTimeMillis()).coerceAtLeast(1))
        }
        try { manager(c).notify(ONGOING, builder.build()) } catch (_: SecurityException) { }
    }
    fun readyNotification(c: Context, id: String, alert: Boolean = false): Notification? {
        val target = WorkoutNotificationState.valid(c, id) ?: return null
        val channel = if (alert) RestTimerFeedback.CHANNEL else CHANNEL
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(c, channel) else Notification.Builder(c)
        if (alert && Build.VERSION.SDK_INT < 26) builder.setSound(RestTimerFeedback.sound(c)).setVibrate(RestTimerFeedback.vibration)
        val complete = completeIntent(c, id, target)
        val open = PendingIntent.getActivity(c, ONGOING, Intent(c, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        builder.setSmallIcon(R.mipmap.ic_launcher).setContentTitle("休憩終了")
            .setContentText("次のセットを行ってください")
            .setStyle(Notification.BigTextStyle().bigText("次のセットを行ってください"))
            .setContentIntent(open).setOngoing(true).setOnlyAlertOnce(!alert)
            .setVisibility(Notification.VISIBILITY_PUBLIC).setUsesChronometer(false).setShowWhen(false)
            .addAction(Notification.Action.Builder(null, "セット完了", complete).build())
        timerLayout(c, builder, 0, target, complete, target.optString("exerciseName"))
        return builder.build()
    }
    fun showReady(c: Context, id: String) {
        val notification = readyNotification(c, id) ?: return
        try { manager(c).notify(ONGOING, notification) } catch (_: SecurityException) { }
    }

}
