package com.github.veneraz.mihon

import android.os.Bundle
import android.content.Intent
import androidx.appcompat.app.AppCompatActivity
import androidx.preference.PreferenceFragmentCompat
import androidx.lifecycle.lifecycleScope
import eu.kanade.tachiyomi.source.ConfigurableSource
import eu.kanade.tachiyomi.source.preferenceKey
import kotlinx.coroutines.*

class MihonSettingsActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        supportActionBar?.setDisplayHomeAsUpEnabled(true)
        if (savedInstanceState == null) supportFragmentManager.beginTransaction()
            .replace(android.R.id.content, SettingsFragment()).commit()
    }
    override fun onDestroy() {
        if (isFinishing) MihonRuntime.active?.invalidate()
        super.onDestroy()
    }
    override fun onSupportNavigateUp(): Boolean { finish(); return true }
    class SettingsFragment : PreferenceFragmentCompat() {
        override fun onCreatePreferences(savedInstanceState: Bundle?, rootKey: String?) {
            val id = requireActivity().intent.getStringExtra("source") ?: return
            lifecycleScope.launch {
                try {
                    val runtime = MihonRuntime.active ?: MihonRuntime(requireContext().applicationContext)
                    val source = withContext(Dispatchers.IO) { runtime.configurable(id) }
                    preferenceManager.sharedPreferencesName = source.preferenceKey()
                    preferenceScreen = preferenceManager.createPreferenceScreen(requireContext())
                    source.setupPreferenceScreen(preferenceScreen)
                    requireActivity().title = source.name
                } catch (error: Exception) {
                    if (error is CancellationException) throw error
                    android.util.Log.e("Mihon", "Source settings failed", error)
                    android.widget.Toast.makeText(requireContext(), R.string.mihon_settings_error, android.widget.Toast.LENGTH_LONG).show()
                    requireActivity().finish()
                }
            }
        }
    }
}
