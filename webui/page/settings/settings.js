import { exec } from 'kernelsu-alt';
import { showPrompt, basePath, moduleDirectory } from '../../utils/util.js';

const configFile = `${basePath}/aot.config`;

// ============================================================
// Config Loading
// Reads aot.config and populates all Settings UI fields
// ============================================================
export async function loadConfig() {
    try {
        const result = await exec(`[ -f ${configFile} ] && cat ${configFile} || echo ""`);
        const content = result.stdout.trim();
        
        if (content) {
            const matches = {
                gateway: content.match(/CUSTOM_GATEWAY="(.+)"/),
                netmask: content.match(/CUSTOM_NETMASK="(.+)"/),
                dns1: content.match(/CUSTOM_DNS1="(.+)"/),
                dns2: content.match(/CUSTOM_DNS2="(.+)"/),
                adbPort: content.match(/WIFI_ADB_PORT="(.+)"/),
                adbLog: content.match(/WIFI_ADB_LOG="(.+)"/),
                adbFreq: content.match(/WIFI_ADB_FREQUENCY="(.+)"/)
            };
            
            if (matches.gateway) document.getElementById('custom-gateway').value = matches.gateway[1];
            if (matches.netmask) document.getElementById('custom-netmask').value = matches.netmask[1];
            if (matches.dns1) document.getElementById('custom-dns1').value = matches.dns1[1];
            if (matches.dns2) document.getElementById('custom-dns2').value = matches.dns2[1];
            if (matches.adbPort) document.getElementById('wifiadb-port').value = matches.adbPort[1];
            if (matches.adbLog) document.getElementById('wifiadb-log-switch').selected = matches.adbLog[1] === '1';
            if (matches.adbFreq) document.getElementById('wifiadb-frequency').value = matches.adbFreq[1];
        }

        // Check ADB over Tethering enabled flag
        const adbCheck = await exec(`[ -f ${basePath}/wifiadb_enabled ] && echo true || echo false`);
        document.getElementById('wifiadb-switch').selected = adbCheck.stdout.trim() === 'true';
    } catch (error) {
        console.error('Error loading config:', error);
    }
}

// ============================================================
// Config Updating (Helper)
// Reads existing config and merges new updates to avoid data loss
// ============================================================
async function updateConfig(updates, silent = false) {
    try {
        // Read existing config first to preserve other fields
        const result = await exec(`[ -f ${configFile} ] && cat ${configFile} || echo ""`);
        const content = result.stdout.trim();
        const config = {};
        
        // Parse existing
        if (content) {
            content.split('\n').forEach(line => {
                const m = line.match(/^(.+)="(.+)"$/);
                if (m) config[m[1]] = m[2];
            });
        }

        // Merge updates
        Object.assign(config, updates);

        // Standardize fallbacks
        const finalLines = [
            `CUSTOM_GATEWAY="${config.CUSTOM_GATEWAY || '10.0.0.1'}"`,
            `CUSTOM_NETMASK="${config.CUSTOM_NETMASK || '255.255.255.0'}"`,
            `CUSTOM_DNS1="${config.CUSTOM_DNS1 || '8.8.8.8'}"`,
            `CUSTOM_DNS2="${config.CUSTOM_DNS2 || '8.8.4.4'}"`,
            `WIFI_ADB_PORT="${config.WIFI_ADB_PORT || '5555'}"`,
            `WIFI_ADB_LOG="${config.WIFI_ADB_LOG || '0'}"`,
            `WIFI_ADB_FREQUENCY="${config.WIFI_ADB_FREQUENCY || '5'}"`
        ];

        const configContent = finalLines.join('\\n');
        await exec(`mkdir -p ${basePath}`);
        await exec(`echo -e '${configContent}' > ${configFile}`);
        if (!silent) showPrompt('Configuration Saved!');
    } catch (error) {
        if (!silent) showPrompt(`Failed to save: ${error.message}`, false);
    }
}

