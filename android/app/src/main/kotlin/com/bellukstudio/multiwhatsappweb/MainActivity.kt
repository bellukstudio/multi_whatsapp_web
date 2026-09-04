package com.bellukstudio.multiwhatsappweb

import com.bellukstudio.multiwhatsappweb.nativewebview.SlotEmbedViewFactory
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "multiwhatsappweb/slot_embed",
                SlotEmbedViewFactory(flutterEngine.dartExecutor.binaryMessenger),
            )
    }
}