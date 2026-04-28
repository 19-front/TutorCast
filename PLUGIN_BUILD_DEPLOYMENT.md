# TutorCast AutoCAD Plugin - Build & Deployment Guide

## 📋 Prerequisites

**On Windows VM:**
- Visual Studio 2022 or Visual Studio Build Tools 2022
- AutoCAD (2021 or later) installed
- .NET Framework 4.7.2+ development tools
- AutoCAD Object Model (AutoCAD SDK/Developer Tools)

## 🔨 Build Instructions

### Method 1: Visual Studio GUI (Easiest)

1. **Create New Project**
   - File → New → Project
   - Select "Class Library (.NET Framework)"
   - Name: `TutorCastPlugin`
   - Framework: .NET Framework 4.7.2
   - Create

2. **Add AutoCAD References**
   - Project → Add Reference
   - Browse to: `C:\Program Files\Autodesk\AutoCAD 20XX\` (where 20XX is your year)
   - Select these DLLs:
     - `acdbmgd.dll` (AutoCAD database manager)
     - `acmgd.dll` (AutoCAD managed core)
     - `accoremgd.dll` (AutoCAD core)

3. **Copy Source Code**
   - Delete the default `Class1.cs`
   - Copy the entire contents of `TutorCastPlugin.cs` from this repo into a new `TutorCastPlugin.cs` file in your project
   - Save

4. **Build the Plugin**
   - Build → Build Solution (Ctrl+Shift+B)
   - Output: `bin\Debug\TutorCastPlugin.dll` or `bin\Release\TutorCastPlugin.dll`

### Method 2: Command Line (dotnet)

```bash
# If you have .csproj file (create if needed)
cd C:\path\to\project
dotnet build -c Release

# Output: bin/Release/TutorCastPlugin.dll
```

### Method 3: MSBuild (from Developer Command Prompt)

```bash
msbuild TutorCastPlugin.csproj /p:Configuration=Release /p:Platform=x64
```

---

## 📦 Deployment Options

### Option A: Direct Copy to AutoCAD Folder (Simple - Not Recommended)

```cmd
# Find your AutoCAD installation
cd C:\Program Files\Autodesk\AutoCAD 2024\

# Copy plugin
copy C:\path\to\TutorCastPlugin.dll .

# Restart AutoCAD - should auto-load
```

⚠️ **Problem:** Will be overwritten on AutoCAD updates

---

### Option B: AppData Local (Recommended for Development)

```cmd
# Create user plugin folder
mkdir "%LOCALAPPDATA%\Autodesk\AutoCAD 2024\Plug-ins\TutorCast"

# Copy plugin
copy C:\path\to\TutorCastPlugin.dll "%LOCALAPPDATA%\Autodesk\AutoCAD 2024\Plug-ins\TutorCast\"

# Create registry entry (see below)
```

---

### Option C: Using .bundle Format (Recommended for Production)

Create `TutorCast.bundle\Contents\Windows\TutorCastPlugin.dll`:

```
TutorCast.bundle/
├── Contents/
│   ├── Windows/
│   │   └── TutorCastPlugin.dll
│   ├── Mac/
│   │   └── TutorCastPlugin.dylib
│   └── PackageContents.xml
```

**PackageContents.xml:**
```xml
<?xml version="1.0" encoding="utf-8"?>
<ApplicationPackage SchemaVersion="1.0" xmlns="http://autodesk.com/packageformat/2018">
  <CompanyDetails Name="TutorCast" Url="https://tutorcast.com"/>
  <Components>
    <RuntimeRequirements OS="Win64" AutoCADVersion="2021-2024"/>
  </Components>
  <RuntimeRequirements>
    <Platform Architecture="x64">
      <Plugin LoadOnDemand="False" AppType="AutoCAD">
        <Name>TutorCast Plugin</Name>
        <Description>Real-time AutoCAD command overlay</Description>
        <Assembly Path="TutorCastPlugin.dll" ClassId="TutorCast.Plugins.AutoCAD.TutorCastPlugin"/>
      </Plugin>
    </Platform>
  </RuntimeRequirements>
</ApplicationPackage>
```

Copy to:
```
C:\Users\<username>\AppData\Roaming\Autodesk\ApplicationPlugins\TutorCast.bundle\
```

---

## 🔑 Registry Method (For APPDATA Deployment)

**Create file: `register-plugin.reg`**

```reg
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\Autodesk\AutoCAD\R24.0\Security\FileOpenSaveTrustedLocations]
"TutorCast Plugin"="C:\\Users\\<username>\\AppData\\Local\\Autodesk\\AutoCAD 2024\\Plug-ins\\TutorCast"
```

Then in Command Prompt (as Administrator):
```cmd
regedit /s register-plugin.reg
```

---

## ✅ Verify Plugin is Loaded

**In AutoCAD:**

1. Type: `NETLOAD`
2. Browse to your `TutorCastPlugin.dll`
3. Click Open
4. Should see: "Command: TUTORCAST" or similar

**Or check AutoCAD console output** for:
```
TutorCast AutoCAD Plugin loaded
Listening on port 19848...
```

---

## 🚀 Quick Start Checklist

- [ ] Build `TutorCastPlugin.dll` in Visual Studio
- [ ] Copy to `%LOCALAPPDATA%\Autodesk\AutoCAD 20XX\Plug-ins\TutorCast\`
- [ ] Restart AutoCAD
- [ ] Verify plugin loaded (type `NETLOAD` and select the DLL)
- [ ] Check TutorCast on macOS is listening: `nc -zv 127.0.0.1 19848` (from VM macOS host)
- [ ] Test: Type `LINE` in AutoCAD, watch TutorCast overlay

---

## 🐛 Troubleshooting

**"DLL not found" error**
- Ensure AutoCAD references are correct
- Check .NET Framework version matches

**Plugin doesn't load**
- Check AutoCAD console: `_NETLOAD` command
- Verify file permissions
- Try Administrator mode

**Can't connect to macOS**
- Verify VM network: `ping 10.211.55.1` (host)
- Check port: `netstat -an | findstr 19848`
- Verify firewall allows port 19848

**Command not recognized**
- Plugin may not have loaded - check console
- Try restarting AutoCAD

---

## 📁 File Structure After Build

```
TutorCastPlugin/
├── TutorCastPlugin.csproj
├── TutorCastPlugin.cs          ← Source code (from repo)
├── obj/
│   └── Debug/
├── bin/
│   ├── Debug/
│   │   └── TutorCastPlugin.dll  ← Use this for development
│   └── Release/
│       └── TutorCastPlugin.dll  ← Use this for production
└── packages/
    └── (NuGet dependencies)
```

---

## Next: Create .csproj File

If you need a project file template, run this on the Windows VM:

```powershell
$csproj = @'
<Project Sdk="Microsoft.NET.Sdk.WindowsDesktop">
  <PropertyGroup>
    <TargetFramework>net472</TargetFramework>
    <OutputType>Library</OutputType>
    <AssemblyName>TutorCastPlugin</AssemblyName>
  </PropertyGroup>
  <ItemGroup>
    <Reference Include="acdbmgd" />
    <Reference Include="acmgd" />
    <Reference Include="accoremgd" />
  </ItemGroup>
</Project>
'@

$csproj | Out-File TutorCastPlugin.csproj -Encoding UTF8
```

Then build with: `dotnet build -c Release`
````
mkdir "%LOCALAPPDATA%\Autodesk\AutoCAD 2024\Plug-ins\TutorCast"
copy TutorCastPlugin.dll "%LOCALAPPDATA%\Autodesk\AutoCAD 2024\Plug-ins\TutorCast\"
```
