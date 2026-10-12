using System;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Diagnostics;
using System.Text.RegularExpressions;
using System.Threading;
using Microsoft.Win32;

namespace ORRTLauncher
{
    class Program
    {
        const string AppName = "ORRT";
        const string BaseUrl = "https://orrt.online";
        const string SetupUrl = "https://orrt.online/setup";

        static void Main(string[] args)
        {
            Console.Title = "ORRT Launcher";
            Console.WriteLine("ORRT Launcher - " + BaseUrl);

            try
            {
                if (args.Length == 0)
                {
                    InstallOrUpdate();
                    Console.ForegroundColor = ConsoleColor.Green;
                    Console.WriteLine("\n[+] Setup completed successfully! You can now join games from orrt.online.");
                    Console.ResetColor();
                    Console.WriteLine("Press Enter to exit...");
                    Console.ReadLine();
                }
                else
                {
                    string launchUri = args[0];
                    if (launchUri.Contains("launchmode:edit") || launchUri.StartsWith("orrt-studio:") || launchUri.StartsWith("roblox-studio:"))
                    {
                        LaunchStudio(launchUri);
                    }
                    else
                    {
                        LaunchGame(launchUri);
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

        static void ConfigureTls()
        {
            try
            {
                // Enable TLS 1.2 and TLS 1.3
                ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072 | (SecurityProtocolType)768 | SecurityProtocolType.Tls;
                ServicePointManager.ServerCertificateValidationCallback = delegate { return true; };
            }
            catch { }
        }

        static void InstallOrUpdate()
        {
            ConfigureTls();
            string installDir = GetInstallDir();
            Console.WriteLine("[*] Checking for updates...");

            using (WebClient client = new WebClient())
            {
                client.Headers.Add("User-Agent", "ORRT-Bootstrapper/1.0");

                string latestVersion = "v1.0.0";
                try
                {
                    latestVersion = client.DownloadString(SetupUrl + "/version").Trim();
                }
                catch { }

                string versionFile = Path.Combine(installDir, "version");
                if (File.Exists(versionFile) && File.ReadAllText(versionFile).Trim() == latestVersion)
                {
                    Console.ForegroundColor = ConsoleColor.Green;
                    Console.WriteLine("[+] ORRT is already up to date (" + latestVersion + ")!");
                    Console.ResetColor();
                    RegisterProtocol();
                    return;
                }

                Console.WriteLine("[*] Updating ORRT to " + latestVersion + "...");
                try
                {
                    string yearsList = client.DownloadString(SetupUrl + "/available-years.txt");
                    string[] years = yearsList.Split(new char[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
                    foreach (string year in years)
                    {
                        string cleanYear = year.Trim();
                        if (string.IsNullOrEmpty(cleanYear)) continue;

                        Console.WriteLine("[*] Downloading client for " + cleanYear + "...");
                        string zipUrl = SetupUrl + "/" + latestVersion + "-ProjectXApp" + cleanYear + ".zip";
                        string tempZip = Path.Combine(Path.GetTempPath(), "orrt_" + cleanYear + ".zip");
                        try
                        {
                            client.DownloadFile(zipUrl, tempZip);
                            string clientDir = Path.Combine(installDir, "Versions", latestVersion, cleanYear);
                            if (!Directory.Exists(clientDir)) Directory.CreateDirectory(clientDir);
                            ZipFile.ExtractToDirectory(tempZip, clientDir);
                            File.Delete(tempZip);
                            Console.WriteLine("[+] Extracted " + cleanYear + " successfully.");
                        }
                        catch (Exception dlEx)
                        {
                            Console.WriteLine("[-] Note: Could not download " + cleanYear + ": " + dlEx.Message);
                        }
                    }
                }
                catch (Exception e)
                {
                    Console.WriteLine("[*] Info: " + e.Message);
                }

                File.WriteAllText(versionFile, latestVersion);
            }

            // Copy self
            try
            {
                string currentExe = Process.GetCurrentProcess().MainModule.FileName;
                if (!string.IsNullOrEmpty(currentExe))
                {
                    string targetExe = Path.Combine(installDir, "ORRTLauncher.exe");
                    if (!string.Equals(currentExe, targetExe, StringComparison.OrdinalIgnoreCase))
                    {
                        File.Copy(currentExe, targetExe, true);
                    }
                }
            }
            catch { }

            RegisterProtocol();
        }

        static void RegisterProtocol()
        {
            string installDir = GetInstallDir();
            string targetExe = Path.Combine(installDir, "ORRTLauncher.exe");
            if (!File.Exists(targetExe))
            {
                try { targetExe = Process.GetCurrentProcess().MainModule.FileName; } catch { targetExe = "ORRTLauncher.exe"; }
            }

            string[] schemes = new string[] { "orrt-player", "orrt-studio", "pekora-player", "pekora2-player", "roblox-player" };
            foreach (string scheme in schemes)
            {
                try
                {
                    using (RegistryKey key = Registry.CurrentUser.CreateSubKey(@"Software\Classes\" + scheme))
                    {
                        key.SetValue("", "URL:" + scheme);
                        key.SetValue("URL Protocol", "");
                        using (RegistryKey openKey = key.CreateSubKey(@"shell\open\command"))
                        {
                            openKey.SetValue("", "\"" + targetExe + "\" \"%1\"");
                        }
                    }
                    Console.WriteLine("[+] Registered URI protocol: " + scheme + "://");
                }
                catch (Exception ex)
                {
                    Console.WriteLine("[-] Failed to register protocol " + scheme + ": " + ex.Message);
                }
            }
        }

        static void LaunchGame(string uri)
        {
            Console.WriteLine("[*] Received game launch request...");
            Match m = Regex.Match(uri, @"(?:orrt-player|pekora-player|pekora2-player|roblox-player):1\+launchmode:(?<mode>[^+]+)\+clientversion:(?<version>[^+]+)\+gameinfo:(?<info>[^+]+)\+placelauncherurl:(?<url>[^+]+)");
            if (!m.Success)
            {
                throw new Exception("Invalid game launch URI format: " + uri);
            }

            string clientVersion = m.Groups["version"].Value;
            string gameInfo = m.Groups["info"].Value;
            string placeLauncherUrl = m.Groups["url"].Value;

            string installDir = GetInstallDir();
            string versionsDir = Path.Combine(installDir, "Versions");

            string clientExe = FindExecutable(versionsDir, clientVersion, "RobloxPlayerBeta.exe", "ProjectXPlayerBeta.exe");

            if (clientExe == null)
            {
                InstallOrUpdate();
                clientExe = FindExecutable(versionsDir, clientVersion, "RobloxPlayerBeta.exe", "ProjectXPlayerBeta.exe");
            }

            // Derive authUrl dynamically from placeLauncherUrl
            string authUrl;
            try
            {
                Uri uriObj = new Uri(placeLauncherUrl);
                authUrl = uriObj.Scheme + "://" + uriObj.Authority + "/Login/Negotiate.ashx";
            }
            catch
            {
                authUrl = BaseUrl + "/Login/Negotiate.ashx";
            }
            Console.WriteLine("[+] Starting game client (" + clientVersion + ")...");
            Console.WriteLine("[*] Auth URL: " + authUrl);

            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = clientExe ?? "RobloxPlayerBeta.exe";
            if (!string.IsNullOrEmpty(clientExe) && File.Exists(clientExe))
            {
                psi.WorkingDirectory = Path.GetDirectoryName(clientExe);
            }
            psi.Arguments = "--play -a \"" + authUrl + "\" -t \"" + gameInfo + "\" -j \"" + placeLauncherUrl + "\"";
            psi.UseShellExecute = false;

            Process.Start(psi);
            Console.WriteLine("[+] Game process started! Have fun on ORRT!");
            Thread.Sleep(3000);
        }

        static void LaunchStudio(string uri)
        {
            Console.WriteLine("[*] Received Studio launch request...");
            string installDir = GetInstallDir();
            string versionsDir = Path.Combine(installDir, "Versions");

            string studioExe = FindExecutable(versionsDir, "2018L", "RobloxStudioBeta.exe", "RobloxStudio.exe");
            if (studioExe == null)
            {
                studioExe = FindExecutable(versionsDir, "2017L", "RobloxStudioBeta.exe", "RobloxStudio.exe");
            }

            if (studioExe == null)
            {
                InstallOrUpdate();
                studioExe = FindExecutable(versionsDir, "2018L", "RobloxStudioBeta.exe", "RobloxStudio.exe");
            }

            Console.WriteLine("[+] Starting Studio...");
            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = studioExe ?? "RobloxStudioBeta.exe";
            psi.Arguments = "-ide -task EditPlace -launchTime " + (long)(DateTime.UtcNow.Subtract(new DateTime(1970, 1, 1))).TotalMilliseconds;
            psi.UseShellExecute = false;

            Process.Start(psi);
            Console.WriteLine("[+] Studio started successfully!");
            Thread.Sleep(3000);
        }

        static string FindExecutable(string versionsDir, string versionTag, params string[] exeNames)
        {
            if (!Directory.Exists(versionsDir)) return null;

            foreach (string vDir in Directory.GetDirectories(versionsDir))
            {
                string targetDir = Path.Combine(vDir, versionTag);
                if (Directory.Exists(targetDir))
                {
                    foreach (string name in exeNames)
                    {
                        string candidate = Path.Combine(targetDir, name);
                        if (File.Exists(candidate)) return candidate;
                    }
                }
            }

            try
            {
                foreach (string file in Directory.GetFiles(versionsDir, "*.exe", SearchOption.AllDirectories))
                {
                    string fName = Path.GetFileName(file);
                    foreach (string name in exeNames)
                    {
                        if (string.Equals(fName, name, StringComparison.OrdinalIgnoreCase))
                            return file;
                    }
                }
            }
            catch { }

            return null;
        }
    }
}
