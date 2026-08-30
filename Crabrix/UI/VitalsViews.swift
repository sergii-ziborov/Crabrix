import SwiftUI

/// The compact health + energy readout, for a toolbar or a card header.
struct VitalsPill: View {
    @ObservedObject var store: CrabrixVitalsStore
    var showsCountdown = true
    /// Tapping opens the recovery detail. Off where the pill sits inside a
    /// button that already goes somewhere.
    var isInteractive = false

    @State private var isShowingRates = false

    var body: some View {
        Group {
            if isInteractive {
                Button {
                    store.refresh()
                    isShowingRates = true
                } label: { meters }
                .buttonStyle(.plain)
                .popover(isPresented: $isShowingRates) {
                    VitalsRatesPopover(store: store)
                        .presentationCompactAdaptation(.popover)
                }
            } else {
                meters
            }
        }
    }

    private var meters: some View {
        HStack(spacing: 12) {
            meter(
                systemImage: "heart.fill",
                tint: CrabrixTheme.coral,
                value: store.health,
                maximum: store.capacity.maxHealth,
                seconds: store.secondsToNextHealth
            )
            meter(
                systemImage: "bolt.fill",
                tint: CrabrixTheme.amber,
                value: store.energy,
                maximum: store.capacity.maxEnergy,
                seconds: store.secondsToNextEnergy
            )
        }
        .font(.caption.monospaced().bold())
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(store.health) of \(store.capacity.maxHealth) health, "
                + "\(store.energy) of \(store.capacity.maxEnergy) energy"
        )
        .accessibilityHint(isInteractive ? "Shows how fast they come back" : "")
    }

    private func meter(
        systemImage: String,
        tint: Color,
        value: Int,
        maximum: Int,
        seconds: TimeInterval?
    ) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .foregroundStyle(value > 0 ? tint : CrabrixTheme.muted)
            // One Text, not three: split across views the ratio wraps mid-way
            // down the middle of "30 / 30" on a narrow phone.
            Text("\(value)/\(maximum)")
                .monospacedDigit()
                .foregroundStyle(CrabrixTheme.primary)
                .lineLimit(1)
                .fixedSize()
            if showsCountdown, let seconds {
                Text("· \(VitalsFormatter.countdown(seconds))")
                    .font(.caption2.monospaced())
                    .foregroundStyle(CrabrixTheme.muted)
                    .lineLimit(1)
            }
        }
        .contentTransition(.numericText())
        .animation(.easeOut(duration: 0.2), value: value)
    }
}

/// The full card: both pools, what rank buys, and what to do when empty.
struct VitalsCard: View {
    @ObservedObject var store: CrabrixVitalsStore
    var onOpenTraining: (() -> Void)?

