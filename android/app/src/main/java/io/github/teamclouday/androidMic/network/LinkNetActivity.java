package io.github.teamclouday.androidMic.network;

import android.app.Activity;
import android.content.Intent;
import android.net.VpnService;
import android.os.Bundle;
import android.util.Log;

/**
 * This (invisible) activity receives the {@link #ACTION_GNIREHTET_START START} and
 * {@link #ACTION_GNIREHTET_STOP} actions from the command line.
 * <p>
 * Recent versions of Android refuse to directly start a {@link android.app.Service Service} or a
 * {@link android.content.BroadcastReceiver BroadcastReceiver}, so actions are always managed by
 * this activity.
 */
public class LinkNetActivity extends Activity {

    private static final String TAG = LinkNetActivity.class.getSimpleName();

    public static final String ACTION_LINK_NET_START = "com.zjx.usblinkmic.START_NETWORK";
    public static final String ACTION_LINK_NET_STOP = "com.zjx.usblinkmic.STOP_NETWORK";

    public static final String EXTRA_DNS_SERVERS = "dnsServers";
    public static final String EXTRA_ROUTES = "routes";

    private static final int VPN_REQUEST_CODE = 0;

    private VpnConfiguration requestedConfig;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        handleIntent(getIntent());
    }

    private void handleIntent(Intent intent) {
        String action = intent.getAction();
        Log.d(TAG, "Received request " + action);
        boolean finish = true;
        if (ACTION_LINK_NET_START.equals(action)) {
            VpnConfiguration config = createConfig(intent);
            finish = startLinkNet(config);
        } else if (ACTION_LINK_NET_STOP.equals(action)) {
            stopLinkNet();
        }

        if (finish) {
            finish();
        }
    }

    private static VpnConfiguration createConfig(Intent intent) {
        String[] dnsServers = intent.getStringArrayExtra(EXTRA_DNS_SERVERS);
        if (dnsServers == null) {
            dnsServers = new String[0];
        }
        String[] routes = intent.getStringArrayExtra(EXTRA_ROUTES);
        if (routes == null) {
            routes = new String[0];
        }
        return new VpnConfiguration(Net.toInetAddresses(dnsServers), Net.toCIDRs(routes));
    }

    private boolean startLinkNet(VpnConfiguration config) {
        Intent vpnIntent = VpnService.prepare(this);
        if (vpnIntent == null) {
            Log.d(TAG, "VPN was already authorized");
            // we got the permission, start the service now
            LinkNetService.start(this, config);
            return true;
        }

        Log.w(TAG, "VPN requires the authorization from the user, requesting...");
        requestAuthorization(vpnIntent, config);
        return false; // do not finish now
    }

    private void stopLinkNet() {
        LinkNetService.stop(this);
    }

    private void requestAuthorization(Intent vpnIntent, VpnConfiguration config) {
        this.requestedConfig = config;
        startActivityForResult(vpnIntent, VPN_REQUEST_CODE);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == VPN_REQUEST_CODE && resultCode == RESULT_OK) {
            LinkNetService.start(this, requestedConfig);
        }
        requestedConfig = null;
        finish();
    }
}
