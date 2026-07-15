using System.ComponentModel;
using System.Runtime.CompilerServices;
using Microsoft.UI.Dispatching;
using Velopack;
using Velopack.Sources;

namespace AgentPulse.WindowsApp;

public sealed class UpdateService : INotifyPropertyChanged
{
    private const string RepositoryUrl = "https://github.com/xiaoaozz/AgentPulse";

    private readonly UpdateManager _manager;
    private readonly Action _exit;
    private readonly DispatcherQueue _dispatcherQueue;
    private UpdateInfo? _pendingUpdate;
    private bool _isVisible;
    private bool _isBusy;
    private bool _readyToApply;
    private int _progress;
    private string _statusText = "";

    public event PropertyChangedEventHandler? PropertyChanged;

    public UpdateService(Action exit)
    {
        _exit = exit;
        _dispatcherQueue = DispatcherQueue.GetForCurrentThread();
        _manager = new UpdateManager(new GithubSource(RepositoryUrl, accessToken: null, prerelease: false));
    }

    public bool IsVisible
    {
        get => _isVisible;
        private set => SetField(ref _isVisible, value);
    }

    public bool IsBusy
    {
        get => _isBusy;
        private set
        {
            if (SetField(ref _isBusy, value))
                OnPropertyChanged(nameof(CanInstall));
        }
    }

    public int Progress
    {
        get => _progress;
        private set => SetField(ref _progress, value);
    }

    public string StatusText
    {
        get => _statusText;
        private set => SetField(ref _statusText, value);
    }

    public bool CanInstall => !IsBusy && (_pendingUpdate is not null || _readyToApply);

    public async Task CheckForUpdatesAsync(bool showUpToDate = false)
    {
        if (IsBusy || !_manager.IsInstalled)
        {
            if (showUpToDate && !_manager.IsInstalled)
            {
                StatusText = "便携版不支持应用内升级，请使用 Setup 安装版";
                IsVisible = true;
            }
            return;
        }

        IsBusy = true;
        Progress = 0;
        if (showUpToDate)
        {
            StatusText = "正在检查更新…";
            IsVisible = true;
        }

        try
        {
            var update = await _manager.CheckForUpdatesAsync();
            if (update is null)
            {
                if (showUpToDate)
                {
                    StatusText = "当前已经是最新版本";
                    IsVisible = true;
                }
                return;
            }

            _pendingUpdate = update;
            StatusText = $"发现新版本 {update.TargetFullRelease.Version}";
            IsVisible = true;
            OnPropertyChanged(nameof(CanInstall));
        }
        catch (Exception error)
        {
            if (showUpToDate)
            {
                StatusText = $"检查更新失败：{error.Message}";
                IsVisible = true;
            }
        }
        finally
        {
            IsBusy = false;
        }
    }

    public async Task InstallUpdateAsync()
    {
        if (IsBusy) return;

        if (_readyToApply)
        {
            ApplyAndRestart();
            return;
        }

        var update = _pendingUpdate;
        if (update is null) return;

        IsBusy = true;
        StatusText = $"正在下载 {update.TargetFullRelease.Version}…";
        Progress = 0;
        try
        {
            await _manager.DownloadUpdatesAsync(update, value => Progress = value);
            _readyToApply = true;
            IsBusy = false;
            StatusText = "下载完成，正在重新启动…";
            ApplyAndRestart();
        }
        catch (Exception error)
        {
            StatusText = $"升级失败：{error.Message}";
            IsBusy = false;
        }
    }

    private void ApplyAndRestart()
    {
        _manager.WaitExitThenApplyUpdates(
            _pendingUpdate?.TargetFullRelease,
            silent: false,
            restart: true);
        _exit();
    }

    private bool SetField<T>(ref T field, T value, [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return false;
        field = value;
        OnPropertyChanged(propertyName);
        return true;
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        if (_dispatcherQueue.HasThreadAccess)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
            return;
        }

        _dispatcherQueue.TryEnqueue(() =>
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName)));
    }
}
