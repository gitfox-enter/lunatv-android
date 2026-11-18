package org.moontechlab.selene;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.os.IBinder;

/**
 * Keeps the local LunaTV server running in the foreground, so Android does
 * not freeze the app (and with it the child process) once the screen is off.
 */
public final class LunaService extends Service {

    public static final String ACTION_START = "com.lunatv.android.action.START";
    public static final String ACTION_STOP = "com.lunatv.android.action.STOP";

    private static final String CHANNEL = "lunatv";
    private static final int NOTIFICATION_ID = 1;

    public static void start(Context ctx) {
        Intent intent = new Intent(ctx, LunaService.class).setAction(ACTION_START);
        ctx.startForegroundService(intent);
    }

    public static void stop(Context ctx) {
        Intent intent = new Intent(ctx, LunaService.class).setAction(ACTION_STOP);
        try {
            ctx.startService(intent);
        } catch (IllegalStateException e) {
            LunaGateway.stop();
        }
    }

    @Override
    public void onCreate() {
        super.onCreate();
        channel(this);
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        String action = intent == null ? ACTION_START : intent.getAction();
        if (ACTION_STOP.equals(action)) {
            LunaGateway.stop();
            stopForeground(STOP_FOREGROUND_REMOVE);
            stopSelf();
            return START_NOT_STICKY;
        }
        startForeground(NOTIFICATION_ID, notification(this));
        LunaGateway.start(this);
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        LunaGateway.stop();
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    private static void channel(Context ctx) {
        NotificationManager nm = ctx.getSystemService(NotificationManager.class);
        NotificationChannel channel = new NotificationChannel(
                CHANNEL,
                "LunaTV 服务",
                NotificationManager.IMPORTANCE_LOW);
        channel.setDescription("LunaTV 本地服务在后台运行");
        nm.createNotificationChannel(channel);
    }

    private Notification notification(Context ctx) {
        int flags = PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE;
        PendingIntent open = PendingIntent.getActivity(
                ctx, 0, new Intent(ctx, MainActivity.class), flags);
        PendingIntent stop = PendingIntent.getService(
                ctx, 1, new Intent(ctx, LunaService.class).setAction(ACTION_STOP), flags);
        String where = "127.0.0.1:" + LunaPrefs.port(ctx);
        return new Notification.Builder(ctx, CHANNEL)
                .setSmallIcon(android.R.drawable.stat_sys_download)
                .setContentTitle("LunaTV 正在运行")
                .setContentText(String.format("服务地址 %s", where))
                .setContentIntent(open)
                .setOngoing(true)
                .addAction(new Notification.Action.Builder(
                        null, "打开", open).build())
                .addAction(new Notification.Action.Builder(
                        null, "停止服务", stop).build())
                .build();
    }
}
