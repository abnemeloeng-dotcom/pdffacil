package com.pdffacil.app

import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.util.Base64
import android.webkit.JavascriptInterface
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.webkit.WebViewAssetLoader
import java.io.File

class MainActivity : AppCompatActivity() {

    private lateinit var web: WebView
    @Volatile private var pendente: String? = null
    private var chooserCallback: ValueCallback<Array<Uri>>? = null

    private val chooser = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { r ->
        chooserCallback?.onReceiveValue(
            WebChromeClient.FileChooserParams.parseResult(r.resultCode, r.data)
        )
        chooserCallback = null
    }

    inner class Ponte {
        @JavascriptInterface
        fun pegarNome(): String {
            val n = pendente ?: ""
            pendente = null
            return n
        }

        @JavascriptInterface
        fun salvar(b64: String, nome: String): Boolean {
            return try {
                val bytes = Base64.decode(b64, Base64.DEFAULT)
                val v = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, nome)
                    put(MediaStore.Downloads.MIME_TYPE, "application/pdf")
                    put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                }
                val u = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, v)!!
                contentResolver.openOutputStream(u)!!.use { it.write(bytes) }
                true
            } catch (e: Exception) {
                false
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val loader = WebViewAssetLoader.Builder()
            .addPathHandler("/assets/", WebViewAssetLoader.AssetsPathHandler(this))
            .addPathHandler("/pdf/", WebViewAssetLoader.PathHandler { _ ->
                val f = File(cacheDir, "atual.pdf")
                if (f.exists()) {
                    WebResourceResponse("application/pdf", null, f.inputStream()).apply {
                        responseHeaders = mapOf("Cache-Control" to "no-store")
                    }
                } else null
            })
            .build()

        web = WebView(this)
        web.setBackgroundColor(0xFF14171A.toInt())
        web.settings.javaScriptEnabled = true
        web.settings.domStorageEnabled = true
        web.settings.allowFileAccess = false
        web.settings.setSupportZoom(false)
        web.settings.builtInZoomControls = false
        web.addJavascriptInterface(Ponte(), "Android")

        web.webViewClient = object : WebViewClient() {
            override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? =
                loader.shouldInterceptRequest(request.url)
        }

        web.webChromeClient = object : WebChromeClient() {
            override fun onShowFileChooser(
                w: WebView,
                cb: ValueCallback<Array<Uri>>,
                p: FileChooserParams
            ): Boolean {
                chooserCallback?.onReceiveValue(null)
                chooserCallback = cb
                return try {
                    chooser.launch(p.createIntent())
                    true
                } catch (e: Exception) {
                    chooserCallback = null
                    false
                }
            }
        }

        setContentView(web)

        ViewCompat.setOnApplyWindowInsetsListener(web) { v, insets ->
            val b = insets.getInsets(
                WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout()
            )
            v.setPadding(b.left, b.top, b.right, b.bottom)
            insets
        }

        if (savedInstanceState == null) tratar(intent)
        web.loadUrl("https://appassets.androidplatform.net/assets/index.html")
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        tratar(intent)
    }

    @Suppress("DEPRECATION")
    private fun uriDoSend(i: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= 33) i.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        else i.getParcelableExtra(Intent.EXTRA_STREAM)

    private fun nomeDe(uri: Uri): String {
        try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    val n = c.getString(0)
                    if (!n.isNullOrBlank()) return n
                }
            }
        } catch (_: Exception) {
        }
        return uri.lastPathSegment?.substringAfterLast('/') ?: "arquivo.pdf"
    }

    private fun tratar(i: Intent?) {
        if (i == null) return
        val uri: Uri = when (i.action) {
            Intent.ACTION_VIEW -> i.data
            Intent.ACTION_SEND -> uriDoSend(i)
            else -> null
        } ?: return

        Thread {
            try {
                val nome = nomeDe(uri)
                contentResolver.openInputStream(uri)!!.use { inp ->
                    File(cacheDir, "atual.pdf").outputStream().use { out -> inp.copyTo(out) }
                }
                runOnUiThread {
                    pendente = nome
                    web.evaluateJavascript("window.abrirDoApp&&window.abrirDoApp()", null)
                }
            } catch (e: Exception) {
                runOnUiThread {
                    Toast.makeText(this, "Não consegui ler o PDF.", Toast.LENGTH_LONG).show()
                }
            }
        }.start()
    }
}