    private enum Meter { case health, energy }
    /// Which bar is showing its recovery detail, if any.
    @State private var expanded: Meter?

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("VITALS", systemImage: "waveform.path.ecg")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(CrabrixTheme.muted)
                Spacer()
                if store.shieldsRemaining > 0 {
                    Label("\(store.shieldsRemaining) shield\(store.shieldsRemaining == 1 ? "" : "s")",
                          systemImage: "shield.lefthalf.filled")
                        .font(.caption2.monospaced().bold())
                        .foregroundStyle(CrabrixTheme.blue)
                }
            }

            Button {
                store.refresh()
                withAnimation(.easeInOut(duration: 0.2)) {
                    expanded = expanded == .health ? nil : .health
                }
            } label: {
                bar(
                    title: "Health",
                    systemImage: "heart.fill",
                    tint: CrabrixTheme.coral,
                    value: store.health,
                    maximum: store.capacity.maxHealth,
                    seconds: store.secondsToNextHealth,
                    caption: "Spent on wrong answers in lessons.",
                    isExpanded: expanded == .health
                )
            }
            .buttonStyle(.plain)

            if expanded == .health {
                detail(
                    tint: CrabrixTheme.coral,
                    value: store.health,
                    maximum: store.capacity.maxHealth,
                    perHour: store.capacity.healthPerHour,
                    seconds: store.secondsToNextHealth,
                    extra: store.shieldsRemaining > 0
                        ? "\(store.shieldsRemaining) shield\(store.shieldsRemaining == 1 ? "" : "s") left today — the next wrong answer costs none."
                        : nil
                )
            }

            Button {
                store.refresh()
                withAnimation(.easeInOut(duration: 0.2)) {
                    expanded = expanded == .energy ? nil : .energy
                }
            } label: {
                bar(
                    title: "Energy",
                    systemImage: "bolt.fill",
                    tint: CrabrixTheme.amber,
                    value: store.energy,
                    maximum: store.capacity.maxEnergy,
                    seconds: store.secondsToNextEnergy,
                    caption: "\(CrabrixVitalsState.energyPerLessonPage) per new lesson page. Re-reading is free.",
                    isExpanded: expanded == .energy
                )
            }
            .buttonStyle(.plain)

            if expanded == .energy {
                detail(
                    tint: CrabrixTheme.amber,
                    value: store.energy,
                    maximum: store.capacity.maxEnergy,
                    perHour: store.capacity.energyPerHour,
                    seconds: store.secondsToNextEnergy,
                    extra: "Training — Quick Practice, Term Train, Code Recall — never costs any."
                )
            }

            if store.isLessonBlocked {
                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        store.isOutOfHealth
                            ? "Lessons are paused while health comes back."
                            : "Lessons are paused while energy comes back.",
                        systemImage: "pause.circle.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CrabrixTheme.amber)
                    // Training never runs out, so there is always a way forward.
                    if let onOpenTraining {
                        Button(action: onOpenTraining) {
                            Label("Train instead — always free", systemImage: "figure.run")
                                .font(.caption.bold())
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(CrabrixTheme.mint)
                    }
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CrabrixTheme.amber.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            } else {
                Text("Rank \(CrabrixRank.rank(for: store.points).title) — refills "
                     + "\(Int(store.capacity.healthPerHour.rounded())) health and "
                     + "\(Int(store.capacity.energyPerHour.rounded())) energy an hour.")
                    .font(.caption2)
                    .foregroundStyle(CrabrixTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .crabrixPanel(cornerRadius: 16)
    }

    private func bar(
        title: String,
        systemImage: String,
        tint: Color,
        value: Int,
        maximum: Int,
        seconds: TimeInterval?,
        caption: String,
        isExpanded: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: systemImage).foregroundStyle(tint)
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(CrabrixTheme.primary)
                Spacer(minLength: 0)
                Text("\(value)/\(maximum)")
                    .font(.caption.monospaced().bold())
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(CrabrixTheme.primary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(CrabrixTheme.muted)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(CrabrixTheme.border)
                    Capsule()
                        .fill(tint)
                        .frame(
                            width: maximum > 0
                                ? geometry.size.width * min(1, Double(value) / Double(maximum))
                                : 0
                        )
                }
            }
            .frame(height: 7)
            .animation(.easeOut(duration: 0.25), value: value)

            HStack(spacing: 5) {
                Text(caption)
                if let seconds {
                    Text("· next in \(VitalsFormatter.countdown(seconds))")
                        .foregroundStyle(tint.opacity(0.9))
                }
            }
            .font(.caption2)
            .foregroundStyle(CrabrixTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
        }
        .contentShape(Rectangle())
    }

    /// The recovery numbers: how fast, when the next point lands, when full.
    private func detail(
        tint: Color,
        value: Int,
        maximum: Int,
        perHour: Double,
        seconds: TimeInterval?,
        extra: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            row("Refills", "+\(VitalsFormatter.rate(perHour)) an hour", tint: tint)
            row("One point every", VitalsFormatter.countdown(3_600 / max(perHour, 0.01)), tint: tint)
            if let seconds {
                row("Next point in", VitalsFormatter.countdown(seconds), tint: tint)
                let missing = Double(maximum - value)
                row("Full in", VitalsFormatter.countdown(missing / max(perHour, 0.01) * 3_600), tint: tint)
            } else {
                row("Status", "Full", tint: CrabrixTheme.mint)
            }
            if let extra {
                Text(extra)
                    .font(.caption2)
                    .foregroundStyle(CrabrixTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func row(_ label: String, _ value: String, tint: Color) -> some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundStyle(CrabrixTheme.muted)
            Spacer(minLength: 0)
            Text(value)
                .font(.caption2.monospaced().bold())
                .foregroundStyle(tint)
        }
    }
}

/// A short line explaining what the last action cost, shown after an answer.
struct VitalsOutcomeBadge: View {
    let outcome: VitalsOutcome

