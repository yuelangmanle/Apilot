package com.example.api_manager

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.TextView

/**
 * 网关悬浮窗：在任意界面显示"网关运行中 · 端口 / 请求数"的小胶囊。
 *
 * 用途：安卓会冻结后台应用，前台服务能保活但用户看不到状态；
 * 悬浮窗让用户随时知道网关在跑（也可一键点开应用）。
 * 只在用户显式开启时显示（需要 SYSTEM_ALERT_WINDOW 权限）。
 */
class GatewayOverlay(private val context: Context) {

    companion object {
        private var instance: GatewayOverlay? = null
        var visible = false
            private set

        fun canShow(context: Context): Boolean =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(context)

        fun overlayPermissionIntent(context: Context): Intent = Intent(
            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
            Uri.parse("package:${context.packageName}")
        )

        fun show(context: Context, port: Int, requests: Int) {
            if (!canShow(context)) return
            instance?.let { it.update(port, requests); visible = true; return }
            instance = GatewayOverlay(context).apply {
                attach(port, requests)
            }
            visible = true
        }

        fun update(port: Int, requests: Int) {
            instance?.update(port, requests)
        }

        fun hide() {
            instance?.detach()
            instance = null
            visible = false
        }
    }

    private var view: View? = null
    private var textView: TextView? = null
    private var params: WindowManager.LayoutParams? = null

    private fun attach(port: Int, requests: Int) {
        val manager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val label = TextView(context).apply {
            setTextColor(Color.WHITE)
            textSize = 12f
            setPadding(28, 14, 28, 14)
            setBackgroundColor(Color.parseColor("#CC2F6FED"))
            text = buildText(port, requests)
        }
        textView = label
        val layoutParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            },
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 24
            y = 220
        }
        params = layoutParams
        // 可拖动 + 单击回到应用。
        var downX = 0f
        var downY = 0f
        var startX = 0
        var startY = 0
        var moved = false
        label.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.rawX
                    downY = event.rawY
                    startX = layoutParams.x
                    startY = layoutParams.y
                    moved = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = (event.rawX - downX).toInt()
                    val dy = (event.rawY - downY).toInt()
                    if (kotlin.math.abs(dx) > 12 || kotlin.math.abs(dy) > 12) moved = true
                    layoutParams.x = startX + dx
                    layoutParams.y = startY + dy
                    try {
                        manager.updateViewLayout(label, layoutParams)
                    } catch (_: Exception) {
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!moved) {
                        try {
                            val intent = Intent(context, MainActivity::class.java).apply {
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                                    Intent.FLAG_ACTIVITY_CLEAR_TOP
                            }
                            context.startActivity(intent)
                        } catch (_: Exception) {
                        }
                    }
                    true
                }
                else -> false
            }
        }
        try {
            manager.addView(label, layoutParams)
            view = label
        } catch (_: Exception) {
            view = null
        }
    }

    private fun update(port: Int, requests: Int) {
        textView?.text = buildText(port, requests)
    }

    private fun buildText(port: Int, requests: Int): String =
        "Apilot 网关 :$port · 请求 $requests"

    private fun detach() {
        val label = view ?: return
        try {
            val manager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
            manager.removeView(label)
        } catch (_: Exception) {
        }
        view = null
        textView = null
    }
}
