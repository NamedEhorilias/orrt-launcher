using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Diagnostics;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using Microsoft.Win32;

namespace ORRTLauncher
{
    class Program
    {
        const string AppName = "ORRT";
        // Dynamic base URL is extracted from placelauncherurl at runtime
        // Falls back to oldrrt.xyz if cannot be determined (HTTP is used to support 2017/2018 Roblox clients)
        const string FallbackBaseUrl = "http://oldrrt.xyz";
        const string ProtocolScheme = "orrt-player";
        const string StudioProtocolScheme = "orrt-studio";

        const string VpsIp = "74.248.20.23";

        static void Log(string message)
        {
            Console.WriteLine(message);
            try
            {
                string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                string logDir = Path.Combine(localAppData, AppName);
                if (!Directory.Exists(logDir)) Directory.CreateDirectory(logDir);
                string logFile = Path.Combine(logDir, "launcher.log");
                File.AppendAllText(logFile, $"[{DateTime.UtcNow:yyyy-MM-dd HH:mm:ss}] {message}\r\n");
            }
            catch { }
        }

        class ParsedLaunchArgs
        {
            public string LaunchMode = "play";
            public string ClientVersion = "2017L";
            public string GameInfo = "";
            public string PlaceLauncherUrl = "";
            public string PlaceId = "";
        }

        static ParsedLaunchArgs ParseLaunchUri(string rawUri)
        {
            var result = new ParsedLaunchArgs();
            if (string.IsNullOrWhiteSpace(rawUri)) return result;

            string clean = rawUri.Trim().Trim('"').Trim('\'');
            int colonIdx = clean.IndexOf(':');
            string body = colonIdx >= 0 ? clean.Substring(colonIdx + 1) : clean;

            string[] tokens = body.Split('+');
            string currentKey = null;
            var currentTokens = new List<string>();

            Action flush = () =>
            {
                if (currentKey == null) return;
                string combinedVal = string.Join("+", currentTokens);
                switch (currentKey.ToLowerInvariant())
                {
                    case "clientversion":
                        result.ClientVersion = combinedVal;
                        break;
                    case "gameinfo":
                    case "ticket":
                        result.GameInfo = combinedVal;
                        break;
                    case "placelauncherurl":
                        result.PlaceLauncherUrl = combinedVal;
                        break;
                    case "launchmode":
                        result.LaunchMode = combinedVal;
                        break;
                    case "placeid":
                        result.PlaceId = combinedVal;
                        break;
                }
            };

            foreach (var token in tokens)
            {
                int firstColon = token.IndexOf(':');
                if (firstColon > 0)
                {
                    string candidateKey = token.Substring(0, firstColon).ToLowerInvariant();
                    if (candidateKey == "clientversion" || candidateKey == "gameinfo" ||
                        candidateKey == "placelauncherurl" || candidateKey == "launchmode" ||
                        candidateKey == "placeid" || candidateKey == "ticket" ||
                        candidateKey == "k" || candidateKey == "suggest" || candidateKey == "client")
                    {
                        flush();
                        currentKey = candidateKey;
                        currentTokens.Clear();
                        currentTokens.Add(token.Substring(firstColon + 1));
                        continue;
                    }
                }

                if (currentKey != null)
                {
                    currentTokens.Add(token);
                }
            }
            flush();

            return result;
        }

        /// <summary>
        /// Extracts the base URL (scheme + host) from the placelauncherurl parameter.
        /// Forces http:// scheme because 2017/2018 Roblox client cannot negotiate modern TLS 1.3 / Cloudflare certs.
        /// </summary>
        static string ExtractBaseUrl(string placeLauncherUrl)
        {
            try
            {
                if (!string.IsNullOrEmpty(placeLauncherUrl))
                {
                    var parsed = new Uri(placeLauncherUrl);
                    return $"http://{parsed.Authority}";
                }
            }
            catch { }
            return FallbackBaseUrl;
        }

        static void CleanHostsFile()
        {
            if (!OperatingSystem.IsWindows()) return;
            try
            {
                string systemDir = Environment.GetFolderPath(Environment.SpecialFolder.System);
                string hostsPath = Path.Combine(systemDir, @"drivers\etc\hosts");
                if (!File.Exists(hostsPath)) return;

                string hostsContent = File.ReadAllText(hostsPath);
                if (hostsContent.Contains("roblox.com") || hostsContent.Contains("rbxcdn.com") ||
                    hostsContent.Contains("pekora.rip") || hostsContent.Contains("Old Roblox Return Today") ||
                    hostsContent.Contains("74.248.20.23"))
                {
                    Log("[*] Cleaning hijacked entries from Windows hosts file...");
                    var lines = File.ReadAllLines(hostsPath);
                    var cleanLines = lines.Where(line => 
                        !line.Contains("roblox.com", StringComparison.OrdinalIgnoreCase) &&
                        !line.Contains("rbxcdn.com", StringComparison.OrdinalIgnoreCase) &&
                        !line.Contains("pekora.rip", StringComparison.OrdinalIgnoreCase) &&
                        !line.Contains("Old Roblox Return Today", StringComparison.OrdinalIgnoreCase) &&
                        !line.Contains("74.248.20.23", StringComparison.OrdinalIgnoreCase)
                    ).ToList();

                    try
                    {
                        File.WriteAllLines(hostsPath, cleanLines);
                        Log("[+] Successfully cleaned Windows hosts file.");
                        FlushDns();
                    }
                    catch
                    {
                        try
                        {
                            string tempClean = Path.Combine(Path.GetTempPath(), $"hosts_clean_{Guid.NewGuid():N}.txt");
                            File.WriteAllLines(tempClean, cleanLines);
                            var psi = new ProcessStartInfo
                            {
                                FileName = "powershell",
                                Arguments = $"-NoProfile -ExecutionPolicy Bypass -Command \"Copy-Item -Path '{tempClean}' -Destination '{hostsPath}' -Force; Remove-Item '{tempClean}' -ErrorAction SilentlyContinue; Clear-DnsClientCache -ErrorAction SilentlyContinue; ipconfig /flushdns\"",
                                Verb = "runas",
                                CreateNoWindow = true,
                                UseShellExecute = true
                            };
                            Process.Start(psi)?.WaitForExit(3000);
                            Log("[+] Successfully cleaned Windows hosts file via elevated PowerShell.");
                        }
                        catch { }
                    }
                }
            }
            catch { }
        }

