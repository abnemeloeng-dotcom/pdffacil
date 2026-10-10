set -e
ROOT="$PWD"
mkdir -p android/app/src/main/java/br/pdffacil/app android/app/src/main/assets android/app/src/main/res/drawable-nodpi
cd android

cat > settings.gradle <<'EOF'
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = 'PDFFacil'
include ':app'
EOF

cat > build.gradle <<'EOF'
plugins {
    id 'com.android.application' version '8.5.2' apply false
}
EOF

cat > gradle.properties <<'EOF'
org.gradle.jvmargs=-Xmx2g
android.useAndroidX=false
EOF

cat > app/build.gradle <<'EOF'
plugins {
    id 'com.android.application'
}
android {
    namespace 'br.pdffacil.app'
    compileSdk 34
    defaultConfig {
        applicationId 'br.pdffacil.app'
        minSdk 29
        targetSdk 34
        versionCode 1
        versionName '1.0'
    }
    signingConfigs {
        release {
            storeFile file('../pdffacil.p12')
            storeType 'pkcs12'
            storePassword 'pdffacil'
            keyAlias 'pdffacil'
            keyPassword 'pdffacil'
        }
    }
    buildTypes {
        release {
            minifyEnabled false
            signingConfig signingConfigs.release
        }
    }
    lint {
        checkReleaseBuilds false
        abortOnError false
    }
}
EOF

cat > app/src/main/AndroidManifest.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="PDFFácil"
        android:icon="@drawable/ic_launcher"
        android:allowBackup="false"
        android:theme="@android:style/Theme.DeviceDefault.NoActionBar">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTask"
            android:windowSoftInputMode="adjustResize"
            android:configChanges="orientation|screenSize|keyboardHidden|smallestScreenSize|screenLayout|density|uiMode">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="content" />
                <data android:scheme="file" />
                <data android:mimeType="application/pdf" />
            </intent-filter>
        </activity>
    </application>
</manifest>
EOF

cat > app/src/main/java/br/pdffacil/app/MainActivity.java <<'EOF'
package br.pdffacil.app;

import android.app.Activity;
import android.content.ContentValues;
import android.content.Intent;
import android.database.Cursor;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.os.Environment;
import android.provider.MediaStore;
import android.provider.OpenableColumns;
import android.util.Base64;
import android.webkit.JavascriptInterface;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import org.json.JSONObject;
import java.io.ByteArrayInputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.HashMap;
import java.util.Map;

