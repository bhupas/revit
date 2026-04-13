namespace SCaddins.NullCarbon.Login.Views
{
    using System.Windows;
    using SCaddins.NullCarbon.Login.ViewModels;

    public partial class LoginView : Window
    {
        public LoginView()
        {
            InitializeComponent();
        }

        // Caliburn.Micro's Message.Attach refuses to bind to Hyperlink because
        // Hyperlink is a FrameworkContentElement, not a FrameworkElement. So
        // the "Check for updates" link goes through a plain WPF Click handler
        // that calls the viewmodel directly.
        private void CheckForUpdatesHyperlink_Click(object sender, RoutedEventArgs e)
        {
            if (DataContext is LoginViewModel vm)
            {
                vm.CheckForUpdates();
            }
        }
    }
}