# ORRT Launcher

Official open-source launchers, bootstrap tools, and client dispatchers for **Old Roblox Return Today (ORRT)**.

This repository provides cross-platform client launchers supporting both Windows and Linux (via Wine/Proton), handling custom URI protocols (`orrt-player://`, `orrt-studio://`), automatic client downloading, authentication ticket negotiation, and Roblox Studio integration.

---

## Repository Structure

```
orrt-launcher/
├── src/
│   ├── ORRTLauncher-WinForms/    # Graphical launcher for Windows (WinForms, .NET 8 / .NET Framework 4.8)
│   ├── ORRTLauncher-CLI/         # Fast single-file console launcher & protocol handler (.NET 8)
│   ├── ORRTLauncher-Net45/       # Legacy lightweight bootstrapper (.NET Framework 4.5 / 4.7.2)
│   └── ORRTLauncher-Rust/        # Native high-performance launcher written in Rust
├── linux/
│   ├── orrt-player-linux.sh      # Linux client & Studio launcher script with DNS interception
│   ├── install-orrt-linux.sh     # Universal Linux installer (Debian, Ubuntu, Fedora, Arch, openSUSE)
│   └── install-orrt-fedora.sh    # Dedicated installer for Fedora / RHEL
├── scripts/
│   ├── fix-roblox.bat            # Windows batch script to clean hosts file redirections
│   └── fix-roblox.ps1            # PowerShell equivalent script
├── LICENSE                       # MIT License
└── README.md
```

---

## Features

- **Multi-Version Support**: Seamlessly manages multiple Roblox client versions (`2017L`, `2018L`, `2020L`).
- **Protocol Handler Registration**: Registers `orrt-player://` and `orrt-studio://` schemes to launch directly from web browsers.
- **Automated Client Provisioning**: Automatically downloads and extracts missing client builds from the ORRT server.
- **Studio Cloud Sync**: Built-in cloud place downloader and auto-saver/uploader for Roblox Studio sessions.
- **DNS Interceptor on Linux**: Injected shared library (`liborrt_hosts.so`) to route legacy Roblox asset requests to ORRT servers without modifying global `/etc/hosts`.
- **Wine / Proton Compatibility**: Tuned registry and display configurations to ensure stable cursor lock, audio, and asset replication.

---

## Building from Source

### 1. ORRTLauncher-CLI (.NET 8)

Prerequisites: [.NET 8 SDK](https://dotnet.microsoft.com/download)

```bash
cd src/ORRTLauncher-CLI

# Build debug binary
dotnet build

# Publish standalone single-file executable for Windows x64
dotnet publish -c Release -r win-x64 --self-contained false -p:PublishSingleFile=true
```

### 2. ORRTLauncher-WinForms (.NET 8 / Windows)

```bash
cd src/ORRTLauncher-WinForms

# Build using .NET 8
dotnet build ORRTLauncher_net8.csproj -c Release

# Publish single-file executable
dotnet publish ORRTLauncher_net8.csproj -c Release -r win-x64 --self-contained false -p:PublishSingleFile=true
```

### 3. ORRTLauncher-Rust

Prerequisites: [Rust and Cargo](https://rustup.rs/)

```bash
cd src/ORRTLauncher-Rust

# Build for Windows target
cargo build --release --target x86_64-pc-windows-gnu
```

---

## Linux Usage

To install the Linux launcher and configure URI handling on your system:

```bash
chmod +x linux/install-orrt-linux.sh
./linux/install-orrt-linux.sh
```

The script will:
1. Verify required tools (`wine`, `python3`, `gcc`, `curl`, `unzip`).
2. Build the `liborrt_hosts.so` DNS interceptor in `~/.cache/orrt/lib/`.
3. Install the launcher script to `~/bin/orrt-player-linux`.
4. Register desktop entry and MIME associations for `orrt-player://` and `orrt-studio://`.
5. Download client binaries if needed.

---

## Protocol URI Format

The launcher receives launch instructions through custom URI schemes structured as:

```text
orrt-player:1+launchmode:play+clientversion:2018L+gameinfo:AUTH_TOKEN+placelauncherurl:ENCODED_URL+k:l+client
```

Key parameters:
- `launchmode`: Mode of operation (`play` or `edit`).
- `clientversion`: Target client generation (e.g. `2017L`, `2018L`, `2020L`).
- `gameinfo`: Authentication security token.
- `placelauncherurl`: Server endpoint to retrieve join script parameters.

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
