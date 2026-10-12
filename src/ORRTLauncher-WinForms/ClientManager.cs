using System;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Threading;
using System.Threading.Tasks;

namespace ORRTLauncher
{
    public class ClientManager
    {
        public string BaseUrl { get; set; } = "https://oldrrt.xyz";

        private static readonly string VersionsRoot =
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                         "ORRT", "Versions");

        public string GetInstalledPlayerPath(string clientVersion)
        {
            string versionDir = Path.Combine(VersionsRoot, clientVersion);
            string projectXExe = Path.Combine(versionDir, "ProjectXPlayerBeta.exe");
            if (File.Exists(projectXExe)) return projectXExe;
            string robloxExe = Path.Combine(versionDir, "RobloxPlayerBeta.exe");
            if (File.Exists(robloxExe)) return robloxExe;
            return null;
        }

        public bool IsInstalled(string clientVersion)
            => GetInstalledPlayerPath(clientVersion) != null;

        public async Task DownloadClientAsync(
            string clientVersion,
            IProgress<(int percent, string status)> onProgress,
            CancellationToken ct = default)
        {
            string downloadUrl = $"{BaseUrl.TrimEnd('/')}/download/client/{Uri.EscapeDataString(clientVersion)}";
            string versionDir  = Path.Combine(VersionsRoot, clientVersion);
            string tmpZip      = Path.Combine(Path.GetTempPath(), $"orrt_{clientVersion}_{Guid.NewGuid():N}.zip");

            Directory.CreateDirectory(versionDir);

            onProgress?.Report((0, $"Connecting to server for {clientVersion}..."));

            try
            {
                using (var wc = new WebClient())
                {
                    wc.DownloadProgressChanged += (s, e) =>
                        onProgress?.Report((e.ProgressPercentage / 2, $"Downloading {clientVersion}... {e.ProgressPercentage}%"));

                    ct.Register(wc.CancelAsync);
                    await wc.DownloadFileTaskAsync(new Uri(downloadUrl), tmpZip);
                }

                ct.ThrowIfCancellationRequested();
                onProgress?.Report((50, $"Extracting {clientVersion}..."));

                // Extract zip with progress approximation
                using (var archive = ZipFile.OpenRead(tmpZip))
                {
                    int total   = archive.Entries.Count;
                    int current = 0;
                    foreach (var entry in archive.Entries)
                    {
                        ct.ThrowIfCancellationRequested();
                        string destPath = Path.Combine(versionDir, entry.FullName.Replace('/', Path.DirectorySeparatorChar));

                        if (entry.FullName.EndsWith("/") || entry.FullName.EndsWith("\\"))
                        {
                            Directory.CreateDirectory(destPath);
                        }
                        else
                        {
                            Directory.CreateDirectory(Path.GetDirectoryName(destPath));
                            entry.ExtractToFile(destPath, overwrite: true);
                        }

                        current++;
                        int pct = 50 + (int)(current / (double)total * 50);
                        onProgress?.Report((pct, $"Extracting... ({current}/{total})"));
                    }
                }

                onProgress?.Report((100, "Done!"));
            }
            finally
            {
                if (File.Exists(tmpZip))
                    try { File.Delete(tmpZip); } catch { }
            }
        }

        public static string BuildPlayerArguments(LaunchArgs args)
        {
            return $":1+launchmode:{args.LaunchMode}"
                 + $"+clientversion:{args.ClientVersion}"
                 + $"+gameinfo:{args.GameInfo}"
                 + $"+placelauncherurl:{args.PlaceLauncherUrl}"
                 + "+k:l+client";
        }
    }
}
