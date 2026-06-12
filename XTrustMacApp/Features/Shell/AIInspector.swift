import AppCore
import SwiftUI

// MARK: - AI Inspector Panel (384px, collapsible)

struct AIInspector: View {
    let minutes: MeetingMinutes?
    let isGeneratingMinutes: Bool
    let isVisible: Bool
    let onToggle: () -> Void
    let onRetryMinutes: () -> Void

    @State private var selectedTab: InspectorTab = .summary

    enum InspectorTab: String, CaseIterable {
        case summary  = "要約"
        case decisions = "決定"
        case actions   = "アクション"
        case risks     = "リスク"
        case knowledge = "ナレッジ"

        var badge: String? {
            switch self {
            case .decisions: return "3"
            case .actions:   return "5"
            case .risks:     return "4"
            default:         return nil
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Collapse toggle affordance
            Divider()

            if isVisible {
                VStack(spacing: 0) {
                    inspectorHeader
                    tabBar
                    Divider().background(XT.C.line)
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            tabContent
                                .padding(.horizontal, 14)
                                .padding(.top, 12)
                                .padding(.bottom, 16)
                        }
                    }
                    inspectorFooter
                }
                .frame(width: XT.Layout.inspectorWidth)
                .background(XT.C.winBg)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    )
                )
            }
        }
    }

    // MARK: - Header

    private var inspectorHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                // Dark box with spark icon
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color(hex: "#131A2E"))
                        .frame(width: 28, height: 28)
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("AI インサイト")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(XT.C.ink)
                    HStack(spacing: 4) {
                        PulseDot(color: XT.C.ok, size: 5)
                        Text("XTRUST · リアルタイム解析中 · ローカル")
                            .font(.system(size: 10.5))
                            .foregroundStyle(XT.C.ink3)
                    }
                }
                Spacer()
                Button(action: onToggle) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(XT.C.ink3)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(XT.C.panel)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(XT.C.winBg)
            Divider().background(XT.C.line)
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(InspectorTab.allCases, id: \.self) { tab in
                Button(action: { selectedTab = tab }) {
                    VStack(spacing: 4) {
                        HStack(spacing: 3) {
                            Text(tab.rawValue)
                                .font(.system(size: 12.5, weight: selectedTab == tab ? .bold : .regular))
                                .foregroundStyle(selectedTab == tab ? XT.C.ink : XT.C.ink3)
                            if let badge = tab.badge {
                                Text(badge)
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundStyle(selectedTab == tab ? XT.C.accentIndigo : XT.C.ink4)
                                    .padding(.horizontal, 3.5)
                                    .padding(.vertical, 1)
                                    .background(
                                        Capsule()
                                            .fill(selectedTab == tab ? XT.C.accentSoft : XT.C.panel)
                                    )
                            }
                        }
                        // Active underline
                        Rectangle()
                            .fill(selectedTab == tab ? XT.C.ink : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .background(XT.C.winBg)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .summary:
            summaryContent
        case .decisions:
            decisionsContent
        case .actions:
            actionsContent
        case .risks:
            risksContent
        case .knowledge:
            knowledgeContent
        }
    }

    // MARK: - Summary Tab (real minutes data)

    private var summaryContent: some View {
        VStack(spacing: 12) {
            inspectorCard(accentColor: XT.C.accentIndigo) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("会議要約")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(XT.C.ink)
                        Spacer()
                        if isGeneratingMinutes || minutes?.status == .pending || minutes?.status == .running {
                            HStack(spacing: 4) {
                                ProgressView().controlSize(.mini)
                                Text("生成中…")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(XT.C.ink3)
                            }
                        } else if let minutes = minutes, minutes.status == .completed {
                            Text("updated \(minutesUpdateTime(minutes))")
                                .font(.system(size: 10))
                                .foregroundStyle(XT.C.ink4)
                        }
                    }
                    Divider().background(XT.C.line)
                    summaryBody
                    Divider().background(XT.C.line)
                    // Footer row
                    HStack(spacing: 10) {
                        HStack(spacing: 3) {
                            Image(systemName: "cpu")
                                .font(.system(size: 10))
                                .foregroundStyle(XT.C.ok)
                            Text("on-device")
                                .font(.system(size: 10))
                                .foregroundStyle(XT.C.ink4)
                        }
                        if let minutes = minutes, let model = minutes.modelIdentifier {
                            Text("·")
                                .foregroundStyle(XT.C.ink4)
                            Text(model)
                                .font(.system(size: 10))
                                .foregroundStyle(XT.C.ink4)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button(action: { retryOrCopy() }) {
                            Image(systemName: minutes?.status == .completed ? "doc.on.doc" : "arrow.clockwise")
                                .font(.system(size: 11))
                                .foregroundStyle(XT.C.ink3)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
        }
    }

    @ViewBuilder
    private var summaryBody: some View {
        if isGeneratingMinutes || minutes?.status == .pending || minutes?.status == .running {
            VStack(alignment: .leading, spacing: 6) {
                Text("議事録を生成中…")
                    .font(.system(size: 12.5))
                    .foregroundStyle(XT.C.ink3)
                Text("ローカル LLM が文字起こしから要約を作成しています。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(XT.C.ink4)
            }
        } else if let minutes = minutes, minutes.status == .completed, let text = minutes.markdownText {
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(XT.C.ink)
                .lineSpacing(4)
                .textSelection(.enabled)
        } else if let minutes = minutes, minutes.status == .failed {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundStyle(XT.C.live)
                    Text("生成に失敗しました")
                        .font(.system(size: 12))
                        .foregroundStyle(XT.C.live)
                }
                if let err = minutes.errorMessage {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundStyle(XT.C.ink4)
                }
                Button("再試行", action: onRetryMinutes)
                    .font(.system(size: 12))
                    .buttonStyle(.plain)
                    .foregroundStyle(XT.C.accentIndigo)
            }
        } else {
            Text("会議を終了すると要約が自動生成されます。")
                .font(.system(size: 12.5))
                .foregroundStyle(XT.C.ink4)
                .italic()
        }
    }

    // MARK: - Decisions Tab (placeholder)

    private var decisionsContent: some View {
        VStack(spacing: 12) {
            inspectorCard(accentColor: XT.C.accentIndigo) {
                VStack(alignment: .leading, spacing: 0) {
                    cardSectionHeader(title: "意思決定", count: 3)
                    Divider().background(XT.C.line)
                    VStack(spacing: 0) {
                        decisionRow(
                            text: "次回DDで情報管理体制および内部統制を追加確認する",
                            person: "山田 有紀", date: "5/22 (金)"
                        )
                        Divider().background(XT.C.line2).padding(.leading, 12)
                        decisionRow(
                            text: "PMI 初期100日プランの素案を3ワークストリームで作成",
                            person: "Priya Nair", date: "5/24 (日)"
                        )
                        Divider().background(XT.C.line2).padding(.leading, 12)
                        decisionRow(
                            text: "CFO 候補のサーチを早期着手で開始",
                            person: "鈴木 恒一", date: "今週中"
                        )
                    }
                }
            }
        }
    }

    private func decisionRow(text: String, person: String, date: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(XT.C.ink)
                .lineSpacing(2)
            HStack(spacing: 6) {
                Text(person)
                    .font(.system(size: 11))
                    .foregroundStyle(XT.C.ink3)
                Text("·")
                    .foregroundStyle(XT.C.ink4)
                Text(date)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(XT.C.ink3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Actions Tab (placeholder)

    private var actionsContent: some View {
        VStack(spacing: 12) {
            inspectorCard(accentColor: XT.C.ok) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        cardSectionHeader(title: "アクションアイテム", count: 5)
                        Spacer()
                        Button("Notionに送る") {}
                            .font(.system(size: 11))
                            .buttonStyle(.plain)
                            .foregroundStyle(XT.C.accentIndigo)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                    Divider().background(XT.C.line)
                    VStack(spacing: 0) {
                        actionRow(person: "佐藤 美咲", task: "財務論点の整理（IRR感応度・KPI再定義）", due: "5/20")
                        Divider().background(XT.C.line2).padding(.leading, 12)
                        actionRow(person: "Priya Nair", task: "PMIリスクと100日プラン素案のドラフト", due: "5/24")
                        Divider().background(XT.C.line2).padding(.leading, 12)
                        actionRow(person: "Michael Chen", task: "既存株主2名との対話・SO設計の確認", due: "5/23")
                        Divider().background(XT.C.line2).padding(.leading, 12)
                        actionRow(person: "山田 有紀", task: "内部統制 / 第三者アクセス権限のレビュー", due: "5/22")
                        Divider().background(XT.C.line2).padding(.leading, 12)
                        actionRow(person: "高橋 直人", task: "主要人材依存のシナリオ分析（CTO / VP Eng）", due: "5/24")
                    }
                }
            }
        }
    }

    private func actionRow(person: String, task: String, due: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "square")
                .font(.system(size: 12))
                .foregroundStyle(XT.C.ink3)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(task)
                    .font(.system(size: 12.5))
                    .foregroundStyle(XT.C.ink)
                    .lineSpacing(2)
                HStack(spacing: 6) {
                    Text(person)
                        .font(.system(size: 11))
                        .foregroundStyle(XT.C.ink3)
                    Text("·")
                        .foregroundStyle(XT.C.ink4)
                    Text("期限 \(due)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(XT.C.ink3)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    // MARK: - Risks Tab (placeholder)

    private var risksContent: some View {
        VStack(spacing: 12) {
            inspectorCard(accentColor: XT.C.live) {
                VStack(alignment: .leading, spacing: 0) {
                    cardSectionHeader(title: "リスク項目", count: 4)
                    Divider().background(XT.C.line)
                    VStack(spacing: 0) {
                        riskRow(level: .high, text: "内部統制・情報管理体制")
                        Divider().background(XT.C.line2).padding(.leading, 12)
                        riskRow(level: .medium, text: "オペレーション統合負荷")
                        Divider().background(XT.C.line2).padding(.leading, 12)
                        riskRow(level: .medium, text: "主要人材依存")
                        Divider().background(XT.C.line2).padding(.leading, 12)
                        riskRow(level: .low, text: "上位顧客集中度（Top10 = 31%）")
                    }
                }
            }
        }
    }

    enum RiskLevel { case high, medium, low }

    private func riskRow(level: RiskLevel, text: String) -> some View {
        HStack(spacing: 8) {
            riskBar(level: level)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(XT.C.ink)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func riskBar(level: RiskLevel) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<3) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(barColor(level: level, index: i))
                    .frame(width: 4, height: 14)
            }
        }
    }

    private func barColor(level: RiskLevel, index: Int) -> Color {
        switch level {
        case .high:   return index < 3 ? XT.C.live : XT.C.line
        case .medium: return index < 2 ? XT.C.warn2 : XT.C.line
        case .low:    return index < 1 ? XT.C.ok : XT.C.line
        }
    }

    // MARK: - Knowledge Tab (placeholder)

    private var knowledgeContent: some View {
        VStack(spacing: 12) {
            // Keywords card
            inspectorCard(accentColor: XT.C.accentIndigo) {
                VStack(alignment: .leading, spacing: 10) {
                    cardSectionHeader(title: "キーワード", count: nil)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                    Divider().background(XT.C.line)
                    keywordsFlow
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                }
            }

            // Knowledge links card
            inspectorCard(accentColor: XT.C.accentIndigo) {
                VStack(alignment: .leading, spacing: 0) {
                    cardSectionHeader(title: "関連ナレッジ", count: 4)
                    Divider().background(XT.C.line)
                    VStack(spacing: 0) {
                        knowledgeRow(icon: "doc.text", title: "C社 PMI 100日 振り返り", date: "2025-09-18")
                        Divider().background(XT.C.line2).padding(.leading, 12)
                        knowledgeRow(icon: "book.closed", title: "PMI Playbook v2.3", date: nil)
                        Divider().background(XT.C.line2).padding(.leading, 12)
                        knowledgeRow(icon: "doc.richtext", title: "A社_DDレポート_v3.pdf", date: "12.4MB")
                        Divider().background(XT.C.line2).padding(.leading, 12)
                        knowledgeRow(icon: "person.2", title: "A社 経営陣ヒアリング 第2回", date: nil)
                    }
                }
            }
        }
    }

    private var keywordsFlow: some View {
        let topKeywords = ["PMI 100日", "内部統制", "NRR 118%"]
        let otherKeywords = ["ARR 14.2億", "CFOサーチ", "主要人材依存", "IRR 27.4%",
                             "SO設計", "ロックアップ", "営業 / CS統合"]
        return FlowLayout(spacing: 5) {
            ForEach(topKeywords, id: \.self) { kw in
                keywordChip(kw, isTop: true)
            }
            ForEach(otherKeywords, id: \.self) { kw in
                keywordChip(kw, isTop: false)
            }
        }
    }

    private func keywordChip(_ text: String, isTop: Bool) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(isTop ? XT.C.accentInk : XT.C.ink3)
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isTop ? XT.C.accentSoft : XT.C.panel)
            )
    }

    private func knowledgeRow(icon: String, title: String, date: String?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(XT.C.ink3)
                .frame(width: 16)
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(XT.C.ink)
                .lineLimit(1)
            Spacer()
            if let date = date {
                Text(date)
                    .font(.system(size: 10))
                    .foregroundStyle(XT.C.ink4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Inspector Footer

    private var inspectorFooter: some View {
        HStack(spacing: 8) {
            Image(systemName: "cpu")
                .font(.system(size: 11))
                .foregroundStyle(XT.C.navTextDim)
            VStack(alignment: .leading, spacing: 1) {
                Text("XTRUST Local LLM")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(XT.C.navText)
                Text("All processing on this device · Gemma 4 E4B · on-device")
                    .font(.system(size: 10))
                    .foregroundStyle(XT.C.navTextMute)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(hex: "#131A2E"))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(XT.C.winBg)
    }

    // MARK: - Helpers

    private func inspectorCard<Content: View>(
        accentColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(XT.C.line, lineWidth: 0.5)
        )
        .overlay(
            HStack {
                RoundedRectangle(cornerRadius: 2)
                    .fill(accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 2)
                Spacer()
            }
        )
        .shadow(color: .black.opacity(0.03), radius: 3, x: 0, y: 1)
    }

    private func cardSectionHeader(title: String, count: Int?) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(XT.C.ink)
            if let count = count {
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(XT.C.ink4)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(XT.C.panel))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private func minutesUpdateTime(_ minutes: MeetingMinutes) -> String {
        let f = DateFormatter()
        f.dateFormat = "H:mm"
        return f.string(from: minutes.completedAt ?? minutes.createdAt)
    }

    private func retryOrCopy() {
        if minutes?.status == .completed {
            if let text = minutes?.markdownText {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        } else {
            onRetryMinutes()
        }
    }
}

// MARK: - Simple flow layout for keywords

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
