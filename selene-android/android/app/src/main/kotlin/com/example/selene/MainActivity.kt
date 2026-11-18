package org.moontechlab.selene

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.Inet4Address
import java.net.NetworkInterface

/**
 * Flutter shell around a bundled LunaTV server.
 *
 * The Dart side never asks the user for a server address or a password: both
 * come from LunaPrefs through the `lunatv/server` channel, while unpacking and
 * process management live in LunaGateway.
 */
class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Start (or reuse) the server as soon as the app opens: the UI waits on
        // the port before it leaves its splash screen.
        LunaService.start(this)
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInfo" -> result.success(
                        mapOf(
                            "url" to "http://127.0.0.1:${LunaPrefs.port(this)}",
                            "username" to LunaPrefs.ADMIN_USER,
                            "password" to LunaPrefs.password(this),
                            "port" to LunaPrefs.port(this),
                            "lanIp" to lanIp(),
                        )
                    )

                    "setPort" -> {
                        val port = call.argument<Int>("port") ?: 0
                        if (port !in 1024..65535) {
                            result.error("bad_port", "端口需在 1024-65535 之间", null)
                        } else {
                            LunaPrefs.setPort(this, port)
                            LunaGateway.stop()
                            LunaService.start(this)
                            result.success(LunaPrefs.port(this))
                        }
                    }

                    "lanAddress" -> result.success(lanIp())

                    // The first launch unpacks ~18k files before the port
                    // answers; the splash screen shows this so a slow start
                    // never looks like a black-screen hang.
                    "getProgress" -> result.success(
                        mapOf(
                            "state" to LunaGateway.extractState(),
                            "ready" to (LunaGateway.isRunning() ||
                                    LunaGateway.portOpen("127.0.0.1", LunaPrefs.port(this), 150))
                        )
                    )

                    "openAdmin" -> {
                        // The admin console is LunaTV's own web UI; the browser
                        // gives it room for editing sources and site settings.
                        val url = "http://127.0.0.1:${LunaPrefs.port(this)}/admin"
                        startActivity(Intent(Intent.ACTION_VIEW, android.net.Uri.parse(url)))
                        result.success(url)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun lanIp(): String? {
        try {
            for (nif in NetworkInterface.getNetworkInterfaces()) {
                if (!nif.isUp || nif.isLoopback) continue
                for (addr in nif.inetAddresses) {
                    if (addr is Inet4Address && !addr.isLoopbackAddress) {
                        return addr.hostAddress
                    }
                }
            }
        } catch (_: Exception) {
        }
        return null
    }

    private companion object {
        const val CHANNEL = "lunatv/server"
    }
}
