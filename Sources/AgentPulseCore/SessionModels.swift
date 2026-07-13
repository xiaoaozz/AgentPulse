import Foundation

public enum SessionPhase: String, Codable, CaseIterable, Sendable {
    case idle
    case preparing
    case running
    case waitingForAction = "waiting_for_action"
    case done
    case warning
    case failed
    case paused
    case offline

    public var needsAttention: Bool { self == .waitingForAction }
    public var isActive: Bool { self == .preparing || self == .running }
    public var isClearable: Bool { self == .done || self == .warning || self == .failed }
    public var isOngoing: Bool {
        isActive || needsAttention || self == .paused
    }

    public var label: String {
        switch self {
        case .idle: "Idle"
        case .preparing: "Preparing"
        case .running: "Running"
        case .waitingForAction: "Waiting for Action"
        case .done: "Done"
        case .warning: "Warning"
        case .failed: "Failed"
        case .paused: "Paused"
        case .offline: "Offline"
        }
    }

    public var meaning: String {
        switch self {
        case .idle: "空闲，无任务"
        case .preparing: "初始化、准备执行"
        case .running: "正在执行任务"
        case .waitingForAction: "等待用户操作"
        case .done: "执行完成"
        case .warning: "已完成，但存在警告或异常"
        case .failed: "执行失败"
        case .paused: "已暂停"
        case .offline: "Agent 离线"
        }
    }
}

public struct AgentEvent: Codable, Sendable {
    public let sessionId: String
    public let agent: String
    public let cwd: String
    public let title: String?
    public let phase: SessionPhase
    public let detail: String?
    public let pid: Int32?
    public let tty: String?
    public let terminalBundleId: String?
    public let occurredAt: Date?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case agent, cwd, title, phase, detail, pid, tty
        case terminalBundleId = "terminal_bundle_id"
        case occurredAt = "occurred_at"
    }

    public init(
        sessionId: String,
        agent: String,
        cwd: String,
        title: String? = nil,
        phase: SessionPhase,
        detail: String? = nil,
        pid: Int32? = nil,
        tty: String? = nil,
        terminalBundleId: String? = nil,
        occurredAt: Date? = nil
    ) {
        self.sessionId = sessionId
        self.agent = agent
        self.cwd = cwd
        self.title = title
        self.phase = phase
        self.detail = detail
        self.pid = pid
        self.tty = tty
        self.terminalBundleId = terminalBundleId
        self.occurredAt = occurredAt
    }
}

public struct AgentSession: Identifiable, Equatable, Sendable {
    public let id: String
    public var agent: String
    public var cwd: String
    public var title: String
    public var phase: SessionPhase
    public var detail: String?
    public var pid: Int32?
    public var tty: String?
    public var terminalBundleId: String?
    public var updatedAt: Date

    public var projectName: String {
        URL(fileURLWithPath: cwd).lastPathComponent.isEmpty ? cwd : URL(fileURLWithPath: cwd).lastPathComponent
    }

    public init(event: AgentEvent, now: Date = .now) {
        id = event.sessionId
        agent = event.agent
        cwd = event.cwd
        title = event.title?.nilIfBlank ?? URL(fileURLWithPath: event.cwd).lastPathComponent
        phase = event.phase
        detail = event.detail
        pid = event.pid
        tty = event.tty
        terminalBundleId = event.terminalBundleId
        updatedAt = event.occurredAt ?? now
    }

    public mutating func apply(_ event: AgentEvent, now: Date = .now) {
        agent = event.agent
        cwd = event.cwd
        if let title = event.title?.nilIfBlank { self.title = title }
        phase = event.phase
        if let detail = event.detail?.nilIfBlank { self.detail = detail }
        pid = event.pid ?? pid
        tty = event.tty ?? tty
        terminalBundleId = event.terminalBundleId ?? terminalBundleId
        updatedAt = event.occurredAt ?? now
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
