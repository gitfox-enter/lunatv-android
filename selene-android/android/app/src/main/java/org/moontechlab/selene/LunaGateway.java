package org.moontechlab.selene;

import android.content.Context;
import android.util.Log;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

/**
 * The bundled LunaTV server: Bun runs the Next.js standalone build as a child
 * process of this app.
 *
 * <p>Two pieces ship inside the APK, the same way magpie-android carries its
 * Go gateway and its Bun:
 *
 * <ul>
 *   <li>{@code lib/<abi>/libbun.so} — Bun built for Android (NDK r27c). An APK
 *       can only carry an executable under {@code lib/<abi>/}, and the one
 *       directory Android lets an app exec from is its native library
 *       directory.</li>
 *   <li>{@code assets/lunatv.zip} — the Next.js standalone build (server.js,
 *       its trimmed node_modules, the compiled app and static assets). It is
 *       unpacked once into the app's files directory before the first run and
 *       whenever the app version changes.</li>
 * </ul>
 *
 * <p>The server stores everything client-side (LunaTV's localstorage mode), so
 * no Redis or other storage backend is needed.
 */
public final class LunaGateway {

    private static final String TAG = "LunaGateway";
    private static final String BUN = "libbun.so";
    private static final String LOG_NAME = "luna.log";
    private static final long LOG_MAX_BYTES = 2L * 1024 * 1024;

    private static final Object LOCK = new Object();
    private static final AtomicBoolean stopping = new AtomicBoolean(false);
    private static Process process;
    private static int restarts;
    private static volatile String extractState = "";

    private LunaGateway() {
    }

    public static boolean isRunning() {
        synchronized (LOCK) {
            return process != null && process.isAlive();
        }
    }

    /** Human-readable extraction state for the waiting screen, "" when done. */
    public static String extractState() {
        return extractState;
    }

    /** Starts the server unless it is already up. */
    public static void start(Context ctx) {
        Context app = ctx.getApplicationContext();
        synchronized (LOCK) {
            if (process != null && process.isAlive()) {
                return;
            }
            stopping.set(false);
            // Extraction writes tens of thousands of small files on the first
            // run; keep it off the main thread so the service never ANRs.
            Thread t = new Thread(() -> {
                try {
                    ensureUnpacked(app);
                    spawn(app);
                } catch (Exception e) {
                    logLine(app, "启动失败: " + e);
                }
            }, "luna-start");
            t.setDaemon(true);
            t.start();
        }
    }

