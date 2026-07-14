using System.Runtime.InteropServices;
using Microsoft.UI.Dispatching;

namespace AgentPulse.WindowsApp;

internal sealed class TrayIcon : IDisposable
{
    private const uint CallbackMessage = 0x8001;
    private const uint LeftButtonUp = 0x0202;
    private const uint RightButtonUp = 0x0205;
    private const uint NotifyMessage = 0x00000001;
    private const uint NotifyIcon = 0x00000002;
    private const uint NotifyTip = 0x00000004;
    private const uint Add = 0x00000000;
    private const uint Modify = 0x00000001;
    private const uint Delete = 0x00000002;
    private const uint SetVersion = 0x00000004;
    private const uint Version4 = 4;
    private const uint IconId = 1;
    private const nuint SubclassId = 0xA617;

    private readonly IntPtr _window;
    private readonly DispatcherQueue _dispatcher;
    private readonly Action _onInvoked;
    private readonly SubclassProcedure _subclassProcedure;
    private NotifyIconData _data;
    private bool _disposed;

    internal TrayIcon(
        IntPtr window,
        DispatcherQueue dispatcher,
        Action onInvoked,
        string tooltip)
    {
        _window = window;
        _dispatcher = dispatcher;
        _onInvoked = onInvoked;
        _subclassProcedure = WindowProcedure;
        SetWindowSubclass(window, _subclassProcedure, SubclassId, 0);

        _data = CreateData(tooltip);
        ShellNotifyIcon(Add, ref _data);
        _data.TimeoutOrVersion = Version4;
        ShellNotifyIcon(SetVersion, ref _data);
    }

    internal void UpdateTooltip(string value)
    {
        _data.Tooltip = Truncate(value, 127);
        ShellNotifyIcon(Modify, ref _data);
    }

    private IntPtr WindowProcedure(
        IntPtr window,
        uint message,
        nuint wordParameter,
        nint longParameter,
        nuint subclassId,
        nuint referenceData)
    {
        if (message == CallbackMessage)
        {
            var mouseMessage = (uint)((long)longParameter & 0xffff);
            if (mouseMessage is LeftButtonUp or RightButtonUp)
                _dispatcher.TryEnqueue(_onInvoked);
        }
        return DefSubclassProc(window, message, wordParameter, longParameter);
    }

    private NotifyIconData CreateData(string tooltip) => new()
    {
        Size = (uint)Marshal.SizeOf<NotifyIconData>(),
        Window = _window,
        Id = IconId,
        Flags = NotifyMessage | NotifyIcon | NotifyTip,
        CallbackMessage = CallbackMessage,
        Icon = LoadIcon(IntPtr.Zero, new IntPtr(32512)),
        Tooltip = Truncate(tooltip, 127),
        Info = string.Empty,
        InfoTitle = string.Empty,
    };

    private static string Truncate(string value, int maximum) =>
        value.Length <= maximum ? value : value[..maximum];

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        ShellNotifyIcon(Delete, ref _data);
        RemoveWindowSubclass(_window, _subclassProcedure, SubclassId);
    }

    private delegate IntPtr SubclassProcedure(
        IntPtr window,
        uint message,
        nuint wordParameter,
        nint longParameter,
        nuint subclassId,
        nuint referenceData);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NotifyIconData
    {
        internal uint Size;
        internal IntPtr Window;
        internal uint Id;
        internal uint Flags;
        internal uint CallbackMessage;
        internal IntPtr Icon;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        internal string Tooltip;
        internal uint State;
        internal uint StateMask;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        internal string Info;
        internal uint TimeoutOrVersion;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)]
        internal string InfoTitle;
        internal uint InfoFlags;
        internal Guid Item;
        internal IntPtr BalloonIcon;
    }

    [DllImport("shell32.dll", EntryPoint = "Shell_NotifyIconW", CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ShellNotifyIcon(uint message, ref NotifyIconData data);

    [DllImport("user32.dll")]
    private static extern IntPtr LoadIcon(IntPtr instance, IntPtr iconName);

    [DllImport("comctl32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowSubclass(
        IntPtr window,
        SubclassProcedure procedure,
        nuint subclassId,
        nuint referenceData);

    [DllImport("comctl32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool RemoveWindowSubclass(
        IntPtr window,
        SubclassProcedure procedure,
        nuint subclassId);

    [DllImport("comctl32.dll")]
    private static extern IntPtr DefSubclassProc(
        IntPtr window,
        uint message,
        nuint wordParameter,
        nint longParameter);
}
