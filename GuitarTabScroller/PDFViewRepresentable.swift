import SwiftUI
import PDFKit

final class PDFController {
    weak var pdfView: PDFView?

    func nextPage() {
        guard let pdfView, pdfView.canGoToNextPage else { return }
        pdfView.goToNextPage(nil)
    }
    func previousPage() {
        guard let pdfView, pdfView.canGoToPreviousPage else { return }
        pdfView.goToPreviousPage(nil)
    }
    func scroll(by dy: CGFloat) {
        guard let pdfView else { return }
        guard let scrollView = findScrollView(in: pdfView) else { return }
        var pt = scrollView.contentView.bounds.origin
        pt.y -= dy
        scrollView.contentView.scroll(to: pt)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let s = view as? NSScrollView { return s }
        for sub in view.subviews {
            if let s = findScrollView(in: sub) { return s }
        }
        return nil
    }
}

struct PDFViewRepresentable: NSViewRepresentable {
    let document: PDFDocument
    let controller: PDFController

    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.document = document
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.backgroundColor = NSColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)
        v.pageShadowsEnabled = false
        controller.pdfView = v
        return v
    }
    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document !== document {
            nsView.document = document
        }
    }
}
