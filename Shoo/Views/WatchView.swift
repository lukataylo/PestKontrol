import SwiftUI
import SwiftData

struct WatchView: View {
    @Environment(Sentry.self) private var sentry
    @Query(sort: \Sighting.date, order: .reverse) private var sightings: [Sighting]

    var body: some View {
        VStack(spacing: 12) {
            header
            BotPanel(status: sentry.status, armed: sentry.armed, volumeLow: sentry.volumeLow, gaze: gaze)
            Viewport()
            controls
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// Where the bot should look: the detection box, mapped to -1…1.
    private var gaze: Double? {
        let f = sentry.frame
        guard let box = f.box,
              f.confidence >= Float(sentry.settings.tuning.threshold) * 0.6 || f.guardedConfidence >= 0.3
        else { return nil }
        return Double(box.midX - 0.5) * 2
    }

    private var header: some View {
        HStack(alignment: Theme.slasher ? .top : .center, spacing: 8) {
            ScreenTitle(text: "SHOO")
                .padding(.leading, Theme.slasher ? -8 : 0)
            if !Theme.slasher { PulseDot(active: sentry.armed) }
            Spacer()
            TimelineView(.periodic(from: .now, by: 10)) { ctx in
                HStack(spacing: 12) {
                    Text(Fmt.clock.string(from: ctx.date))
                    Text(battery)
                }
                .font(Theme.mono(12, .medium))
                .foregroundStyle(Theme.dim)
            }
        }
    }

    private var battery: String {
        let device = UIDevice.current
        guard device.batteryLevel >= 0 else { return "--%" }
        let pct = "\(Int(device.batteryLevel * 100))%"
        return device.batteryState == .charging || device.batteryState == .full ? "+" + pct : pct
    }

    private var controls: some View {
        let today = sightings.filter { Calendar.current.isDateInToday($0.date) }
        let fired = today.filter { $0.outcome == .fired }.count

        return HStack(spacing: 12) {
            HStack(spacing: 16) {
                stat(Glyphs.eye, today.count, "visits today")
                stat(Glyphs.speaker, fired, "deterred today")
            }
            Spacer()
            DotIconButton(icon: Glyphs.bulb, label: sentry.torch ? "Lamp off" : "Lamp on",
                          fill: sentry.torch ? Theme.ink : Theme.panel, fg: sentry.torch ? .black : Theme.ink) {
                sentry.torch.toggle()
            }
            DotIconButton(icon: Glyphs.moon, label: "Dim screen") {
                sentry.stealth = true
            }
            DotIconButton(icon: Glyphs.power, label: sentry.armed ? "Disarm" : "Arm",
                          fill: sentry.armed ? Theme.red : Theme.ink, fg: sentry.armed ? .white : .black, size: 64) {
                sentry.armed.toggle()
            }
            .sensoryFeedback(.impact(weight: .heavy), trigger: sentry.armed)
        }
    }

    private func stat(_ icon: [String], _ n: Int, _ label: String) -> some View {
        HStack(spacing: 7) {
            DotSprite(rows: icon, pitch: 2, color: Theme.dim)
            DotText("\(n)", pitch: 3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(n) \(label)")
    }
}

/// Live camera in a rounded window. The bot does the talking; this just shows what it sees.
struct Viewport: View {
    @Environment(Sentry.self) private var sentry
    @AppStorage("shoo.debug") private var debug = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        ZStack {
            Theme.panel
            if sentry.cameraDenied {
                VStack(spacing: 14) {
                    DotText("NO CAMERA", pitch: 3.5)
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    } label: {
                        Chip(text: "Open Settings", fill: Theme.ink, fg: .black, stroke: .clear)
                    }
                    .buttonStyle(.plain)
                }
            } else if Theme.slasher {
                FilteredCameraView(tap: sentry.previewTap)
                Splatter(anchor: .leading, seed: 8, amount: 1.4)
                Splatter(anchor: .bottomLeading, seed: 9, amount: 1.2)
            } else {
                CameraPreview(session: sentry.camera.session)
            }
            GeometryReader { geo in overlays(in: geo.size) }
        }
        .clipShape(shape)
        .overlay {
            if Theme.slasher {
                DistressedBorder(cornerRadius: 28, seed: 6, color: sentry.armed ? Theme.red : Theme.ink)
            } else {
                shape.strokeBorder(sentry.armed ? Theme.red : Theme.line, lineWidth: sentry.armed ? 2 : 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func overlays(in size: CGSize) -> some View {
        let f = sentry.frame
        return ZStack(alignment: .topLeading) {
            crosshair.position(x: size.width / 2, y: Theme.slasher ? 40 : size.height / 2)

            if Theme.slasher {
                HStack(spacing: 7) {
                    Circle().fill(Theme.red).frame(width: 9, height: 9)
                    Text("LIVE").font(Theme.mono(12, .medium)).tracking(1.5).foregroundStyle(Theme.ink)
                }
                .padding(16)
                .opacity(sentry.running ? 1 : 0.3)
            }

            if Theme.slasher, shownBox(in: size) == nil {
                // Resting brackets: the trap, waiting.
                Brackets(length: 26)
                    .stroke(Theme.ink.opacity(0.85), style: StrokeStyle(lineWidth: 2, lineCap: .square))
                    .frame(width: size.width * 0.45, height: size.height * 0.48)
                    .position(x: size.width / 2, y: size.height * 0.56)
            }

            if let rect = shownBox(in: size) {
                let guarded = f.guardedConfidence > f.confidence
                Brackets(length: 18)
                    .stroke(guarded ? Theme.ink : Theme.red, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .animation(.easeOut(duration: 0.2), value: rect)
                if let label = boxLabel {
                    Group {
                        if Theme.slasher {
                            Text(label.uppercased())
                                .font(Theme.mono(13, .bold))
                                .tracking(2)
                                .foregroundStyle(guarded ? .black : Theme.black)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(Rectangle().fill(guarded ? Theme.ink : Theme.red))
                        } else {
                            Chip(text: label, fill: guarded ? Theme.ink : Theme.red, fg: guarded ? .black : .white, stroke: .clear)
                        }
                    }
                    .position(x: min(max(rect.midX, 60), size.width - 60), y: max(rect.minY - 18, 16))
                }
            }

            if debug {
                VStack(alignment: .trailing, spacing: 3) {
                    if f.moving { Text("MOTION").foregroundStyle(Theme.red) }
                    ForEach(Array(f.topLabels.enumerated()), id: \.offset) { _, label in
                        Text("\(label.0) \(String(format: "%.2f", label.1))")
                    }
                }
                .font(Theme.mono(10, .medium))
                .foregroundStyle(Theme.ink)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.6)))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(12)
            }

            HStack(spacing: 6) {
                if f.luma < DetectionFrame.darkLuma && sentry.running {
                    Chip(text: "Night", fill: .black.opacity(0.5))
                }
                if sentry.thermal == .serious || sentry.thermal == .critical {
                    Chip(text: "Hot · slowed", fill: Theme.red, fg: .white, stroke: .clear)
                }
                if sentry.settings.isQuiet(at: .now) {
                    Chip(text: "Quiet", fill: .black.opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(14)
        }
        .frame(width: size.width, height: size.height)
    }

    private var boxLabel: String? {
        let f = sentry.frame
        if f.guardedConfidence > f.confidence, let g = f.guarded { return g.code }
        guard let s = f.species else { return nil }
        return "\(s.code) \(Int(f.confidence * 100))%"
    }

    private var crosshair: some View {
        ZStack {
            Rectangle().frame(width: 14, height: 1)
            Rectangle().frame(width: 1, height: 14)
        }
        .foregroundStyle(.white.opacity(0.35))
    }

    /// Maps the normalized box onto an aspect-filled 9:16 preview.
    private func shownBox(in size: CGSize) -> CGRect? {
        let f = sentry.frame
        let threshold = Float(sentry.settings.tuning.threshold)
        guard let box = f.box, f.confidence >= threshold * 0.6 || f.guardedConfidence >= 0.3 else { return nil }
        let scale = max(size.width / videoAspect, size.height)
        let videoW = scale * videoAspect, videoH = scale
        let ox = (size.width - videoW) / 2, oy = (size.height - videoH) / 2
        return CGRect(x: ox + box.minX * videoW, y: oy + box.minY * videoH,
                      width: box.width * videoW, height: box.height * videoH)
    }
}
