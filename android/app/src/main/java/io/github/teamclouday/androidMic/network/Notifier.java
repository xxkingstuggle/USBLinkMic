package io.github.teamclouday.androidMic.network;

import android.annotation.TargetApi;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.Build;
import io.github.teamclouday.androidMic.R;

/**
 * Manage the notification necessary for the foreground service (mandatory since Android O).
 */
public class Notifier {

    private static final int NOTIFICATION_ID = 42;
    private static final String CHANNEL_ID = "LinkNet";

    private final Service context;
    private boolean failure;

    public Notifier(Service context) {
        this.context = context;
    }

    private Notification createNotification(boolean failure) {
        Notification.Builder notificationBuilder = createNotificationBuilder();
        notificationBuilder.setContentTitle(context.getString(R.string.app_name));
        if (failure) {
            notificationBuilder.setContentText(context.getString(R.string.relay_disconnected));
            notificationBuilder.setSmallIcon(R.mipmap.ic_launcher);
        }
        notificationBuilder.addAction(createStopAction());
        return notificationBuilder.build();
    }

    @SuppressWarnings("deprecation")
    private Notification.Builder createNotificationBuilder() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            return new Notification.Builder(context, CHANNEL_ID);
        }
        return new Notification.Builder(context);
    }

    @TargetApi(26)
    private void createNotificationChannel() {
        NotificationChannel channel = new NotificationChannel(CHANNEL_ID, context.getString(R.string.app_name), NotificationManager
                .IMPORTANCE_DEFAULT);
        getNotificationManager().createNotificationChannel(channel);
    }

    @TargetApi(26)
    private void deleteNotificationChannel() {
        getNotificationManager().deleteNotificationChannel(CHANNEL_ID);
    }

    public void start() {
        failure = false; // reset failure flag
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            createNotificationChannel();
        }
        Notification notification = createNotification(false);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            context.startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);
        } else {
            context.startForeground(NOTIFICATION_ID, notification);
        }
    }

    public void stop() {
        context.stopForeground(true);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            deleteNotificationChannel();
        }
    }

    public void setFailure(boolean failure) {
        if (this.failure != failure) {
            this.failure = failure;
            Notification notification = createNotification(failure);
            getNotificationManager().notify(NOTIFICATION_ID, notification);
        }
    }

    private Notification.Action createStopAction() {
        Intent stopIntent = LinkNetService.createStopIntent(context);
        int flags = PendingIntent.FLAG_ONE_SHOT;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags |= PendingIntent.FLAG_IMMUTABLE;
        }
        PendingIntent stopPendingIntent = PendingIntent.getService(context, 0, stopIntent, flags);
        // the non-deprecated constructor is not available in API 21
        @SuppressWarnings("deprecation")
        Notification.Action.Builder actionBuilder = new Notification.Action.Builder(android.R.drawable.ic_menu_close_clear_cancel, context.getString(R.string.stop_vpn),
                stopPendingIntent);
        return actionBuilder.build();
    }

    private NotificationManager getNotificationManager() {
        return (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
    }
}