    /** Stops the server and leaves it stopped (no watchdog restart). */
    public static void stop() {
        Process p;
        synchronized (LOCK) {
            stopping.set(true);
            p = process;
            process = null;
        }
        if (p == null) {
            return;
        }
        p.destroy();
        try {
            if (!p.waitFor(3, TimeUnit.SECONDS)) {
                p.destroyForcibly();
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    /** Whether something accepts connections on host:port right now. */
    public static boolean portOpen(String host, int port, int timeoutMs) {
        try (Socket socket = new Socket()) {
            socket.connect(new InetSocketAddress(host, port), timeoutMs);
            return true;
        } catch (IOException e) {
            return false;
        }
    }

    /** The URL the WebView loads, e.g. http://127.0.0.1:3000. */
    public static String pageUrl(Context ctx) {
        return "http://127.0.0.1:" + LunaPrefs.port(ctx);
    }

    public static File logFile(Context ctx) {
        return new File(dir(ctx, "logs"), LOG_NAME);
    }

    public static void logLine(Context ctx, String line) {
        String stamp = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(new Date());
        // Also to logcat: the log file lives in the app's private dir which
        // adb cannot read (non-debuggable release), but logcat can.
        Log.i(TAG, line);
        try (OutputStream out = new FileOutputStream(logFile(ctx), true)) {
            out.write((stamp + "  " + line + "\n").getBytes("UTF-8"));
        } catch (IOException e) {
            Log.w(TAG, "could not append to the log", e);
        }
    }

    // ------------------------------------------------------------ unpacking

    /**
     * Unpacks assets/lunatv.zip over files/lunatv when the app's version
     * differs from the one unpacked last time, then writes the marker.
     */
    private static void ensureUnpacked(Context ctx) throws IOException {
        String version;
        try {
            version = ctx.getPackageManager()
                    .getPackageInfo(ctx.getPackageName(), 0).versionName;
        } catch (Exception e) {
            version = "1";
        }
        long zipSize;
        try (InputStream probe = ctx.getAssets().open("lunatv.zip")) {
            zipSize = probe.available();
        }
        // The marker includes the zip size: assets can change without an app
        // version bump, and install -r keeps app data (and the stale marker).
        String marker = version + ":" + zipSize;
        if (LunaPrefs.unpackedVersion(ctx).equals(marker)) {
            return;
        }
        File root = dir(ctx, "lunatv");
        extractState = "正在准备运行环境…";
        deleteTree(root);
        extractState = "正在解压运行环境…";
        root.mkdirs();
        try (InputStream in = ctx.getAssets().open("lunatv.zip");
             ZipInputStream zip = new ZipInputStream(in)) {
            byte[] buf = new byte[1 << 16];
            ZipEntry entry;
            long done = 0;
            while ((entry = zip.getNextEntry()) != null) {
                File out = new File(root, entry.getName());
                if (entry.isDirectory()) {
                    out.mkdirs();
                    continue;
                }
                File parent = out.getParentFile();
                if (parent != null) {
                    parent.mkdirs();
                }
                try (OutputStream os = new FileOutputStream(out)) {
                    int n;
                    while ((n = zip.read(buf)) > 0) {
                        os.write(buf, 0, n);
                        done += n;
                    }
                }
                if (done % (8L << 20) < (1 << 16)) {
                    extractState = String.format(Locale.US,
                            "正在解压运行环境… %.0f MB", done / 1048576.0);
                }
            }
        }
        // Bun refuses to run a server file others may have written over; the
        // extracted tree is ours alone, but an explicit no-exec bit on the
        // script files keeps Android's judgement clean.
        LunaPrefs.setUnpackedVersion(ctx, marker);
        extractState = "正在启动本地服务…";
        logLine(ctx, "LunaTV " + version + " 解压完成 -> " + root);
    }

    private static void deleteTree(File f) {
        if (f == null || !f.exists()) {
            return;
        }
        File[] children = f.listFiles();
        if (children != null) {
            for (File c : children) {
                deleteTree(c);
            }
        }
        f.delete();
    }

    // ------------------------------------------------------------ process

    private static void spawn(Context ctx) {
        File bin = new File(ctx.getApplicationInfo().nativeLibraryDir, BUN);
        if (!bin.isFile()) {
            logLine(ctx, "Bun 二进制缺失: " + bin);
            return;
        }
        File home = dir(ctx, "lunatv");
        File server = new File(home, "server.js");
        if (!server.isFile()) {
            logLine(ctx, "server.js 缺失: " + server);
            return;
        }
        File logs = dir(ctx, "logs");
        File log = logFile(ctx);
        if (log.length() > LOG_MAX_BYTES) {
            File old = new File(logs, LOG_NAME + ".1");
            old.delete();
            log.renameTo(old);
        }

        int port = LunaPrefs.port(ctx);

        // A server from an earlier launch can still own the port (the service
        // outlives the activity). Spawning another Bun then dies instantly
        // with "address in use" and the watchdog loops for ever, so reuse it.
        if (portOpen("127.0.0.1", port, 300)) {
            logLine(ctx, "127.0.0.1:" + port + " 已在服务，复用既有进程");
            return;
        }

        List<String> cmd = new ArrayList<>();
        cmd.add(bin.getAbsolutePath());
        cmd.add("run");
        cmd.add(server.getAbsolutePath());

        ProcessBuilder pb = new ProcessBuilder(cmd);
        pb.directory(home);
        pb.redirectErrorStream(true);
        Map<String, String> env = pb.environment();
        env.put("HOME", dir(ctx, "home").getAbsolutePath());
        env.put("XDG_CONFIG_HOME", dir(ctx, "config").getAbsolutePath());
        env.put("XDG_CACHE_HOME", dir(ctx, "cache").getAbsolutePath());
        env.put("XDG_DATA_HOME", dir(ctx, "data").getAbsolutePath());
        env.put("XDG_STATE_HOME", dir(ctx, "state").getAbsolutePath());
        env.put("TMPDIR", dir(ctx, "tmp").getAbsolutePath());
        env.put("TMP", dir(ctx, "tmp").getAbsolutePath());
        env.put("PATH", ctx.getApplicationInfo().nativeLibraryDir + ":/system/bin:/system/xbin:/product/bin");
        env.put("LANG", "C.UTF-8");
        env.put("NODE_ENV", "production");
        env.put("PORT", String.valueOf(port));
        // 0.0.0.0 rather than loopback: the point of the bundled server is that
        // any device on the same Wi-Fi can open it in a browser. The owner
        // password still gates every request.
        env.put("HOSTNAME", "0.0.0.0");
        // File-backed storage: the app is single-user and there is no Redis or
        // WebView localStorage to hold favourites, records or the admin config.
        env.put("NEXT_PUBLIC_STORAGE_TYPE", "file");
        env.put("DATA_DIR", dir(ctx, "lunatv-data").getAbsolutePath());
        // Without a PASSWORD LunaTV redirects every request to /warning; the
        // shell generates one per install and signs the WebView in with the
        // matching cookie (MainActivity), so the user never sees it.
        env.put("PASSWORD", LunaPrefs.password(ctx));
        // Logging in with this name + the generated password hits LunaTV's
        // owner branch, so the app (and anyone on the LAN who types it) gets
        // admin rights over sources and site settings.
        env.put("USERNAME", LunaPrefs.ADMIN_USER);
        // Android's seccomp filter refuses a syscall Bun's JIT makes; with the
        // JIT off the server runs fine (the same mitigation magpie-android
        // ships for its plugin installs).
        env.put("BUN_JSC_useJIT", "0");
        env.put("BUN_JSC_useConcurrentJIT", "0");
        env.remove("LD_PRELOAD");
        env.remove("LD_LIBRARY_PATH");
        logLine(ctx, "启动 Bun: " + bin + " run server.js (PORT=" + port + ")");

        try {
            Process p = pb.start();
            synchronized (LOCK) {
                process = p;
            }
            logLine(ctx, "started 127.0.0.1:" + port);
            pump(p, log);
            watch(ctx, p);
        } catch (IOException e) {
            logLine(ctx, "could not start the server: " + e);
            Log.w(TAG, "could not start the server", e);
        }
    }

    /** The child's output, straight into the log file the menu shows. */
    private static void pump(Process p, File log) {
        Thread thread = new Thread(() -> {
            try (OutputStream out = new FileOutputStream(log, true);
                 InputStream in = p.getInputStream()) {
                byte[] buffer = new byte[8192];
                int n;
                while ((n = in.read(buffer)) >= 0) {
                    out.write(buffer, 0, n);
                    out.flush();
                }
            } catch (IOException ignored) {
                // the process ended; the watchdog says so
            }
        }, "luna-log");
        thread.setDaemon(true);
        thread.start();
    }

    /** Restarts the server when it exits on its own, backing off as it repeats. */
    private static void watch(Context ctx, Process p) {
        Thread thread = new Thread(() -> {
            int code;
            try {
                code = p.waitFor();
            } catch (InterruptedException e) {
                return;
            }
            synchronized (LOCK) {
                if (process != p) {
                    return; // stopped on purpose
                }
                process = null;
            }
            if (stopping.get()) {
                logLine(ctx, "服务已停止 (exit " + code + ")");
                return;
            }
            // Exit 1 while the port still answers means another instance is
            // serving; restarting forever only burns CPU and floods the log.
            if (code != 0 && portOpen("127.0.0.1", LunaPrefs.port(ctx), 400)) {
                logLine(ctx, "端口仍有服务应答，停止重启");
                return;
            }
            restarts++;
            long backoff = Math.min(30_000L, 2_000L * restarts);
            logLine(ctx, "服务退出 (exit " + code + ")，" + backoff / 1000 + " 秒后重启 (第 " + restarts + " 次)");
            try {
                Thread.sleep(backoff);
            } catch (InterruptedException e) {
                return;
            }
            Context app = ctx.getApplicationContext();
            synchronized (LOCK) {
                if (!stopping.get() && (process == null)) {
                    spawn(app);
                }
            }
        }, "luna-watch");
        thread.setDaemon(true);
        thread.start();
    }

    private static File dir(Context ctx, String name) {
        File d = new File(ctx.getFilesDir(), name);
        d.mkdirs();
        return d;
    }
}
