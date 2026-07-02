package io.github.teamclouday.androidMic

import android.content.Context

interface AppModule {
    fun appPreferences(): AppPreferences
}

class AppModuleImpl(context: Context) : AppModule {
    private val _prefs by lazy { AppPreferences(context.applicationContext) }
    override fun appPreferences(): AppPreferences = _prefs
}
