import SwiftUI

/// One session in the expanded list: agent identity, live activity, task progress, and —
/// when the agent needs the user — an inline permission or question card.
struct SessionRow: View {
    let session: AgentSession
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            identity
            if settings.showTasks, !session.tasks.isEmpty {
                TaskListView(tasks: session.tasks)
            }
            if settings.showSubAgents, !session.subAgents.isEmpty {
                SubAgentListView(subAgents: session.subAgents)
            }
            if let permission = session.permission {
                PermissionCard(session: session, request: permission)
            }
            if let question = session.question {
                // Key by the question so a superseding prompt resets the card's
                // selection/other-text state instead of carrying stale choices over.
                QuestionCard(session: session, question: question)
                    .id(question)
            }
            if let plan = session.plan {
                // Key by the plan so a superseding plan clears any typed feedback.
                PlanReviewCard(session: session, plan: plan)
                    .id(plan)
            }
            // A send started from a card here has no input bar to report under, so the
            // failure lands on the card itself.
            if let err = store.sendError(for: session.id) {
                SendErrorNotice(message: err.message,
                                showsAccessibilityButton: err.needsAccessibility)
            }
        }
        .padding(Theme.Space.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .fill(needsAttention ? session.status.color.opacity(0.06) : Theme.Fill.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .stroke(borderColor, lineWidth: needsAttention ? 1 : 0.5)
        )
    }

    private var needsAttention: Bool {
        session.status == .waiting || session.status == .asking || session.status == .planning
    }

    private var borderColor: Color {
        needsAttention ? session.status.color.opacity(0.5) : Theme.Fill.hairline
    }

    // MARK: - Identity block (tappable — opens the live chat)

    private var identity: some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            // Local: Herdr-style status dot instead of the agent badge.
            HerdrDot(status: session.status, size: 10)
                .frame(width: 14, height: 18)
            VStack(alignment: .leading, spacing: 5) {
                // Title + agent tag + elapsed, mirroring a native message header.
                HStack(spacing: Theme.Space.sm) {
                    Text(session.title)
                        .font(Theme.Font.title(12.5))
                        .foregroundStyle(Theme.Ink.primary)
                        .lineLimit(1)
                    Spacer(minLength: Theme.Space.sm)
                    AgentTag(agent: session.agent)
                    if store.demoMode {
                        Text("DEMO")
                            .font(Theme.Font.label(8, weight: .bold))
                            .foregroundStyle(Theme.Ink.tertiary)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Capsule().fill(Color.white.opacity(0.1)))
                    }
                    Text(session.elapsedText)
                        .font(Theme.Font.label(9.5, weight: .regular))
                        .foregroundStyle(Theme.Ink.faint)
                    if session.status == .done {
                        ArchiveButton { store.archive(id: session.id) }
                    }
                }
                Text(ChatMessageView.chatMarkdown(session.lastMessage))
                    .font(Theme.Font.prose(11))
                    .foregroundStyle(Theme.Ink.secondary)
                    .lineLimit(1)
                // Status + terminal + token meter, the calm bottom line.
                HStack(spacing: Theme.Space.sm) {
                    StatusPill(status: session.status)
                    if settings.showModel, let model = session.model {
                        Text(model)
                            .font(Theme.Font.label(9.5, weight: .medium))
                            // Neutral: the badge and the name tag already carry the agent's
                            // hue, so a third tinted item on this line buys nothing but noise.
                            .foregroundStyle(Theme.Ink.secondary)
                            .lineLimit(1)
                    }
                    if settings.showTerminal {
                        Text(session.terminal)
                            .font(Theme.Font.label(9.5, weight: .regular))
                            .foregroundStyle(Theme.Ink.tertiary)
                    }
                    if settings.showTokens, let tok = session.tokenText {
                        HStack(spacing: 3) {
                            Image(systemName: "circle.hexagongrid.fill").font(.system(size: 7))
                            Text(tok)
                        }
                        .font(Theme.Font.label(9.5, weight: .regular))
                        .foregroundStyle(Theme.Ink.faint)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Honor the click-to-jump preference: when off, the card is inert so a stray
            // click never opens the conversation or pulls focus.
            guard settings.clickToJump else { return }
            store.openChat(session)
        }
    }
}

