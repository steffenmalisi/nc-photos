package com.nkming.nc_photos.plugin.image_processor

import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import com.nkming.nc_photos.plugin.BitmapResizeMethod
import com.nkming.nc_photos.plugin.BitmapUtil
import com.nkming.nc_photos.plugin.ImageFilter
import com.nkming.nc_photos.plugin.use

class ImageFilterProcessor(
	context: Context, maxWidth: Int, maxHeight: Int, filters: List<ImageFilter>
) {
	companion object {
		const val TAG = "ImageFilterProcessor"
	}

	fun apply(imageUri: Uri): Bitmap {
		var img = BitmapUtil.loadImage(
			context, imageUri, maxWidth, maxHeight, BitmapResizeMethod.FIT,
			isAllowSwapSide = true, shouldUpscale = false,
			shouldFixOrientation = true
		).use {
			Rgba8Image(TfLiteHelper.bitmapToRgba8Array(it), it.width, it.height)
		}

		for (f in filters) {
			img = f.apply(img)
		}
		return img.toBitmap()
	}

	private val context = context
	private val maxWidth = maxWidth
	private val maxHeight = maxHeight
	private val filters = filters
}
