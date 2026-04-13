// (C) 2024-2026 nullCarbon. Licensed under LGPL-3.0-or-later. See COPYING.LESSER.
namespace SCaddins.NullCarbon.Update
{
    using System;
    using System.Diagnostics;
    using System.IO;
    using System.Linq;
    using System.Net;
    using System.Net.Http;
    using Autodesk.Revit.UI;
    using Newtonsoft.Json;

    /// <summary>
    /// One-click updater for the nullCarbon Revit Export.
    /// Checks the fork's GitHub Releases for a newer version, prompts the user
    /// with a Revit TaskDialog, downloads the per-user MSI, and runs it
    /// silently via msiexec.
    /// </summary>
    internal static class NullCarbonUpdater
    {
        // Session-level snooze. If the user clicks "Later" once, we won't
        // pester them again from background checks (Revit-startup task) for
        // the rest of this Revit session. A manual click of the "Check for
        // updates" link bypasses this and always runs.
        private static bool sessionSnoozed;

        public static void CheckForUpdates(bool quietIfNotNewer)
        {
            // Background callers (quietIfNotNewer=true) respect the snooze
            // flag. Manual callers (quietIfNotNewer=false) always run -- the
            // user explicitly asked.
            if (quietIfNotNewer && sessionSnoozed)
            {
                Debug.WriteLine("nullCarbon updater: skipped (session-snoozed)");
                return;
            }

            ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;

            LatestVersion latest;
            try
            {
                latest = FetchLatestVersionWithRetry();
            }
            catch (Exception ex)
            {
                Debug.WriteLine("nullCarbon updater: " + ex.Message);
                if (!quietIfNotNewer)
                {
                    ShowError("Could not reach GitHub to check for updates.\n\n" + ex.Message);
                }
                return;
            }

            if (latest == null || string.IsNullOrEmpty(latest.tag_name))
            {
                if (!quietIfNotNewer) ShowError("No releases found.");
                return;
            }

            Version installed = SCaddinsApp.Version;
            Version available;
            try
            {
                available = new Version(latest.tag_name.Replace("v", string.Empty).Trim());
            }
            catch (Exception)
            {
                if (!quietIfNotNewer) ShowError("Could not parse release tag '" + latest.tag_name + "'.");
                return;
            }

            if (available <= installed)
            {
                if (!quietIfNotNewer)
                {
                    ShowInfo("You're up to date.\n\nInstalled version: " + installed);
                }
                return;
            }

            string downloadUrl = SelectPreferredAsset(latest);
            string fileName    = SelectPreferredAssetName(latest);
            if (string.IsNullOrEmpty(downloadUrl))
            {
                ShowError("A new version (" + available + ") is available, but no installer asset was found in the release.\n\nOpen the releases page manually:\n" + Branding.ReleasesLink);
                return;
            }

            if (!ConfirmInstall(installed, available, latest.body))
            {
                // User clicked "Later". Snooze for the rest of this Revit
                // session so the background check doesn't re-pester them.
                // The next Revit start (or a manual click) will re-prompt.
                sessionSnoozed = true;
                return;
            }

            string installerPath;
            try
            {
                installerPath = DownloadInstaller(downloadUrl, fileName);
            }
            catch (Exception ex)
            {
                ShowError("Download failed.\n\n" + ex.Message + "\n\nYou can download manually:\n" + Branding.ReleasesLink);
                return;
            }

            LaunchInstaller(installerPath);
        }

        // ---- HTTP fetch -----------------------------------------------------

        // Single retry on transient failures. Most update-check failures we
        // see in practice are flaky DNS, captive portals, or a 5xx from
        // GitHub. One retry with a short backoff fixes the common cases
        // without making startup feel slow when the network is genuinely down.
        private static LatestVersion FetchLatestVersionWithRetry()
        {
            try
            {
                return FetchLatestVersion();
            }
            catch (Exception firstEx)
            {
                Debug.WriteLine("nullCarbon updater: first fetch failed (" + firstEx.GetType().Name + "), retrying once after 2s...");
                System.Threading.Thread.Sleep(2000);
                return FetchLatestVersion();
            }
        }

        private static LatestVersion FetchLatestVersion()
        {
            // Deserialize with Newtonsoft.Json on BOTH framework targets. We used
            // to call System.Text.Json.JsonSerializer.Deserialize on the .NET 8
            // branch, but in Revit's hosted CLR the fusion loader failed to
            // resolve System.Text.Json 9.0.0 at runtime despite the DLL being
            // present in the install folder -- presumably because Revit pre-
            // loads an older STJ into the AppDomain. Newtonsoft.Json is already
            // shipped for the net48 branch and works fine on net8 too, so use
            // it everywhere and avoid the assembly-load wart.
            string json;
#if NET48
            var req = (HttpWebRequest)WebRequest.Create(Branding.LatestReleaseApi);
            req.ContentType = "application/json";
            req.UserAgent   = Branding.UserAgent;
            using (var s  = req.GetResponse().GetResponseStream())
            using (var sr = new StreamReader(s))
            {
                json = sr.ReadToEnd();
            }
#else
            using (var http = new HttpClient())
            {
                http.DefaultRequestHeaders.Add("User-Agent", Branding.UserAgent);
                var resp = http.Send(new HttpRequestMessage(HttpMethod.Get, Branding.LatestReleaseApi));
                using (var reader = new StreamReader(resp.Content.ReadAsStream()))
                {
                    json = reader.ReadToEnd();
                }
            }
#endif
            return JsonConvert.DeserializeObject<LatestVersion>(json);
        }

