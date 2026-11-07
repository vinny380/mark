import AppKit
import MarkCore
import WebKit

/// Renders Mermaid diagrams and TeX math for Preview in an invisible web view.
/// The libraries load from jsDelivr (pinned versions, integrity-checked) instead of shipping inside the app:
/// they're ~5 MB, Mark is ~2 MB. Only the libraries are downloaded; your note never leaves the Mac.
/// Offline or invalid source → nil, and Preview shows the source instead. Results post `Images.didLoad`.
@MainActor final class Diagrams: NSObject, WKNavigationDelegate {
    static let shared = Diagrams()

    private struct Key: Hashable { let kind: DiagramKind; let src: String; let dark: Bool }
    // ponytail: unbounded in-memory cache for the app's lifetime, like Images.
    private var cache: [Key: NSImage] = [:]
    private var seen: Set<Key> = [] // asked for once; a failure isn't retried until the source changes
    private var queue: [Key] = []
    private var web: WKWebView?
    private var loaded = false, busy = false

    func image(_ kind: DiagramKind, _ src: String, dark: Bool) -> NSImage? {
        let key = Key(kind: kind, src: src, dark: dark)
        if let hit = cache[key] { return hit }
        if seen.insert(key).inserted { queue.append(key); pump() }
        return nil
    }

    private func pump() {
        guard let web else {
            let w = WKWebView(frame: NSRect(x: 0, y: 0, width: 1000, height: 800))
            w.navigationDelegate = self
            w.loadHTMLString(Self.page, baseURL: Self.base)
            web = w
            return
        }
        guard loaded, !busy, !queue.isEmpty else { return }
        busy = true
        let key = queue.removeFirst()
        let kind: String = switch key.kind { case .mermaid: "mermaid"; case .math(let display): display ? "block" : "inline" }
        Task {
            defer { busy = false; pump() }
            guard let r = try? await web.callAsyncJavaScript("return await render(kind, src, dark)",
                                                              arguments: ["kind": kind, "src": key.src, "dark": key.dark], contentWorld: .page) as? [String: Any],
                  let png = (r["png"] as? String).flatMap({ Data(base64Encoded: $0) }), let picture = NSImage(data: png),
                  let w = r["w"] as? Double, let h = r["h"] as? Double, w > 0, h > 0 else { return }
            picture.size = NSSize(width: w, height: h)
            cache[key] = picture
            NotificationCenter.default.post(name: Images.didLoad, object: nil)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded = true
        pump()
    }

    /// Couldn't load the libraries (offline): forget the web view so the next request tries again.
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) { reset() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) { reset() }
    private func reset() {
        web = nil; loaded = false
        seen.subtract(queue); queue = []
    }

    /// The page only ever loads itself; diagram links and anything else are refused.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        action.request.url == Self.base ? .allow : .cancel
    }

    private static let base = URL(string: "https://cdn.jsdelivr.net/")!
    private static let page = #"""
    <!doctype html><html><head>
    <script src="https://cdn.jsdelivr.net/npm/mermaid@11.4.1/dist/mermaid.min.js" integrity="sha384-rbtjAdnIQE/aQJGEgXrVUlMibdfTSa4PQju4HDhN3sR2PmaKFzhEafuePsl9H/9I" crossorigin="anonymous"></script>
    <script>window.MathJax = { svg: { fontCache: 'none' }, startup: { typeset: false } };</script>
    <script src="https://cdn.jsdelivr.net/npm/mathjax@3.2.2/es5/tex-svg-full.js" integrity="sha384-4kE/rQ11E8xT9QgrCBTyvenkuPfQo8rXYQvJZuMgxyPOoUfpatjQPlgdv6V5yhUK" crossorigin="anonymous"></script>
    <script>
    // SVG → 2x PNG inside WebKit, which handles CSS, markers and fonts the native SVG reader skips.
    async function raster(svg) {
      document.body.appendChild(svg);
      const r = svg.getBoundingClientRect(), w = Math.ceil(r.width), h = Math.ceil(r.height);
      svg.setAttribute('width', w); svg.setAttribute('height', h);
      const xml = new XMLSerializer().serializeToString(svg); svg.remove();
      const img = new Image(); img.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(xml); await img.decode();
      const c = document.createElement('canvas'); c.width = w * 2; c.height = h * 2;
      const g = c.getContext('2d'); g.scale(2, 2); g.drawImage(img, 0, 0, w, h);
      return { png: c.toDataURL('image/png').slice(22), w, h };
    }
    async function render(kind, src, dark) {
      const ink = dark ? '#ededed' : '#171717', paper = dark ? '#0a0a0a' : '#ffffff';
      if (kind === 'mermaid') {
        mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', htmlLabels: false, flowchart: { htmlLabels: false },
          theme: 'base', themeCSS: `.edgeLabel rect, .labelBkg { fill: ${paper} !important; opacity: 1 !important; }`,
          themeVariables: { fontFamily: '-apple-system, Helvetica, sans-serif', fontSize: '15px', textColor: ink,
            primaryColor: dark ? '#171717' : '#fafafa', primaryTextColor: ink, primaryBorderColor: dark ? '#3f3f3f' : '#d4d4d4',
            lineColor: dark ? '#8f8f8f' : '#666666', secondaryColor: dark ? '#1f1f1f' : '#f2f2f2', tertiaryColor: paper,
            edgeLabelBackground: paper } });
        const { svg } = await mermaid.render('m' + Math.random().toString(36).slice(2), src);
        const box = document.createElement('div'); box.innerHTML = svg;
        const el = box.querySelector('svg'), vb = el.viewBox.baseVal;
        el.removeAttribute('style'); el.setAttribute('width', vb.width); el.setAttribute('height', vb.height);
        return raster(el);
      }
      await MathJax.startup.promise;
      const el = MathJax.tex2svg(src, { display: kind === 'block' }).querySelector('svg');
      el.setAttribute('color', ink); el.style.fontSize = kind === 'block' ? '19px' : '16px';
      return raster(el);
    }
    </script></head><body style="margin:0"></body></html>
    """#
}
