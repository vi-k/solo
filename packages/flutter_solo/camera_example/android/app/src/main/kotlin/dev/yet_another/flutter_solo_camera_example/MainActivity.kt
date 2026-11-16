package dev.yet_another.flutter_solo_camera_example

import android.content.Context
import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The app's activity, which also answers `CameraLights` of the Dart side:
 * the `camera` plugin cannot say which cameras have a flash unit.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LIGHTS)
            .setMethodCallHandler { call, result ->
                if (call.method != "lights") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                // The name of a camera of `camera_android_camerax` is its
                // id in Camera2.
                val names = call.arguments<List<String>>() ?: emptyList()
                val manager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
                val answer = HashMap<String, Map<String, Boolean>>()
                for (name in names) {
                    val unit = try {
                        manager.getCameraCharacteristics(name)
                            .get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
                    } catch (error: IllegalArgumentException) {
                        continue
                    } catch (error: CameraAccessException) {
                        continue
                    }
                    // The flash unit is the torch as well.
                    answer[name] = mapOf("torch" to unit, "flash" to unit)
                }
                result.success(answer)
            }
    }

    private companion object {
        const val LIGHTS = "dev.yet_another.flutter_solo_camera_example/lights"
    }
}
