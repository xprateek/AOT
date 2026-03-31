import { exec } from 'kernelsu-alt';
import { showPrompt, moduleDirectory } from '../../utils/util.js';

const logFile = '/data/adb/aot/aot.log';

export async function fetchLogs() {
    const logArea = document.getElementById('log-content');
    if (!logArea) return;

    try {
        const result = await exec(`[ -f ${logFile} ] && tail -n 100 ${logFile} || echo "No logs found yet. Start tethering to generate logs."`);
        const raw = result.stdout || '';
        const lines = raw.split('\n');
        const deduped = [];
        for (const line of lines) {
            if (deduped.length === 0 || deduped[deduped.length - 1] !== line) {
                deduped.push(line);
            }
        }
        logArea.textContent = deduped.join('\n') || 'Empty log file.';
        
        // Auto-scroll to bottom
        const container = document.getElementById('log-container');
        if (container) {
            container.scrollTop = container.scrollHeight;
        }
    } catch (error) {
        logArea.textContent = `Error fetching logs: ${error.message}`;
    }
}

async function clearLogs() {
    try {
        await exec(`su -c sh ${moduleDirectory}/aot-cli.sh clear_logs`);
        showPrompt('Logs cleared.');
        fetchLogs();
    } catch (error) {
        showPrompt(`Failed to clear: ${error.message}`, false);
    }
}

async function copyLogs() {
    const logArea = document.getElementById('log-content');
    if (!logArea) return;

    try {
        const text = logArea.textContent;
        await navigator.clipboard.writeText(text);
        showPrompt('Logs copied to clipboard!');
    } catch (error) {
        showPrompt(`Failed to copy: ${error.message}`, false);
    }
}

export function mount(container) {
    document.getElementById('refresh-logs').addEventListener('click', fetchLogs);
    document.getElementById('clear-logs').addEventListener('click', clearLogs);
    document.getElementById('copy-logs').addEventListener('click', copyLogs);
}

export function onShow() {
    fetchLogs();
}

export function onHide() {
    // No-op
}
