$ErrorActionPreference = "Stop"

# Get the directory where this script is located
$ScriptDir = $PSScriptRoot
$ProjectRoot = Join-Path $ScriptDir ".."

$PubspecPath = Join-Path $ProjectRoot "pubspec.yaml"
$AppName = "WeSpeek"
$BuildDir = Join-Path $ProjectRoot "build\windows\x64\runner\Release"
$DistDir = Join-Path $ProjectRoot "dist"
$InstallerScript = Join-Path $ProjectRoot "installers\wespeek.iss"

# Extract Version from pubspec.yaml
Write-Host "Reading version from $PubspecPath..." -ForegroundColor Yellow
$content = Get-Content $PubspecPath -Raw
if ($content -match "version:\s*(.+)") {
    $fullVersion = $matches[1].Trim()
    $versionParts = $fullVersion.Split('+')
    $Version = $versionParts[0]
    Write-Host "Detected Version: $Version" -ForegroundColor Green
} else {
    Write-Error "Could not find version in pubspec.yaml"
    exit 1
}

Write-Host "Starting Build Process for $AppName v$Version..." -ForegroundColor Cyan

# 1. Clean and Build Release
Write-Host "1. Building Flutter Release..." -ForegroundColor Yellow
Push-Location $ProjectRoot
flutter clean
flutter pub get
flutter build windows --release --build-name=$Version
Pop-Location

if (-not (Test-Path $BuildDir)) {
    Write-Error "Build failed! Directory $BuildDir not found."
    exit 1
}

# 2. Prepare Dist Directory
if (-not (Test-Path $DistDir)) {
    New-Item -ItemType Directory -Path $DistDir | Out-Null
}

# 3. Create Portable Zip
Write-Host "2. Creating Portable Zip..." -ForegroundColor Yellow
$ZipName = "$DistDir\${AppName}_Portable_v${Version}.zip"
if (Test-Path $ZipName) { Remove-Item $ZipName }

Compress-Archive -Path "$BuildDir\*" -DestinationPath $ZipName
Write-Host "Portable version created: $ZipName" -ForegroundColor Green

# 4. Check/Download Language Files
Write-Host "3. Checking Language Files..." -ForegroundColor Yellow
$LangDir = Join-Path $ProjectRoot "installers\Languages"
$LangFile = Join-Path $LangDir "ChineseSimplified.isl"
$LangUrl = "https://raw.githubusercontent.com/jrsoftware/issrc/main/Files/Languages/Unofficial/ChineseSimplified.isl"

if (-not (Test-Path $LangDir)) {
    New-Item -ItemType Directory -Path $LangDir | Out-Null
}

if (-not (Test-Path $LangFile)) {
    Write-Host "Downloading ChineseSimplified.isl..." -ForegroundColor Yellow
    try {
        Invoke-WebRequest -Uri $LangUrl -OutFile $LangFile
        Write-Host "Language file downloaded successfully." -ForegroundColor Green
    } catch {
        Write-Warning "Failed to download language file. Installer compilation might fail."
        Write-Error $_
    }
}

# 5. Download Visual C++ Redistributable
Write-Host "4. Downloading Visual C++ Redistributable..." -ForegroundColor Yellow
$VcRedistUrl = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
$VcRedistPath = Join-Path $ProjectRoot "installers\vc_redist.x64.exe"

if (-not (Test-Path $VcRedistPath)) {
    try {
        Invoke-WebRequest -Uri $VcRedistUrl -OutFile $VcRedistPath
        Write-Host "Visual C++ Redistributable downloaded successfully." -ForegroundColor Green
    } catch {
        Write-Warning "Failed to download Visual C++ Redistributable. Installer compilation might fail."
        Write-Error $_
    }
}

# 6. Create Installer (if Inno Setup is available)
Write-Host "5. Checking for Inno Setup..." -ForegroundColor Yellow

$InnoPath = ""
$PossiblePaths = @(
    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    "C:\Program Files\Inno Setup 6\ISCC.exe",
    "${env:LocalAppData}\Programs\Inno Setup 6\ISCC.exe"
)

# Check PATH
if (Get-Command "ISCC.exe" -ErrorAction SilentlyContinue) {
    $InnoPath = "ISCC.exe"
} else {
    foreach ($path in $PossiblePaths) {
        if (Test-Path $path) {
            $InnoPath = $path
            break
        }
    }
}

if ($InnoPath -ne "") {
    Write-Host "Inno Setup found at: $InnoPath" -ForegroundColor Green
    Write-Host "Compiling Installer..." -ForegroundColor Yellow
    & $InnoPath $InstallerScript
    Write-Host "Installer created in $DistDir" -ForegroundColor Green
} else {
    Write-Host "WARNING: Inno Setup (ISCC.exe) not found." -ForegroundColor Red
    Write-Host "To create the installer, please install Inno Setup 6: https://jrsoftware.org/isdl.php"
    Write-Host "Then run this script again or compile 'installers\wespeek.iss' manually."
}

Write-Host "Done!" -ForegroundColor Cyan
