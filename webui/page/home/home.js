import { exec } from 'kernelsu-alt';
import { showPrompt, moduleDirectory, basePath } from '../../utils/util.js';

let isUsbEnabled = false;
let isEthEnabled = false;

async function checkState() {
    try {
        const result = await exec(`su -c sh ${moduleDirectory}/aot-cli.sh status --json`);
        const status = JSON.parse(result.stdout.trim());
        
        isUsbEnabled = status.usb.active;
        document.getElementById('usb-switch').selected = isUsbEnabled;

        isEthEnabled = status.eth.active;
        document.getElementById('eth-switch').selected = isEthEnabled;

        const gwText = document.getElementById('gateway-ip-text');
        if (isUsbEnabled) {
            gwText.textContent = `Active Gateway (USB): ${status.usb.gateway || '10.0.0.1'} | Client IP: ${status.usb.ip || 'Assigning...'}`;
        } else if (isEthEnabled) {
            gwText.textContent = `Active Gateway (Eth): ${status.eth.gateway || '10.0.0.1'} | Client IP: ${status.eth.ip || 'Assigning...'}`;
        } else {
            gwText.textContent = 'Active Gateway: None (Idle)';
        }

        document.getElementById('status-text').textContent = 'Ready';
        
        // Update instruction card based on current config
        updateInstructions();
    } catch (error) {
        document.getElementById('status-text').textContent = 'Error checking status.';
        console.error(error);
    }
}

async function updateInstructions() {
    const configFile = `${basePath}/aot.config`;
    let gateway = "10.0.0.1";
    let netmask = "255.255.255.0";
    let dns1 = "8.8.8.8";

    try {
        const result = await exec(`[ -f ${configFile} ] && cat ${configFile} || echo ""`);
        const content = result.stdout.trim();
        if (content) {
            const mg = content.match(/CUSTOM_GATEWAY="(.+)"/);
            const mn = content.match(/CUSTOM_NETMASK="(.+)"/);
            const md = content.match(/CUSTOM_DNS1="(.+)"/);
            if (mg) gateway = mg[1];
            if (mn) netmask = mn[1];
            if (md) dns1 = md[1];
        }
    } catch (e) {}

    // Derive a sample client IP (increment last octet)
    const clientIp = gateway.replace(/\.[0-9]+$/, (match) => {
        const val = parseInt(match.slice(1));
        return `.${val + 1}`;
    });

    const elIp = document.getElementById('instr-ip');
    const elMask = document.getElementById('instr-mask');
    const elGw = document.getElementById('instr-gw');
    const elDns = document.getElementById('instr-dns');

    if (elIp) elIp.textContent = clientIp;
    if (elMask) elMask.textContent = netmask;
    if (elGw) elGw.textContent = gateway;
    if (elDns) elDns.textContent = dns1;
}

async function toggleUsb() {
    const sw = document.getElementById('usb-switch');
    const ethSw = document.getElementById('eth-switch');
    isUsbEnabled = sw.selected;

    document.getElementById('status-text').textContent = isUsbEnabled ? 'Enabling USB Tethering...' : 'Disabling USB Tethering...';
    
    await exec(`mkdir -p ${basePath}`);
    
    let result;
    if (isUsbEnabled) {
        if (ethSw.selected) {
            ethSw.selected = false;
            await exec(`rm -f ${basePath}/eth_enabled`);
        }
        await exec(`touch ${basePath}/usb_enabled`);
        result = await exec(`su -c sh ${moduleDirectory}/aot-cli.sh usb enable`);
    } else {
        await exec(`rm -f ${basePath}/usb_enabled`);
        result = await exec(`su -c sh ${moduleDirectory}/aot-cli.sh usb disable`);
    }

    if (result.errno === 0) {
        showPrompt(`USB Tethering ${isUsbEnabled ? 'Enabled' : 'Disabled'}`);
    } else {
        showPrompt(`Failed: ${result.stderr}`, false);
        sw.selected = !isUsbEnabled; 
    }
    document.getElementById('status-text').textContent = 'Ready';
}

async function toggleEth() {
    const sw = document.getElementById('eth-switch');
    const usbSw = document.getElementById('usb-switch');
    isEthEnabled = sw.selected;

    document.getElementById('status-text').textContent = isEthEnabled ? 'Enabling Ethernet Tethering...' : 'Disabling Ethernet Tethering...';
    
    await exec(`mkdir -p ${basePath}`);
    
    let result;
    if (isEthEnabled) {
        if (usbSw.selected) {
            usbSw.selected = false;
            await exec(`rm -f ${basePath}/usb_enabled`);
        }
        await exec(`touch ${basePath}/eth_enabled`);
        result = await exec(`su -c sh ${moduleDirectory}/aot-cli.sh eth enable`);
    } else {
        await exec(`rm -f ${basePath}/eth_enabled`);
        result = await exec(`su -c sh ${moduleDirectory}/aot-cli.sh eth disable`);
    }

    if (result.errno === 0) {
        showPrompt(`Ethernet Tethering ${isEthEnabled ? 'Enabled' : 'Disabled'}`);
    } else {
        showPrompt(`Failed: ${result.stderr}`, false);
        sw.selected = !isEthEnabled; 
    }
    document.getElementById('status-text').textContent = 'Ready';
}

