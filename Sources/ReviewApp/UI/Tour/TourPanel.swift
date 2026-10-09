import SwiftUI

/// The setup tour's coach panel, over the foot of the stage: first-run
/// V3's coach panel as connect-flow V6 draws it
/// (`docs/prototypes/2026-10-08-lab/agent-onboarding/`). Its dots and "Step
/// N of 5", the step's title and words, and its buttons: Skip Tour, Next or
/// Later, Write an Example, Finish. The close button keeps the step. Each
/// step rings the part of the window it is about (`WindowModel.tourRings`).
struct TourPanel: View {
    let model: WindowModel
    @Environment(\.palette) private var palette

    /// How wide the panel is.
    static let width: CGFloat = 380

    private var setup: SetupDesk { model.app.setup }
    private var step: TourStep { model.tour.step }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(TourStep.allCases, id: \.self) { each in
                    Capsule()
                        .fill(each.number < step.number ? palette[.stateDone] : each == step ? palette[.accent] : palette[.track])
                        .frame(width: each == step ? 18 : 7, height: 7)
                }
                Text("Step \(step.number) of \(TourStep.allCases.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(palette[.textSecondary])
                    .padding(.leading, 4)
                Spacer()
                Button {
                    _ = try? model.closeTour()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(palette[.textTertiary])
                        .frame(width: 18, height: 18)
                        .background(palette[.controlHover], in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Close the tour. It keeps your place.")
                .accessibilityLabel("Close the tour")
            }
            .accessibilityElement(children: .contain)
            Text(model.tourTitle)
                .font(.headline)
                .foregroundStyle(palette[.textPrimary])
            content
        }
        .padding(14)
        .frame(width: Self.width, alignment: .topLeading)
        .background {
            // The theme's popover surface, so the panel reads over any frame.
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette[.popover])
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette[.accent].opacity(0.06))
        }
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(palette[.accent].opacity(0.35), lineWidth: 1))
        .shadow(color: palette[.shadow], radius: 16, y: 6)
        .animation(.smooth(duration: 0.25), value: step)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Setup tour, step \(step.number) of \(TourStep.allCases.count)")
        // Both tools turned detected: the tools step moves on a moment
        // later, so the two checks show first. Tools detected before the
        // tour opened leave Next to the person.
        .onChange(of: setup.isDetected) { _, detected in
            guard detected, step == .tools else { return }
            Task {
                try? await Task.sleep(for: .seconds(0.8))
                model.tourNoticedSetup()
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .tools:
            para(Text("Link the \(code("havooch")) command line and install the \(code("/havooch-mate")) skill. Both are in the sidebar, in the ring."))
            HStack(spacing: 14) {
                check(setup.isLinked, CodeLabel.commandLine)
                check(setup.isSkillDetected, CodeLabel.skill)
            }
            HStack { skip; Spacer(); next(setup.isDetected ? "Next" : "Later") }
        case .connect:
            let connected = model.isAgentConnected
            para(Text("Pick your agent and copy the prompt. Paste it in your agent's session. Havooch shows it here once it listens."))
            check(connected, Text(connected ? "\(model.tourAgentName) is listening" : "No agent is listening yet"))
            HStack { skip; Spacer(); next(connected ? "Next" : "Later") }
        case .write:
            para(Text("Pause the video, or drag a box on the frame, then write in the field under the threads. Return queues it."))
            HStack {
                skip
                Spacer()
                Button("Write an Example") { model.writeTourExample() }
                    .controlSize(.small)
                    .help("Put an example in the composer")
                next("Next")
            }
        case .send:
            para(Text(model.isAgentConnected
                ? "Press ⌘↩ or click Send: every queued message goes to \(model.tourAgentName) at once, with the frame, the box and the transcript."
                : "No agent listens yet. Send anyway: the messages wait in the outbox and go out when one connects."))
            HStack { skip; Spacer() }
        case .reply:
            if model.tourReplied {
                para(Text("It worked in its repo with its own skills and answered on each thread. Open a thread to reply."))
                HStack {
                    Spacer()
                    Button("Finish") { _ = try? model.nextTourStep() }
                        .filledButton(palette)
                        .controlSize(.small)
                }
            } else if model.isTourSendWaiting {
                para(Text("Nothing is lost. Connect an agent in the sidebar and they go out at once."))
                HStack { skip; Spacer() }
            } else {
                para(Text("It got the batch and works in its repo. Each thread turns Done when it answers."))
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Working…").font(.callout).foregroundStyle(palette[.textSecondary])
                    Spacer()
                    skip
                }
            }
        }
    }

    /// A code name in the panel's words, in monospace.
    private func code(_ name: String) -> AttributedString {
        var text = AttributedString(name)
        text.font = .callout.monospaced()
        return text
    }

    private func para(_ text: Text) -> some View {
        text
            .font(.callout)
            .foregroundStyle(palette[.textSecondary])
            .fixedSize(horizontal: false, vertical: true)
    }

    private func check(_ done: Bool, _ label: some View) -> some View {
        HStack(spacing: 6) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(done ? palette[.stateDone] : palette[.textTertiary])
                .accessibilityLabel(done ? "Done" : "Not done")
            label
                .font(.callout.weight(.medium))
                .foregroundStyle(done ? palette[.textPrimary] : palette[.textSecondary])
        }
        .accessibilityElement(children: .combine)
    }

    private func next(_ title: String) -> some View {
        Button(title) { _ = try? model.nextTourStep() }
            .controlSize(.small)
    }

    private var skip: some View {
        Button("Skip Tour") { _ = try? model.skipTour() }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundStyle(palette[.textSecondary])
    }
}
