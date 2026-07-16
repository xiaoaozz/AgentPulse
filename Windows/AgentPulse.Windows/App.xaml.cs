using AgentPulse.Windows.Core.Services;
using Microsoft.UI.Xaml;
using Velopack;

namespace AgentPulse.WindowsApp;

public partial class App : Application
{
    private readonly Mutex _singleInstance;
    private readonly bool _ownsMutex;
    private MainWindow? _window;
    private TrayIcon? _trayIcon;
    private NamedPipeEventServer? _server;
    private bool _isExiting;

    public App()
    {
        VelopackApp.Build().Run();
        _singleInstance = new Mutex(true, "Local\\AgentPulse", out _ownsMutex);
        InitializeComponent();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        if (!_ownsMutex)
        {
            Current.Exit();
            return;
        }

        var repository = new SessionRepository();
        _window = new MainWindow(repository, ExitAsync);
        _window.InitializeHidden();
        _trayIcon = new TrayIcon(
            _window.WindowHandle,
            _window.DispatcherQueue,
            _window.TogglePanel,
            "AgentPulse · 等待 Agent 会话");
        repository.PropertyChanged += (_, _) =>
            _trayIcon?.UpdateTooltip($"AgentPulse · {repository.OngoingCount} 个进行中会话");

        _server = new NamedPipeEventServer(value =>
        {
            _window.DispatcherQueue.TryEnqueue(() => repository.Receive(value));
        });
        _server.Start();
    }

    private async void ExitAsync()
    {
        if (_isExiting) return;
        _isExiting = true;
        _trayIcon?.Dispose();
        if (_ownsMutex) _singleInstance.ReleaseMutex();
        if (_server is not null) await _server.DisposeAsync();
        _singleInstance.Dispose();
        Current.Exit();
    }
}
