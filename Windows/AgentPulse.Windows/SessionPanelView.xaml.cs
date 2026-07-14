using AgentPulse.Windows.Core.Models;
using AgentPulse.Windows.Core.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace AgentPulse.WindowsApp;

public sealed partial class SessionPanelView : UserControl
{
    private readonly Action<AgentSession> _jump;
    private readonly Action _exit;

    public SessionRepository Repository { get; }

    public SessionPanelView(
        SessionRepository repository,
        Action<AgentSession> jump,
        Action exit)
    {
        Repository = repository;
        _jump = jump;
        _exit = exit;
        InitializeComponent();
    }

    private void Jump_Click(object sender, RoutedEventArgs args)
    {
        if ((sender as FrameworkElement)?.DataContext is AgentSession session)
            _jump(session);
    }

    private void Remove_Click(object sender, RoutedEventArgs args)
    {
        if ((sender as FrameworkElement)?.DataContext is AgentSession session)
            Repository.RemoveCompletedSession(session.Id);
    }

    private void ClearCompleted_Click(object sender, RoutedEventArgs args) => Repository.ClearCompleted();

    private void Exit_Click(object sender, RoutedEventArgs args) => _exit();
}
