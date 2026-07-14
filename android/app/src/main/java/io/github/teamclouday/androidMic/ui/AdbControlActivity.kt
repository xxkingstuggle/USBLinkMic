package io.github.teamclouday.androidMic.ui

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.util.Log
import androidx.core.content.ContextCompat
import io.github.teamclouday.androidMic.domain.service.ForegroundService
import io.github.teamclouday.androidMic.domain.service.START_MIC_ACTION
import io.github.teamclouday.androidMic.domain.service.STOP_MIC_ACTION

/**
 * ADB-only entry point for microphone control.
 *
 * The manifest requires android.permission.DUMP, which is held by the ADB shell but not by
 * ordinary third-party apps. Keeping this separate from the launcher activity prevents another
 * app from starting microphone capture by sending an explicit intent to MainActivity.
 */
class AdbControlActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val action = intent?.action
        if (action != START_MIC_ACTION && action != STOP_MIC_ACTION) {
            finish()
            return
        }

        if (action == START_MIC_ACTION && !hasRecordAudioPermission()) {
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQUEST_RECORD_AUDIO)
            return
        }

        dispatchControlIntent(intent, action)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_RECORD_AUDIO) return

        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            dispatchControlIntent(intent, START_MIC_ACTION)
        } else {
            Log.w(TAG, "Microphone start cancelled because RECORD_AUDIO was denied")
            launchMainActivity()
            finish()
        }
    }

    private fun hasRecordAudioPermission() =
        ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) ==
                PackageManager.PERMISSION_GRANTED

    private fun dispatchControlIntent(source: Intent, action: String) {
        try {
            startForegroundService(buildServiceIntent(source, action))
            launchMainActivity()
        } catch (e: Exception) {
            Log.e(TAG, "ADB control failed for $action", e)
        } finally {
            finish()
        }
    }

    private fun launchMainActivity() {
        startActivity(
            Intent(this, MainActivity::class.java).addFlags(
                Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            )
        )
    }

    private fun buildServiceIntent(source: Intent, action: String) =
        Intent(this, ForegroundService::class.java).apply {
            this.action = action
            if (action == START_MIC_ACTION) {
                copyIntExtra(source, "port")
                copyIntExtra(source, "sampleRate")
                copyIntExtra(source, "channelCount")
                copyStringExtra(source, "audioFormat")
                copyStringExtra(source, "audioSource")
            }
        }

    private fun Intent.copyIntExtra(source: Intent, key: String) {
        if (source.hasExtra(key)) putExtra(key, source.getIntExtra(key, 0))
    }

    private fun Intent.copyStringExtra(source: Intent, key: String) {
        source.getStringExtra(key)?.let { putExtra(key, it) }
    }

    companion object {
        private const val TAG = "AdbControlActivity"
        private const val REQUEST_RECORD_AUDIO = 1001
    }
}
