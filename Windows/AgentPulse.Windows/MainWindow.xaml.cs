using AgentPulse.Windows.Core.Models;
using AgentPulse.Windows.Core.Services;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using WinRT.Interop;

namespace AgentPulse.WindowsApp;

public sealed partial class MainWindow : Window
{
    private readonly AppWindow _appWindow;
    private bool _isVisible;

    public SessionRepository Repository { get; }
    public IntPtr WindowHandle { get; }

    public MainWindow(SessionRepository repository, Action exit)
    {
        Repository = repository;
        InitializeComponent();
        Content = new SessionPanelView(repository, JumpToSession, exit);

        WindowHandle = WindowNative.GetWindowHandle(this);
        var windowId = Microsoft.UI.Win32Interop.GetWindowIdFromWindow(WindowHandle);
        _appWindow = AppWindow.GetFromWindowId(windowId);
        _appWindow.Resize(new global::Windows.Graphics.SizeInt32(400, 520));
        if (_appWindow.Presenter is OverlappedPresenter presenter)
        {
            presenter.IsResizable = false;
            presenter.IsMaximizable = false;
            presenter.IsMinimizable = false;
            presenter.SetBorderAndTitleBar(false, false);
        }
        NativeMethods.PreferRoundedCorners(WindowHandle);
        Activated += MainWindow_Activated;
    }

    public void InitializeHidden()
    {
        _appWindow.Move(new global::Windows.Graphics.PointInt32(-10_000, -10_000));
        Activate();
        HidePanel();
    }

    public void TogglePanel()
    {
        if (_isVisible) HidePanel();
        else ShowPanel();
    }

    private void ShowPanel()
    {
        var display = DisplayArea.GetFromWindowId(_appWindow.Id, DisplayAreaFallback.Primary);
        var workArea = display.WorkArea;
        const int margin = 12;
        _appWindow.Move(new global::Windows.Graphics.PointInt32(
            workArea.X + workArea.Width - _appWindow.Size.Width - margin,
            workArea.Y + workArea.Height - _appWindow.Size.Height - margin));
        NativeMethods.ShowWindow(WindowHandle, NativeMethods.ShowWindowCommand.Show);
        Activate();
        NativeMethods.SetForegroundWindow(WindowHandle);
        _isVisible = true;
    }

    private void HidePanel()
    {
        NativeMethods.ShowWindow(WindowHandle, NativeMethods.ShowWindowCommand.Hide);
        _isVisible = false;
    }

    private void MainWindow_Activated(object sender, WindowActivatedEventArgs args)
    {
        if (_isVisible && args.WindowActivationState == WindowActivationState.Deactivated)
            HidePanel();
    }

    private void JumpToSession(AgentSession session)
    {
        WindowActivator.Activate(session);
        HidePanel();
    }
}
