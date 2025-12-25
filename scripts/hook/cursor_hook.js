/**
 * Cursor Device Identifier Hook Module
 * 
 * 🎯 Function: Intercept all device identifier generation from the bottom layer to achieve permanent machine code modification
 * 
 * 🔧 Hook Points:
 * 1. child_process.execSync - Intercept REG.exe query for MachineGuid
 * 2. crypto.createHash - Intercept SHA256 hash calculation
 * 3. @vscode/deviceid - Intercept devDeviceId retrieval
 * 4. @vscode/windows-registry - Intercept registry reads
 * 5. os.networkInterfaces - Intercept MAC address retrieval
 * 
 * 📦 Usage:
 * Inject this code into the top of main.js file (after Sentry initialization)
 * 
 * ⚙️ Configuration:
 * 1. Environment variables: CURSOR_MACHINE_ID, CURSOR_MAC_MACHINE_ID, CURSOR_DEV_DEVICE_ID, CURSOR_SQM_ID
 * 2. Configuration file: ~/.cursor_ids.json
 * 3. Auto-generate: If not configured, automatically generate and persist
 */

// ==================== Configuration Area ====================
// Use var to ensure it works in ES Module environments
var __cursor_hook_config__ = {
    // Whether to enable Hook (set to false to temporarily disable)
    enabled: true,
    // Whether to output debug logs (set to true to view detailed logs)
    debug: false,
    // Configuration file path (relative to user directory)
    configFileName: '.cursor_ids.json',
    // Flag: prevent duplicate injection
    injected: false
};

