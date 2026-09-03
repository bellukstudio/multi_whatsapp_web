package com.bellukstudio.multi_whatsapp_web

import com.bellukstudio.multi_whatsapp_web.nativewebview.SlotEmbedViewFactory
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "multi_whatsapp_web/slot_embed",
                SlotEmbedViewFactory(flutterEngine.dartExecutor.binaryMessenger),
            )
    }
}