public class MainActivity extends Activity {
    private static final String HOST = "appassets.androidplatform.net";
    private WebView web;
    private volatile Uri currentUri;
    private volatile String pendingName = "";
    private volatile boolean pageReady = false;
    private ValueCallback<Uri[]> chooser;
    private OutputStream saveOut;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        getWindow().setStatusBarColor(Color.parseColor("#14171A"));
        getWindow().setNavigationBarColor(Color.parseColor("#14171A"));
        web = new WebView(this);
        web.setBackgroundColor(Color.parseColor("#1D2126"));
        setContentView(web);
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setAllowFileAccess(false);
        web.addJavascriptInterface(new Bridge(), "AndroidApp");
        web.setWebViewClient(new WebViewClient() {
            @Override
            public WebResourceResponse shouldInterceptRequest(WebView v, WebResourceRequest r) {
                return intercept(r.getUrl());
            }
            @Override
            public boolean shouldOverrideUrlLoading(WebView v, WebResourceRequest r) {
                return true;
            }
            @Override
            public void onPageFinished(WebView v, String url) {
                pageReady = true;
            }
        });
        web.setWebChromeClient(new WebChromeClient() {
            @Override
            public boolean onShowFileChooser(WebView w, ValueCallback<Uri[]> cb, FileChooserParams p) {
                if (chooser != null) chooser.onReceiveValue(null);
                chooser = cb;
                try {
                    startActivityForResult(p.createIntent(), 1);
                } catch (Exception e) {
                    chooser = null;
                    return false;
                }
                return true;
            }
        });
        handleIntent(getIntent());
        web.loadUrl("https://" + HOST + "/index.html");
    }

    @Override
    protected void onNewIntent(Intent i) {
        super.onNewIntent(i);
        setIntent(i);
        handleIntent(i);
        if (pageReady) deliver();
    }

    @Override
    protected void onActivityResult(int req, int res, Intent data) {
        super.onActivityResult(req, res, data);
        if (req == 1 && chooser != null) {
            chooser.onReceiveValue(WebChromeClient.FileChooserParams.parseResult(res, data));
            chooser = null;
        }
    }

    private void handleIntent(Intent i) {
        if (i == null) return;
        if (Intent.ACTION_VIEW.equals(i.getAction()) && i.getData() != null) {
            currentUri = i.getData();
            pendingName = nameOf(currentUri);
        }
    }

    private void deliver() {
        String n = pendingName;
        pendingName = "";
        if (n.isEmpty()) return;
        web.evaluateJavascript("window.abrirDoApp&&window.abrirDoApp(" + JSONObject.quote(n) + ")", null);
    }

    private String nameOf(Uri u) {
        String n = null;
        try (Cursor c = getContentResolver().query(u, null, null, null, null)) {
            if (c != null && c.moveToFirst()) {
                int i = c.getColumnIndex(OpenableColumns.DISPLAY_NAME);
                if (i >= 0) n = c.getString(i);
            }
        } catch (Exception e) {
        }
        if (n == null || n.isEmpty()) n = u.getLastPathSegment();
        if (n == null || n.isEmpty()) n = "documento.pdf";
        return n;
    }

    private String mime(String name) {
        if (name.endsWith(".html")) return "text/html";
        if (name.endsWith(".js")) return "application/javascript";
        if (name.endsWith(".css")) return "text/css";
        if (name.endsWith(".png")) return "image/png";
        return "application/octet-stream";
    }

    private WebResourceResponse reply(int code, String type, InputStream in) {
        Map<String, String> h = new HashMap<>();
        h.put("Cache-Control", "no-store");
        String reason = code == 200 ? "OK" : (code == 404 ? "Not Found" : "Forbidden");
        String enc = type.startsWith("text/") || type.endsWith("javascript") ? "utf-8" : null;
        return new WebResourceResponse(type, enc, code, reason, h, in);
    }

    private WebResourceResponse empty(int code) {
        return reply(code, "text/plain", new ByteArrayInputStream(new byte[0]));
    }

    private WebResourceResponse intercept(Uri u) {
        if (!HOST.equals(u.getHost())) return empty(403);
        String p = u.getPath();
        if (p == null || p.equals("/")) p = "/index.html";
        try {
            if (p.equals("/current.pdf")) {
                Uri src = currentUri;
                if (src == null) return empty(404);
                InputStream in = getContentResolver().openInputStream(src);
                if (in == null) return empty(404);
                return reply(200, "application/pdf", in);
            }
            String name = p.substring(1);
            if (name.contains("..")) return empty(404);
            return reply(200, mime(name), getAssets().open(name));
        } catch (Exception e) {
            return empty(404);
        }
    }

    public class Bridge {
        @JavascriptInterface
        public String pending() {
            String n = pendingName;
            pendingName = "";
            return n;
        }

        @JavascriptInterface
        public boolean saveBegin(String name) {
            try {
                ContentValues v = new ContentValues();
                v.put(MediaStore.Downloads.DISPLAY_NAME, name);
                v.put(MediaStore.Downloads.MIME_TYPE, "application/pdf");
                v.put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS);
                Uri u = getContentResolver().insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, v);
                if (u == null) return false;
                saveOut = getContentResolver().openOutputStream(u);
                return saveOut != null;
            } catch (Exception e) {
                return false;
            }
        }

        @JavascriptInterface
        public boolean saveChunk(String b64) {
            try {
                saveOut.write(Base64.decode(b64, Base64.DEFAULT));
                return true;
            } catch (Exception e) {
                return false;
            }
        }

        @JavascriptInterface
        public boolean saveEnd() {
            try {
                if (saveOut != null) saveOut.close();
                saveOut = null;
                return true;
            } catch (Exception e) {
                return false;
            }
        }
    }
}
EOF

cp "$ROOT/index.html" app/src/main/assets/index.html
cp "$ROOT/icon-512.png" app/src/main/res/drawable-nodpi/ic_launcher.png
base64 -d > pdffacil.p12 <<'EOF'
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
eRNMAgInEA==
EOF
echo "Projeto Android montado."
