using System;
using System.Linq;
using System.Windows.Forms;
using System.IO;

namespace ORRTLauncher
{
    internal static class Program
    {
        [STAThread]
        static void Main(string[] rawArgs)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            // The browser passes the URI as a command-line argument
            // e.g. ORRTLauncher.exe "orrt-player:1+launchmode:play+clientversion:2018L+..."
            string uri = null;
            if (rawArgs != null && rawArgs.Length > 0)
            {
                uri = string.Join(" ", rawArgs).Trim('"');
            }

            // First run / ensure the protocol handler is registered
            ProtocolManager.EnsureRegistered();

            if (string.IsNullOrEmpty(uri) || !uri.StartsWith("orrt-player:", StringComparison.OrdinalIgnoreCase))
            {
                // Launched directly (not via browser protocol) – show the main launcher window
                Application.Run(new LaunchScreen(null));
            }
            else
            {
                LaunchArgs parsed;
                try
                {
                    parsed = LaunchArgumentParser.Parse(uri);
                }
                catch (Exception ex)
                {
                    MessageBox.Show(
                        "Failed to parse launch arguments:\n" + ex.Message,
                        "ORRT Launcher",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Error);
                    return;
                }

                Application.Run(new LaunchScreen(parsed));
            }
        }
    }
}
