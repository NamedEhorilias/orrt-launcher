using System;
using System.Windows.Forms;
using Microsoft.Win32;

namespace ORRTLauncher
{
    public static class ProtocolManager
    {
        private const string SchemeName = "orrt-player";
        private const string SchemeDescription = "URL:ORRT Player Protocol";

        public static void EnsureRegistered()
        {
            try
            {
                string exePath = Application.ExecutablePath;
                string expectedCommand = $"\"{exePath}\" \"%1\"";

                using (RegistryKey root = Registry.CurrentUser.OpenSubKey(@"Software\Classes", writable: true))
                {
                    if (root == null) return;

                    // Read current command (if any)
                    string currentCommand = null;
                    using (RegistryKey existing = root.OpenSubKey($@"{SchemeName}\shell\open\command"))
                    {
                        currentCommand = existing?.GetValue(null) as string;
                    }

                    // Already correctly registered – skip
                    if (string.Equals(currentCommand, expectedCommand, StringComparison.OrdinalIgnoreCase))
                        return;

                    // Write registration
                    using (RegistryKey schemeKey = root.CreateSubKey(SchemeName))
                    {
                        schemeKey.SetValue(null, SchemeDescription);
                        schemeKey.SetValue("URL Protocol", string.Empty);

                        using (RegistryKey commandKey = schemeKey.CreateSubKey(@"shell\open\command"))
                        {
                            commandKey.SetValue(null, expectedCommand);
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                // Non-fatal – log and continue; the user can still launch manually
                Console.WriteLine($"[WARN] Could not register protocol handler: {ex.Message}");
            }
        }

        public static bool IsRegistered()
        {
            try
            {
                string exePath = Application.ExecutablePath;
                string expectedCommand = $"\"{exePath}\" \"%1\"";
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey($@"Software\Classes\{SchemeName}\shell\open\command"))
                {
                    string cmd = key?.GetValue(null) as string;
                    return string.Equals(cmd, expectedCommand, StringComparison.OrdinalIgnoreCase);
                }
            }
            catch
            {
                return false;
            }
        }

        public static void Unregister()
        {
            try
            {
                Registry.CurrentUser.DeleteSubKeyTree($@"Software\Classes\{SchemeName}", throwOnMissingSubKey: false);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[WARN] Could not unregister protocol handler: {ex.Message}");
            }
        }
    }
}
