# Set output encoding to UTF-8
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Color definitions
$RED = "`e[31m"
$GREEN = "`e[32m"
$YELLOW = "`e[33m"
$BLUE = "`e[34m"
$NC = "`e[0m"

# Configuration file paths
$STORAGE_FILE = "$env:APPDATA\Cursor\User\globalStorage\storage.json"
$BACKUP_DIR = "$env:APPDATA\Cursor\User\globalStorage\backups"

# PowerShell native method to generate random string
function Generate-RandomString {
    param([int]$Length)
    $chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    $result = ""
    for ($i = 0; $i -lt $Length; $i++) {
        $result += $chars[(Get-Random -Maximum $chars.Length)]
    }
    return $result
}

# 🔧 Modify Cursor kernel JS files for device identification bypass (Enhanced Hook solution)
# Solution A: someValue placeholder replacement - stable anchor, doesn't depend on obfuscated function names
# Solution B: Deep Hook injection - intercept all device identifier generation from bottom layer
# Solution C: Module.prototype.require hijacking - intercept child_process, crypto, os and other modules
function Modify-CursorJSFiles {
    Write-Host ""
    Write-Host "$BLUE🔧 [Kernel Modification]$NC Starting to modify Cursor kernel JS files for device identification bypass..."
    Write-Host "$BLUE💡 [Solution]$NC Using enhanced Hook solution: deep module hijacking + someValue replacement"
    Write-Host ""

    # Windows version Cursor application path
    $cursorAppPath = "${env:LOCALAPPDATA}\Programs\Cursor"
    if (-not (Test-Path $cursorAppPath)) {
        # Try other possible installation paths
        $alternatePaths = @(
            "${env:ProgramFiles}\Cursor",
            "${env:ProgramFiles(x86)}\Cursor",
            "${env:USERPROFILE}\AppData\Local\Programs\Cursor"
        )

        foreach ($path in $alternatePaths) {
            if (Test-Path $path) {
                $cursorAppPath = $path
                break
            }
        }

        if (-not (Test-Path $cursorAppPath)) {
            Write-Host "$RED❌ [Error]$NC Cursor application installation path not found"
            Write-Host "$YELLOW💡 [Tip]$NC Please ensure Cursor is properly installed"
            return $false
        }
    }

    Write-Host "$GREEN✅ [Found]$NC Found Cursor installation path: $cursorAppPath"

    # Generate new device identifiers (use fixed format to ensure compatibility)
    $newUuid = [System.Guid]::NewGuid().ToString().ToLower()
    $randomBytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
    $rng.GetBytes($randomBytes)
    $machineId = [System.BitConverter]::ToString($randomBytes) -replace '-',''
    $rng.Dispose()
    $deviceId = [System.Guid]::NewGuid().ToString().ToLower()
    $randomBytes2 = New-Object byte[] 32
    $rng2 = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
    $rng2.GetBytes($randomBytes2)
    $macMachineId = [System.BitConverter]::ToString($randomBytes2) -replace '-',''
    $rng2.Dispose()
    $sqmId = "{" + [System.Guid]::NewGuid().ToString().ToUpper() + "}"
    $sessionId = [System.Guid]::NewGuid().ToString().ToLower()
    $macAddress = "00:11:22:33:44:55"

    Write-Host "$GREEN🔑 [Generate]$NC Generated new device identifiers"
    Write-Host "   machineId: $($machineId.Substring(0,16))..."
    Write-Host "   deviceId: $($deviceId.Substring(0,16))..."
    Write-Host "   macMachineId: $($macMachineId.Substring(0,16))..."
    Write-Host "   sqmId: $sqmId"

    # Save ID configuration to user directory (for Hook to read)
    # Delete old configuration and regenerate each time to ensure new device identifiers
    $idsConfigPath = "$env:USERPROFILE\.cursor_ids.json"
    if (Test-Path $idsConfigPath) {
        Remove-Item -Path $idsConfigPath -Force
        Write-Host "$YELLOW🗑️  [Cleanup]$NC Deleted old ID configuration file"
    }
    $idsConfig = @{
        machineId = $machineId
        macMachineId = $macMachineId
        devDeviceId = $deviceId
        sqmId = $sqmId
        macAddress = $macAddress
        createdAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    }
    $idsConfig | ConvertTo-Json | Set-Content -Path $idsConfigPath -Encoding UTF8
    Write-Host "$GREEN💾 [Save]$NC New ID configuration saved to: $idsConfigPath"

    # Target JS file list (Windows paths, sorted by priority)
    $jsFiles = @(
        "$cursorAppPath\resources\app\out\main.js"
    )

    $modifiedCount = 0

    # Close Cursor process
    Write-Host "$BLUE🔄 [Close]$NC Closing Cursor process for file modification..."
    Stop-AllCursorProcesses -MaxRetries 3 -WaitSeconds 3 | Out-Null

    # Create backup directory
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupPath = "$cursorAppPath\resources\app\out\backups"

    Write-Host "$BLUE💾 [Backup]$NC Creating Cursor JS file backup..."
    try {
        New-Item -ItemType Directory -Path $backupPath -Force | Out-Null

        # Check if original backup exists
        $originalBackup = "$backupPath\main.js.original"

        foreach ($file in $jsFiles) {
            if (-not (Test-Path $file)) {
                Write-Host "$YELLOW⚠️  [Warning]$NC File does not exist: $(Split-Path $file -Leaf)"
                continue
            }

            $fileName = Split-Path $file -Leaf
            $fileOriginalBackup = "$backupPath\$fileName.original"

            # If original backup doesn't exist, create it first
            if (-not (Test-Path $fileOriginalBackup)) {
                # Check if current file has been modified
                $content = Get-Content $file -Raw -ErrorAction SilentlyContinue
                if ($content -and $content -match "__cursor_patched__") {
                    Write-Host "$YELLOW⚠️  [Warning]$NC File has been modified but no original backup exists, will use current version as base"
                }
                Copy-Item $file $fileOriginalBackup -Force
                Write-Host "$GREEN✅ [Backup]$NC Original backup created successfully: $fileName"
            } else {
                # Restore from original backup to ensure clean injection each time
                Write-Host "$BLUE🔄 [Restore]$NC Restoring from original backup: $fileName"
                Copy-Item $fileOriginalBackup $file -Force
            }
        }

        # Create timestamped backup (record state before each modification)
        foreach ($file in $jsFiles) {
            if (Test-Path $file) {
                $fileName = Split-Path $file -Leaf
                Copy-Item $file "$backupPath\$fileName.backup_$timestamp" -Force
            }
        }
        Write-Host "$GREEN✅ [Backup]$NC Timestamped backup created successfully: $backupPath"
    } catch {
        Write-Host "$RED❌ [Error]$NC Failed to create backup: $($_.Exception.Message)"
        return $false
    }

    # Modify JS files (re-inject each time since restored from original backup)
    Write-Host "$BLUE🔧 [Modify]$NC Starting to modify JS files (using new device identifiers)..."

    foreach ($file in $jsFiles) {
        if (-not (Test-Path $file)) {
            Write-Host "$YELLOW⚠️  [Skip]$NC File does not exist: $(Split-Path $file -Leaf)"
            continue
        }

        Write-Host "$BLUE📝 [Processing]$NC Processing: $(Split-Path $file -Leaf)"

        try {
            $content = Get-Content $file -Raw -Encoding UTF8
            $replaced = $false

            # ========== Solution A: someValue placeholder replacement (stable anchor) ==========
            # These strings are fixed placeholders, will not be modified by obfuscator, stable across versions
            # Important note:
            # In current Cursor's main.js, placeholders usually appear as string literals, e.g.:
            #   this.machineId="someValue.machineId"
            # If we directly replace someValue.machineId with "\"<real_value>\"", it will form ""<real_value>"" causing JS syntax error (Invalid token).
            # Therefore, we prioritize replacing complete string literals (including outer quotes), and use JSON string literals to ensure escape safety.

            # 🔧 New: firstSessionDate (reset first session date)
            $firstSessionDateValue = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")

            $placeholders = @(
                @{ Name = 'someValue.machineId';         Value = [string]$machineId },
                @{ Name = 'someValue.macMachineId';      Value = [string]$macMachineId },
                @{ Name = 'someValue.devDeviceId';       Value = [string]$deviceId },
                @{ Name = 'someValue.sqmId';             Value = [string]$sqmId },
                @{ Name = 'someValue.sessionId';         Value = [string]$sessionId },
                @{ Name = 'someValue.firstSessionDate';  Value = [string]$firstSessionDateValue }
            )

            foreach ($ph in $placeholders) {
                $name = $ph.Name
                $jsonValue = ($ph.Value | ConvertTo-Json -Compress)  # Generate JSON string literal with double quotes

                $changed = $false

                # Prioritize replacing quoted placeholder literals to avoid ""abc"" breaking syntax
                $doubleLiteral = '"' + $name + '"'
                if ($content.Contains($doubleLiteral)) {
                    $content = $content.Replace($doubleLiteral, $jsonValue)
                    $changed = $true
                }
                $singleLiteral = "'" + $name + "'"
                if ($content.Contains($singleLiteral)) {
                    $content = $content.Replace($singleLiteral, $jsonValue)
                    $changed = $true
                }

                # Fallback: If placeholder appears as non-string literal, replace with JSON string literal (includes quotes)
                if (-not $changed -and $content.Contains($name)) {
                    $content = $content.Replace($name, $jsonValue)
                    $changed = $true
                }

                if ($changed) {
                    Write-Host "   $GREEN✓$NC [Solution A] Replaced $name"
                    $replaced = $true
                }
            }

            # ========== Solution B: Enhanced deep Hook injection ==========
            # Intercept all device identifier generation from bottom layer:
            # 1. Module.prototype.require hijacking - intercept child_process, crypto, os and other modules
            # 2. child_process.execSync - intercept REG.exe query MachineGuid
            # 3. crypto.createHash - intercept SHA256 hash calculation
            # 4. crypto.randomUUID - intercept UUID generation
            # 5. os.networkInterfaces - intercept MAC address retrieval
            # 6. @vscode/deviceid - intercept devDeviceId retrieval
            # 7. @vscode/windows-registry - intercept registry reads

            $injectCode = @"
// ========== Cursor Hook Injection Start ==========
;(async function(){/*__cursor_patched__*/
'use strict';
if(globalThis.__cursor_patched__)return;

// ESM compatibility: ensure available require (some versions of main.js may be pure ESM, require not guaranteed)
var __require__=typeof require==='function'?require:null;
if(!__require__){
    try{
        var __m__=await import('module');
        __require__=__m__.createRequire(import.meta.url);
    }catch(e){
        // Exit directly when unable to get require, avoid affecting main process startup
        return;
    }
}

globalThis.__cursor_patched__=true;

// Fixed device identifiers
var __ids__={
    machineId:'$machineId',
    macMachineId:'$macMachineId',
    devDeviceId:'$deviceId',
    sqmId:'$sqmId',
    macAddress:'$macAddress'
};

// Expose to global
globalThis.__cursor_ids__=__ids__;

// Hook Module.prototype.require
var Module=__require__('module');
var _origReq=Module.prototype.require;
var _hooked=new Map();

Module.prototype.require=function(id){
    var result=_origReq.apply(this,arguments);
    if(_hooked.has(id))return _hooked.get(id);
    var hooked=result;

    // Hook child_process
    if(id==='child_process'){
        var _origExecSync=result.execSync;
        result.execSync=function(cmd,opts){
            var cmdStr=String(cmd).toLowerCase();
            if(cmdStr.includes('reg')&&cmdStr.includes('machineguid')){
                return Buffer.from('\r\n    MachineGuid    REG_SZ    '+__ids__.machineId.substring(0,36)+'\r\n');
            }
            if(cmdStr.includes('ioreg')&&cmdStr.includes('ioplatformexpertdevice')){
                return Buffer.from('"IOPlatformUUID" = "'+__ids__.machineId.substring(0,36).toUpperCase()+'"');
            }
            return _origExecSync.apply(this,arguments);
        };
        hooked=result;
    }
    // Hook os
    else if(id==='os'){
        var _origNI=result.networkInterfaces;
        result.networkInterfaces=function(){
            return{'Ethernet':[{address:'192.168.1.100',netmask:'255.255.255.0',family:'IPv4',mac:__ids__.macAddress,internal:false}]};
        };
        hooked=result;
    }
    // Hook crypto
    else if(id==='crypto'){
        var _origCreateHash=result.createHash;
        var _origRandomUUID=result.randomUUID;
        result.createHash=function(algo){
            var hash=_origCreateHash.apply(this,arguments);
            if(algo.toLowerCase()==='sha256'){
                var _origDigest=hash.digest.bind(hash);
                var _origUpdate=hash.update.bind(hash);
                var inputData='';
                hash.update=function(data,enc){inputData+=String(data);return _origUpdate(data,enc);};
                hash.digest=function(enc){
                    if(inputData.includes('MachineGuid')||inputData.includes('IOPlatformUUID')||(inputData.length>=32&&inputData.length<=40)){
                        return enc==='hex'?__ids__.machineId:Buffer.from(__ids__.machineId,'hex');
                    }
                    return _origDigest(enc);
                };
            }
            return hash;
        };
        if(_origRandomUUID){
            var uuidCount=0;
            result.randomUUID=function(){
                uuidCount++;
                if(uuidCount<=2)return __ids__.devDeviceId;
                return _origRandomUUID.apply(this,arguments);
            };
        }
        hooked=result;
    }
    // Hook @vscode/deviceid
    else if(id==='@vscode/deviceid'){
        hooked={...result,getDeviceId:async function(){return __ids__.devDeviceId;}};
    }
    // Hook @vscode/windows-registry
    else if(id==='@vscode/windows-registry'){
        var _origGetReg=result.GetStringRegKey;
        hooked={...result,GetStringRegKey:function(hive,path,name){
            if(name==='MachineId'||path.includes('SQMClient'))return __ids__.sqmId;
            if(name==='MachineGuid'||path.includes('Cryptography'))return __ids__.machineId.substring(0,36);
            return _origGetReg?_origGetReg.apply(this,arguments):'';
        }};
    }

    if(hooked!==result)_hooked.set(id,hooked);
    return hooked;
};

console.log('[Cursor ID Modifier] Enhanced Hook Activated - Official Account【煎饼果子卷AI】');
})();
// ========== Cursor Hook Injection End ==========

"@

            # Find copyright notice end position and inject after it
            if ($content -match '(\*/\s*\n)') {
                $content = $content -replace '(\*/\s*\n)', "`$1$injectCode"
                Write-Host "   $GREEN✓$NC [Solution B] Enhanced Hook code injected (after copyright notice)"
            } else {
                # If copyright notice not found, inject at file beginning
                $content = $injectCode + $content
                Write-Host "   $GREEN✓$NC [Solution B] Enhanced Hook code injected (at file beginning)"
            }

            # Write modified content
            Set-Content -Path $file -Value $content -Encoding UTF8 -NoNewline

            if ($replaced) {
                Write-Host "$GREEN✅ [Success]$NC Enhanced hybrid solution modification successful (someValue replacement + deep Hook)"
            } else {
                Write-Host "$GREEN✅ [Success]$NC Enhanced Hook modification successful"
            }
            $modifiedCount++

        } catch {
            Write-Host "$RED❌ [Error]$NC Failed to modify file: $($_.Exception.Message)"
            # Try to restore from backup
            $fileName = Split-Path $file -Leaf
            $backupFile = "$backupPath\$fileName.original"
            if (Test-Path $backupFile) {
                Copy-Item $backupFile $file -Force
                Write-Host "$YELLOW🔄 [Restore]$NC File restored from backup"
            }
        }
    }

    if ($modifiedCount -gt 0) {
        Write-Host ""
        Write-Host "$GREEN🎉 [Complete]$NC Successfully modified $modifiedCount JS file(s)"
        Write-Host "$BLUE💾 [Backup]$NC Original file backup location: $backupPath"
        Write-Host "$BLUE💡 [Description]$NC Using enhanced Hook solution:"
        Write-Host "   • Solution A: someValue placeholder replacement (stable anchor, cross-version compatible)"
        Write-Host "   • Solution B: Deep module hijacking (child_process, crypto, os, @vscode/*)"
        Write-Host "$BLUE📁 [Configuration]$NC ID configuration file: $idsConfigPath"
        return $true
    } else {
        Write-Host "$RED❌ [Failed]$NC No files were successfully modified"
        return $false
    }
}


