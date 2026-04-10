import SwiftUI
import PDFKit
import Combine

enum ScrollMode { case auto, voice }

final class ScrollerModel: ObservableObject {
    @Published var document: PDFDocument?
    @Published var isPlaying = false
    @Published var mode: ScrollMode = .auto
    @Published var scrollSpeed: Double = 40    // pixels per second
    @Published var sensitivity: Double = 0.88 {  // cosine-similarity threshold
        didSet { audio.threshold = Float(sensitivity) }
    }
    @Published var isRecordingCue = false
    @Published var hasCue = false
    @Published var inputLevel: Float = 0

    let pdfController = PDFController()
    private let audio = AudioCueEngine()
    private var displayLink: CVDisplayLink?
    private var lastTick: CFTimeInterval = 0

    init() {
        audio.onLevel = { [weak self] lvl in
            DispatchQueue.main.async { self?.inputLevel = lvl }
        }
        audio.onCueDetected = { [weak self] in
            DispatchQueue.main.async { self?.pdfController.nextPage() }
        }
        audio.onCueRecorded = { [weak self] in
            DispatchQueue.main.async {
                self?.isRecordingCue = false
                self?.hasCue = true
            }
        }
    }

    func load(url: URL) {
        // Security-scoped access for file importer
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        if let doc = PDFDocument(url: url) {
            self.document = doc
        }
    }

    func togglePlay() {
        isPlaying.toggle()
        if isPlaying {
            if mode == .auto { startAutoScroll() }
            else { audio.startListening() }
        } else {
            stopAutoScroll()
            audio.stopListening()
        }
    }

    func recordCue() {
        isRecordingCue = true
        audio.recordCue()
    }

    // MARK: - Auto scroll loop
    private var timer: Timer?
    private func startAutoScroll() {
        lastTick = CACurrentMediaTime()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = CACurrentMediaTime()
            let dt = now - self.lastTick
            self.lastTick = now
            self.pdfController.scroll(by: CGFloat(self.scrollSpeed * dt))
        }
    }
    private func stopAutoScroll() {
        timer?.invalidate(); timer = nil
    }
}
