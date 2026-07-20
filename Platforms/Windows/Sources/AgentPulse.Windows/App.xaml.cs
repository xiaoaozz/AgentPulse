using AgentPulse.Windows.Core.Services;
using AgentPulse.Windows.Core.Models;
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
    private Microsoft.UI.Dispatching.DispatcherQueueTimer? _statusTimer;
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
            "AgentPulse · Ready");
        repository.PropertyChanged += (_, _) => UpdateTrayTooltip(repository);
        _statusTimer = _window.DispatcherQueue.CreateTimer();
        _statusTimer.Interval = TimeSpan.FromSeconds(1);
        _statusTimer.Tick += (_, _) => UpdateTrayTooltip(repository);
        _statusTimer.Start();

        _server = new NamedPipeEventServer(value =>
        {
            _window.DispatcherQueue.TryEnqueue(() => repository.Receive(value));
        });
        _server.Start();
    }

    private void UpdateTrayTooltip(SessionRepository repository)
    {
        var text = repository.GlobalPhase == SessionPhase.Done
            ? "AgentPulse · Done"
            : repository.OngoingCount == 0
                ? "AgentPulse · Ready"
                : $"AgentPulse · {repository.OngoingCount} 个进行中会话";
        _trayIcon?.UpdateTooltip(text);
    }

    private async void ExitAsync()
    {
        if (_isExiting) return;
        _isExiting = true;
        _statusTimer?.Stop();
        _trayIcon?.Dispose();
        if (_ownsMutex) _singleInstance.ReleaseMutex();
        if (_server is not null) await _server.DisposeAsync();
        _singleInstance.Dispose();
        Current.Exit();
    }
}
