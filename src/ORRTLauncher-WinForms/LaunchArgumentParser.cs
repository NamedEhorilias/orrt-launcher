using System;
using System.Collections.Generic;

namespace ORRTLauncher
{
    public class LaunchArgs
    {
        public string LaunchMode { get; set; }
        public string ClientVersion { get; set; }
        public string GameInfo { get; set; }
        public string PlaceLauncherUrl { get; set; }
        public string RetroArgs { get; set; }
    }

    public static class LaunchArgumentParser
    {
        private static readonly HashSet<string> KnownKeys = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "launchmode", "clientversion", "gameinfo", "placelauncherurl", "suggest", "k", "client"
        };

        public static LaunchArgs Parse(string rawUri)
        {
            if (rawUri == null) throw new ArgumentNullException(nameof(rawUri));

            // Strip the scheme prefix "orrt-player:" 
            int schemeEnd = rawUri.IndexOf(':');
            if (schemeEnd < 0) throw new FormatException("URI has no scheme separator.");
            string body = rawUri.Substring(schemeEnd + 1); // e.g. "1+launchmode:play+..."

            // Split on '+' into raw tokens
            string[] tokens = body.Split('+');

            var result = new LaunchArgs();

            // We reconstruct the placelauncherurl which may contain un-encoded '+' characters
            // by collecting all tokens after "placelauncherurl:" until we hit another known key.
            string pendingKey = null;
            string pendingValue = null;
            var urlParts = new System.Collections.Generic.List<string>();

            foreach (string token in tokens)
            {
                // Check if this token is a key:value pair
                int colon = token.IndexOf(':');
                if (colon > 0)
                {
                    string key = token.Substring(0, colon).ToLowerInvariant();
                    string value = token.Substring(colon + 1);

                    if (KnownKeys.Contains(key))
                    {
                        // Flush previous pending placelauncherurl
                        if (pendingKey == "placelauncherurl" && urlParts.Count > 0)
                        {
                            result.PlaceLauncherUrl = string.Join("+", urlParts);
                            urlParts.Clear();
                        }
                        else if (pendingKey != null)
                        {
                            AssignField(result, pendingKey, pendingValue);
                        }

                        pendingKey = key;
                        pendingValue = value;

                        if (key == "placelauncherurl")
                        {
                            urlParts.Add(value);
                        }
                        continue;
                    }
                }

                // Token is a continuation of the previous value (e.g. URL fragment after '+')
                if (pendingKey == "placelauncherurl")
                {
                    urlParts.Add(token);
                }
            }

            // Flush last pending
            if (pendingKey == "placelauncherurl" && urlParts.Count > 0)
            {
                result.PlaceLauncherUrl = string.Join("+", urlParts);
            }
            else if (pendingKey != null)
            {
                AssignField(result, pendingKey, pendingValue);
            }

            return result;
        }

        private static void AssignField(LaunchArgs args, string key, string value)
        {
            switch (key)
            {
                case "launchmode": args.LaunchMode = value; break;
                case "clientversion": args.ClientVersion = value; break;
                case "gameinfo": args.GameInfo = value; break;
                // ignore k, client, suggest
            }
        }
    }
}
