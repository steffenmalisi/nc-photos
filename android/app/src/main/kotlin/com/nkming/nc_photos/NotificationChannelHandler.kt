package com.nkming.nc_photos

import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.max

/*
 * Show notification on device
 *
 * Methods:
 * fun notifyItemDownloadSuccessful(fileUri: String, mimeType: String): Unit
 */
class NotificationChannelHandler(activity: Activity)
		: MethodChannel.MethodCallHandler {
	companion object {
		const val CHANNEL = "com.nkming.nc_photos/notification"

		private const val DOWNLOAD_CHANNEL_ID = "download"
		private const val DOWNLOAD_NOTIFICATION_ID = 1
	}

	init {
		createDownloadChannel(activity)
	}

	override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
		if (call.method == "notifyItemDownloadSuccessful") {
			try {
				notifyItemDownloadSuccessful(call.argument<String>("fileUri")!!,
						call.argument<String>("mimeType")!!, result)
			} catch (e: Throwable) {
				result.error("systemException", e.toString(), null)
			}
		} else {
			result.notImplemented()
		}
	}

	private fun notifyItemDownloadSuccessful(fileUri: String, mimeType: String,
			result: MethodChannel.Result) {
		val uriStr = fileUri
		val uri = Uri.parse(uriStr)
		val openIntent = Intent().apply {
			action = Intent.ACTION_VIEW
			setDataAndType(uri, mimeType)
			addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
			addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
		}
		val openPendingIntent = PendingIntent.getActivity(_context, 0,
				openIntent, PendingIntent.FLAG_UPDATE_CURRENT)

		val shareIntent = Intent().apply {
			action = Intent.ACTION_SEND
			putExtra(Intent.EXTRA_STREAM, uri)
			type = mimeType
			addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
			addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
		}
		val shareChooser = Intent.createChooser(shareIntent, _context.getString(
				R.string.download_successful_notification_action_share_chooser))
		val sharePendingIntent = PendingIntent.getActivity(_context, 1,
				shareChooser, PendingIntent.FLAG_UPDATE_CURRENT)

		val builder = NotificationCompat.Builder(_context, DOWNLOAD_CHANNEL_ID)
				.setSmallIcon(R.drawable.baseline_download_white_18)
				.setTicker(_context.getString(
						R.string.download_successful_notification_title))
				.setContentTitle(_context.getString(
						R.string.download_successful_notification_title))
				.setContentText(_context.getString(
						R.string.download_successful_notification_text))
				.setWhen(System.currentTimeMillis())
				.setContentIntent(openPendingIntent)
				.addAction(0, _context.getString(
						R.string.download_successful_notification_action_share),
						sharePendingIntent)
				.setPriority(NotificationCompat.PRIORITY_HIGH)
				.setSound(RingtoneManager.getDefaultUri(
						RingtoneManager.TYPE_NOTIFICATION))
				.setOnlyAlertOnce(false)
				.setAutoCancel(true)
				.setLocalOnly(true)

		// show preview if available
		val preview = if (mimeType.startsWith("image/"))
				loadNotificationImage(uri) else null;
		if (preview != null) {
			builder.setStyle(NotificationCompat.BigPictureStyle()
					.bigPicture(loadNotificationImage(uri)))
		}

		with(NotificationManagerCompat.from(_context)) {
			notify(DOWNLOAD_NOTIFICATION_ID, builder.build())
		}
	}

	private fun loadNotificationImage(fileUri: Uri): Bitmap? {
		try {
			val resolver = _context.applicationContext.contentResolver
			resolver.openFileDescriptor(fileUri, "r").use { pfd ->
				val metaOpts = BitmapFactory.Options().apply {
					inJustDecodeBounds = true
				}
				BitmapFactory.decodeFileDescriptor(pfd!!.fileDescriptor, null,
						metaOpts)
				val longSide = max(metaOpts.outWidth, metaOpts.outHeight)
				val opts = BitmapFactory.Options().apply {
					// just a preview in the panel, useless to be in high res
					inSampleSize = longSide / 720
				}
				return BitmapFactory.decodeFileDescriptor(pfd.fileDescriptor,
						null, opts)
			}
		} catch (e: Throwable) {
			Log.e("NotificationChannelHandler::loadNotificationImage",
					"Failed generating preview image", e)
			return null
		}
	}

	private fun createDownloadChannel(context: Context) {
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
			val name = context.getString(
					R.string.download_notification_channel_name)
			val descriptionStr = context.getString(
					R.string.download_notification_channel_description)
			val channel = NotificationChannel(DOWNLOAD_CHANNEL_ID, name,
					NotificationManager.IMPORTANCE_HIGH).apply {
						description = descriptionStr
					}

			val manager = context.getSystemService(Context.NOTIFICATION_SERVICE)
					as NotificationManager
			manager.createNotificationChannel(channel)
		}
	}

	private val _activity = activity
	private val _context get() = _activity
}