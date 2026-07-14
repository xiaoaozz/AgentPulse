using System.Runtime.InteropServices;

namespace AgentPulse.WindowsApp;

internal static class NativeMethods
{
    internal enum ShowWindowCommand
    {
        Hide = 0,
        Show = 5,
        Restore = 9,
    }

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool ShowWindow(IntPtr window, ShowWindowCommand command);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool SetForegroundWindow(IntPtr window);

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(
        IntPtr window,
        int attribute,
        ref int value,
        int valueSize);

    internal static void PreferRoundedCorners(IntPtr window)
    {
        const int DwmWindowCornerPreference = 33;
        const int Round = 2;
        var preference = Round;
        _ = DwmSetWindowAttribute(window, DwmWindowCornerPreference, ref preference, sizeof(int));
    }
}
