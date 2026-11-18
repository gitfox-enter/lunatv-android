package org.moontechlab.selene;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.widget.Toast;

/**
 * Starts the local server again after boot or an app update, so playback
 * history and the page come up without a manual launch.
 */
public final class BootReceiver extends BroadcastReceiver {

    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent == null ? "" : intent.getAction();
        if (!Intent.ACTION_BOOT_COMPLETED.equals(action)
                && !Intent.ACTION_MY_PACKAGE_REPLACED.equals(action)) {
            return;
        }
        LunaService.start(context);
        Toast.makeText(context, "LunaTV 服务已随开机启动",
                Toast.LENGTH_SHORT).show();
    }
}
