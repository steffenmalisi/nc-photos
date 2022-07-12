package com.nkming.nc_photos.plugin

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class ImageProcessorChannelHandler(context: Context) :
	MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
	companion object {
		const val METHOD_CHANNEL = "${K.LIB_ID}/image_processor_method"

		private const val TAG = "ImageProcessorChannelHandler"
	}

	override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
		when (call.method) {
			"zeroDce" -> {
				try {
					zeroDce(
						call.argument("fileUrl")!!,
						call.argument("headers"),
						call.argument("filename")!!,
						call.argument("maxWidth")!!,
						call.argument("maxHeight")!!,
						call.argument("iteration")!!,
						result
					)
				} catch (e: Throwable) {
					logE(TAG, "Uncaught exception", e)
					result.error("systemException", e.toString(), null)
				}
			}

			"deepLab3Portrait" -> {
				try {
					deepLab3Portrait(
						call.argument("fileUrl")!!,
						call.argument("headers"),
						call.argument("filename")!!,
						call.argument("maxWidth")!!,
						call.argument("maxHeight")!!,
						call.argument("radius")!!,
						result
					)
				} catch (e: Throwable) {
					logE(TAG, "Uncaught exception", e)
					result.error("systemException", e.toString(), null)
				}
			}

			"esrgan" -> {
				try {
					esrgan(
						call.argument("fileUrl")!!,
						call.argument("headers"),
						call.argument("filename")!!,
						call.argument("maxWidth")!!,
						call.argument("maxHeight")!!,
						result
					)
				} catch (e: Throwable) {
					logE(TAG, "Uncaught exception", e)
					result.error("systemException", e.toString(), null)
				}
			}

			"arbitraryStyleTransfer" -> {
				try {
					arbitraryStyleTransfer(
						call.argument("fileUrl")!!,
						call.argument("headers"),
						call.argument("filename")!!,
						call.argument("maxWidth")!!,
						call.argument("maxHeight")!!,
						call.argument("styleUri")!!,
						call.argument("weight")!!,
						result
					)
				} catch (e: Throwable) {
					logE(TAG, "Uncaught exception", e)
					result.error("systemException", e.toString(), null)
				}
			}

			else -> result.notImplemented()
		}
	}

	override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
		eventSink = events
	}

	override fun onCancel(arguments: Any?) {
		eventSink = null
	}

	private fun zeroDce(
		fileUrl: String, headers: Map<String, String>?, filename: String,
		maxWidth: Int, maxHeight: Int, iteration: Int,
		result: MethodChannel.Result
	) = method(
		fileUrl, headers, filename, maxWidth, maxHeight,
		ImageProcessorService.METHOD_ZERO_DCE, result, onIntent = {
			it.putExtra(ImageProcessorService.EXTRA_ITERATION, iteration)
		}
	)

	private fun deepLab3Portrait(
		fileUrl: String, headers: Map<String, String>?, filename: String,
		maxWidth: Int, maxHeight: Int, radius: Int, result: MethodChannel.Result
	) = method(
		fileUrl, headers, filename, maxWidth, maxHeight,
		ImageProcessorService.METHOD_DEEP_LAP_PORTRAIT, result, onIntent = {
			it.putExtra(ImageProcessorService.EXTRA_RADIUS, radius)
		}
	)

	private fun esrgan(
		fileUrl: String, headers: Map<String, String>?, filename: String,
		maxWidth: Int, maxHeight: Int, result: MethodChannel.Result
	) = method(
		fileUrl, headers, filename, maxWidth, maxHeight,
		ImageProcessorService.METHOD_ESRGAN, result
	)

	private fun arbitraryStyleTransfer(
		fileUrl: String, headers: Map<String, String>?, filename: String,
		maxWidth: Int, maxHeight: Int, styleUri: String, weight: Float,
		result: MethodChannel.Result
	) = method(
		fileUrl, headers, filename, maxWidth, maxHeight,
		ImageProcessorService.METHOD_ARBITRARY_STYLE_TRANSFER, result,
		onIntent = {
			it.putExtra(
				ImageProcessorService.EXTRA_STYLE_URI, Uri.parse(styleUri)
			)
			it.putExtra(ImageProcessorService.EXTRA_WEIGHT, weight)
		}
	)

	private fun method(
		fileUrl: String, headers: Map<String, String>?, filename: String,
		maxWidth: Int, maxHeight: Int, method: String,
		result: MethodChannel.Result, onIntent: ((Intent) -> Unit)? = null
	) {
		val intent = Intent(context, ImageProcessorService::class.java).apply {
			putExtra(ImageProcessorService.EXTRA_METHOD, method)
			putExtra(ImageProcessorService.EXTRA_FILE_URL, fileUrl)
			putExtra(
				ImageProcessorService.EXTRA_HEADERS,
				headers?.let { HashMap(it) })
			putExtra(ImageProcessorService.EXTRA_FILENAME, filename)
			putExtra(ImageProcessorService.EXTRA_MAX_WIDTH, maxWidth)
			putExtra(ImageProcessorService.EXTRA_MAX_HEIGHT, maxHeight)
			onIntent?.invoke(this)
		}
		ContextCompat.startForegroundService(context, intent)
		result.success(null)
	}

	private val context = context
	private var eventSink: EventChannel.EventSink? = null
}
