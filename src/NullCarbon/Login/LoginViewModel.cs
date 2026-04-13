using Caliburn.Micro;
using Newtonsoft.Json;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Net.Http;
using System.Reflection;
using System.Text;
using System.Threading.Tasks;
using System.Windows;

namespace SCaddins.NullCarbon.Login.ViewModels
{
    public class LoginViewModel : Screen
    {
        private string username;
        private string password;
        private string statusMessage;
        private bool isLoggingIn;

        // Matches the shape every other ShowDialogAsync callsite in the repo
        // uses. LoginCommand passes this to SCaddinsApp.WindowManager.ShowDialogAsync
        // so the host window is sized and titled explicitly instead of relying
        // on Caliburn's auto-wrap defaults (which historically caused the
        // dialog to never appear from Revit's async action-message path).
        public static IDictionary<string, object> DefaultWindowSettings => new Dictionary<string, object>
        {
            { "Title", "Log ind til nullCarbon" },
            { "SizeToContent", System.Windows.SizeToContent.Manual },
            { "Width", 500.0 },
            { "Height", 580.0 },
            { "ResizeMode", System.Windows.ResizeMode.NoResize },
            { "WindowStartupLocation", System.Windows.WindowStartupLocation.CenterScreen },
            { "ShowInTaskbar", true },
        };

        public string Username
        {
            get => username;
            set
            {
                if (username != value)
                {
                    username = value;
                    NotifyOfPropertyChange(() => Username);
                    NotifyOfPropertyChange(() => CanLogin);
                }
            }
        }

        // Password is collected from the OnPasswordChanged event
        public string Password
        {
            get => password;
            set
            {
                if (password != value)
                {
                    password = value;
                    NotifyOfPropertyChange(() => Password);
                    NotifyOfPropertyChange(() => CanLogin);
                }
            }
        }

        public string StatusMessage
        {
            get => statusMessage;
            set
            {
                if (statusMessage != value)
                {
                    statusMessage = value;
                    NotifyOfPropertyChange(() => StatusMessage);
                }
            }
        }

        public bool IsLoggingIn
        {
            get => isLoggingIn;
            set
            {
                if (isLoggingIn != value)
                {
                    isLoggingIn = value;
                    NotifyOfPropertyChange(() => IsLoggingIn);
                    NotifyOfPropertyChange(() => CanLogin);
                }
            }
        }

        public bool CanLogin => !IsLoggingIn && !string.IsNullOrWhiteSpace(Username) && !string.IsNullOrWhiteSpace(Password);

        // Single source of truth: Branding.VersionShort reads from the assembly,
        // which is rewritten by scripts\release.ps1 -Version X.Y.Z.
        public string VersionLabel => "Build " + SCaddins.NullCarbon.Branding.VersionShort;

        // Bound to the "Check for updates" Hyperlink in LoginView.xaml.
        // Pass quietIfNotNewer:false so the user gets a confirmation dialog
        // even when there's no update -- otherwise clicking the link with
        // nothing to update would look broken.
        public void CheckForUpdates()
        {
            try
            {
                SCaddins.NullCarbon.Update.NullCarbonUpdater.CheckForUpdates(quietIfNotNewer: false);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine("nullCarbon updater (manual): " + ex.Message);
            }
        }

        // Called from XAML when the PasswordBox changes
        public void OnPasswordChanged(object source)
        {
            if (source is System.Windows.Controls.PasswordBox pwd)
            {
                Password = pwd.Password;
            }
        }

        public async Task Login()
        {
            if (!CanLogin)
            {
                return;
            }

            IsLoggingIn = true;
            StatusMessage = "Logging in...";

            try
            {
                // API endpoint configuration
                string baseUrl = "https://backend.nullcarbon.dk";
                string loginRoute = "/auth/jwt/create";
                string fullUrl = baseUrl + loginRoute;

                var requestData = new
                {
                    username = Username,
                    password = Password
                };

                var jsonString = JsonConvert.SerializeObject(requestData);
                var requestContent = new StringContent(jsonString, Encoding.UTF8, "application/json");

                using (var client = new HttpClient())
                {
                    client.Timeout = TimeSpan.FromSeconds(30);
                    var response = await client.PostAsync(fullUrl, requestContent);
                    var responseBody = await response.Content.ReadAsStringAsync();

                    if (response.IsSuccessStatusCode)
                    {
                        // Deserialize the JSON response for tokens
                        var tokenData = JsonConvert.DeserializeObject<LoginResponse>(responseBody);

                        if (tokenData != null && !string.IsNullOrEmpty(tokenData.Access))
                        {
                            // Store the tokens
                            TokenCache.AccessToken = tokenData.Access;
                            TokenCache.RefreshToken = tokenData.Refresh;

                            StatusMessage = "Login successful!";

                            // Close the dialog on successful login
                            await Task.Delay(500); // Small delay to show success message
                            await TryCloseAsync(true);
                        }
                        else
                        {
                            StatusMessage = "Login succeeded, but no valid token was returned.";
                        }
                    }
                    else
                    {
                        // Try to get a more specific error message from the response
                        try
                        {
                            var errorObject = JsonConvert.DeserializeObject<dynamic>(responseBody);
                            string errorMsg = "Login failed";

                            // Check for common error fields in API responses
                            if (errorObject.detail != null)
                            {
                                errorMsg += ": " + errorObject.detail.ToString();
                            }
                            else if (errorObject.error != null)
                            {
                                errorMsg += ": " + errorObject.error.ToString();
                            }
                            else if (errorObject.message != null)
                            {
                                errorMsg += ": " + errorObject.message.ToString();
                            }
                            else if (!string.IsNullOrEmpty(responseBody))
                            {
                                errorMsg += ": " + (responseBody.Length > 100 ? responseBody.Substring(0, 100) + "..." : responseBody);
                            }

                            StatusMessage = errorMsg;
                        }
                        catch
                        {
                            StatusMessage = $"Login failed with status code: {response.StatusCode}";
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                StatusMessage = $"Login error: {ex.Message}";
            }
            finally
            {
                IsLoggingIn = false;
            }
        }

        public void SignUp()
        {
            try
            {
                Process.Start(new ProcessStartInfo
                {
                    FileName = "https://www.nullcarbon.dk/pricing-plans/list",
                    UseShellExecute = true
                });
            }
            catch (Exception ex)
            {
                StatusMessage = $"Could not open the signup page: {ex.Message}";
            }
        }
    }

    // Helper class for deserializing the JSON response
    public class LoginResponse
    {
        [JsonProperty("access")]
        public string Access { get; set; }

        [JsonProperty("refresh")]
        public string Refresh { get; set; }
    }

    // Simple static cache for storing tokens in memory
    public static class TokenCache
    {
        public static string AccessToken { get; set; }
        public static string RefreshToken { get; set; }

        public static bool IsTokenValid => !string.IsNullOrEmpty(AccessToken);

        public static void ClearTokens()
        {
            AccessToken = null;
            RefreshToken = null;
        }
    }
}