        // ---- Asset selection ------------------------------------------------

        private static Asset PickAsset(LatestVersion latest)
        {
            if (latest == null || latest.assets == null || latest.assets.Count == 0) return null;

            // Prefer the MSI matching Branding.PreferredAssetSuffix (".msi").
            // Fall back to anything ending in .msi, then any first asset.
            return
                   latest.assets.FirstOrDefault(a => a.name != null && a.name.EndsWith(Branding.PreferredAssetSuffix, StringComparison.OrdinalIgnoreCase))
                ?? latest.assets.FirstOrDefault(a => a.name != null && a.name.EndsWith(".msi",  StringComparison.OrdinalIgnoreCase))
                ?? latest.assets.FirstOrDefault();
        }

        private static string SelectPreferredAsset(LatestVersion latest)
        {
            var a = PickAsset(latest);
            return a == null ? null : a.browser_download_url;
        }

        private static string SelectPreferredAssetName(LatestVersion latest)
        {
            var a = PickAsset(latest);
            return (a != null && !string.IsNullOrEmpty(a.name)) ? a.name : "nullCarbon-LCA-Export.msi";
        }

        // ---- Download -------------------------------------------------------

        private static string DownloadInstaller(string url, string fileName)
        {
            string tempDir = Path.Combine(Path.GetTempPath(), "nullCarbon-RevitExport-Update");
            Directory.CreateDirectory(tempDir);
            string outPath = Path.Combine(tempDir, fileName);

            // Best-effort delete of any prior partial download.
            try { if (File.Exists(outPath)) File.Delete(outPath); } catch { }

#if NET48
            using (var wc = new WebClient())
            {
                wc.Headers.Add(HttpRequestHeader.UserAgent, Branding.UserAgent);
                wc.DownloadFile(url, outPath);
            }
#else
            using (var http = new HttpClient())
            {
                http.DefaultRequestHeaders.Add("User-Agent", Branding.UserAgent);
                http.Timeout = TimeSpan.FromMinutes(10);
                var bytes = http.GetByteArrayAsync(url).GetAwaiter().GetResult();
                File.WriteAllBytes(outPath, bytes);
            }
#endif
            return outPath;
        }

        // ---- Install --------------------------------------------------------

        private static void LaunchInstaller(string installerPath)
        {
            // We shell out to cmd.exe so msiexec starts in its own process tree,
            // detached from Revit. The 3-second delay gives this Revit session
            // time to close after the user dismisses our TaskDialog -- if
            // msiexec were to start while Revit still held the addin DLLs,
            // Restart Manager would have to force-close Revit mid-UI.
            //
            // msiexec flags:
            //   /i <path>   install (or upgrade) this package
            //   /qn         fully silent, no UI
            //   /norestart  never trigger a Windows reboot
            //
            // The MSI is per-user -- no UAC elevation. Windows' Restart
            // Manager (enabled by default) will still handle any lingering
            // DLL locks gracefully.
            try
            {
                var quoted = "\"" + installerPath + "\"";
                var cmdLine =
                    "/c timeout /t 3 /nobreak > NUL && " +
                    "msiexec.exe /i " + quoted + " /qn /norestart";

                Process.Start(new ProcessStartInfo
                {
                    FileName        = "cmd.exe",
                    Arguments       = cmdLine,
                    UseShellExecute = true,
                    CreateNoWindow  = true,
                    WindowStyle     = ProcessWindowStyle.Hidden,
                });

                ShowInfo(
                    "The update will install in a few seconds.\n\n" +
                    "Please close Revit now so the new files can be written. " +
                    "Re-open Revit afterwards to pick up the new version.");
            }
            catch (Exception ex)
            {
                ShowError("Could not launch msiexec for:\n" + installerPath + "\n\n" + ex.Message);
            }
        }

        // ---- TaskDialog wrappers --------------------------------------------

        private static bool ConfirmInstall(Version installed, Version available, string releaseNotes)
        {
            var dlg = new TaskDialog(Branding.ProductName + " update");
            dlg.MainInstruction = "An update is available";
            dlg.MainContent =
                "Installed: " + installed + "\n" +
                "Available: " + available + "\n\n" +
                (string.IsNullOrEmpty(releaseNotes) ? string.Empty : ("What's new:\n" + Truncate(releaseNotes, 600)));
            dlg.CommonButtons = TaskDialogCommonButtons.None;
            dlg.AddCommandLink(TaskDialogCommandLinkId.CommandLink1, "Update now", "Download and install. Revit will close automatically.");
            dlg.AddCommandLink(TaskDialogCommandLinkId.CommandLink2, "Later",      "Skip this update for now.");
            dlg.DefaultButton = TaskDialogResult.CommandLink1;
            return dlg.Show() == TaskDialogResult.CommandLink1;
        }

        private static void ShowInfo(string message)
        {
            var dlg = new TaskDialog(Branding.ProductName + " update");
            dlg.MainContent = message;
            dlg.CommonButtons = TaskDialogCommonButtons.Ok;
            dlg.Show();
        }

        private static void ShowError(string message)
        {
            var dlg = new TaskDialog(Branding.ProductName + " update");
            dlg.MainIcon = TaskDialogIcon.TaskDialogIconWarning;
            dlg.MainContent = message;
            dlg.CommonButtons = TaskDialogCommonButtons.Ok;
            dlg.Show();
        }

        private static string Truncate(string s, int max)
        {
            if (string.IsNullOrEmpty(s) || s.Length <= max) return s ?? string.Empty;
            return s.Substring(0, max) + "…";
        }
    }
}