// ============================================================
// v1 Operator Console: Diagnostics & Logs Logic
// ============================================================
async function runAotCommand(action, subAction = '') {
    const outputContainer = document.getElementById('diag-output-container');
    const outputText = document.getElementById('diag-output-text');
    
    outputContainer.style.display = 'block';
    outputText.textContent = `Running ${action}... Please wait.`;
    
    try {
        const result = await exec(`su -c sh ${moduleDirectory}/aot-cli.sh ${action} ${subAction}`);
        if (result.errno === 0) {
            outputText.textContent = result.stdout || 'Command completed successfully (no output).';
        } else {
            outputText.textContent = `Error (${result.errno}):\n${result.stderr}`;
        }
    } catch (error) {
        outputText.textContent = `Execution Error: ${error.message}`;
    }
}

async function loadLiveLogs() {
    const logContainer = document.getElementById('live-log-container');
    const logFile = '/data/adb/aot/aot.log';
    
    try {
        const result = await exec(`[ -f ${logFile} ] && tail -n 50 ${logFile} || echo "No logs found."`);
        logContainer.innerText = result.stdout.trim() || 'Log file is empty.';
        // Auto-scroll to bottom
        const parent = logContainer.parentElement;
        parent.scrollTop = parent.scrollHeight;
    } catch (e) {
        logContainer.innerText = 'Failed to load logs.';
    }
}

function setupConsoleEvents() {
    document.getElementById('run-probe').onclick = () => runAotCommand('probe');
    document.getElementById('run-verify').onclick = async () => {
        // Find which interface is active
        const usbSw = document.getElementById('usb-switch');
        const ethSw = document.getElementById('eth-switch');
        const iface = usbSw.selected ? 'rndis0' : (ethSw.selected ? 'eth0' : 'none');
        
        if (iface === 'none') {
            showPrompt('No interface active to verify.', false);
            return;
        }
        await runAotCommand('verify', iface);
    };
    
    document.getElementById('run-diag').onclick = async () => {
        await runAotCommand('diag');
        showPrompt('Diagnostics snapshot saved to /data/adb/aot/diag.txt');
    };
}

// ============================================================
// ADB Status Management
// ============================================================
async function checkAdbStatus() {
    const statusText = document.getElementById('adb-status-text');
    const connectContainer = document.getElementById('adb-connect-container');
    const cmdText = document.getElementById('adb-cmd-dashboard');
    const configFile = `${basePath}/aot.config`;

    try {
        // 1. Get current config from file
        const configResult = await exec(`[ -f ${configFile} ] && cat ${configFile} || echo ""`);
        const configContent = configResult.stdout.trim();
        let gateway = '10.0.0.1';
        let configPort = '5555';

        if (configContent) {
            const gMatch = configContent.match(/CUSTOM_GATEWAY="(.+)"/);
            const pMatch = configContent.match(/WIFI_ADB_PORT="(.+)"/);
            if (gMatch) gateway = gMatch[1];
            if (pMatch) configPort = pMatch[1];
        }

        // 2. Check actual system property
        const adbPropResult = await exec('getprop service.adb.tcp.port');
        const activePort = adbPropResult.stdout.trim();

        if (activePort !== '' && activePort !== '-1') {
            // Re-fetch live IP to ensure ADB command is accurate
            const statusResult = await exec(`su -c sh ${moduleDirectory}/aot-cli.sh status --json`);
            const status = JSON.parse(statusResult.stdout.trim());
            const liveIp = status.usb.active ? status.usb.ip : (status.eth.active ? status.eth.ip : gateway);

            statusText.innerText = 'Status: Active';
            statusText.style.color = 'var(--md-sys-color-primary)';
            cmdText.innerText = `adb connect ${liveIp || gateway}:${activePort}`;
            connectContainer.style.display = 'block';
        } else {
            statusText.innerText = 'Status: Inactive';
            statusText.style.color = 'inherit';
            connectContainer.style.display = 'none';
        }
    } catch (e) {
        statusText.innerText = 'Status: Error checking adbd';
        connectContainer.style.display = 'none';
    }
}

function setupCopyAdb() {
    const btn = document.getElementById('copy-adb-dashboard');
    const cmd = document.getElementById('adb-cmd-dashboard');
    if (!btn || !cmd) return;

    btn.onclick = () => {
        const text = cmd.innerText;
        navigator.clipboard.writeText(text).then(() => {
            showPrompt('Command copied to clipboard!');
        });
    };
}

export function mount(container) {
    document.getElementById('usb-switch').addEventListener('change', toggleUsb);
    document.getElementById('eth-switch').addEventListener('change', toggleEth);
    setupCopyAdb();
    setupConsoleEvents();
}

export function onShow() {
    checkState();
    checkAdbStatus();
}

export function onHide() {
    // No-op
}