/// A small dismiss control shown on finished rows — archives the session out of the island
/// without waiting for it to age out. Its own tap is handled here so it doesn't fall through
/// to the row's open-chat gesture.
private struct ArchiveButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "archivebox")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.Ink.tertiary)
                .padding(3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Dismiss this session")
    }
}

/// The compact agent mark — a tinted rounded tile with the agent's glyph.
struct AgentBadge: View {
    let agent: AgentKind
    var size: CGFloat = 28
    var body: some View {
        Text(agent.glyph)
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(agent.glyphTint)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.3)
                    .fill(agent.tint.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.3)
                    .stroke(agent.tint.opacity(0.35), lineWidth: 0.5)
            )
    }
}

/// The agent-name pill (e.g. "Claude"), tinted to the agent's accent — the competitor's
/// most recognizable identity cue.
struct AgentTag: View {
    let agent: AgentKind
    var body: some View {
        Text(agent.displayName)
            .font(Theme.Font.label(9, weight: .semibold))
            .foregroundStyle(agent.glyphTint)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(agent.glyphTint.opacity(0.16)))
            .fixedSize()
    }
}

struct StatusPill: View {
    let status: SessionStatus
    var body: some View {
        HStack(spacing: 4) {
            StatusDot(status: status)
            Text(status.label)
                .font(Theme.Font.label(9, weight: .semibold))
                .foregroundStyle(status.color)
        }
        .padding(.trailing, 2)
    }
}

/// Local: Herdr-style status dot — orange = working, filled green = done and not yet read,
/// hollow green = read (idle), red = waiting on a permission/question/plan.
struct HerdrDot: View {
    let status: SessionStatus
    var size: CGFloat = 6
    /// Crisp ring drawn around the dot, like the outline of the battery icon in the menu bar.
    var outline: Color? = nil

    static let working = Color(red: 0.98, green: 0.66, blue: 0.26)
    static let done = Color(red: 0.36, green: 0.83, blue: 0.55)
    static let blocked = Color(red: 0.98, green: 0.40, blue: 0.38)

    var body: some View {
        ZStack {
            switch status {
            case .idle:
                Circle().strokeBorder(Self.done, lineWidth: max(1.5, size * 0.22))
                    .padding(outline == nil ? 0 : 1)
            case .done:
                Circle().fill(Self.done)
            case .working:
                Circle().fill(Self.working)
            case .waiting, .asking, .planning:
                Circle().fill(Self.blocked)
            }
            if let outline {
                Circle().strokeBorder(outline, lineWidth: 1)
            }
        }
        .frame(width: size, height: size)
    }

    /// Order for the row beside the notch: read first (far left), attention nearest the notch.
    static func rank(_ status: SessionStatus) -> Int {
        switch status {
        case .idle: return 0
        case .done: return 1
        case .working: return 2
        case .waiting, .asking, .planning: return 3
        }
    }
}

/// Local: the at-a-glance row of dots shown beside the notch while the island is collapsed.
struct NotchDots: View {
    let sessions: [AgentSession]

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // Everything that wants attention (working, unread done, blocked) gets its own dot.
        // Read sessions show as a single hollow dot, and only when nothing else is there.
        let active = sessions.filter { $0.status != .idle }
            .sorted { HerdrDot.rank($0.status) < HerdrDot.rank($1.status) }
        // Menu-bar ink: black on a light bar, white on a dark one — like the native items.
        let ink = scheme == .dark ? Color.white.opacity(0.9) : Color.black.opacity(0.85)
        HStack(spacing: 6) {
            if active.isEmpty, sessions.contains(where: { $0.status == .idle }) {
                HerdrDot(status: .idle, size: 13, outline: ink)
            }
            ForEach(active.suffix(14)) { s in
                HerdrDot(status: s.status, size: 13, outline: ink)
            }
        }
        .allowsHitTesting(false)
    }
}