# 🚀 New Cursor trial Pro deletion folder function
function Remove-CursorTrialFolders {
    Write-Host ""
    Write-Host "$GREEN🎯 [Core Function]$NC Executing Cursor trial Pro deletion folder..."
    Write-Host "$BLUE📋 [Description]$NC This function will delete specified Cursor-related folders to reset trial status"
    Write-Host ""

    # Define folders to delete
    $foldersToDelete = @()

    # Windows Administrator user paths
    $adminPaths = @(
        "C:\Users\Administrator\.cursor",
        "C:\Users\Administrator\AppData\Roaming\Cursor"
    )

    # Current user paths
    $currentUserPaths = @(
        "$env:USERPROFILE\.cursor",
        "$env:APPDATA\Cursor"
    )

    # Merge all paths
    $foldersToDelete += $adminPaths
    $foldersToDelete += $currentUserPaths

    Write-Host "$BLUE📂 [Detection]$NC Will check the following folders:"
    foreach ($folder in $foldersToDelete) {
        Write-Host "   📁 $folder"
    }
    Write-Host ""

    $deletedCount = 0
    $skippedCount = 0
    $errorCount = 0

    # Delete specified folders
    foreach ($folder in $foldersToDelete) {
        Write-Host "$BLUE🔍 [Check]$NC Checking folder: $folder"

        if (Test-Path $folder) {
            try {
                Write-Host "$YELLOW⚠️  [Warning]$NC Folder found, deleting..."
                Remove-Item -Path $folder -Recurse -Force -ErrorAction Stop
                Write-Host "$GREEN✅ [Success]$NC Deleted folder: $folder"
                $deletedCount++
            }
            catch {
                Write-Host "$RED❌ [Error]$NC Failed to delete folder: $folder"
                Write-Host "$RED💥 [Details]$NC Error message: $($_.Exception.Message)"
                $errorCount++
            }
        } else {
            Write-Host "$YELLOW⏭️  [Skip]$NC Folder does not exist: $folder"
            $skippedCount++
        }
        Write-Host ""
    }

    # Display operation statistics
    Write-Host "$GREEN📊 [Statistics]$NC Operation completion statistics:"
    Write-Host "   ✅ Successfully deleted: $deletedCount folder(s)"
    Write-Host "   ⏭️  Skipped: $skippedCount folder(s)"
    Write-Host "   ❌ Deletion failed: $errorCount folder(s)"
    Write-Host ""

    if ($deletedCount -gt 0) {
        Write-Host "$GREEN🎉 [Complete]$NC Cursor trial Pro folder deletion completed!"

        # 🔧 Pre-create necessary directory structure to avoid permission issues
        Write-Host "$BLUE🔧 [Fix]$NC Pre-creating necessary directory structure to avoid permission issues..."

        $cursorAppData = "$env:APPDATA\Cursor"
        $cursorLocalAppData = "$env:LOCALAPPDATA\cursor"
        $cursorUserProfile = "$env:USERPROFILE\.cursor"

        # Create main directories
        try {
            if (-not (Test-Path $cursorAppData)) {
                New-Item -ItemType Directory -Path $cursorAppData -Force | Out-Null
            }
            if (-not (Test-Path $cursorUserProfile)) {
                New-Item -ItemType Directory -Path $cursorUserProfile -Force | Out-Null
            }
            Write-Host "$GREEN✅ [Complete]$NC Directory structure pre-creation completed"
        } catch {
            Write-Host "$YELLOW⚠️  [Warning]$NC Issue occurred while pre-creating directories: $($_.Exception.Message)"
        }
    } else {
        Write-Host "$YELLOW🤔 [Tip]$NC No folders found that need deletion, may have been cleaned already"
    }
    Write-Host ""
}

