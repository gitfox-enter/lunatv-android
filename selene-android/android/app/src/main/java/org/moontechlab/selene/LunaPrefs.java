package org.moontechlab.selene;

import android.content.Context;
import android.content.SharedPreferences;

import java.security.SecureRandom;

/**
 * Small preference facade: the local server's port, its PASSWORD (LunaTV
 * redirects everything to a warning page when it is unset), and the marker
 * that says which build of the bundled LunaTV zip has been unpacked.
 */
public final class LunaPrefs {

    private static final String FILE = "luna";
    private static final String KEY_PORT = "port";
    private static final String KEY_PASSWORD = "password";
    private static final String KEY_UNPACKED_VERSION = "unpackedVersion";

    private static final int DEFAULT_PORT = 3000;

    /** Login name that maps to LunaTV's owner role in single-user mode. */
    public static final String ADMIN_USER = "admin";

    private LunaPrefs() {
    }

    private static SharedPreferences prefs(Context ctx) {
        return ctx.getSharedPreferences(FILE, Context.MODE_PRIVATE);
    }

    /** The port the local Next.js server listens on. */
    public static int port(Context ctx) {
        return prefs(ctx).getInt(KEY_PORT, DEFAULT_PORT);
    }

    public static void setPort(Context ctx, int port) {
        prefs(ctx).edit().putInt(KEY_PORT, port).apply();
    }

    /**
     * The server's PASSWORD, generated once per install. The user never sees
     * it: the WebView is signed in programmatically with the matching auth
     * cookie (see MainActivity), and the server binds 127.0.0.1 only.
     */
    public static String password(Context ctx) {
        SharedPreferences p = prefs(ctx);
        String v = p.getString(KEY_PASSWORD, "");
        if (v.isEmpty()) {
            v = newPassword();
            p.edit().putString(KEY_PASSWORD, v).apply();
        }
        return v;
    }

    private static String newPassword() {
        String alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
        SecureRandom r = new SecureRandom();
        StringBuilder sb = new StringBuilder(32);
        for (int i = 0; i < 32; i++) {
            sb.append(alphabet.charAt(r.nextInt(alphabet.length())));
        }
        return sb.toString();
    }

    /** The LunaTV version currently unpacked under files/lunatv, "" for none. */
    public static String unpackedVersion(Context ctx) {
        return prefs(ctx).getString(KEY_UNPACKED_VERSION, "");
    }

    public static void setUnpackedVersion(Context ctx, String version) {
        prefs(ctx).edit().putString(KEY_UNPACKED_VERSION, version).apply();
    }
}
