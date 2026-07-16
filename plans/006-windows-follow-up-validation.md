# Plan 006: Run deferred Windows validation for completed transport/session fixes

> **Context**: Plans 001-005 have already been implemented in the working tree on 2026-07-16. macOS Swift tests, Node hook tests, and Python hook tests have passed. This follow-up plan exists only because no Windows environment was available during implementation.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: verification
- **Planned at**: 2026-07-16

## Why this matters

The repository now contains Windows-specific behavior changes in the session contract path and named-pipe transport. Those code paths were updated together with new tests, but they still need to be exercised on an actual Windows machine before the work can be considered fully verified.

## Scope

**In scope**:
- Running the existing Windows contract-test executable
- Running the Windows app build
- Recording pass/fail results back into `plans/README.md`

**Out of scope**:
- New feature work
- Additional refactors
- Reopening completed Plans 001-005 unless verification reveals a regression

## Commands to run on Windows

```powershell
dotnet run --project Windows/AgentPulse.Windows.ContractTests/AgentPulse.Windows.ContractTests.csproj --configuration Release -- Protocol/Fixtures/session-scenarios.json
dotnet build Windows/AgentPulse.Windows/AgentPulse.Windows.csproj --configuration Release -p:Platform=x64
```

## Expected results

- The contract-test command should report the shared session scenarios and named-pipe integration tests passing.
- The Windows app project should build successfully in `Release` for `x64`.

## Done criteria

- [ ] Windows contract tests pass.
- [ ] Windows app build passes.
- [ ] `plans/README.md` is updated from `TODO` to `DONE`, or `BLOCKED` with a one-line reason if the environment/setup is unavailable.

## Notes

- If either command fails, capture the exact failure and treat that as a new follow-up item rather than silently changing the implementation.
