package com.signify.hue.flutterreactiveble

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result

class ReactiveBlePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var pluginController: PluginController? = null
    private var methodChannel: MethodChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val channel = MethodChannel(binding.binaryMessenger, "flutter_reactive_ble_method")
        channel.setMethodCallHandler(this)
        methodChannel = channel
        val controller = PluginController()
        controller.initialize(binding.binaryMessenger, binding.applicationContext)
        pluginController = controller
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        pluginController?.deinitialize()
        pluginController = null
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result,
    ) {
        val controller = pluginController
        if (controller == null) {
            result.error("not_attached", "ReactiveBlePlugin is not attached to an engine", null)
            return
        }
        controller.execute(call, result)
    }
}
