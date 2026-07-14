using System.IO.Pipes;
using System.Text.Json;
using AgentPulse.Windows.Core.Models;

namespace AgentPulse.Windows.Core.Services;

public sealed class NamedPipeEventServer : IAsyncDisposable
{
    public const string DefaultPipeName = "agentpulse";

    private readonly string _pipeName;
    private readonly Action<AgentEvent> _onEvent;
    private readonly Action<Exception> _onError;
    private readonly CancellationTokenSource _cancellation = new();
    private Task? _listener;

    public NamedPipeEventServer(
        Action<AgentEvent> onEvent,
        Action<Exception>? onError = null,
        string pipeName = DefaultPipeName)
    {
        _onEvent = onEvent;
        _onError = onError ?? (_ => { });
        _pipeName = pipeName;
    }

    public void Start() => _listener ??= ListenAsync(_cancellation.Token);

    private async Task ListenAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                await using var pipe = new NamedPipeServerStream(
                    _pipeName,
                    PipeDirection.In,
                    NamedPipeServerStream.MaxAllowedServerInstances,
                    PipeTransmissionMode.Byte,
                    PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
                await pipe.WaitForConnectionAsync(cancellationToken);
                using var reader = new StreamReader(pipe);
                var encoded = await reader.ReadToEndAsync(cancellationToken);
                if (string.IsNullOrWhiteSpace(encoded)) continue;
                var value = JsonSerializer.Deserialize<AgentEvent>(encoded);
                if (value is not null) _onEvent(value);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                return;
            }
            catch (Exception error)
            {
                _onError(error);
            }
        }
    }

    public async ValueTask DisposeAsync()
    {
        await _cancellation.CancelAsync();
        if (_listener is not null)
        {
            try { await _listener; }
            catch (OperationCanceledException) { }
        }
        _cancellation.Dispose();
    }
}