// ============================================================
// Network Settings Saving
// ============================================================
async function saveNetworkConfig() {
    const gateway = document.getElementById('custom-gateway').value.trim();
    const netmask = document.getElementById('custom-netmask').value.trim();
    const dns1 = document.getElementById('custom-dns1').value.trim();
    const dns2 = document.getElementById('custom-dns2').value.trim();

    const ipRegex = /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/;
    if (!ipRegex.test(gateway) || !ipRegex.test(netmask)) {
        showPrompt('Please enter valid IP addresses for Gateway and Subnet.', false);
        return;
    }
    if (dns1 && !ipRegex.test(dns1)) {
        showPrompt('Please enter a valid Primary DNS address.', false);
        return;
    }
    if (dns2 && !ipRegex.test(dns2)) {
        showPrompt('Please enter a valid Fallback DNS address.', false);
        return;
    }

    await updateConfig({
        CUSTOM_GATEWAY: gateway,
        CUSTOM_NETMASK: netmask,
        CUSTOM_DNS1: dns1,
        CUSTOM_DNS2: dns2
    });
}

// ============================================================
// ADB Settings Saving
// ============================================================
async function saveAdbConfig(silent = false) {
    const adbPort = document.getElementById('wifiadb-port').value.trim();
    const adbLog = document.getElementById('wifiadb-log-switch').selected ? '1' : '0';
    const adbFreq = document.getElementById('wifiadb-frequency').value.trim();

    const portNum = parseInt(adbPort);
    if (isNaN(portNum) || portNum < 1 || portNum > 65535) {
        if (!silent) showPrompt('ADB port must be between 1 and 65535.', false);
        return;
    }

    const freqNum = parseInt(adbFreq);
    if (isNaN(freqNum) || freqNum < 1 || freqNum > 10) {
        if (!silent) showPrompt('Check frequency must be between 1 and 10 seconds.', false);
        return;
    }

    await updateConfig({
        WIFI_ADB_PORT: adbPort,
        WIFI_ADB_LOG: adbLog,
        WIFI_ADB_FREQUENCY: adbFreq
    }, silent);
}

// ============================================================
// ADB over Tethering Toggle
// ============================================================
async function toggleWifiAdb() {
    const sw = document.getElementById('wifiadb-switch');
    const enabled = sw.selected;
    const port = document.getElementById('wifiadb-port').value.trim() || '5555';

    // Auto-save the specific ADB meta-data when toggled
    await saveAdbConfig(true);

    let result;
    if (enabled) {
        result = await exec(`su -c sh ${moduleDirectory}/aot-cli.sh adb-tcp enable ${port}`);
    } else {
        result = await exec(`su -c sh ${moduleDirectory}/aot-cli.sh adb-tcp disable`);
    }

    if (result.errno === 0) {
        showPrompt(`ADB over Tethering ${enabled ? 'enabled' : 'disabled'}`);
    } else {
        showPrompt(`Failed: ${result.stderr}`, false);
        sw.selected = !enabled;
    }
}

// ============================================================
// DNS Preset Chips
// ============================================================
function setupDnsChips() {
    document.querySelectorAll('.dns-chip').forEach(chip => {
        chip.addEventListener('click', () => {
            document.getElementById('custom-dns1').value = chip.dataset.dns1;
            document.getElementById('custom-dns2').value = chip.dataset.dns2;
            showPrompt(`DNS set to ${chip.label}`);
        });
    });
}

// ============================================================
// Lifecycle Hooks
// ============================================================
export function mount(container) {
    document.getElementById('save-network').addEventListener('click', saveNetworkConfig);
    document.getElementById('save-adb').addEventListener('click', () => saveAdbConfig(false));
    document.getElementById('wifiadb-switch').addEventListener('change', toggleWifiAdb);
    setupDnsChips();
}

export function onShow() {
    loadConfig();
}

export function onHide() {
    // No-op
}