        static void FlushDns()
        {
            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName = "ipconfig",
                    Arguments = "/flushdns",
                    CreateNoWindow = true,
                    UseShellExecute = false
                };
                Process.Start(psi)?.WaitForExit(2000);
            }
            catch { }
        }

        static async Task Main(string[] args)
        {
            Console.ForegroundColor = ConsoleColor.Red;
            Console.WriteLine(@"
    ____   _____   _____ _______ 
   / __ \ |  __ \ |  __ \__   __|
  | |  | || |__) || |__) | | |   
  | |  | ||  _  / |  _  /  | |   
  | |__| || | \ \ | | \ \  | |   
   \____/ |_|  \_\|_|  \_\ |_|   
");
            Console.ForegroundColor = ConsoleColor.White;
            Console.WriteLine(" Old Roblox Return Today - " + FallbackBaseUrl);
            Console.WriteLine("==================================================");
            Console.ResetColor();

            try
            {
                CleanHostsFile();

                if (args.Length == 0)
                {
                    await InstallOrUpdateAsync();
                    Console.ForegroundColor = ConsoleColor.Green;
                    Console.WriteLine("\n[+] Setup completed successfully! You can now join games and open Studio from orrt.online.");
                    Console.ResetColor();
                    Console.WriteLine("Press Enter to exit...");
                    Console.ReadLine();
                }
                else
                {
                    string launchUri = args[0];
                    if (launchUri.Contains("launchmode:edit") || launchUri.StartsWith("orrt-studio:") || launchUri.StartsWith("roblox-studio:"))
                    {
                        await LaunchStudioAsync(launchUri);
                    }
                    else
                    {
                        await LaunchGameAsync(launchUri);
                    }
                }
            }
            catch (Exception ex)
            {
                Console.ForegroundColor = ConsoleColor.Red;
                Console.WriteLine("\n[-] Error: " + ex.Message);
                Console.ResetColor();
                Console.WriteLine("Press Enter to exit...");
                Console.ReadLine();
            }
        }

        static string GetInstallDir()
        {
            string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string dir = Path.Combine(localAppData, AppName);
            if (!Directory.Exists(dir))
            {
                Directory.CreateDirectory(dir);
            }
            return dir;
        }

        static async Task DownloadFileWithProgressAsync(HttpClient client, string url, string destinationPath, string displayName)
        {
            using var response = await client.GetAsync(url, HttpCompletionOption.ResponseHeadersRead);
            response.EnsureSuccessStatusCode();

            long? totalBytes = response.Content.Headers.ContentLength;
            using var contentStream = await response.Content.ReadAsStreamAsync();
            using var fileStream = new FileStream(destinationPath, FileMode.Create, FileAccess.Write, FileShare.None, 81920, true);

            var buffer = new byte[81920];
            long totalRead = 0;
            int bytesRead;
            int lastPercent = -1;

            while ((bytesRead = await contentStream.ReadAsync(buffer, 0, buffer.Length)) > 0)
            {
                await fileStream.WriteAsync(buffer, 0, bytesRead);
                totalRead += bytesRead;

                if (totalBytes.HasValue && totalBytes.Value > 0)
                {
                    int percent = (int)((totalRead * 100) / totalBytes.Value);
                    if (percent != lastPercent)
                    {
                        lastPercent = percent;
                        int barWidth = 25;
                        int filled = (percent * barWidth) / 100;
                        string bar = new string('=', filled) + new string('-', barWidth - filled);
                        double mbRead = totalRead / (1024.0 * 1024.0);
                        double mbTotal = totalBytes.Value / (1024.0 * 1024.0);
                        Console.Write($"\r[*] {displayName} [{bar}] {percent}% ({mbRead:F1}/{mbTotal:F1} MB)   ");
                    }
                }
                else
                {
                    double mbRead = totalRead / (1024.0 * 1024.0);
                    Console.Write($"\r[*] {displayName} ({mbRead:F1} MB downloaded)   ");
                }
            }
            Console.WriteLine();
        }

        static void EnsureClientConfigFiles(string clientDir, string baseUrl)
        {
            try
            {
                string clientBaseUrl = baseUrl.StartsWith("https://", StringComparison.OrdinalIgnoreCase)
                    ? "http://" + baseUrl.Substring(8)
                    : baseUrl;
                string cleanBaseUrl = clientBaseUrl.TrimEnd('/') + "/";
                string appSettings = $"<Settings><ContentFolder>content</ContentFolder><BaseUrl>{cleanBaseUrl}</BaseUrl></Settings>";
                File.WriteAllText(Path.Combine(clientDir, "AppSettings.xml"), appSettings);

                string clientSettingsDir = Path.Combine(clientDir, "ClientSettings");
                if (!Directory.Exists(clientSettingsDir)) Directory.CreateDirectory(clientSettingsDir);
                string clientAppSettings = $"{{\n\t\"BaseUrl\": \"{cleanBaseUrl}\",\n\t\"DFIntTaskSchedulerTargetFps\": 180\n}}";
                File.WriteAllText(Path.Combine(clientSettingsDir, "ClientAppSettings.json"), clientAppSettings);
            }
            catch { }
        }

        static void EnsureClientLibraries(string versionsDir)
        {
            try
            {
                if (!Directory.Exists(versionsDir)) return;
                var allDlls = new[] { "msvcp140.dll", "vcruntime140.dll", "d3dx9_43.dll", "d3dcompiler_43.dll", "d3dcompiler_47.dll" };

                // Find any existing DLLs across version folders to propagate them
                var foundDlls = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                foreach (var file in Directory.GetFiles(versionsDir, "*.dll", SearchOption.AllDirectories))
                {
                    string fName = Path.GetFileName(file);
                    if (allDlls.Contains(fName, StringComparer.OrdinalIgnoreCase) && !foundDlls.ContainsKey(fName))
                    {
                        foundDlls[fName] = file;
                    }
                }

                // Ensure all client directories have every DLL
                foreach (var dir in Directory.GetDirectories(versionsDir, "*", SearchOption.AllDirectories))
                {
                    if (File.Exists(Path.Combine(dir, "RobloxPlayerBeta.exe")) || File.Exists(Path.Combine(dir, "ProjectXPlayerBeta.exe")))
                    {
                        foreach (var dllName in allDlls)
                        {
                            string target = Path.Combine(dir, dllName);
                            if (!File.Exists(target) && foundDlls.TryGetValue(dllName, out string src) && File.Exists(src))
                            {
                                try { File.Copy(src, target, true); } catch { }
                            }
                        }
                    }
                }
            }
            catch { }
        }

        static void EnsureFirewallRules(string clientExe, string ruleName)
        {
            try
            {
                if (OperatingSystem.IsWindows() && File.Exists(clientExe))
                {
                    var psi = new ProcessStartInfo
                    {
                        FileName = "netsh",
                        Arguments = $"advfirewall firewall add rule name=\"{ruleName}\" dir=in action=allow program=\"{clientExe}\" enable=yes",
                        CreateNoWindow = true,
                        UseShellExecute = false
                    };
                    Process.Start(psi)?.WaitForExit(2000);
                }
            }
            catch { }
        }

        static async Task<bool> DownloadSingleClientAsync(string baseUrl, string clientVersion, string installDir)
        {
            try
            {
                using var httpClient = new HttpClient();
                httpClient.DefaultRequestHeaders.Add("User-Agent", "ORRT-Bootstrapper/1.0");

                string latestVersion = "v1.0.0";
                try
                {
                    latestVersion = (await httpClient.GetStringAsync(baseUrl + "/setup/version")).Trim();
                }
                catch { }

                string[] possibleUrls = new[]
                {
                    $"{baseUrl}/setup/{latestVersion}-ProjectXApp{clientVersion}.zip",
                    $"{baseUrl}/download/client/{clientVersion}",
                    $"{baseUrl}/setup/ORRT_{clientVersion}.zip",
                    $"{baseUrl}/setup/{clientVersion}.zip"
                };

                string tempZip = Path.Combine(Path.GetTempPath(), $"orrt_{clientVersion}.zip");
                bool downloaded = false;
                foreach (var zipUrl in possibleUrls)
                {
                    try
                    {
                        Console.WriteLine($"[*] Trying to download {clientVersion} from {zipUrl}...");
                        await DownloadFileWithProgressAsync(httpClient, zipUrl, tempZip, clientVersion);
                        downloaded = true;
                        break;
                    }
                    catch { }
                }

                if (!downloaded)
                {
                    throw new Exception($"Could not download client archive for {clientVersion} from any URL.");
                }

                string clientDir = Path.Combine(installDir, "Versions", latestVersion, clientVersion);
                if (!Directory.Exists(clientDir)) Directory.CreateDirectory(clientDir);

                Console.WriteLine($"[*] Extracting {clientVersion}...");
                ZipFile.ExtractToDirectory(tempZip, clientDir, true);
                File.Delete(tempZip);

                EnsureClientConfigFiles(clientDir, baseUrl);
                EnsureClientLibraries(Path.Combine(installDir, "Versions"));
                Console.WriteLine($"[+] Installed {clientVersion} successfully!");
                return true;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[-] Failed to download {clientVersion}: {ex.Message}");
                return false;
            }
        }

        static async Task InstallOrUpdateAsync(string customBaseUrl = null)
        {
            string baseUrl = !string.IsNullOrEmpty(customBaseUrl) ? customBaseUrl : FallbackBaseUrl;
            string installDir = GetInstallDir();
            Console.WriteLine("[*] Checking for updates from " + baseUrl + "...");

            using var httpClient = new HttpClient();
            httpClient.DefaultRequestHeaders.Add("User-Agent", "ORRT-Bootstrapper/1.0");

            string latestVersion = "v1.0.0";
            try
            {
                latestVersion = (await httpClient.GetStringAsync(baseUrl + "/setup/version")).Trim();
            }
            catch { }

            string versionFile = Path.Combine(installDir, "version");
            string versionsDir = Path.Combine(installDir, "Versions");
            bool has2017 = File.Exists(Path.Combine(versionsDir, latestVersion, "2017L", "RobloxPlayerBeta.exe")) ||
                           File.Exists(Path.Combine(versionsDir, latestVersion, "2017L", "ORRTPlayerBeta.exe")) ||
                           File.Exists(Path.Combine(versionsDir, latestVersion, "2017L", "ProjectXPlayerBeta.exe"));
            bool has2018 = File.Exists(Path.Combine(versionsDir, latestVersion, "2018L", "RobloxPlayerBeta.exe")) ||
                           File.Exists(Path.Combine(versionsDir, latestVersion, "2018L", "ORRTPlayerBeta.exe")) ||
                           File.Exists(Path.Combine(versionsDir, latestVersion, "2018L", "ProjectXPlayerBeta.exe"));
            bool has2020 = File.Exists(Path.Combine(versionsDir, latestVersion, "2020L", "RobloxPlayerBeta.exe")) ||
                           File.Exists(Path.Combine(versionsDir, latestVersion, "2020L", "ORRTPlayerBeta.exe")) ||
                           File.Exists(Path.Combine(versionsDir, latestVersion, "2020L", "ProjectXPlayerBeta.exe"));

            if (File.Exists(versionFile) && File.ReadAllText(versionFile).Trim() == latestVersion && has2017 && has2018 && has2020)
            {
                Console.ForegroundColor = ConsoleColor.Green;
                Console.WriteLine("[+] ORRT is already up to date (" + latestVersion + ")!");
                Console.ResetColor();
                EnsureClientLibraries(versionsDir);
                RegisterProtocol();
                return;
            }

            Console.WriteLine("[*] Setting up ORRT client (" + latestVersion + ")...");
            try
            {
                string yearsList = "";
                try { yearsList = await httpClient.GetStringAsync(baseUrl + "/setup/available-years.txt"); } catch { }
                string[] years = !string.IsNullOrEmpty(yearsList) 
                    ? yearsList.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries)
                    : new[] { "2017L", "2018L", "2020L" };

                foreach (string year in years)
                {
                    string cleanYear = year.Trim();
                    if (string.IsNullOrEmpty(cleanYear)) continue;

                    string clientDir = Path.Combine(installDir, "Versions", latestVersion, cleanYear);
                    string targetExe = Path.Combine(clientDir, "RobloxPlayerBeta.exe");
                    if (File.Exists(targetExe) || File.Exists(Path.Combine(clientDir, "ORRTPlayerBeta.exe")) || File.Exists(Path.Combine(clientDir, "ProjectXPlayerBeta.exe")))
                    {
                        Console.WriteLine($"[+] {cleanYear} is already installed.");
                        EnsureClientConfigFiles(clientDir, baseUrl);
                        continue;
                    }

                    string[] possibleUrls = new[]
                    {
                        $"{baseUrl}/setup/{latestVersion}-ProjectXApp{cleanYear}.zip",
                        $"{baseUrl}/download/client/{cleanYear}",
                        $"{baseUrl}/setup/ORRT_{cleanYear}.zip",
                        $"{baseUrl}/setup/{cleanYear}.zip"
                    };

                    string tempZip = Path.Combine(Path.GetTempPath(), $"orrt_{cleanYear}.zip");
                    bool downloaded = false;
                    foreach (var zipUrl in possibleUrls)
                    {
                        try
                        {
                            Console.WriteLine($"[*] Trying to download {cleanYear} from {zipUrl}...");
                            await DownloadFileWithProgressAsync(httpClient, zipUrl, tempZip, cleanYear);
                            downloaded = true;
                            break;
                        }
                        catch { }
                    }

                    if (downloaded)
                    {
                        try
                        {
                            if (!Directory.Exists(clientDir)) Directory.CreateDirectory(clientDir);
                            ZipFile.ExtractToDirectory(tempZip, clientDir, true);
                            File.Delete(tempZip);

                            EnsureClientConfigFiles(clientDir, baseUrl);
                            Console.WriteLine("[+] Extracted " + cleanYear + " successfully.");
                        }
                        catch (Exception ex)
                        {
                            Console.WriteLine("[-] Note: Could not extract " + cleanYear + ": " + ex.Message);
                        }
                    }
                    else
                    {
                        Console.WriteLine("[-] Note: Could not download " + cleanYear + " from any URL.");
                    }
                }
            }
            catch (Exception e)
            {
                Console.WriteLine("[*] Info: " + e.Message);
            }

            EnsureClientLibraries(versionsDir);
            File.WriteAllText(versionFile, latestVersion);

            // Copy self
            string currentExe = Process.GetCurrentProcess().MainModule?.FileName;
            if (!string.IsNullOrEmpty(currentExe))
            {
                string targetExe = Path.Combine(installDir, "ORRTLauncher.exe");
                if (!string.Equals(currentExe, targetExe, StringComparison.OrdinalIgnoreCase))
                {
                    try { File.Copy(currentExe, targetExe, true); } catch { }
                }
            }

            RegisterProtocol();
            CleanHostsFile();
        }

        static void RegisterProtocol()
        {
            string installDir = GetInstallDir();
            string targetExe = Path.Combine(installDir, "ORRTLauncher.exe");
            if (!File.Exists(targetExe))
            {
                targetExe = Process.GetCurrentProcess().MainModule?.FileName ?? "ORRTLauncher.exe";
            }

            string[] schemes = new[] { "orrt-player", "orrt-studio", "pekora-player", "pekora2-player" };
            foreach (string scheme in schemes)
            {
                try
                {
                    if (OperatingSystem.IsWindows())
                    {
                        using var key = Registry.CurrentUser.CreateSubKey(@"Software\Classes\" + scheme);
                        key.SetValue("", "URL:" + scheme);
                        key.SetValue("URL Protocol", "");
                        using var openKey = key.CreateSubKey(@"shell\open\command");
                        openKey.SetValue("", "\"" + targetExe + "\" \"%1\"");
                        Console.WriteLine("[+] Registered URI protocol: " + scheme + "://");
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine("[-] Failed to register protocol " + scheme + ": " + ex.Message);
                }
            }
        }

        [System.Runtime.InteropServices.DllImport("wininet.dll", CharSet = System.Runtime.InteropServices.CharSet.Auto, SetLastError = true)]
        static extern bool InternetSetCookie(string lpszUrlName, string lpszCookieName, string lpszCookieData);

        static async Task LaunchGameAsync(string uri)
        {
            Log("[*] Processing game launch request...");
            var parsed = ParseLaunchUri(uri);
            string clientVersion = string.IsNullOrEmpty(parsed.ClientVersion) ? "2017L" : parsed.ClientVersion;
            string gameInfo = parsed.GameInfo;
            string placeLauncherUrl = parsed.PlaceLauncherUrl;

            // Extract the dynamic base URL from placelauncherurl (supports oldrrt.xyz, etc.)
            string baseUrl = ExtractBaseUrl(placeLauncherUrl);
            if (baseUrl.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
            {
                baseUrl = "http://" + baseUrl.Substring(8);
            }
            baseUrl = baseUrl.TrimEnd('/');
            Log("[*] Server domain: " + baseUrl);

            if (string.IsNullOrEmpty(placeLauncherUrl))
            {
                placeLauncherUrl = $"{baseUrl}/Game/PlaceLauncher.ashx";
            }

            // Redirect any stray roblox.com references or https schemes to http
            placeLauncherUrl = placeLauncherUrl.Replace("https://www.roblox.com", baseUrl)
                                               .Replace("http://www.roblox.com", baseUrl)
                                               .Replace("https://roblox.com", baseUrl)
                                               .Replace("http://roblox.com", baseUrl)
                                               .Replace("https://oldrrt.xyz", "http://oldrrt.xyz")
                                               .Replace("https://orrt.online", "http://orrt.online");
            if (placeLauncherUrl.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
            {
                placeLauncherUrl = "http://" + placeLauncherUrl.Substring(8);
            }

            string installDir = GetInstallDir();
            string versionsDir = Path.Combine(installDir, "Versions");

            string clientExe = FindExecutable(versionsDir, clientVersion, "ORRTPlayerBeta.exe", "RobloxPlayerBeta.exe", "ProjectXPlayerBeta.exe");

            if (clientExe == null)
            {
                Log($"[*] Client {clientVersion} is not installed yet. Downloading now...");
                await DownloadSingleClientAsync(baseUrl, clientVersion, installDir);
                clientExe = FindExecutable(versionsDir, clientVersion, "ORRTPlayerBeta.exe", "RobloxPlayerBeta.exe", "ProjectXPlayerBeta.exe");
            }

            if (clientExe == null)
            {
                throw new Exception($"Failed to locate or download client for version '{clientVersion}'.");
            }

            string clientDir = Path.GetDirectoryName(clientExe);
            EnsureClientConfigFiles(clientDir, baseUrl);
            EnsureClientLibraries(versionsDir);
            EnsureFirewallRules(clientExe, $"ORRT {clientVersion}");
            CleanHostsFile();

            // Build auth URL with required suggest query parameter
            string authUrl = $"{baseUrl}/Login/Negotiate.ashx";
            try { foreach (var cu in new[]{"http://oldrrt.xyz/","http://www.oldrrt.xyz/",baseUrl+"/"}) { InternetSetCookie(cu, ".ROBLOSECURITY", gameInfo + "; path=/; domain=" + new Uri(cu).Host); } } catch { }
            Log("[+] Starting game client (" + clientVersion + ")...");
            Log("[*] Executable: " + clientExe);
            Log("[*] Auth URL: " + authUrl);
            Log("[*] PlaceLauncher URL: " + placeLauncherUrl);

            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = clientExe;
            psi.WorkingDirectory = clientDir;
            // Standard bootstrapper flags matching official client and Linux launcher
            psi.Arguments = $"-a \"{authUrl}\" -t \"{gameInfo}\" -j \"{placeLauncherUrl}\"";
            psi.UseShellExecute = true;

            var process = Process.Start(psi);
            if (process == null)
            {
                throw new Exception($"Failed to start client process: {clientExe}");
            }

            Log($"[+] Client process started with PID {process.Id}");

            // Monitor process for 3 seconds to catch early startup failures
            await Task.Delay(3000);
            if (process.HasExited)
            {
                Log($"[-] Client exited unexpectedly with code {process.ExitCode}");
                Console.ForegroundColor = ConsoleColor.Red;
                Console.WriteLine($"\n[-] Game client exited unexpectedly (Exit code: {process.ExitCode}).");
                Console.WriteLine("If this happens repeatedly, please ensure your antivirus allows ORRT.");
                Console.ResetColor();
                Console.WriteLine("Press Enter to close...");
                Console.ReadLine();
            }
            else
            {
                Log("[+] Game client running successfully. Enjoy ORRT!");
                Console.WriteLine("[+] Game process is running! Have fun on ORRT!");
            }
        }

        static async Task LaunchStudioAsync(string uri)
        {
            Log("[*] Processing Studio launch request...");
            var parsed = ParseLaunchUri(uri);
            string clientVersion = string.IsNullOrEmpty(parsed.ClientVersion) ? "2017L" : parsed.ClientVersion;
            string placeId = parsed.PlaceId;
            string ticket = parsed.GameInfo;

            string baseUrl = ExtractBaseUrl(parsed.PlaceLauncherUrl);
            if (string.IsNullOrEmpty(baseUrl)) baseUrl = FallbackBaseUrl;
            CleanHostsFile();

            string installDir = GetInstallDir();
            string studioDir = Path.Combine(installDir, "Studio", clientVersion);
            string studioExe = Path.Combine(studioDir, "RobloxStudioBeta.exe");

            using var httpClient = new HttpClient();
            httpClient.DefaultRequestHeaders.Add("User-Agent", "ORRT-Bootstrapper/1.0");

            if (!File.Exists(studioExe))
            {
                Console.WriteLine($"[*] Studio {clientVersion} not found, downloading from {baseUrl}...");
                if (!Directory.Exists(studioDir)) Directory.CreateDirectory(studioDir);

                string latestVersion = "v1.0.0";
                try
                {
                    latestVersion = (await httpClient.GetStringAsync(baseUrl + "/setup/version")).Trim();
                }
                catch { }

                string zipUrl = $"{baseUrl}/setup/{latestVersion}-Studio{clientVersion}.zip";
                string tempZip = Path.Combine(Path.GetTempPath(), $"orrt_studio_{clientVersion}.zip");

                try
                {
                    var bytes = await httpClient.GetByteArrayAsync(zipUrl);
                    await File.WriteAllBytesAsync(tempZip, bytes);
                    ZipFile.ExtractToDirectory(tempZip, studioDir, true);
                    File.Delete(tempZip);
                    Console.WriteLine("[+] Studio extracted successfully.");
                }
                catch (Exception ex)
                {
                    Console.WriteLine("[-] Failed to download Studio: " + ex.Message);
                    throw;
                }
            }

            // Ensure AppSettings.xml is configured with HTTP BaseUrl
            try
            {
                string clientBaseUrl = baseUrl.StartsWith("https://", StringComparison.OrdinalIgnoreCase)
                    ? "http://" + baseUrl.Substring(8)
                    : baseUrl;
                string cleanBaseUrl = clientBaseUrl.TrimEnd('/') + "/";
                string appSettings = $"<Settings><ContentFolder>content</ContentFolder><BaseUrl>{cleanBaseUrl}</BaseUrl></Settings>";
                File.WriteAllText(Path.Combine(studioDir, "AppSettings.xml"), appSettings);
            }
            catch { }

            // Ensure ORRTCustomizer.lua plugin is configured (avatar appearance + publisher)
            try
            {
                string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                string pluginsDir = Path.Combine(localAppData, "Roblox", "Plugins");
                if (!Directory.Exists(pluginsDir)) Directory.CreateDirectory(pluginsDir);
                // Remove old minimal plugin if present
                string oldPlugin = Path.Combine(pluginsDir, "ORRTPublisher.lua");
                if (File.Exists(oldPlugin)) File.Delete(oldPlugin);

                // Fetch user identity
                string userId = "1";
                string userName = "Player";
                if (!string.IsNullOrEmpty(ticket))
                {
                    try
                    {
                        using var authReq = new HttpRequestMessage(HttpMethod.Get, baseUrl + "/apisite/users/v1/users/authenticated");
                        authReq.Headers.Add("Cookie", $".ROBLOSECURITY={ticket}");
                        var authResp = await httpClient.SendAsync(authReq);
                        string authBody = await authResp.Content.ReadAsStringAsync();
                        var idMatch = System.Text.RegularExpressions.Regex.Match(authBody, "\"id\"\\s*:\\s*(\\d+)");
                        var nameMatch = System.Text.RegularExpressions.Regex.Match(authBody, "\"name\"\\s*:\\s*\"([^\"]+)\"");
                        if (idMatch.Success) userId = idMatch.Groups[1].Value;
                        if (nameMatch.Success) userName = nameMatch.Groups[1].Value;
                    }
                    catch { }
                }
                Console.WriteLine($"[*] Studio user: {userName} (ID: {userId})");

                // Fetch BodyColors
                int hc = 1001, tc = 1003, la = 1001, ra = 1001, ll = 1001, rl = 1001;
                try
                {
                    using var bcReq = new HttpRequestMessage(HttpMethod.Get, $"{baseUrl}/Asset/BodyColors.ashx?userId={userId}");
                    bcReq.Headers.Add("User-Agent", "Roblox/WinInet");
                    var bcResp = await httpClient.SendAsync(bcReq);
                    string bcXml = await bcResp.Content.ReadAsStringAsync();
                    int ParseColor(string tag, int def) {
                        var m = System.Text.RegularExpressions.Regex.Match(bcXml, $"<int name=\"{tag}\">(\\d+)</int>");
                        return m.Success ? int.Parse(m.Groups[1].Value) : def;
                    }
                    hc = ParseColor("HeadColor", 1001); tc = ParseColor("TorsoColor", 1003);
                    la = ParseColor("LeftArmColor", 1001); ra = ParseColor("RightArmColor", 1001);
                    ll = ParseColor("LeftLegColor", 1001); rl = ParseColor("RightLegColor", 1001);
                }
                catch { }

                // Fetch CharacterFetch (asset URLs)
                string fetchStr = "";
                try
                {
                    using var fetchReq = new HttpRequestMessage(HttpMethod.Get, $"{baseUrl}/asset/CharacterFetch.ashx?userId={userId}");
                    fetchReq.Headers.Add("User-Agent", "Roblox/WinInet");
                    var fetchResp = await httpClient.SendAsync(fetchReq);
                    fetchStr = await fetchResp.Content.ReadAsStringAsync();
                }
                catch { }

                var assetUrls = fetchStr.Split(';')
                    .Select(u => u.Trim())
                    .Where(u => !string.IsNullOrEmpty(u) && !u.Contains("BodyColors"))
                    .ToList();
                string urlsLua = string.Join(",\n    ", assetUrls.Select(u => $"\"{u.Replace("\"", "\\\"")}\""));
                string uploadUrl = $"{baseUrl}/Data/Upload.ashx?assetId={placeId}";
                int placeIdInt = int.TryParse(placeId, out int pid) ? pid : 0;

                string pluginScript = $@"print(""[ORRT] Studio Customizer & Publisher Plugin Initializing..."")
local USER_ID = {userId}
local USER_NAME = ""{userName.Replace("\"", "\\\"")}""
local PLACE_ID = {placeIdInt}
local UPLOAD_URL = ""{uploadUrl}""
pcall(function()
    game:SetPlaceID(PLACE_ID); game:SetUniverseId(PLACE_ID)
    local visit = game:GetService(""Visit"")
    visit:SetUploadUrl(UPLOAD_URL)
end)
local BODY_COLORS = {{ HeadColor={hc}, TorsoColor={tc}, LeftArmColor={la}, RightArmColor={ra}, LeftLegColor={ll}, RightLegColor={rl} }}
local ASSET_URLS = {{
    {urlsLua}
}}
local function ensureR6Attachments(char)
    if not char then return end
    local function addAtt(p,n,cf) local pt=char:FindFirstChild(p); if pt and pt:IsA(""BasePart"") and not pt:FindFirstChild(n) then local a=Instance.new(""Attachment""); a.Name=n; a.CFrame=cf; a.Parent=pt end end
    addAtt(""Head"",""HairAttachment"",CFrame.new(0,0.6,0)); addAtt(""Head"",""HatAttachment"",CFrame.new(0,0.6,0))
    addAtt(""Head"",""FaceCenterAttachment"",CFrame.new(0,0,0)); addAtt(""Head"",""FaceFrontAttachment"",CFrame.new(0,0,-0.6))
    addAtt(""Torso"",""BodyFrontAttachment"",CFrame.new(0,0,-0.5)); addAtt(""Torso"",""BodyBackAttachment"",CFrame.new(0,0,0.5))
    addAtt(""Torso"",""LeftCollarAttachment"",CFrame.new(-1,1,0)); addAtt(""Torso"",""RightCollarAttachment"",CFrame.new(1,1,0))
    addAtt(""Torso"",""NeckAttachment"",CFrame.new(0,1,0)); addAtt(""Torso"",""WaistCenterAttachment"",CFrame.new(0,-1,0))
    addAtt(""Left Arm"",""LeftShoulderAttachment"",CFrame.new(0,1,0)); addAtt(""Left Arm"",""LeftGripAttachment"",CFrame.new(0,-1,0))
    addAtt(""Right Arm"",""RightShoulderAttachment"",CFrame.new(0,1,0)); addAtt(""Right Arm"",""RightGripAttachment"",CFrame.new(0,-1,0))
    addAtt(""Left Leg"",""LeftFootAttachment"",CFrame.new(0,-1,0)); addAtt(""Right Leg"",""RightFootAttachment"",CFrame.new(0,-1,0))
end
local applied={{}}
local function customizeCharacter(char)
    if not char or applied[char] then return end
    local hum=char:WaitForChild(""Humanoid"",10); if not hum then return end
    applied[char]=true
    print(""[ORRT] Customizing Character: ""..tostring(char.Name))
    pcall(function() char.Name=USER_NAME; local p=game:GetService(""Players""):GetPlayerFromCharacter(char); if p then p.Name=USER_NAME end end)
    if not char:FindFirstChild(""UpperTorso"") then ensureR6Attachments(char) end
    pcall(function()
        local bc=char:FindFirstChildOfClass(""BodyColors"") or Instance.new(""BodyColors"",char)
        bc.HeadColor=BrickColor.new(BODY_COLORS.HeadColor); bc.TorsoColor=BrickColor.new(BODY_COLORS.TorsoColor)
        bc.LeftArmColor=BrickColor.new(BODY_COLORS.LeftArmColor); bc.RightArmColor=BrickColor.new(BODY_COLORS.RightArmColor)
        bc.LeftLegColor=BrickColor.new(BODY_COLORS.LeftLegColor); bc.RightLegColor=BrickColor.new(BODY_COLORS.RightLegColor)
        local function cp(n,c) local pt=char:FindFirstChild(n); if pt and pt:IsA(""BasePart"") then pt.BrickColor=BrickColor.new(c) end end
        cp(""Head"",BODY_COLORS.HeadColor); cp(""Torso"",BODY_COLORS.TorsoColor)
        cp(""Left Arm"",BODY_COLORS.LeftArmColor); cp(""Right Arm"",BODY_COLORS.RightArmColor)
        cp(""Left Leg"",BODY_COLORS.LeftLegColor); cp(""Right Leg"",BODY_COLORS.RightLegColor)
        print(""[ORRT] BodyColors applied for ""..USER_NAME)
    end)
    spawn(function()
        for _,itemUrl in ipairs(ASSET_URLS) do
            pcall(function()
                local objs=game:GetObjects(itemUrl)
                if objs then for _,obj in ipairs(objs) do
                    if obj:IsA(""Accessory"") or obj:IsA(""Hat"") then hum:AddAccessory(obj)
                    elseif obj:IsA(""Shirt"") or obj:IsA(""Pants"") or obj:IsA(""ShirtGraphic"") or obj:IsA(""CharacterMesh"") then obj.Parent=char
                    elseif obj:IsA(""Decal"") and string.lower(obj.Name)==""face"" then
                        local h=char:FindFirstChild(""Head""); if h then local o=h:FindFirstChild(""face""); if o then o:Destroy() end; obj.Parent=h end
                    elseif obj:IsA(""SpecialMesh"") then
                        local h=char:FindFirstChild(""Head""); if h then local o=h:FindFirstChildOfClass(""SpecialMesh""); if o then o:Destroy() end; obj.Parent=h end
                    end
                end end
            end)
        end
        print(""[ORRT] Appearance applied for ""..USER_NAME)
    end)
end
local RunService=game:GetService(""RunService"")
local function scan() for _,c in ipairs(workspace:GetChildren()) do if c:IsA(""Model"") and c:FindFirstChild(""Humanoid"") and not applied[c] then customizeCharacter(c) end end end
RunService.Heartbeat:connect(scan)
workspace.ChildAdded:connect(function(c) if c:IsA(""Model"") and c:FindFirstChild(""Humanoid"") then scan() end end)
print(""[ORRT] Studio Customizer Ready!"")
";
                File.WriteAllText(Path.Combine(pluginsDir, "ORRTCustomizer.lua"), pluginScript);
                Console.WriteLine("[+] ORRTCustomizer.lua generated with avatar data.");
            }
            catch (Exception pluginEx)
            {
                Console.WriteLine("[-] Failed to generate ORRTCustomizer.lua: " + pluginEx.Message);
            }

            // Download place file
            string placesDir = Path.Combine(installDir, "Places");
            if (!Directory.Exists(placesDir)) Directory.CreateDirectory(placesDir);
            string placeFile = Path.Combine(placesDir, $"place_{placeId}.rbxl");

            Console.WriteLine($"[*] Downloading place {placeId}...");
            try
            {
                using var request = new HttpRequestMessage(HttpMethod.Get, $"{baseUrl}/asset/?id={placeId}");
                if (!string.IsNullOrEmpty(ticket))
                {
                    request.Headers.Add("Cookie", $".ROBLOSECURITY={ticket}");
                }
                var response = await httpClient.SendAsync(request);
                var placeBytes = await response.Content.ReadAsByteArrayAsync();
                await File.WriteAllBytesAsync(placeFile, placeBytes);
                Console.WriteLine("[+] Place downloaded successfully.");
            }
            catch (Exception ex)
            {
                Console.WriteLine("[-] Failed to download place: " + ex.Message);
            }

            // Create cookies.txt and ClientSettings for Studio authentication
            try
            {
                string clientSettingsDir = Path.Combine(studioDir, "ClientSettings");
                if (!Directory.Exists(clientSettingsDir)) Directory.CreateDirectory(clientSettingsDir);
                string studioHttpUrl = baseUrl.StartsWith("https://", StringComparison.OrdinalIgnoreCase)
                    ? "http://" + baseUrl.Substring(8)
                    : baseUrl;
                string clientSettingsJson = $"{{\n  \"BaseUrl\": \"{studioHttpUrl.TrimEnd('/')}/\"\n}}";
                File.WriteAllText(Path.Combine(clientSettingsDir, "ClientAppSettings.json"), clientSettingsJson);
                File.WriteAllText(Path.Combine(clientSettingsDir, "StudioAppSettings.json"), clientSettingsJson);

                if (!string.IsNullOrEmpty(ticket))
                {
                    Uri parsedUri = new Uri(baseUrl);
                    string host = parsedUri.Host;
                    string cookiesTxt = $"# Netscape HTTP Cookie File\n.{host}\tTRUE\t/\tTRUE\t0\t.ROBLOSECURITY\t{ticket}\n{host}\tFALSE\t/\tTRUE\t0\t.ROBLOSECURITY\t{ticket}\n.{host}\tTRUE\t/\tTRUE\t0\t.PEKOSECURITY\t{ticket}\n{host}\tFALSE\t/\tTRUE\t0\t.PEKOSECURITY\t{ticket}\n";
                    File.WriteAllText(Path.Combine(studioDir, "cookies.txt"), cookiesTxt);
                }
            }
            catch { }

            Console.WriteLine("[+] Starting Roblox Studio 2017...");
            string studioArgs = $"\"{placeFile}\"";
            ProcessStartInfo psi = new ProcessStartInfo
            {
                FileName = studioExe,
                Arguments = studioArgs,
                WorkingDirectory = studioDir,
                UseShellExecute = false
            };

            Process studioProcess = Process.Start(psi);
            if (studioProcess == null)
            {
                throw new Exception("Failed to start Roblox Studio process.");
            }

            Console.WriteLine("[+] Studio started! Background auto-sync watcher active.");
            Console.WriteLine("[*] Save place in Studio (Ctrl+S) or close Studio to sync changes to ORRT.");

            string lastHash = GetFileHash(placeFile);

            // Sync watcher loop
            while (!studioProcess.HasExited)
            {
                await Task.Delay(2000);
                if (File.Exists(placeFile))
                {
                    string curHash = GetFileHash(placeFile);
                    if (!string.IsNullOrEmpty(curHash) && curHash != lastHash)
                    {
                        Console.WriteLine("[*] File modification detected! Auto-publishing to ORRT...");
                        await UploadPlaceAsync(baseUrl, placeId, ticket, placeFile);
                        lastHash = curHash;
                    }
                }
            }

            // Final sync after exit
            if (File.Exists(placeFile))
            {
                string finalHash = GetFileHash(placeFile);
                if (!string.IsNullOrEmpty(finalHash) && finalHash != lastHash)
                {
                    Console.WriteLine("[*] Final save detected after Studio exit. Uploading...");
                    await UploadPlaceAsync(baseUrl, placeId, ticket, placeFile);
                }
            }

            Console.WriteLine("[+] Studio session finished. All changes synced!");
            await Task.Delay(2000);
        }

        static string GetFileHash(string path)
        {
            try
            {
                if (!File.Exists(path)) return "";
                using var md5 = System.Security.Cryptography.MD5.Create();
                using var stream = File.Open(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
                byte[] hash = md5.ComputeHash(stream);
                return BitConverter.ToString(hash).Replace("-", "").ToLowerInvariant();
            }
            catch { return ""; }
        }

        static async Task UploadPlaceAsync(string baseUrl, string placeId, string ticket, string placeFile)
        {
            try
            {
                using var client = new HttpClient();
                using var fileStream = File.Open(placeFile, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
                using var content = new StreamContent(fileStream);
                content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("application/octet-stream");

                string uploadUrl = $"{baseUrl}/Data/Upload.ashx?assetId={placeId}&suggest={ticket}";
                var resp = await client.PostAsync(uploadUrl, content);
                string respBody = await resp.Content.ReadAsStringAsync();
                Console.WriteLine("[+] Upload response: " + respBody);
            }
            catch (Exception ex)
            {
                Console.WriteLine("[-] Upload failed: " + ex.Message);
            }
        }

        static string FindExecutable(string versionsDir, string versionTag, params string[] exeNames)
        {
            if (!Directory.Exists(versionsDir)) return null;

            foreach (var vDir in Directory.GetDirectories(versionsDir))
            {
                string targetDir = Path.Combine(vDir, versionTag);
                if (Directory.Exists(targetDir))
                {
                    foreach (var name in exeNames)
                    {
                        string candidate = Path.Combine(targetDir, name);
                        if (File.Exists(candidate)) return candidate;
                    }
                }
            }

            foreach (var file in Directory.GetFiles(versionsDir, "*.exe", SearchOption.AllDirectories))
            {
                string fName = Path.GetFileName(file);
                foreach (var name in exeNames)
                {
                    if (string.Equals(fName, name, StringComparison.OrdinalIgnoreCase))
                        return file;
                }
            }

            return null;
        }
    }
}