    var body: some View {
        if let described {
            Label(described.text, systemImage: described.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(described.tint)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var described: (text: String, icon: String, tint: Color)? {
        switch outcome {
        case .free:
            nil
        case let .spent(energy):
            ("−\(energy) energy", "bolt.fill", CrabrixTheme.amber)
        case let .damaged(health):
            ("−\(health) health", "heart.slash.fill", CrabrixTheme.coral)
        case .shielded:
            ("Shield absorbed that one", "shield.lefthalf.filled", CrabrixTheme.blue)
        case let .refunded(energy):
            ("+\(energy) energy — nice run", "bolt.badge.checkmark", CrabrixTheme.mint)
        case let .recovered(health, energy):
            (
                "+\(health) health" + (energy > 0 ? " · +\(energy) energy" : ""),
                "heart.circle.fill",
                CrabrixTheme.mint
            )
        case .blocked:
            ("Out of vitals — training is still open", "pause.circle.fill", CrabrixTheme.muted)
        }
    }
}

/// Shown in place of a lesson while health or energy is recovering.
///
/// It never dead-ends: training costs nothing and is one tap away, so there is
/// always something to do while the pool refills.
struct LessonPausedView: View {
    @ObservedObject var store: CrabrixVitalsStore
    let onTrain: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: store.isOutOfHealth ? "heart.slash.fill" : "bolt.slash.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(store.isOutOfHealth ? CrabrixTheme.coral : CrabrixTheme.amber)
                    .padding(.top, 40)

                VStack(spacing: 8) {
                    Text(store.isOutOfHealth ? "Out of health" : "Out of energy")
                        .font(.title.bold())
                    Text(
                        store.isOutOfHealth
                            ? "Wrong answers in lessons cost health. It comes back on its own — and faster at a higher rank."
                            : "New lesson pages cost energy. It comes back on its own — and faster at a higher rank."
                    )
                    .font(.subheadline)
                    .foregroundStyle(CrabrixTheme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                }

                if let seconds = store.isOutOfHealth ? store.secondsToNextHealth : store.secondsToNextEnergy {
                    Label("Next point in \(VitalsFormatter.countdown(seconds))", systemImage: "clock.fill")
                        .font(.headline.monospaced())
                        .foregroundStyle(CrabrixTheme.blue)
                }

                VitalsCard(store: store)

                Button(action: onTrain) {
                    Label("Train instead — always free", systemImage: "figure.run")
                        .frame(maxWidth: .infinity)
                }
                .font(.headline)
                .buttonStyle(.borderedProminent)
                .tint(CrabrixTheme.mint)

                Text("Term Train and Quick Practice never cost health or energy.")
                    .font(.caption)
                    .foregroundStyle(CrabrixTheme.muted)
            }
            .padding(24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(CrabrixTheme.background.ignoresSafeArea())
        .foregroundStyle(CrabrixTheme.primary)
        .navigationTitle("Recovering")
        .navigationBarTitleDisplayMode(.inline)
        .task { store.refresh() }
    }
}


/// How fast the pools refill, and what the next point costs in time.
struct VitalsRatesPopover: View {
    @ObservedObject var store: CrabrixVitalsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("RECOVERY")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(CrabrixTheme.muted)

            rate(
                title: "Health",
                systemImage: "heart.fill",
                tint: CrabrixTheme.coral,
                value: store.health,
                maximum: store.capacity.maxHealth,
                perHour: store.capacity.healthPerHour,
                seconds: store.secondsToNextHealth
            )

            rate(
                title: "Energy",
                systemImage: "bolt.fill",
                tint: CrabrixTheme.amber,
                value: store.energy,
                maximum: store.capacity.maxEnergy,
                perHour: store.capacity.energyPerHour,
                seconds: store.secondsToNextEnergy
            )

            Divider().overlay(CrabrixTheme.border)

            Label(
                "Rank \(CrabrixRank.rank(for: store.points).title) — a higher rank means a bigger pool and a faster refill.",
                systemImage: "crown.fill"
            )
            .font(.caption2)
            .foregroundStyle(CrabrixTheme.muted)
            .fixedSize(horizontal: false, vertical: true)

            if store.shieldsRemaining > 0 {
                Label(
                    "\(store.shieldsRemaining) shield\(store.shieldsRemaining == 1 ? "" : "s") left today — the next wrong answer costs no health.",
                    systemImage: "shield.lefthalf.filled"
                )
                .font(.caption2)
                .foregroundStyle(CrabrixTheme.blue)
                .fixedSize(horizontal: false, vertical: true)
            }

            Label("Training never costs either.", systemImage: "infinity")
                .font(.caption2)
                .foregroundStyle(CrabrixTheme.mint)
        }
        .padding(16)
        .frame(width: 280)
        .background(CrabrixTheme.panel)
        .foregroundStyle(CrabrixTheme.primary)
        .task { store.refresh() }
    }

    private func rate(
        title: String,
        systemImage: String,
        tint: Color,
        value: Int,
        maximum: Int,
        perHour: Double,
        seconds: TimeInterval?
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).foregroundStyle(tint)
                Text(title).font(.subheadline.bold())
                Spacer(minLength: 0)
                Text("\(value)/\(maximum)")
                    .font(.caption.monospaced().bold())
                    .monospacedDigit()
            }
            Text("+\(VitalsFormatter.rate(perHour)) an hour · one every \(VitalsFormatter.countdown(3_600 / max(perHour, 0.01)))")
                .font(.caption2)
                .foregroundStyle(CrabrixTheme.muted)
            if let seconds {
                Text("Next in \(VitalsFormatter.countdown(seconds))")
                    .font(.caption2.bold())
                    .foregroundStyle(tint)
            } else {
                Text("Full")
                    .font(.caption2.bold())
                    .foregroundStyle(CrabrixTheme.mint)
            }
        }
    }

}