# 🔄 Restart Cursor and wait for configuration file generation
function Restart-CursorAndWait {
    Write-Host ""
    Write-Host "$GREEN🔄 [Restart]$NC Restarting Cursor to regenerate configuration file..."

    if (-not $global:CursorProcessInfo) {
        Write-Host "$RED❌ [Error]$NC Cursor process information not found, cannot restart"
        return $false
    }

    $cursorPath = $global:CursorProcessInfo.Path

    # Fix: Ensure path is string type
    if ($cursorPath -is [array]) {
        $cursorPath = $cursorPath[0]
    }

    # Verify path is not empty
    if ([string]::IsNullOrEmpty($cursorPath)) {
        Write-Host "$RED❌ [Error]$NC Cursor path is empty"
        return $false
    }

    Write-Host "$BLUE📍 [Path]$NC Using path: $cursorPath"

    if (-not (Test-Path $cursorPath)) {
        Write-Host "$RED❌ [Error]$NC Cursor executable file does not exist: $cursorPath"

        # Try to use backup paths
        $backupPaths = @(
            "$env:LOCALAPPDATA\Programs\cursor\Cursor.exe",
            "$env:PROGRAMFILES\Cursor\Cursor.exe",
            "$env:PROGRAMFILES(X86)\Cursor\Cursor.exe"
        )

        $foundPath = $null
        foreach ($backupPath in $backupPaths) {
            if (Test-Path $backupPath) {
                $foundPath = $backupPath
                Write-Host "$GREEN💡 [Found]$NC Using backup path: $foundPath"
                break
            }
        }

        if (-not $foundPath) {
            Write-Host "$RED❌ [Error]$NC Unable to find valid Cursor executable file"
            return $false
        }

        $cursorPath = $foundPath
    }

    try {
        Write-Host "$GREEN🚀 [Start]$NC Starting Cursor..."
        $process = Start-Process -FilePath $cursorPath -PassThru -WindowStyle Hidden

        Write-Host "$YELLOW⏳ [Wait]$NC Waiting 20 seconds for Cursor to fully start and generate configuration file..."
        Start-Sleep -Seconds 20

        # Check if configuration file is generated
        $configPath = "$env:APPDATA\Cursor\User\globalStorage\storage.json"
        $maxWait = 45
        $waited = 0

        while (-not (Test-Path $configPath) -and $waited -lt $maxWait) {
            Write-Host "$YELLOW⏳ [Wait]$NC Waiting for configuration file generation... ($waited/$maxWait seconds)"
            Start-Sleep -Seconds 1
            $waited++
        }

        if (Test-Path $configPath) {
            Write-Host "$GREEN✅ [Success]$NC Configuration file generated: $configPath"

            # Additional wait to ensure file is fully written
            Write-Host "$YELLOW⏳ [Wait]$NC Waiting 5 seconds to ensure configuration file is fully written..."
            Start-Sleep -Seconds 5
        } else {
            Write-Host "$YELLOW⚠️  [Warning]$NC Configuration file not generated within expected time"
            Write-Host "$BLUE💡 [Tip]$NC May need to manually start Cursor once to generate configuration file"
        }

        # Force close Cursor
        Write-Host "$YELLOW🔄 [Close]$NC Closing Cursor for configuration modification..."
        if ($process -and -not $process.HasExited) {
            $process.Kill()
            $process.WaitForExit(5000)
        }

        # Ensure all Cursor processes are closed
        Get-Process -Name "Cursor" -ErrorAction SilentlyContinue | Stop-Process -Force
        Get-Process -Name "cursor" -ErrorAction SilentlyContinue | Stop-Process -Force

        Write-Host "$GREEN✅ [Complete]$NC Cursor restart process completed"
        return $true

    } catch {
        Write-Host "$RED❌ [Error]$NC Failed to restart Cursor: $($_.Exception.Message)"
        Write-Host "$BLUE💡 [Debug]$NC Error details: $($_.Exception.GetType().FullName)"
        return $false
    }
}

# 🔒 Force close all Cursor processes (Enhanced version)
function Stop-AllCursorProcesses {
    param(
        [int]$MaxRetries = 3,
        [int]$WaitSeconds = 5
    )

    Write-Host "$BLUE🔒 [Process Check]$NC Checking and closing all Cursor-related processes..."

    # Define all possible Cursor process names
    $cursorProcessNames = @(
        "Cursor",
        "cursor",
        "Cursor Helper",
        "Cursor Helper (GPU)",
        "Cursor Helper (Plugin)",
        "Cursor Helper (Renderer)",
        "CursorUpdater"
    )

    for ($retry = 1; $retry -le $MaxRetries; $retry++) {
        Write-Host "$BLUE🔍 [Check]$NC Process check attempt $retry/$MaxRetries..."

        $foundProcesses = @()
        foreach ($processName in $cursorProcessNames) {
            $processes = Get-Process -Name $processName -ErrorAction SilentlyContinue
            if ($processes) {
                $foundProcesses += $processes
                Write-Host "$YELLOW⚠️  [Found]$NC Process: $processName (PID: $($processes.Id -join ', '))"
            }
        }

        if ($foundProcesses.Count -eq 0) {
            Write-Host "$GREEN✅ [Success]$NC All Cursor processes have been closed"
            return $true
        }

        Write-Host "$YELLOW🔄 [Close]$NC Closing $($foundProcesses.Count) Cursor process(es)..."

        # First try graceful shutdown
        foreach ($process in $foundProcesses) {
            try {
                $process.CloseMainWindow() | Out-Null
                Write-Host "$BLUE  • Graceful shutdown: $($process.ProcessName) (PID: $($process.Id))$NC"
            } catch {
                Write-Host "$YELLOW  • Graceful shutdown failed: $($process.ProcessName)$NC"
            }
        }

        Start-Sleep -Seconds 3

        # Force terminate processes still running
        foreach ($processName in $cursorProcessNames) {
            $processes = Get-Process -Name $processName -ErrorAction SilentlyContinue
            if ($processes) {
                foreach ($process in $processes) {
                    try {
                        Stop-Process -Id $process.Id -Force
                        Write-Host "$RED  • Force terminated: $($process.ProcessName) (PID: $($process.Id))$NC"
                    } catch {
                        Write-Host "$RED  • Force termination failed: $($process.ProcessName)$NC"
                    }
                }
            }
        }

        if ($retry -lt $MaxRetries) {
            Write-Host "$YELLOW⏳ [Wait]$NC Waiting $WaitSeconds seconds before re-checking..."
            Start-Sleep -Seconds $WaitSeconds
        }
    }

    Write-Host "$RED❌ [Failed]$NC After $MaxRetries attempts, Cursor processes are still running"
    return $false
}

# 🔐 Check file permissions and lock status
function Test-FileAccessibility {
    param(
        [string]$FilePath
    )

    Write-Host "$BLUE🔐 [Permission Check]$NC Checking file access permissions: $(Split-Path $FilePath -Leaf)"

    if (-not (Test-Path $FilePath)) {
        Write-Host "$RED❌ [Error]$NC File does not exist"
        return $false
    }

    # Check if file is locked
    try {
        $fileStream = [System.IO.File]::Open($FilePath, 'Open', 'ReadWrite', 'None')
        $fileStream.Close()
        Write-Host "$GREEN✅ [Permission]$NC File is readable/writable, not locked"
        return $true
    } catch [System.IO.IOException] {
        Write-Host "$RED❌ [Locked]$NC File is locked by another process: $($_.Exception.Message)"
        return $false
    } catch [System.UnauthorizedAccessException] {
        Write-Host "$YELLOW⚠️  [Permission]$NC File permissions restricted, attempting to modify permissions..."

        # Try to modify file permissions
        try {
            $file = Get-Item $FilePath
            if ($file.IsReadOnly) {
                $file.IsReadOnly = $false
                Write-Host "$GREEN✅ [Fix]$NC Removed read-only attribute"
            }

            # Test again
            $fileStream = [System.IO.File]::Open($FilePath, 'Open', 'ReadWrite', 'None')
            $fileStream.Close()
            Write-Host "$GREEN✅ [Permission]$NC Permission fix successful"
            return $true
        } catch {
            Write-Host "$RED❌ [Permission]$NC Unable to fix permissions: $($_.Exception.Message)"
            return $false
        }
    } catch {
        Write-Host "$RED❌ [Error]$NC Unknown error: $($_.Exception.Message)"
        return $false
    }
}

# 🧹 Cursor initialization cleanup function (ported from older version)
function Invoke-CursorInitialization {
    Write-Host ""
    Write-Host "$GREEN🧹 [Initialization]$NC Executing Cursor initialization cleanup..."
    $BASE_PATH = "$env:APPDATA\Cursor\User"

    $filesToDelete = @(
        (Join-Path -Path $BASE_PATH -ChildPath "globalStorage\state.vscdb"),
        (Join-Path -Path $BASE_PATH -ChildPath "globalStorage\state.vscdb.backup")
    )

    $folderToCleanContents = Join-Path -Path $BASE_PATH -ChildPath "History"
    $folderToDeleteCompletely = Join-Path -Path $BASE_PATH -ChildPath "workspaceStorage"

    Write-Host "$BLUE🔍 [Debug]$NC Base path: $BASE_PATH"

    # Delete specified files
    foreach ($file in $filesToDelete) {
        Write-Host "$BLUE🔍 [Check]$NC Checking file: $file"
        if (Test-Path $file) {
            try {
                Remove-Item -Path $file -Force -ErrorAction Stop
                Write-Host "$GREEN✅ [Success]$NC Deleted file: $file"
            }
            catch {
                Write-Host "$RED❌ [Error]$NC Failed to delete file $file : $($_.Exception.Message)"
            }
        } else {
            Write-Host "$YELLOW⚠️  [Skip]$NC File does not exist, skipping deletion: $file"
        }
    }

    # Clear specified folder contents
    Write-Host "$BLUE🔍 [Check]$NC Checking folder to clear contents: $folderToCleanContents"
    if (Test-Path $folderToCleanContents) {
        try {
            Get-ChildItem -Path $folderToCleanContents -Recurse | Remove-Item -Force -Recurse -ErrorAction Stop
            Write-Host "$GREEN✅ [Success]$NC Cleared folder contents: $folderToCleanContents"
        }
        catch {
            Write-Host "$RED❌ [Error]$NC Failed to clear folder $folderToCleanContents : $($_.Exception.Message)"
        }
    } else {
        Write-Host "$YELLOW⚠️  [Skip]$NC Folder does not exist, skipping clear: $folderToCleanContents"
    }

    # Completely delete specified folder
    Write-Host "$BLUE🔍 [Check]$NC Checking folder to delete completely: $folderToDeleteCompletely"
    if (Test-Path $folderToDeleteCompletely) {
        try {
            Remove-Item -Path $folderToDeleteCompletely -Recurse -Force -ErrorAction Stop
            Write-Host "$GREEN✅ [Success]$NC Deleted folder: $folderToDeleteCompletely"
        }
        catch {
            Write-Host "$RED❌ [Error]$NC Failed to delete folder $folderToDeleteCompletely : $($_.Exception.Message)"
        }
    } else {
        Write-Host "$YELLOW⚠️  [Skip]$NC Folder does not exist, skipping deletion: $folderToDeleteCompletely"
    }

    Write-Host "$GREEN✅ [Complete]$NC Cursor initialization cleanup completed"
    Write-Host ""
}

