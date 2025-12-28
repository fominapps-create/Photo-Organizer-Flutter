package com.example.photo_organizer_flutter

import android.database.ContentObserver
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    private val PHOTO_CHANGES_CHANNEL = "com.example.photo_organizer/photo_changes"
    private var photoObserver: ContentObserver? = null
    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, PHOTO_CHANGES_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    registerPhotoObserver()
                }

                override fun onCancel(arguments: Any?) {
                    unregisterPhotoObserver()
                    eventSink = null
                }
            })
    }

    private fun registerPhotoObserver() {
        photoObserver = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean, uri: Uri?) {
                eventSink?.success(mapOf(
                    "type" to "change",
                    "uri" to uri?.toString()
                ))
            }
        }
        
        contentResolver.registerContentObserver(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            true,
            photoObserver!!
        )
    }

    private fun unregisterPhotoObserver() {
        photoObserver?.let {
            contentResolver.unregisterContentObserver(it)
        }
        photoObserver = null
    }

    override fun onDestroy() {
        unregisterPhotoObserver()
        super.onDestroy()
    }
}