// ==================== Hook Implementation ====================
// Use IIFE to ensure code executes immediately
(function() {
    'use strict';

    // Prevent duplicate injection
    if (globalThis.__cursor_patched__ || __cursor_hook_config__.injected) {
        return;
    }
    globalThis.__cursor_patched__ = true;
    __cursor_hook_config__.injected = true;

    // Debug log function
    const log = (...args) => {
        if (__cursor_hook_config__.debug) {
            console.log('[CursorHook]', ...args);
        }
    };

    // ==================== ID Generation and Management ====================

    // Generate UUID v4
    const generateUUID = () => {
        return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
            const r = Math.random() * 16 | 0;
            const v = c === 'x' ? r : (r & 0x3 | 0x8);
            return v.toString(16);
        });
    };

    // Generate 64-bit hexadecimal string (for machineId)
    const generateHex64 = () => {
        let hex = '';
        for (let i = 0; i < 64; i++) {
            hex += Math.floor(Math.random() * 16).toString(16);
        }
        return hex;
    };

    // Generate MAC address format string
    const generateMacAddress = () => {
        const hex = '0123456789ABCDEF';
        let mac = '';
        for (let i = 0; i < 6; i++) {
            if (i > 0) mac += ':';
            mac += hex[Math.floor(Math.random() * 16)];
            mac += hex[Math.floor(Math.random() * 16)];
        }
        return mac;
    };

    // Load or generate ID configuration
    // Note: Use createRequire to support ES Module environment
    const loadOrGenerateIds = () => {
        // In ES Module environment, need to use createRequire to load CommonJS modules
        let fs, path, os;
        try {
            // Try to use Node.js built-in modules
            const { createRequire } = require('module');
            const require2 = createRequire(import.meta?.url || __filename);
            fs = require2('fs');
            path = require2('path');
            os = require2('os');
        } catch (e) {
            // Fallback to direct require
            fs = require('fs');
            path = require('path');
            os = require('os');
        }

        const configPath = path.join(os.homedir(), __cursor_hook_config__.configFileName);

        let ids = null;

        // Try to read from environment variables
        if (process.env.CURSOR_MACHINE_ID) {
            ids = {
                machineId: process.env.CURSOR_MACHINE_ID,
                macMachineId: process.env.CURSOR_MAC_MACHINE_ID || generateHex64(),
                devDeviceId: process.env.CURSOR_DEV_DEVICE_ID || generateUUID(),
                sqmId: process.env.CURSOR_SQM_ID || `{${generateUUID().toUpperCase()}}`
            };
            log('Loaded ID configuration from environment variables');
            return ids;
        }

        // Try to read from configuration file
        try {
            if (fs.existsSync(configPath)) {
                const content = fs.readFileSync(configPath, 'utf8');
                ids = JSON.parse(content);
                log('Loaded ID configuration from file:', configPath);
                return ids;
            }
        } catch (e) {
            log('Failed to read configuration file:', e.message);
        }

        // Generate new IDs
        ids = {
            machineId: generateHex64(),
            macMachineId: generateHex64(),
            devDeviceId: generateUUID(),
            sqmId: `{${generateUUID().toUpperCase()}}`,
            macAddress: generateMacAddress(),
            createdAt: new Date().toISOString()
        };

        // Save to configuration file
        try {
            fs.writeFileSync(configPath, JSON.stringify(ids, null, 2), 'utf8');
            log('Generated and saved new ID configuration:', configPath);
        } catch (e) {
            log('Failed to save configuration file:', e.message);
        }

        return ids;
    };

    // Load ID configuration
    const __cursor_ids__ = loadOrGenerateIds();
    log('Current ID configuration:', __cursor_ids__);
    
    // ==================== Module Hook ====================
    
    const Module = require('module');
    const originalRequire = Module.prototype.require;
    
    // Cache hooked modules
    const hookedModules = new Map();
    
    Module.prototype.require = function(id) {
        const result = originalRequire.apply(this, arguments);
        
        // If already hooked, return cached result
        if (hookedModules.has(id)) {
            return hookedModules.get(id);
        }
        
        let hooked = result;
        
        // Hook child_process module
        if (id === 'child_process') {
            hooked = hookChildProcess(result);
        }
        // Hook os module
        else if (id === 'os') {
            hooked = hookOs(result);
        }
        // Hook crypto module
        else if (id === 'crypto') {
            hooked = hookCrypto(result);
        }
        // Hook @vscode/deviceid module
        else if (id === '@vscode/deviceid') {
            hooked = hookDeviceId(result);
        }
        // Hook @vscode/windows-registry module
        else if (id === '@vscode/windows-registry') {
            hooked = hookWindowsRegistry(result);
        }

        // Cache hook result
        if (hooked !== result) {
            hookedModules.set(id, hooked);
            log(`Hooked module: ${id}`);
        }

        return hooked;
    };

    // ==================== child_process Hook ====================

    function hookChildProcess(cp) {
        const originalExecSync = cp.execSync;

        cp.execSync = function(command, options) {
            const cmdStr = String(command).toLowerCase();

            // Intercept MachineGuid query
            if (cmdStr.includes('reg') && cmdStr.includes('machineguid')) {
                log('Intercepting MachineGuid query');
                // Return formatted registry output
                return Buffer.from(`\r\n    MachineGuid    REG_SZ    ${__cursor_ids__.machineId.substring(0, 36)}\r\n`);
            }

            // Intercept ioreg command (macOS)
            if (cmdStr.includes('ioreg') && cmdStr.includes('ioplatformexpertdevice')) {
                log('Intercepting IOPlatformUUID query');
                return Buffer.from(`"IOPlatformUUID" = "${__cursor_ids__.machineId.substring(0, 36).toUpperCase()}"`);
            }

            // Intercept machine-id read (Linux)
            if (cmdStr.includes('machine-id') || cmdStr.includes('hostname')) {
                log('Intercepting machine-id query');
                return Buffer.from(__cursor_ids__.machineId.substring(0, 32));
            }

            return originalExecSync.apply(this, arguments);
        };

        return cp;
    }

    // ==================== os Hook ====================

    function hookOs(os) {
        const originalNetworkInterfaces = os.networkInterfaces;

        os.networkInterfaces = function() {
            log('Intercepting networkInterfaces call');
            // Return virtual network interface with fixed MAC address
            return {
                'Ethernet': [{
                    address: '192.168.1.100',
                    netmask: '255.255.255.0',
                    family: 'IPv4',
                    mac: __cursor_ids__.macAddress || '00:00:00:00:00:00',
                    internal: false
                }]
            };
        };

        return os;
    }

    // ==================== crypto Hook ====================

    function hookCrypto(crypto) {
        const originalCreateHash = crypto.createHash;
        const originalRandomUUID = crypto.randomUUID;

        // Hook createHash - used to intercept SHA256 calculation for machineId
        crypto.createHash = function(algorithm) {
            const hash = originalCreateHash.apply(this, arguments);

            if (algorithm.toLowerCase() === 'sha256') {
                const originalUpdate = hash.update.bind(hash);
                const originalDigest = hash.digest.bind(hash);

                let inputData = '';

                hash.update = function(data, encoding) {
                    inputData += String(data);
                    return originalUpdate(data, encoding);
                };

                hash.digest = function(encoding) {
                    // Check if this is a machineId-related hash calculation
                    if (inputData.includes('MachineGuid') ||
                        inputData.includes('IOPlatformUUID') ||
                        inputData.length === 32 ||
                        inputData.length === 36) {
                        log('Intercepting SHA256 hash calculation, returning fixed machineId');
                        if (encoding === 'hex') {
                            return __cursor_ids__.machineId;
                        }
                        return Buffer.from(__cursor_ids__.machineId, 'hex');
                    }
                    return originalDigest(encoding);
                };
            }

            return hash;
        };

        // Hook randomUUID - used to intercept devDeviceId generation
        if (originalRandomUUID) {
            let uuidCallCount = 0;
            crypto.randomUUID = function() {
                uuidCallCount++;
                // First call returns fixed devDeviceId
                if (uuidCallCount <= 2) {
                    log('Intercepting randomUUID call, returning fixed devDeviceId');
                    return __cursor_ids__.devDeviceId;
                }
                return originalRandomUUID.apply(this, arguments);
            };
        }

        return crypto;
    }

    // ==================== @vscode/deviceid Hook ====================

    function hookDeviceId(deviceIdModule) {
        log('Hooking @vscode/deviceid module');

        return {
            ...deviceIdModule,
            getDeviceId: async function() {
                log('Intercepting getDeviceId call');
                return __cursor_ids__.devDeviceId;
            }
        };
    }

    // ==================== @vscode/windows-registry Hook ====================

    function hookWindowsRegistry(registryModule) {
        log('Hooking @vscode/windows-registry module');

        const originalGetStringRegKey = registryModule.GetStringRegKey;

        return {
            ...registryModule,
            GetStringRegKey: function(hive, path, name) {
                // Intercept MachineId read
                if (name === 'MachineId' || path.includes('SQMClient')) {
                    log('Intercepting registry MachineId/SQMClient read');
                    return __cursor_ids__.sqmId;
                }
                // Intercept MachineGuid read
                if (name === 'MachineGuid' || path.includes('Cryptography')) {
                    log('Intercepting registry MachineGuid read');
                    return __cursor_ids__.machineId.substring(0, 36);
                }
                return originalGetStringRegKey?.apply(this, arguments) || '';
            }
        };
    }

    // ==================== Dynamic import Hook ====================

    // Cursor uses dynamic import() to load modules, we need to hook these modules
    // Due to ES Module limitations, we implement this by hooking global objects

    // Store hooked dynamic import modules
    const hookedDynamicModules = new Map();

    // Hook dynamic import of crypto module
    const hookDynamicCrypto = (cryptoModule) => {
        if (hookedDynamicModules.has('crypto')) {
            return hookedDynamicModules.get('crypto');
        }

        const hooked = { ...cryptoModule };

        // Hook createHash
        if (cryptoModule.createHash) {
            const originalCreateHash = cryptoModule.createHash;
            hooked.createHash = function(algorithm) {
                const hash = originalCreateHash.apply(this, arguments);

                if (algorithm.toLowerCase() === 'sha256') {
                    const originalDigest = hash.digest.bind(hash);
                    let inputData = '';

                    const originalUpdate = hash.update.bind(hash);
                    hash.update = function(data, encoding) {
                        inputData += String(data);
                        return originalUpdate(data, encoding);
                    };

                    hash.digest = function(encoding) {
                        // Detect machineId-related hash
                        if (inputData.includes('MachineGuid') ||
                            inputData.includes('IOPlatformUUID') ||
                            (inputData.length >= 32 && inputData.length <= 40)) {
                            log('Dynamic import: intercepting SHA256 hash');
                            return encoding === 'hex' ? __cursor_ids__.machineId : Buffer.from(__cursor_ids__.machineId, 'hex');
                        }
                        return originalDigest(encoding);
                    };
                }
                return hash;
            };
        }

        hookedDynamicModules.set('crypto', hooked);
        return hooked;
    };

    // Hook dynamic import of @vscode/deviceid module
    const hookDynamicDeviceId = (deviceIdModule) => {
        if (hookedDynamicModules.has('@vscode/deviceid')) {
            return hookedDynamicModules.get('@vscode/deviceid');
        }

        const hooked = {
            ...deviceIdModule,
            getDeviceId: async () => {
                log('Dynamic import: intercepting getDeviceId');
                return __cursor_ids__.devDeviceId;
            }
        };

        hookedDynamicModules.set('@vscode/deviceid', hooked);
        return hooked;
    };

    // Hook dynamic import of @vscode/windows-registry module
    const hookDynamicWindowsRegistry = (registryModule) => {
        if (hookedDynamicModules.has('@vscode/windows-registry')) {
            return hookedDynamicModules.get('@vscode/windows-registry');
        }

        const originalGetStringRegKey = registryModule.GetStringRegKey;
        const hooked = {
            ...registryModule,
            GetStringRegKey: function(hive, path, name) {
                if (name === 'MachineId' || path?.includes('SQMClient')) {
                    log('Dynamic import: intercepting SQMClient');
                    return __cursor_ids__.sqmId;
                }
                if (name === 'MachineGuid' || path?.includes('Cryptography')) {
                    log('Dynamic import: intercepting MachineGuid');
                    return __cursor_ids__.machineId.substring(0, 36);
                }
                return originalGetStringRegKey?.apply(this, arguments) || '';
            }
        };

        hookedDynamicModules.set('@vscode/windows-registry', hooked);
        return hooked;
    };

    // Expose hook functions to global for later use
    globalThis.__cursor_hook_dynamic__ = {
        crypto: hookDynamicCrypto,
        deviceId: hookDynamicDeviceId,
        windowsRegistry: hookDynamicWindowsRegistry,
        ids: __cursor_ids__
    };

    log('Cursor Hook initialization completed');
    log('machineId:', __cursor_ids__.machineId.substring(0, 16) + '...');
    log('devDeviceId:', __cursor_ids__.devDeviceId);
    log('sqmId:', __cursor_ids__.sqmId);

})();

// ==================== Export Configuration (for external use) ====================
if (typeof module !== 'undefined' && module.exports) {
    module.exports = { __cursor_hook_config__ };
}

// ==================== ES Module Compatibility ====================
// If in ES Module environment, also expose configuration
if (typeof globalThis !== 'undefined') {
    globalThis.__cursor_hook_config__ = __cursor_hook_config__;
}