# 🔧 Modify system registry MachineGuid (ported from older version)
function Update-MachineGuid {
    try {
        Write-Host "$BLUE🔧 [Registry]$NC Modifying system registry MachineGuid..."

        # Check if registry path exists, create if not
        $registryPath = "HKLM:\SOFTWARE\Microsoft\Cryptography"
        if (-not (Test-Path $registryPath)) {
            Write-Host "$YELLOW⚠️  [Warning]$NC Registry path does not exist: $registryPath, creating..."
            New-Item -Path $registryPath -Force | Out-Null
            Write-Host "$GREEN✅ [Info]$NC Registry path created successfully"
        }

        # Get current MachineGuid, use empty string as default if not exists
        $originalGuid = ""
        try {
            $currentGuid = Get-ItemProperty -Path $registryPath -Name MachineGuid -ErrorAction SilentlyContinue
            if ($currentGuid) {
                $originalGuid = $currentGuid.MachineGuid
                Write-Host "$GREEN✅ [Info]$NC Current registry value:"
                Write-Host "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography"
                Write-Host "    MachineGuid    REG_SZ    $originalGuid"
            } else {
                Write-Host "$YELLOW⚠️  [Warning]$NC MachineGuid value does not exist, will create new value"
            }
        } catch {
            Write-Host "$YELLOW⚠️  [Warning]$NC Failed to read registry: $($_.Exception.Message)"
            Write-Host "$YELLOW⚠️  [Warning]$NC Will attempt to create new MachineGuid value"
        }

        # Create backup file (only when original value exists)
        $backupFile = $null
        if ($originalGuid) {
            $backupFile = "$BACKUP_DIR\MachineGuid_$(Get-Date -Format 'yyyyMMdd_HHmmss').reg"
            Write-Host "$BLUE💾 [Backup]$NC Backing up registry..."
            $backupResult = Start-Process "reg.exe" -ArgumentList "export", "`"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography`"", "`"$backupFile`"" -NoNewWindow -Wait -PassThru

            if ($backupResult.ExitCode -eq 0) {
                Write-Host "$GREEN✅ [Backup]$NC Registry key backed up to: $backupFile"
            } else {
                Write-Host "$YELLOW⚠️  [Warning]$NC Backup creation failed, continuing..."
                $backupFile = $null
            }
        }

        # Generate new GUID
        $newGuid = [System.Guid]::NewGuid().ToString()
        Write-Host "$BLUE🔄 [Generate]$NC New MachineGuid: $newGuid"

        # Update or create registry value
        Set-ItemProperty -Path $registryPath -Name MachineGuid -Value $newGuid -Force -ErrorAction Stop

        # Verify update
        $verifyGuid = (Get-ItemProperty -Path $registryPath -Name MachineGuid -ErrorAction Stop).MachineGuid
        if ($verifyGuid -ne $newGuid) {
            throw "Registry verification failed: updated value ($verifyGuid) does not match expected value ($newGuid)"
        }

        Write-Host "$GREEN✅ [Success]$NC Registry update successful:"
        Write-Host "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography"
        Write-Host "    MachineGuid    REG_SZ    $newGuid"
        return $true
    }
    catch {
        Write-Host "$RED❌ [Error]$NC Registry operation failed: $($_.Exception.Message)"

        # Try to restore backup (if exists)
        if ($backupFile -and (Test-Path $backupFile)) {
            Write-Host "$YELLOW🔄 [Restore]$NC Restoring from backup..."
            $restoreResult = Start-Process "reg.exe" -ArgumentList "import", "`"$backupFile`"" -NoNewWindow -Wait -PassThru

            if ($restoreResult.ExitCode -eq 0) {
                Write-Host "$GREEN✅ [Restore Success]$NC Original registry value restored"
            } else {
                Write-Host "$RED❌ [Error]$NC Restore failed, please manually import backup file: $backupFile"
            }
        } else {
            Write-Host "$YELLOW⚠️  [Warning]$NC Backup file not found or backup creation failed, cannot automatically restore"
        }

        return $false
    }
}

# Check configuration file and environment
function Test-CursorEnvironment {
    param(
        [string]$Mode = "FULL"
    )

    Write-Host ""
    Write-Host "$BLUE🔍 [Environment Check]$NC Checking Cursor environment..."

    $configPath = "$env:APPDATA\Cursor\User\globalStorage\storage.json"
    $cursorAppData = "$env:APPDATA\Cursor"
    $issues = @()

    # Check configuration file
    if (-not (Test-Path $configPath)) {
        $issues += "Configuration file does not exist: $configPath"
    } else {
        try {
            $content = Get-Content $configPath -Raw -Encoding UTF8 -ErrorAction Stop
            $config = $content | ConvertFrom-Json -ErrorAction Stop
            Write-Host "$GREEN✅ [Check]$NC Configuration file format is correct"
        } catch {
            $issues += "Configuration file format error: $($_.Exception.Message)"
        }
    }

    # Check Cursor directory structure
    if (-not (Test-Path $cursorAppData)) {
        $issues += "Cursor application data directory does not exist: $cursorAppData"
    }

    # Check Cursor installation
    $cursorPaths = @(
        "$env:LOCALAPPDATA\Programs\cursor\Cursor.exe",
        "$env:PROGRAMFILES\Cursor\Cursor.exe",
        "$env:PROGRAMFILES(X86)\Cursor\Cursor.exe"
    )

    $cursorFound = $false
    foreach ($path in $cursorPaths) {
        if (Test-Path $path) {
            Write-Host "$GREEN✅ [Check]$NC Found Cursor installation: $path"
            $cursorFound = $true
            break
        }
    }

    if (-not $cursorFound) {
        $issues += "Cursor installation not found, please confirm Cursor is properly installed"
    }

    # Return check results
    if ($issues.Count -eq 0) {
        Write-Host "$GREEN✅ [Environment Check]$NC All checks passed"
        return @{ Success = $true; Issues = @() }
    } else {
        Write-Host "$RED❌ [Environment Check]$NC Found $($issues.Count) issues:"
        foreach ($issue in $issues) {
            Write-Host "$RED  • ${issue}$NC"
        }
        return @{ Success = $false; Issues = $issues }
    }
}

# �🛠️ Modify machine code configuration (Enhanced Version)
function Modify-MachineCodeConfig {
    param(
        [string]$Mode = "FULL"
    )

    Write-Host ""
    Write-Host "$GREEN🛠️  [Configuration]$NC Modifying machine code configuration..."

    $configPath = "$env:APPDATA\Cursor\User\globalStorage\storage.json"

    # Enhanced configuration file check
    if (-not (Test-Path $configPath)) {
        Write-Host "$RED❌ [Error]$NC Configuration file does not exist: $configPath"
        Write-Host ""
        Write-Host "$YELLOW💡 [Solution]$NC Please try the following steps:"
        Write-Host "$BLUE  1️⃣  Manually start Cursor application$NC"
        Write-Host "$BLUE  2️⃣  Wait for Cursor to fully load (about 30 seconds)$NC"
        Write-Host "$BLUE  3️⃣  Close Cursor application$NC"
        Write-Host "$BLUE  4️⃣  Re-run this script$NC"
        Write-Host ""
        Write-Host "$YELLOW⚠️  [Alternative]$NC If the problem persists:"
        Write-Host "$BLUE  • Select the script's 'Reset Environment + Modify Machine Code' option$NC"
        Write-Host "$BLUE  • This option will automatically generate the configuration file$NC"
        Write-Host ""

        # Provide user choice
        $userChoice = Read-Host "Do you want to try starting Cursor now to generate configuration file? (y/n)"
        if ($userChoice -match "^(y|yes)$") {
            Write-Host "$BLUE🚀 [Attempt]$NC Attempting to start Cursor..."
            return Start-CursorToGenerateConfig
        }

        return $false
    }

    # Even in machine code only modification mode, ensure processes are completely closed
    if ($Mode -eq "MODIFY_ONLY") {
        Write-Host "$BLUE🔒 [Safety Check]$NC Even in machine code only modification mode, need to ensure Cursor processes are completely closed"
        if (-not (Stop-AllCursorProcesses -MaxRetries 3 -WaitSeconds 3)) {
            Write-Host "$RED❌ [Error]$NC Unable to close all Cursor processes, modification may fail"
            $userChoice = Read-Host "Do you want to force continue? (y/n)"
            if ($userChoice -notmatch "^(y|yes)$") {
                return $false
            }
        }
    }

    # Check file permissions and lock status
    if (-not (Test-FileAccessibility -FilePath $configPath)) {
        Write-Host "$RED❌ [Error]$NC Unable to access configuration file, may be locked or insufficient permissions"
        return $false
    }

    # Verify configuration file format and display structure
    try {
        Write-Host "$BLUE🔍 [Verify]$NC Checking configuration file format..."
        $originalContent = Get-Content $configPath -Raw -Encoding UTF8 -ErrorAction Stop
        $config = $originalContent | ConvertFrom-Json -ErrorAction Stop
        Write-Host "$GREEN✅ [Verify]$NC Configuration file format is correct"

        # Display relevant properties in current configuration file
        Write-Host "$BLUE📋 [Current Configuration]$NC Checking existing telemetry properties:"
        $telemetryProperties = @('telemetry.machineId', 'telemetry.macMachineId', 'telemetry.devDeviceId', 'telemetry.sqmId')
        foreach ($prop in $telemetryProperties) {
            if ($config.PSObject.Properties[$prop]) {
                $value = $config.$prop
                $displayValue = if ($value.Length -gt 20) { "$($value.Substring(0,20))..." } else { $value }
                Write-Host "$GREEN  ✓ ${prop}$NC = $displayValue"
            } else {
                Write-Host "$YELLOW  - ${prop}$NC (does not exist, will create)"
            }
        }
        Write-Host ""
    } catch {
        Write-Host "$RED❌ [Error]$NC Configuration file format error: $($_.Exception.Message)"
        Write-Host "$YELLOW💡 [Suggestion]$NC Configuration file may be corrupted, suggest selecting 'Reset Environment + Modify Machine Code' option"
        return $false
    }

    # Implement atomic file operations and retry mechanism
    $maxRetries = 3
    $retryCount = 0

    while ($retryCount -lt $maxRetries) {
        $retryCount++
        Write-Host ""
        Write-Host "$BLUE🔄 [Attempt]$NC Modification attempt $retryCount/$maxRetries..."

        try {
            # Display operation progress
            Write-Host "$BLUE⏳ [Progress]$NC 1/6 - Generating new device identifiers..."

            # Generate new IDs
            $MAC_MACHINE_ID = [System.Guid]::NewGuid().ToString()
            $UUID = [System.Guid]::NewGuid().ToString()
            $prefixBytes = [System.Text.Encoding]::UTF8.GetBytes("auth0|user_")
            $prefixHex = -join ($prefixBytes | ForEach-Object { '{0:x2}' -f $_ })
            $randomBytes = New-Object byte[] 32
            $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
            $rng.GetBytes($randomBytes)
            $randomPart = [System.BitConverter]::ToString($randomBytes) -replace '-',''
            $rng.Dispose()
            $MACHINE_ID = "${prefixHex}${randomPart}"
            $SQM_ID = "{$([System.Guid]::NewGuid().ToString().ToUpper())}"
            # 🔧 New: serviceMachineId (for storage.serviceMachineId)
            $SERVICE_MACHINE_ID = [System.Guid]::NewGuid().ToString()
            # 🔧 New: firstSessionDate (reset first session date)
            $FIRST_SESSION_DATE = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")

            Write-Host "$GREEN✅ [Progress]$NC 1/7 - Device identifier generation completed"

            Write-Host "$BLUE⏳ [Progress]$NC 2/7 - Creating backup directory..."

            # Backup original values (enhanced version)
            $backupDir = "$env:APPDATA\Cursor\User\globalStorage\backups"
            if (-not (Test-Path $backupDir)) {
                New-Item -ItemType Directory -Path $backupDir -Force -ErrorAction Stop | Out-Null
            }

            $backupName = "storage.json.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')_retry$retryCount"
            $backupPath = "$backupDir\$backupName"

            Write-Host "$BLUE⏳ [Progress]$NC 3/7 - Backing up original configuration..."
            Copy-Item $configPath $backupPath -ErrorAction Stop

            # Verify backup was successful
            if (Test-Path $backupPath) {
                $backupSize = (Get-Item $backupPath).Length
                $originalSize = (Get-Item $configPath).Length
                if ($backupSize -eq $originalSize) {
                    Write-Host "$GREEN✅ [Progress]$NC 3/7 - Configuration backup successful: $backupName"
                } else {
                    Write-Host "$YELLOW⚠️  [Warning]$NC Backup file size mismatch, but continuing..."
                }
            } else {
                throw "Backup file creation failed"
            }

            Write-Host "$BLUE⏳ [Progress]$NC 4/7 - Reading original configuration to memory..."

            # Atomic operation: read original content to memory
            $originalContent = Get-Content $configPath -Raw -Encoding UTF8 -ErrorAction Stop
            $config = $originalContent | ConvertFrom-Json -ErrorAction Stop

            Write-Host "$BLUE⏳ [Progress]$NC 5/7 - Updating configuration in memory..."

            # Update configuration values (safe way, ensure properties exist)
            # 🔧 Fix: Add storage.serviceMachineId and telemetry.firstSessionDate
            $propertiesToUpdate = @{
                'telemetry.machineId' = $MACHINE_ID
                'telemetry.macMachineId' = $MAC_MACHINE_ID
                'telemetry.devDeviceId' = $UUID
                'telemetry.sqmId' = $SQM_ID
                'storage.serviceMachineId' = $SERVICE_MACHINE_ID
                'telemetry.firstSessionDate' = $FIRST_SESSION_DATE
            }

            foreach ($property in $propertiesToUpdate.GetEnumerator()) {
                $key = $property.Key
                $value = $property.Value

                # Use Add-Member or direct assignment in a safe way
                if ($config.PSObject.Properties[$key]) {
                    # Property exists, update directly
                    $config.$key = $value
                    Write-Host "$BLUE  ✓ Updated property: ${key}$NC"
                } else {
                    # Property does not exist, add new property
                    $config | Add-Member -MemberType NoteProperty -Name $key -Value $value -Force
                    Write-Host "$BLUE  + Added property: ${key}$NC"
                }
            }

            Write-Host "$BLUE⏳ [Progress]$NC 6/7 - Atomically writing new configuration file..."

            # Atomic operation: delete original file, write new file
            $tempPath = "$configPath.tmp"
            $updatedJson = $config | ConvertTo-Json -Depth 10

            # Write to temporary file
            [System.IO.File]::WriteAllText($tempPath, $updatedJson, [System.Text.Encoding]::UTF8)

            # Verify temporary file
            $tempContent = Get-Content $tempPath -Raw -Encoding UTF8
            $tempConfig = $tempContent | ConvertFrom-Json

            # Verify all properties are correctly written
            $tempVerificationPassed = $true
            foreach ($property in $propertiesToUpdate.GetEnumerator()) {
                $key = $property.Key
                $expectedValue = $property.Value
                $actualValue = $tempConfig.$key

                if ($actualValue -ne $expectedValue) {
                    $tempVerificationPassed = $false
                    Write-Host "$RED  ✗ Temporary file verification failed: ${key}$NC"
                    break
                }
            }

            if (-not $tempVerificationPassed) {
                Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
                throw "Temporary file verification failed"
            }

            # Atomic replacement: delete original file, rename temporary file
            Remove-Item $configPath -Force
            Move-Item $tempPath $configPath

            # Set file to read-only (optional)
            $file = Get-Item $configPath
            $file.IsReadOnly = $false  # Keep writable for subsequent modifications

            # Final verification of modification results
            Write-Host "$BLUE⏳ [Progress]$NC 7/7 - Verifying new configuration file..."

            $verifyContent = Get-Content $configPath -Raw -Encoding UTF8
            $verifyConfig = $verifyContent | ConvertFrom-Json

            $verificationPassed = $true
            $verificationResults = @()

            # Safely verify each property
            foreach ($property in $propertiesToUpdate.GetEnumerator()) {
                $key = $property.Key
                $expectedValue = $property.Value
                $actualValue = $verifyConfig.$key

                if ($actualValue -eq $expectedValue) {
                    $verificationResults += "✓ ${key}: Verification passed"
                } else {
                    $verificationResults += "✗ ${key}: Verification failed (Expected: ${expectedValue}, Actual: ${actualValue})"
                    $verificationPassed = $false
                }
            }

            # Display verification results
            Write-Host "$BLUE📋 [Verification Details]$NC"
            foreach ($result in $verificationResults) {
                Write-Host "   $result"
            }

            if ($verificationPassed) {
                Write-Host "$GREEN✅ [Success]$NC Attempt $retryCount modification successful!"
                Write-Host ""
                Write-Host "$GREEN🎉 [Complete]$NC Machine code configuration modification completed!"
                Write-Host "$BLUE📋 [Details]$NC Updated the following identifiers:"
                Write-Host "   🔹 machineId: $MACHINE_ID"
                Write-Host "   🔹 macMachineId: $MAC_MACHINE_ID"
                Write-Host "   🔹 devDeviceId: $UUID"
                Write-Host "   🔹 sqmId: $SQM_ID"
                Write-Host "   🔹 serviceMachineId: $SERVICE_MACHINE_ID"
                Write-Host "   🔹 firstSessionDate: $FIRST_SESSION_DATE"
                Write-Host ""
                Write-Host "$GREEN💾 [Backup]$NC Original configuration backed up to: $backupName"

                # 🔧 New: Modify machineid file
                Write-Host "$BLUE🔧 [machineid]$NC Modifying machineid file..."
                $machineIdFilePath = "$env:APPDATA\Cursor\machineid"
                try {
                    if (Test-Path $machineIdFilePath) {
                        # Backup original machineid file
                        $machineIdBackup = "$backupDir\machineid.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
                        Copy-Item $machineIdFilePath $machineIdBackup -Force
                        Write-Host "$GREEN💾 [Backup]$NC machineid file backed up: $machineIdBackup"
                    }
                    # Write new serviceMachineId to machineid file
                    [System.IO.File]::WriteAllText($machineIdFilePath, $SERVICE_MACHINE_ID, [System.Text.Encoding]::UTF8)
                    Write-Host "$GREEN✅ [machineid]$NC machineid file modification successful: $SERVICE_MACHINE_ID"

                    # Set machineid file to read-only
                    $machineIdFile = Get-Item $machineIdFilePath
                    $machineIdFile.IsReadOnly = $true
                    Write-Host "$GREEN🔒 [Protection]$NC machineid file set to read-only"
                } catch {
                    Write-Host "$YELLOW⚠️  [machineid]$NC machineid file modification failed: $($_.Exception.Message)"
                    Write-Host "$BLUE💡 [Tip]$NC You can manually modify file: $machineIdFilePath"
                }

                # 🔧 New: Modify .updaterId file (updater device identifier)
                Write-Host "$BLUE🔧 [updaterId]$NC Modifying .updaterId file..."
                $updaterIdFilePath = "$env:APPDATA\Cursor\.updaterId"
                try {
                    if (Test-Path $updaterIdFilePath) {
                        # Backup original .updaterId file
                        $updaterIdBackup = "$backupDir\.updaterId.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
                        Copy-Item $updaterIdFilePath $updaterIdBackup -Force
                        Write-Host "$GREEN💾 [Backup]$NC .updaterId file backed up: $updaterIdBackup"
                    }
                    # Generate new updaterId (UUID format)
                    $newUpdaterId = [System.Guid]::NewGuid().ToString()
                    [System.IO.File]::WriteAllText($updaterIdFilePath, $newUpdaterId, [System.Text.Encoding]::UTF8)
                    Write-Host "$GREEN✅ [updaterId]$NC .updaterId file modification successful: $newUpdaterId"

                    # Set .updaterId file to read-only
                    $updaterIdFile = Get-Item $updaterIdFilePath
                    $updaterIdFile.IsReadOnly = $true
                    Write-Host "$GREEN🔒 [Protection]$NC .updaterId file set to read-only"
                } catch {
                    Write-Host "$YELLOW⚠️  [updaterId]$NC .updaterId file modification failed: $($_.Exception.Message)"
                    Write-Host "$BLUE💡 [Tip]$NC You can manually modify file: $updaterIdFilePath"
                }

                # 🔒 Add configuration file protection mechanism
                Write-Host "$BLUE🔒 [Protection]$NC Setting configuration file protection..."
                try {
                    $configFile = Get-Item $configPath
                    $configFile.IsReadOnly = $true
                    Write-Host "$GREEN✅ [Protection]$NC Configuration file set to read-only to prevent Cursor from overwriting modifications"
                    Write-Host "$BLUE💡 [Tip]$NC File path: $configPath"
                } catch {
                    Write-Host "$YELLOW⚠️  [Protection]$NC Failed to set read-only attribute: $($_.Exception.Message)"
                    Write-Host "$BLUE💡 [Suggestion]$NC You can manually right-click file → Properties → Check 'Read-only'"
                }
                Write-Host "$BLUE 🔒 [Security]$NC Recommend restarting Cursor to ensure configuration takes effect"
                return $true
            } else {
                Write-Host "$RED❌ [Failed]$NC Attempt $retryCount verification failed"
                if ($retryCount -lt $maxRetries) {
                    Write-Host "$BLUE🔄 [Restore]$NC Restoring backup, preparing to retry..."
                    Copy-Item $backupPath $configPath -Force
                    Start-Sleep -Seconds 2
                    continue  # Continue to next retry
                } else {
                    Write-Host "$RED❌ [Final Failure]$NC All retries failed, restoring original configuration"
                    Copy-Item $backupPath $configPath -Force
                    return $false
                }
            }

        } catch {
            Write-Host "$RED❌ [Exception]$NC Attempt $retryCount encountered exception: $($_.Exception.Message)"
            Write-Host "$BLUE💡 [Debug Info]$NC Error type: $($_.Exception.GetType().FullName)"

            # Clean up temporary files
            if (Test-Path "$configPath.tmp") {
                Remove-Item "$configPath.tmp" -Force -ErrorAction SilentlyContinue
            }

            if ($retryCount -lt $maxRetries) {
                Write-Host "$BLUE🔄 [Restore]$NC Restoring backup, preparing to retry..."
                if (Test-Path $backupPath) {
                    Copy-Item $backupPath $configPath -Force
                }
                Start-Sleep -Seconds 3
                continue  # Continue to next retry
            } else {
                Write-Host "$RED❌ [Final Failure]$NC All retries failed"
                # Try to restore backup
                if (Test-Path $backupPath) {
                    Write-Host "$BLUE🔄 [Restore]$NC Restoring backup configuration..."
                    try {
                        Copy-Item $backupPath $configPath -Force
                        Write-Host "$GREEN✅ [Restore]$NC Original configuration restored"
                    } catch {
                        Write-Host "$RED❌ [Error]$NC Restore backup failed: $($_.Exception.Message)"
                    }
                }
                return $false
            }
        }
    }

    # If we reach here, all retries have failed
    Write-Host "$RED❌ [Final Failure]$NC Unable to complete modification after $maxRetries attempts"
    return $false

}

# Start Cursor to generate configuration file
function Start-CursorToGenerateConfig {
    Write-Host "$BLUE🚀 [Start]$NC Attempting to start Cursor to generate configuration file..."

    # Find Cursor executable file
    $cursorPaths = @(
        "$env:LOCALAPPDATA\Programs\cursor\Cursor.exe",
        "$env:PROGRAMFILES\Cursor\Cursor.exe",
        "$env:PROGRAMFILES(X86)\Cursor\Cursor.exe"
    )

    $cursorPath = $null
    foreach ($path in $cursorPaths) {
        if (Test-Path $path) {
            $cursorPath = $path
            break
        }
    }

    if (-not $cursorPath) {
        Write-Host "$RED❌ [Error]$NC Cursor installation not found, please confirm Cursor is properly installed"
        return $false
    }

    try {
        Write-Host "$BLUE📍 [Path]$NC Using Cursor path: $cursorPath"

        # Start Cursor
        $process = Start-Process -FilePath $cursorPath -PassThru -WindowStyle Normal
        Write-Host "$GREEN🚀 [Start]$NC Cursor started, PID: $($process.Id)"

        Write-Host "$YELLOW⏳ [Wait]$NC Please wait for Cursor to fully load (about 30 seconds)..."
        Write-Host "$BLUE💡 [Tip]$NC You can manually close Cursor after it fully loads"

        # Wait for configuration file generation
        $configPath = "$env:APPDATA\Cursor\User\globalStorage\storage.json"
        $maxWait = 60
        $waited = 0

        while (-not (Test-Path $configPath) -and $waited -lt $maxWait) {
            Start-Sleep -Seconds 2
            $waited += 2
            if ($waited % 10 -eq 0) {
                Write-Host "$YELLOW⏳ [Wait]$NC Waiting for configuration file generation... ($waited/$maxWait seconds)"
            }
        }

        if (Test-Path $configPath) {
            Write-Host "$GREEN✅ [Success]$NC Configuration file generated!"
            Write-Host "$BLUE💡 [Tip]$NC You can now close Cursor and re-run the script"
            return $true
        } else {
            Write-Host "$YELLOW⚠️  [Timeout]$NC Configuration file not generated within expected time"
            Write-Host "$BLUE💡 [Suggestion]$NC Please manually operate Cursor (e.g., create a new file) to trigger configuration generation"
            return $false
        }

    } catch {
        Write-Host "$RED❌ [Error]$NC Failed to start Cursor: $($_.Exception.Message)"
        return $false
    }
}

# Check administrator privileges
function Test-Administrator {
    $user = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($user)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    Write-Host "$RED[ERROR]$NC Please run this script as Administrator"
    Write-Host "Right-click the script and select 'Run as Administrator'"
    Read-Host "Press Enter to exit"
    exit 1
}

# Display Logo
Clear-Host
Write-Host @"

    ██████╗██╗   ██╗██████╗ ███████╗ ██████╗ ██████╗ 
   ██╔════╝██║   ██║██╔══██╗██╔════╝██╔═══██╗██╔══██╗
   ██║     ██║   ██║██████╔╝███████╗██║   ██║██████╔╝
   ██║     ██║   ██║██╔══██╗╚════██║██║   ██║██╔══██╗
   ╚██████╗╚██████╔╝██║  ██║███████║╚██████╔╝██║  ██║
    ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝  ╚═╝

"@
Write-Host "$BLUE================================$NC"
Write-Host "$GREEN🚀   Cursor Free Trial Reset Tool          $NC"
Write-Host "$YELLOW📱  Follow Official Account【煎饼果子卷AI】 $NC"
Write-Host "$YELLOW🤝  Share more Cursor tips and AI knowledge (Script is free, follow the account to join group for more tips and experts)  $NC"
Write-Host "$YELLOW💡  [Important] This tool is free. If it helps you, please follow the official account【煎饼果子卷AI】  $NC"
Write-Host ""
Write-Host "$YELLOW⚡  [Advertisement] Official Cursor Accounts: Pro¥65 | Pro+¥265 | Ultra¥888 Exclusive account/7-day warranty, WeChat: JavaRookie666  $NC"
Write-Host "$BLUE================================$NC"

# 🎯 User Selection Menu
Write-Host ""
Write-Host "$GREEN🎯 [Selection Mode]$NC Please select the operation you want to perform:"
Write-Host ""
Write-Host "$BLUE  1️⃣  Modify Machine Code Only$NC"
Write-Host "$YELLOW      • Execute machine code modification$NC"
Write-Host "$YELLOW      • Inject JS code into core files$NC"
Write-Host "$YELLOW      • Skip folder deletion/environment reset steps$NC"
Write-Host "$YELLOW      • Preserve existing Cursor configuration and data$NC"
Write-Host ""
Write-Host "$BLUE  2️⃣  Reset Environment + Modify Machine Code$NC"
Write-Host "$RED      • Execute complete environment reset (delete Cursor folders)$NC"
Write-Host "$RED      • ⚠️  Configuration will be lost, please backup$NC"
Write-Host "$YELLOW      • Modify machine code$NC"
Write-Host "$YELLOW      • Inject JS code into core files$NC"
Write-Host "$YELLOW      • This is equivalent to the full script behavior$NC"
Write-Host ""

# Get user selection
do {
    $userChoice = Read-Host "Please enter your choice (1 or 2)"
    if ($userChoice -eq "1") {
        Write-Host "$GREEN✅ [Selection]$NC You selected: Modify Machine Code Only"
        $executeMode = "MODIFY_ONLY"
        break
    } elseif ($userChoice -eq "2") {
        Write-Host "$GREEN✅ [Selection]$NC You selected: Reset Environment + Modify Machine Code"
        Write-Host "$RED⚠️  [Important Warning]$NC This operation will delete all Cursor configuration files!"
        $confirmReset = Read-Host "Confirm complete reset? (Enter yes to confirm, any other key to cancel)"
        if ($confirmReset -eq "yes") {
            $executeMode = "RESET_AND_MODIFY"
            break
        } else {
            Write-Host "$YELLOW👋 [Cancelled]$NC User cancelled reset operation"
            continue
        }
    } else {
        Write-Host "$RED❌ [Error]$NC Invalid choice, please enter 1 or 2"
    }
} while ($true)

Write-Host ""

# 📋 Display execution flow based on selection
if ($executeMode -eq "MODIFY_ONLY") {
    Write-Host "$GREEN📋 [Execution Flow]$NC Modify Machine Code Only mode will execute the following steps:"
    Write-Host "$BLUE  1️⃣  Detect Cursor configuration file$NC"
    Write-Host "$BLUE  2️⃣  Backup existing configuration file$NC"
    Write-Host "$BLUE  3️⃣  Modify machine code configuration$NC"
    Write-Host "$BLUE  4️⃣  Display operation completion information$NC"
    Write-Host ""
    Write-Host "$YELLOW⚠️  [Notes]$NC"
    Write-Host "$YELLOW  • Will not delete any folders or reset environment$NC"
    Write-Host "$YELLOW  • Preserves all existing configuration and data$NC"
    Write-Host "$YELLOW  • Original configuration file will be automatically backed up$NC"
} else {
    Write-Host "$GREEN📋 [Execution Flow]$NC Reset Environment + Modify Machine Code mode will execute the following steps:"
    Write-Host "$BLUE  1️⃣  Detect and close Cursor processes$NC"
    Write-Host "$BLUE  2️⃣  Save Cursor program path information$NC"
    Write-Host "$BLUE  3️⃣  Delete specified Cursor trial-related folders$NC"
    Write-Host "$BLUE      📁 C:\Users\Administrator\.cursor$NC"
    Write-Host "$BLUE      📁 C:\Users\Administrator\AppData\Roaming\Cursor$NC"
    Write-Host "$BLUE      📁 C:\Users\%USERNAME%\.cursor$NC"
    Write-Host "$BLUE      📁 C:\Users\%USERNAME%\AppData\Roaming\Cursor$NC"
    Write-Host "$BLUE  3.5️⃣ Pre-create necessary directory structure to avoid permission issues$NC"
    Write-Host "$BLUE  4️⃣  Restart Cursor to generate new configuration file$NC"
    Write-Host "$BLUE  5️⃣  Wait for configuration file generation (up to 45 seconds)$NC"
    Write-Host "$BLUE  6️⃣  Close Cursor process$NC"
    Write-Host "$BLUE  7️⃣  Modify newly generated machine code configuration file$NC"
    Write-Host "$BLUE  8️⃣  Display operation completion statistics$NC"
    Write-Host ""
    Write-Host "$YELLOW⚠️  [Notes]$NC"
    Write-Host "$YELLOW  • Do not manually operate Cursor during script execution$NC"
    Write-Host "$YELLOW  • It is recommended to close all Cursor windows before execution$NC"
    Write-Host "$YELLOW  • Cursor needs to be restarted after execution completes$NC"
    Write-Host "$YELLOW  • Original configuration file will be automatically backed up to backups folder$NC"
}
Write-Host ""

# 🤔 User confirmation
Write-Host "$GREEN🤔 [Confirmation]$NC Please confirm you understand the above execution flow"
$confirmation = Read-Host "Continue execution? (Enter y or yes to continue, any other key to exit)"
if ($confirmation -notmatch "^(y|yes)$") {
    Write-Host "$YELLOW👋 [Exit]$NC User cancelled execution, script exiting"
    Read-Host "Press Enter to exit"
    exit 0
}
Write-Host "$GREEN✅ [Confirmation]$NC User confirmed to continue execution"
Write-Host ""

# Get and display Cursor version
function Get-CursorVersion {
    try {
        # Primary detection path
        $packagePath = "$env:LOCALAPPDATA\\Programs\\cursor\\resources\\app\\package.json"
        
        if (Test-Path $packagePath) {
            $packageJson = Get-Content $packagePath -Raw | ConvertFrom-Json
            if ($packageJson.version) {
                Write-Host "$GREEN[Info]$NC Currently installed Cursor version: v$($packageJson.version)"
                return $packageJson.version
            }
        }

        # Alternate path detection
        $altPath = "$env:LOCALAPPDATA\\cursor\\resources\\app\\package.json"
        if (Test-Path $altPath) {
            $packageJson = Get-Content $altPath -Raw | ConvertFrom-Json
            if ($packageJson.version) {
                Write-Host "$GREEN[Info]$NC Currently installed Cursor version: v$($packageJson.version)"
                return $packageJson.version
            }
        }

        Write-Host "$YELLOW[Warning]$NC Unable to detect Cursor version"
        Write-Host "$YELLOW[Tip]$NC Please ensure Cursor is properly installed"
        return $null
    }
    catch {
        Write-Host "$RED[Error]$NC Failed to get Cursor version: $_"
        return $null
    }
}

# Get and display version information
$cursorVersion = Get-CursorVersion
Write-Host ""

Write-Host "$YELLOW💡 [Important Note]$NC Latest 1.0.x versions are supported"

Write-Host ""

# 🔍 Check and close Cursor processes
Write-Host "$GREEN🔍 [Check]$NC Checking Cursor processes..."

function Get-ProcessDetails {
    param($processName)
    Write-Host "$BLUE🔍 [Debug]$NC Getting detailed information for $processName process:"
    Get-WmiObject Win32_Process -Filter "name='$processName'" |
        Select-Object ProcessId, ExecutablePath, CommandLine |
        Format-List
}

# Define maximum retry count and wait time
$MAX_RETRIES = 5
$WAIT_TIME = 1

# 🔄 Handle process closure and save process information
function Close-CursorProcessAndSaveInfo {
    param($processName)

    $global:CursorProcessInfo = $null

    $processes = Get-Process -Name $processName -ErrorAction SilentlyContinue
    if ($processes) {
        Write-Host "$YELLOW⚠️  [Warning]$NC Found $processName is running"

        # 💾 Save process information for later restart - Fix: ensure getting single process path
        $firstProcess = if ($processes -is [array]) { $processes[0] } else { $processes }
        $processPath = $firstProcess.Path

        # Ensure path is string not array
        if ($processPath -is [array]) {
            $processPath = $processPath[0]
        }

        $global:CursorProcessInfo = @{
            ProcessName = $firstProcess.ProcessName
            Path = $processPath
            StartTime = $firstProcess.StartTime
        }
        Write-Host "$GREEN💾 [Saved]$NC Process information saved: $($global:CursorProcessInfo.Path)"

        Get-ProcessDetails $processName

        Write-Host "$YELLOW🔄 [Operation]$NC Attempting to close $processName..."
        Stop-Process -Name $processName -Force

        $retryCount = 0
        while ($retryCount -lt $MAX_RETRIES) {
            $process = Get-Process -Name $processName -ErrorAction SilentlyContinue
            if (-not $process) { break }

            $retryCount++
            if ($retryCount -ge $MAX_RETRIES) {
                Write-Host "$RED❌ [Error]$NC Unable to close $processName after $MAX_RETRIES attempts"
                Get-ProcessDetails $processName
                Write-Host "$RED💥 [Error]$NC Please manually close the process and retry"
                Read-Host "Press Enter to exit"
                exit 1
            }
            Write-Host "$YELLOW⏳ [Waiting]$NC Waiting for process to close, attempt $retryCount/$MAX_RETRIES..."
            Start-Sleep -Seconds $WAIT_TIME
        }
        Write-Host "$GREEN✅ [Success]$NC $processName has been successfully closed"
    } else {
        Write-Host "$BLUE💡 [Info]$NC No $processName process found running"
        # Try to find Cursor installation path
        $cursorPaths = @(
            "$env:LOCALAPPDATA\Programs\cursor\Cursor.exe",
            "$env:PROGRAMFILES\Cursor\Cursor.exe",
            "$env:PROGRAMFILES(X86)\Cursor\Cursor.exe"
        )

        foreach ($path in $cursorPaths) {
            if (Test-Path $path) {
                $global:CursorProcessInfo = @{
                    ProcessName = "Cursor"
                    Path = $path
                    StartTime = $null
                }
                Write-Host "$GREEN💾 [Found]$NC Found Cursor installation path: $path"
                break
            }
        }

        if (-not $global:CursorProcessInfo) {
            Write-Host "$YELLOW⚠️  [Warning]$NC Cursor installation path not found, will use default path"
            $global:CursorProcessInfo = @{
                ProcessName = "Cursor"
                Path = "$env:LOCALAPPDATA\Programs\cursor\Cursor.exe"
                StartTime = $null
            }
        }
    }
}

# �️ Ensure backup directory exists
if (-not (Test-Path $BACKUP_DIR)) {
    try {
        New-Item -ItemType Directory -Path $BACKUP_DIR -Force | Out-Null
        Write-Host "$GREEN✅ [Backup Directory]$NC Backup directory created successfully: $BACKUP_DIR"
    } catch {
        Write-Host "$YELLOW⚠️  [Warning]$NC Backup directory creation failed: $($_.Exception.Message)"
    }
}

# �🚀 Execute corresponding function based on user selection
if ($executeMode -eq "MODIFY_ONLY") {
    Write-Host "$GREEN🚀 [Start]$NC Starting machine code only modification function..."

    # First perform environment check
    $envCheck = Test-CursorEnvironment -Mode "MODIFY_ONLY"
    if (-not $envCheck.Success) {
        Write-Host ""
        Write-Host "$RED❌ [Environment Check Failed]$NC Cannot continue execution, found the following issues:"
        foreach ($issue in $envCheck.Issues) {
            Write-Host "$RED  • ${issue}$NC"
        }
        Write-Host ""
        Write-Host "$YELLOW💡 [Suggestion]$NC Please select one of the following operations:"
        Write-Host "$BLUE  1️⃣  Select 'Reset Environment + Modify Machine Code' option (Recommended)$NC"
        Write-Host "$BLUE  2️⃣  Manually start Cursor once, then re-run the script$NC"
        Write-Host "$BLUE  3️⃣  Check if Cursor is properly installed$NC"
        Write-Host ""
        Read-Host "Press Enter to exit"
        exit 1
    }

    # Execute machine code modification
    $configSuccess = Modify-MachineCodeConfig -Mode "MODIFY_ONLY"

    if ($configSuccess) {
        Write-Host ""
        Write-Host "$GREEN🎉 [Configuration File]$NC Machine code configuration file modification completed!"

        # Add registry modification
        Write-Host "$BLUE🔧 [Registry]$NC Modifying system registry..."
        $registrySuccess = Update-MachineGuid

        # 🔧 New: JavaScript injection function (enhanced device identification bypass)
        Write-Host ""
        Write-Host "$BLUE🔧 [Device Identification Bypass]$NC Executing JavaScript injection function..."
        Write-Host "$BLUE💡 [Description]$NC This function will directly modify Cursor core JS files to achieve deeper device identification bypass"
        $jsSuccess = Modify-CursorJSFiles

        if ($registrySuccess) {
            Write-Host "$GREEN✅ [Registry]$NC System registry modification successful"

            if ($jsSuccess) {
                Write-Host "$GREEN✅ [JavaScript Injection]$NC JavaScript injection function executed successfully"
                Write-Host ""
                Write-Host "$GREEN🎉 [Complete]$NC All machine code modifications completed (Enhanced version)!"
                Write-Host "$BLUE📋 [Details]$NC Completed the following modifications:"
                Write-Host "$GREEN  ✓ Cursor configuration file (storage.json)$NC"
                Write-Host "$GREEN  ✓ System registry (MachineGuid)$NC"
                Write-Host "$GREEN  ✓ JavaScript kernel injection (device identification bypass)$NC"
            } else {
                Write-Host "$YELLOW⚠️  [JavaScript Injection]$NC JavaScript injection function failed, but other functions succeeded"
                Write-Host ""
                Write-Host "$GREEN🎉 [Complete]$NC All machine code modifications completed!"
                Write-Host "$BLUE📋 [Details]$NC Completed the following modifications:"
                Write-Host "$GREEN  ✓ Cursor configuration file (storage.json)$NC"
                Write-Host "$GREEN  ✓ System registry (MachineGuid)$NC"
                Write-Host "$YELLOW  ⚠ JavaScript kernel injection (partially failed)$NC"
            }

            # 🔒 Add configuration file protection mechanism
            Write-Host "$BLUE🔒 [Protection]$NC Setting configuration file protection..."
            try {
                $configPath = "$env:APPDATA\Cursor\User\globalStorage\storage.json"
                $configFile = Get-Item $configPath
                $configFile.IsReadOnly = $true
                Write-Host "$GREEN✅ [Protection]$NC Configuration file set to read-only to prevent Cursor from overwriting modifications"
                Write-Host "$BLUE💡 [Tip]$NC File path: $configPath"
            } catch {
                Write-Host "$YELLOW⚠️  [Protection]$NC Failed to set read-only attribute: $($_.Exception.Message)"
                Write-Host "$BLUE💡 [Suggestion]$NC You can manually right-click file → Properties → Check 'Read-only'"
            }
        } else {
            Write-Host "$YELLOW⚠️  [Registry]$NC Registry modification failed, but configuration file modification succeeded"

            if ($jsSuccess) {
                Write-Host "$GREEN✅ [JavaScript Injection]$NC JavaScript injection function executed successfully"
                Write-Host ""
                Write-Host "$YELLOW🎉 [Partially Complete]$NC Configuration file and JavaScript injection completed, registry modification failed"
                Write-Host "$BLUE💡 [Suggestion]$NC May need administrator privileges to modify registry"
                Write-Host "$BLUE📋 [Details]$NC Completed the following modifications:"
                Write-Host "$GREEN  ✓ Cursor configuration file (storage.json)$NC"
                Write-Host "$YELLOW  ⚠ System registry (MachineGuid) - Failed$NC"
                Write-Host "$GREEN  ✓ JavaScript kernel injection (device identification bypass)$NC"
            } else {
                Write-Host "$YELLOW⚠️  [JavaScript Injection]$NC JavaScript injection function failed"
                Write-Host ""
                Write-Host "$YELLOW🎉 [Partially Complete]$NC Configuration file modification completed, registry and JavaScript injection failed"
                Write-Host "$BLUE💡 [Suggestion]$NC May need administrator privileges to modify registry"
            }

            # 🔒 Even if registry modification failed, protect configuration file
            Write-Host "$BLUE🔒 [Protection]$NC Setting configuration file protection..."
            try {
                $configPath = "$env:APPDATA\Cursor\User\globalStorage\storage.json"
                $configFile = Get-Item $configPath
                $configFile.IsReadOnly = $true
                Write-Host "$GREEN✅ [Protection]$NC Configuration file set to read-only to prevent Cursor from overwriting modifications"
                Write-Host "$BLUE💡 [Tip]$NC File path: $configPath"
            } catch {
                Write-Host "$YELLOW⚠️  [Protection]$NC Failed to set read-only attribute: $($_.Exception.Message)"
                Write-Host "$BLUE💡 [Suggestion]$NC You can manually right-click file → Properties → Check 'Read-only'"
            }
        }

        Write-Host "$BLUE💡 [Tip]$NC You can now start Cursor with the new machine code configuration"
    } else {
        Write-Host ""
        Write-Host "$RED❌ [Failed]$NC Machine code modification failed!"
        Write-Host "$YELLOW💡 [Suggestion]$NC Please try 'Reset Environment + Modify Machine Code' option"
    }
} else {
    # Complete reset environment + modify machine code flow
    Write-Host "$GREEN🚀 [Start]$NC Starting Reset Environment + Modify Machine Code function..."

    # 🚀 Close all Cursor processes and save information
    Close-CursorProcessAndSaveInfo "Cursor"
    if (-not $global:CursorProcessInfo) {
        Close-CursorProcessAndSaveInfo "cursor"
    }

    # 🚨 Important warning prompt
    Write-Host ""
    Write-Host "$RED🚨 [Important Warning]$NC ============================================"
    Write-Host "$YELLOW⚠️  [Risk Control Reminder]$NC Cursor's risk control mechanism is very strict!"
    Write-Host "$YELLOW⚠️  [Must Delete]$NC Must completely delete specified folders, no residual settings allowed"
    Write-Host "$YELLOW⚠️  [Prevent Trial Loss]$NC Only thorough cleanup can effectively prevent losing Pro trial status"
    Write-Host "$RED🚨 [Important Warning]$NC ============================================"
    Write-Host ""

    # 🎯 Execute Cursor trial Pro deletion folder function
    Write-Host "$GREEN🚀 [Start]$NC Starting core function..."
    Remove-CursorTrialFolders



    # 🔄 Restart Cursor to regenerate configuration file
    Restart-CursorAndWait

    # 🛠️ Modify machine code configuration
    $configSuccess = Modify-MachineCodeConfig
    
    # 🧹 Execute Cursor initialization cleanup
    Invoke-CursorInitialization

    if ($configSuccess) {
        Write-Host ""
        Write-Host "$GREEN🎉 [Configuration File]$NC Machine code configuration file modification completed!"

        # Add registry modification
        Write-Host "$BLUE🔧 [Registry]$NC Modifying system registry..."
        $registrySuccess = Update-MachineGuid

        # 🔧 New: JavaScript injection function (enhanced device identification bypass)
        Write-Host ""
        Write-Host "$BLUE🔧 [Device Identification Bypass]$NC Executing JavaScript injection function..."
        Write-Host "$BLUE💡 [Description]$NC This function will directly modify Cursor core JS files to achieve deeper device identification bypass"
        $jsSuccess = Modify-CursorJSFiles

        if ($registrySuccess) {
            Write-Host "$GREEN✅ [Registry]$NC System registry modification successful"

            if ($jsSuccess) {
                Write-Host "$GREEN✅ [JavaScript Injection]$NC JavaScript injection function executed successfully"
                Write-Host ""
                Write-Host "$GREEN🎉 [Complete]$NC All operations completed (Enhanced Version)!"
                Write-Host "$BLUE📋 [Details]$NC Completed the following operations:"
                Write-Host "$GREEN  ✓ Deleted Cursor trial-related folders$NC"
                Write-Host "$GREEN  ✓ Cursor initialization cleanup$NC"
                Write-Host "$GREEN  ✓ Regenerated configuration file$NC"
                Write-Host "$GREEN  ✓ Modified machine code configuration$NC"
                Write-Host "$GREEN  ✓ Modified system registry$NC"
                Write-Host "$GREEN  ✓ JavaScript kernel injection (device identification bypass)$NC"
            } else {
                Write-Host "$YELLOW⚠️  [JavaScript Injection]$NC JavaScript injection function failed, but other functions succeeded"
                Write-Host ""
                Write-Host "$GREEN🎉 [Complete]$NC All operations completed!"
                Write-Host "$BLUE📋 [Details]$NC Completed the following operations:"
                Write-Host "$GREEN  ✓ Deleted Cursor trial-related folders$NC"
                Write-Host "$GREEN  ✓ Cursor initialization cleanup$NC"
                Write-Host "$GREEN  ✓ Regenerated configuration file$NC"
                Write-Host "$GREEN  ✓ Modified machine code configuration$NC"
                Write-Host "$GREEN  ✓ Modified system registry$NC"
                Write-Host "$YELLOW  ⚠ JavaScript kernel injection (partially failed)$NC"
            }

            # 🔒 Add configuration file protection mechanism
            Write-Host "$BLUE🔒 [Protection]$NC Setting configuration file protection..."
            try {
                $configPath = "$env:APPDATA\Cursor\User\globalStorage\storage.json"
                $configFile = Get-Item $configPath
                $configFile.IsReadOnly = $true
                Write-Host "$GREEN✅ [Protection]$NC Configuration file set to read-only to prevent Cursor from overwriting modifications"
                Write-Host "$BLUE💡 [Tip]$NC File path: $configPath"
            } catch {
                Write-Host "$YELLOW⚠️  [Protection]$NC Failed to set read-only attribute: $($_.Exception.Message)"
                Write-Host "$BLUE💡 [Suggestion]$NC You can manually right-click file → Properties → Check 'Read-only'"
            }
        } else {
            Write-Host "$YELLOW⚠️  [Registry]$NC Registry modification failed, but other operations succeeded"

            if ($jsSuccess) {
                Write-Host "$GREEN✅ [JavaScript Injection]$NC JavaScript injection function executed successfully"
                Write-Host ""
                Write-Host "$YELLOW🎉 [Partially Complete]$NC Most operations completed, registry modification failed"
                Write-Host "$BLUE💡 [Suggestion]$NC May require administrator privileges to modify registry"
                Write-Host "$BLUE📋 [Details]$NC Completed the following operations:"
                Write-Host "$GREEN  ✓ Deleted Cursor trial-related folders$NC"
                Write-Host "$GREEN  ✓ Cursor initialization cleanup$NC"
                Write-Host "$GREEN  ✓ Regenerated configuration file$NC"
                Write-Host "$GREEN  ✓ Modified machine code configuration$NC"
                Write-Host "$YELLOW  ⚠ Modified system registry - Failed$NC"
                Write-Host "$GREEN  ✓ JavaScript kernel injection (device identification bypass)$NC"
            } else {
                Write-Host "$YELLOW⚠️  [JavaScript Injection]$NC JavaScript injection function failed"
                Write-Host ""
                Write-Host "$YELLOW🎉 [Partially Complete]$NC Most operations completed, registry and JavaScript injection failed"
                Write-Host "$BLUE💡 [Suggestion]$NC May require administrator privileges to modify registry"
            }

            # 🔒 Even if registry modification failed, protect configuration file
            Write-Host "$BLUE🔒 [Protection]$NC Setting configuration file protection..."
            try {
                $configPath = "$env:APPDATA\Cursor\User\globalStorage\storage.json"
                $configFile = Get-Item $configPath
                $configFile.IsReadOnly = $true
                Write-Host "$GREEN✅ [Protection]$NC Configuration file set to read-only to prevent Cursor from overwriting modifications"
                Write-Host "$BLUE💡 [Tip]$NC File path: $configPath"
            } catch {
                Write-Host "$YELLOW⚠️  [Protection]$NC Failed to set read-only attribute: $($_.Exception.Message)"
                Write-Host "$BLUE💡 [Suggestion]$NC You can manually right-click file → Properties → Check 'Read-only'"
            }
        }
    } else {
        Write-Host ""
        Write-Host "$RED❌ [Failed]$NC Machine code configuration modification failed!"
        Write-Host "$YELLOW💡 [Suggestion]$NC Please check error messages and retry"
    }
}


# 📱 Display official account information
Write-Host ""
Write-Host "$GREEN================================$NC"
Write-Host "$YELLOW📱  Follow Official Account【煎饼果子卷AI】to share more Cursor tips and AI knowledge (Script is free, follow the account to join group for more tips and experts)  $NC"
Write-Host "$YELLOW⚡   [Advertisement] Official Cursor Accounts: Pro¥65 | Pro+¥265 | Ultra¥888 Exclusive account/7-day warranty, WeChat: JavaRookie666  $NC"
Write-Host "$GREEN================================$NC"
Write-Host ""

# 🎉 Script execution complete
Write-Host "$GREEN🎉 [Script Complete]$NC Thank you for using Cursor Machine Code Modification Tool!"
Write-Host "$BLUE💡 [Tip]$NC If you have any questions, please refer to the official account or re-run the script"
Write-Host ""
Read-Host "Press Enter to exit"
exit 0
