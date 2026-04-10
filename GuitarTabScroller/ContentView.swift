import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = ScrollerModel()
    @State private var showFileImporter = false

    var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.07, blue: 0.08).ignoresSafeArea()

            VStack(spacing: 0) {
                // PDF area
                ZStack {
                    if let doc = model.document {
                        PDFViewRepresentable(document: doc, controller: model.pdfController)
                    } else {
                        DropPrompt { showFileImporter = true }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                ControlBar(model: model, openAction: { showFileImporter = true })
            }
        }
        .preferredColorScheme(.dark)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                model.load(url: url)
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.pathExtension.lowercased() == "pdf" {
                    DispatchQueue.main.async { model.load(url: url) }
                }
            }
            return true
        }
        .background(KeyCatcher(model: model))
    }
}

struct DropPrompt: View {
    var onTap: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "music.note.list")
                .font(.system(size: 56, weight: .ultraLight))
                .foregroundColor(.white.opacity(0.5))
            Text("Drop a PDF here")
                .font(.system(size: 18, weight: .light))
                .foregroundColor(.white.opacity(0.7))
            Text("or click to choose")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

struct ControlBar: View {
    @ObservedObject var model: ScrollerModel
    var openAction: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Divider().background(Color.white.opacity(0.08))

            HStack(spacing: 16) {
                Button(action: openAction) {
                    Image(systemName: "folder")
                }.buttonStyle(IconButtonStyle())

                Button(action: { model.togglePlay() }) {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                }.buttonStyle(IconButtonStyle())

                Button(action: { model.pdfController.previousPage() }) {
                    Image(systemName: "chevron.left")
                }.buttonStyle(IconButtonStyle())

                Button(action: { model.pdfController.nextPage() }) {
                    Image(systemName: "chevron.right")
                }.buttonStyle(IconButtonStyle())

                Spacer()

                // Mode picker
                Picker("", selection: $model.mode) {
                    Text("Auto-scroll").tag(ScrollMode.auto)
                    Text("Voice cue").tag(ScrollMode.voice)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            .padding(.horizontal, 20)

            // Mode-specific controls
            Group {
                if model.mode == .auto {
                    HStack(spacing: 12) {
                        Image(systemName: "tortoise.fill").foregroundColor(.white.opacity(0.5))
                        Slider(value: $model.scrollSpeed, in: 5...200)
                        Image(systemName: "hare.fill").foregroundColor(.white.opacity(0.5))
                        Text("\(Int(model.scrollSpeed)) px/s")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 70, alignment: .trailing)
                    }
                } else {
                    HStack(spacing: 12) {
                        Button(action: { model.recordCue() }) {
                            HStack(spacing: 6) {
                                Image(systemName: model.isRecordingCue ? "record.circle.fill" : "mic.fill")
                                Text(model.isRecordingCue ? "Recording…" : (model.hasCue ? "Re-record cue" : "Record cue"))
                                    .font(.system(size: 12))
                            }
                        }.buttonStyle(IconButtonStyle())

                        if model.hasCue {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green.opacity(0.7))
                        }

                        Spacer()

                        Text("Sensitivity")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.5))
                        Slider(value: $model.sensitivity, in: 0.3...0.95)
                            .frame(width: 150)

                        // Live level meter
                        LevelMeter(level: model.inputLevel)
                            .frame(width: 60, height: 8)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
        }
        .background(Color(red: 0.10, green: 0.10, blue: 0.11))
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white.opacity(0.85))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.15 : 0.08))
            )
    }
}

struct LevelMeter: View {
    var level: Float
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.1))
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.green.opacity(0.7))
                    .frame(width: geo.size.width * CGFloat(min(max(level, 0), 1)))
            }
        }
    }
}

// Keyboard shortcuts
struct KeyCatcher: NSViewRepresentable {
    var model: ScrollerModel
    func makeNSView(context: Context) -> NSView {
        let v = KeyView()
        v.model = model
        DispatchQueue.main.async { v.window?.makeFirstResponder(v) }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}

    class KeyView: NSView {
        var model: ScrollerModel?
        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with event: NSEvent) {
            guard let model else { return super.keyDown(with: event) }
            switch event.keyCode {
            case 49: model.togglePlay()                    // space
            case 123: model.pdfController.previousPage()   // left
            case 124: model.pdfController.nextPage()       // right
            default: super.keyDown(with: event)
            }
        }
    }
}
