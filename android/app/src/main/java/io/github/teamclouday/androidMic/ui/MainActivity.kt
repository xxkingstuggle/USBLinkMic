package io.github.teamclouday.androidMic.ui

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.core.content.ContextCompat
import io.github.teamclouday.androidMic.AndroidMicApp
import io.github.teamclouday.androidMic.ui.home.HomeScreen
import io.github.teamclouday.androidMic.ui.theme.USBLinkMicTheme

class MainActivity : ComponentActivity() {
    val vm: MainViewModel by viewModels()

    private val requestPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        val allGranted = permissions.values.all { it }
        if (allGranted) {
            vm.requestedConnect?.let { vm.connect(it) }
            vm.requestedConnect = null
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            USBLinkMicTheme {
                HomeScreen(vm, ::requestPermissions)
            }
        }
    }

    override fun onStart() {
        super.onStart()
        vm.handlerServiceResponse()
        (application as AndroidMicApp).bindService()
    }

    override fun onStop() {
        super.onStop()
        (application as AndroidMicApp).unBindService()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.getBooleanExtra("ForegroundServiceBound", false)) {
            vm.bindCheck()
        }
    }

    fun requestPermissions(callback: () -> Unit) {
        val needed = mutableListOf<String>()
        if (!hasPermission(Manifest.permission.RECORD_AUDIO)) needed.add(Manifest.permission.RECORD_AUDIO)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !hasPermission(Manifest.permission.POST_NOTIFICATIONS))
            needed.add(Manifest.permission.POST_NOTIFICATIONS)
        if (needed.isEmpty()) {
            callback()
        } else {
            vm.requestedConnect = callback
            requestPermissionLauncher.launch(needed.toTypedArray())
        }
    }

    private fun hasPermission(permission: String): Boolean =
        ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED
}
