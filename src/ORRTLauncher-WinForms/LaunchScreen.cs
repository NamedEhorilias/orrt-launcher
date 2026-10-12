using System;
using System.Diagnostics;
using System.IO;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace ORRTLauncher
{
    public partial class LaunchScreen : Form
    {
        private readonly LaunchArgs _args;
        private readonly ClientManager _clientManager = new ClientManager();

        public LaunchScreen(LaunchArgs args)
        {
            InitializeComponent();
            _args = args;
        }

        private async void LaunchScreen_Load(object sender, EventArgs e)
        {
            if (_args == null)
            {
                // User opened the launcher manually (not from browser play button)
                lblStatus.Text = "ORRT Player is installed!";
                lblDetails.Text = "You can launch games directly from the website.";
                progressBar.Value = 100;
                return;
            }

            string clientVersion = string.IsNullOrEmpty(_args.ClientVersion) ? "2017L" : _args.ClientVersion;
            lblStatus.Text = $"Starting ORRT ({clientVersion})...";

            try
            {
                if (!_clientManager.IsInstalled(clientVersion))
                {
                    lblStatus.Text = $"Downloading client ({clientVersion})...";
                    var progress = new Progress<(int percent, string status)>(p =>
                    {
                        progressBar.Value = Math.Max(0, Math.Min(100, p.percent));
                        lblDetails.Text = p.status;
                    });

                    await _clientManager.DownloadClientAsync(clientVersion, progress);
                }

                lblStatus.Text = "Launching game...";
                progressBar.Value = 100;
                lblDetails.Text = "Starting RobloxPlayerBeta.exe...";

                string playerExe = _clientManager.GetInstalledPlayerPath(clientVersion);
                if (string.IsNullOrEmpty(playerExe) || !File.Exists(playerExe))
                {
                    throw new FileNotFoundException($"RobloxPlayerBeta.exe was not found for version {clientVersion}.");
                }

                // Build auth URL from the PlaceLauncherUrl base (same host, different path)
                string plUrl = _args.PlaceLauncherUrl ?? string.Empty;
                string authUrl;
                if (Uri.TryCreate(plUrl, UriKind.Absolute, out Uri plUri))
                    authUrl = $"{plUri.Scheme}://{plUri.Host}{(plUri.IsDefaultPort ? "" : ":" + plUri.Port)}/Login/Negotiate.ashx";
                else
                    authUrl = "https://oldrrt.xyz/Login/Negotiate.ashx";

                var startInfo = new ProcessStartInfo
                {
                    FileName = playerExe,
                    Arguments = $"-a \"{authUrl}\" -t \"{_args.GameInfo}\" -j \"{_args.PlaceLauncherUrl}\"",
                    WorkingDirectory = Path.GetDirectoryName(playerExe),
                    UseShellExecute = false
                };

                string logFile = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ORRT", "launcher.log");
                try
                {
                    Directory.CreateDirectory(Path.GetDirectoryName(logFile));
                    File.AppendAllText(logFile, $"[{DateTime.UtcNow}] Launching: {playerExe} {startInfo.Arguments}\n");
                }
                catch { }

                var proc = Process.Start(startInfo);
                if (proc == null)
                {
                    throw new Exception($"Process.Start returned null for {playerExe}");
                }

                // Wait slightly to verify process did not immediately crash or exit
                await Task.Delay(2000);
                if (proc.HasExited && proc.ExitCode != 0)
                {
                    try { File.AppendAllText(logFile, $"[{DateTime.UtcNow}] Process immediately exited with code: {proc.ExitCode}\n"); } catch { }
                    throw new Exception($"RobloxPlayerBeta.exe exited immediately with code {proc.ExitCode}.\nPlease check if your antivirus or Windows SmartScreen blocked it.");
                }

                Application.Exit();
            }
            catch (Exception ex)
            {
                string logFile = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ORRT", "launcher.log");
                try { File.AppendAllText(logFile, $"[{DateTime.UtcNow}] Error: {ex}\n"); } catch { }

                lblStatus.Text = "Launch failed!";
                lblDetails.Text = ex.Message;
                MessageBox.Show(
                    $"Error launching game:\n\n{ex.Message}\n\nLog saved to:\n{logFile}",
                    "ORRT Launcher Error",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error
                );
                Application.Exit();
            }
        }
    }
}
