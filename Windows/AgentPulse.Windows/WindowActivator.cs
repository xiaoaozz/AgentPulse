using System.Diagnostics;
using System.Runtime.InteropServices;
using AgentPulse.Windows.Core.Models;

namespace AgentPulse.WindowsApp;

internal static class WindowActivator
{
    private delegate bool EnumWindowsCallback(IntPtr window, IntPtr parameter);

    internal static bool Activate(AgentSession session)
    {
        if (session.ProcessId is int processId && ActivateProcess(processId)) return true;
        if (!string.IsNullOrWhiteSpace(session.TerminalProcess) && ActivateByName(session.TerminalProcess))
            return true;

        foreach (var processName in new[] { "WindowsTerminal", "Code", "Warp", "pwsh", "powershell" })
        {
            if (ActivateByName(processName)) return true;
        }
        return false;
    }

    private static bool ActivateByName(string value)
    {
        var processName = Path.GetFileNameWithoutExtension(value);
        foreach (var process in Process.GetProcessesByName(processName))
        {
            using (process)
            {
                if (ActivateProcess(process.Id)) return true;
            }
        }
        return false;
    }

    private static bool ActivateProcess(int processId)
    {
        IntPtr candidate = IntPtr.Zero;
        EnumWindows((window, _) =>
        {
            GetWindowThreadProcessId(window, out var ownerProcessId);
            if (ownerProcessId != processId || !IsWindowVisible(window) || GetWindow(window, 4) != IntPtr.Zero)
                return true;
            candidate = window;
            return false;
        }, IntPtr.Zero);

        if (candidate == IntPtr.Zero) return false;
        NativeMethods.ShowWindow(candidate, NativeMethods.ShowWindowCommand.Restore);
        return NativeMethods.SetForegroundWindow(candidate);
    }

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EnumWindows(EnumWindowsCallback callback, IntPtr parameter);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr window, out int processId);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindowVisible(IntPtr window);

    [DllImport("user32.dll")]
    private static extern IntPtr GetWindow(IntPtr window, uint command);
}
