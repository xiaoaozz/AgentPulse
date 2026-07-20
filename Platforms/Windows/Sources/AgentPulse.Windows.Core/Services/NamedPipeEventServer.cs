using System.IO.Pipes;
using System.Text;
using System.Text.Json;
using AgentPulse.Windows.Core.Models;

namespace AgentPulse.Windows.Core.Services;

public sealed class NamedPipeEventServer : IAsyncDisposable
{
    public const string DefaultPipeName = "agentpulse";
    public const int MaxMessageBytes = 64 * 1024;
    private static readonly TimeSpan ConnectionTimeout = TimeSpan.FromSeconds(1);

    private readonly string _pipeName;
    private readonly Action<AgentEvent> _onEvent;
    private readonly Action<Exception> _onError;
    private readonly CancellationTokenSource _cancellation = new();
    private readonly object _lifecycleLock = new();
    private Task? _listener;
    private Task? _disposeTask;

    public NamedPipeEventServer(
        Action<AgentEvent> onEvent,
        Action<Exception>? onError = null,
        string pipeName = DefaultPipeName)
    {
        _onEvent = onEvent;
        _onError = onError ?? (_ => { });
        _pipeName = pipeName;
    }

    public void Start()
    {
        lock (_lifecycleLock)
        {
            if (_disposeTask is not null)
                throw new ObjectDisposedException(nameof(NamedPipeEventServer));
            _listener ??= ListenAsync(_cancellation.Token);
        }
    }

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
                var value = await ReadEventAsync(pipe, cancellationToken);
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

    private static async Task<AgentEvent?> ReadEventAsync(
        NamedPipeServerStream pipe,
        CancellationToken cancellationToken)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(ConnectionTimeout);

        using var buffer = new MemoryStream();
        var chunk = new byte[8_192];
        while (true)
        {
            int read;
            try
            {
                read = await pipe.ReadAsync(chunk, timeout.Token);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (OperationCanceledException) when (timeout.IsCancellationRequested)
            {
                throw new TimeoutException("Named pipe client did not finish sending within one second.");
            }

            if (read == 0) break;
            if (buffer.Length + read > MaxMessageBytes)
                throw new InvalidDataException($"Named pipe payload exceeds {MaxMessageBytes} bytes.");
            await buffer.WriteAsync(chunk.AsMemory(0, read), cancellationToken);
        }

        if (buffer.Length == 0) return null;
        var encoded = Encoding.UTF8.GetString(buffer.ToArray());
        if (string.IsNullOrWhiteSpace(encoded)) return null;
        return JsonSerializer.Deserialize<AgentEvent>(encoded);
    }

    public ValueTask DisposeAsync()
    {
        lock (_lifecycleLock)
        {
            _disposeTask ??= DisposeCoreAsync();
            return new ValueTask(_disposeTask);
        }
    }

    private async Task DisposeCoreAsync()
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
