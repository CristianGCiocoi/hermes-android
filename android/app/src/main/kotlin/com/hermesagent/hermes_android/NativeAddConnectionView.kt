package com.hermesagent.hermes_android

import android.content.Context
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.view.View
import android.widget.ImageButton
import android.widget.ImageView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

internal const val NATIVE_ADD_CONNECTION_VIEW_TYPE = "hermes/native_add_connection"
private const val CHANNEL_PREFIX = "hermes/native_add_connection"

internal class NativeAddConnectionViewFactory(
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        NativeAddConnectionView(context, viewId, messenger)
}

private class NativeAddConnectionView(
    context: Context,
    viewId: Int,
    messenger: BinaryMessenger,
) : PlatformView {
    private val channel = MethodChannel(messenger, "$CHANNEL_PREFIX/$viewId")
    private var flutterReady = false
    private var pendingPress = false
    private val button = ImageButton(context).apply {
        id = R.id.hermes_connection_add
        contentDescription = context.getString(
            R.string.hermes_connection_add_content_description,
        )
        isClickable = true
        isEnabled = true
        isFocusable = true
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
        setImageResource(android.R.drawable.ic_input_add)
        setColorFilter(Color.BLACK)
        scaleType = ImageView.ScaleType.CENTER
        background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(Color.rgb(212, 175, 55))
        }
        elevation = 6f * resources.displayMetrics.density
        setPadding(
            (16f * resources.displayMetrics.density).toInt(),
            (16f * resources.displayMetrics.density).toInt(),
            (16f * resources.displayMetrics.density).toInt(),
            (16f * resources.displayMetrics.density).toInt(),
        )
        setOnClickListener {
            if (flutterReady) {
                emitPressed()
            } else {
                // Coalesce taps received before Flutter installs its handler.
                pendingPress = true
            }
        }
    }

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "ready") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            flutterReady = true
            result.success(null)
            if (pendingPress) {
                pendingPress = false
                emitPressed()
            }
        }
    }

    private fun emitPressed() {
        channel.invokeMethod("pressed", null)
    }

    override fun getView(): View = button

    override fun dispose() {
        button.setOnClickListener(null)
        channel.setMethodCallHandler(null)
    }
}
