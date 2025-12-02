import UIKit
import WebKit
import SwiftUI

class WebViewController: UIViewController {
    private var webView: WKWebView!
    private var placeholderWebView: WKWebView?
    private var url: URL
    private var userAgent: String?
    private var placeholderHtml: String?
    private static weak var currentInstance: WebViewController?
    private var isReloading: Bool = false
    private var isNavigating: Bool = false
    
    init(url: URL, userAgent: String? = nil, placeholderHtml: String? = nil) {
        self.url = url
        self.userAgent = userAgent
        self.placeholderHtml = placeholderHtml
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        WebViewController.currentInstance = self
        setupWebView()

        if let placeholderHtml = placeholderHtml, !placeholderHtml.isEmpty {
            setupPlaceholderView(html: placeholderHtml)
        }

        loadUrl()
    }
    
    @objc private func closeTapped() {
        WebViewController.currentInstance = nil
        dismiss(animated: true)
    }
    
    private func setupWebView() {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptEnabled = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.websiteDataStore = .default()

        configuration.userContentController.add(self, name: "closeWebView")

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        if let userAgent = userAgent {
            webView.customUserAgent = userAgent
        }

        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func setupPlaceholderView(html: String) {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptEnabled = true

        placeholderWebView = WKWebView(frame: .zero, configuration: configuration)
        placeholderWebView?.translatesAutoresizingMaskIntoConstraints = false
        placeholderWebView?.scrollView.contentInsetAdjustmentBehavior = .never
        placeholderWebView?.loadHTMLString(html, baseURL: nil)

        if let placeholderWebView = placeholderWebView {
            view.addSubview(placeholderWebView)

            NSLayoutConstraint.activate([
                placeholderWebView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                placeholderWebView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                placeholderWebView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                placeholderWebView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        }
    }
    
    private func loadUrl() {
        let request = URLRequest(url: url)
        webView.load(request)
    }
    
    internal func reloadContent() {
        guard !isReloading && !isNavigating else {
            Logger.d("WebViewController", "Skipping reload - already reloading or navigating")
            return
        }

        isReloading = true
        Logger.d("WebViewController", "Starting content reload")
        webView.reload()
    }
    
    private func removePlaceholder() {
        guard let placeholderWebView = placeholderWebView else { return }

        UIView.animate(withDuration: 0.3, animations: {
            placeholderWebView.alpha = 0
        }) { _ in
            placeholderWebView.removeFromSuperview()
            self.placeholderWebView = nil
        }
    }
    
    @MainActor
    static func present(url: URL, userAgent: String? = nil, placeholderHtml: String? = nil) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            Logger.e("WebViewController", "Failed to get root view controller")
            return
        }

        let webViewController = WebViewController(url: url, userAgent: userAgent, placeholderHtml: placeholderHtml)
        webViewController.modalPresentationStyle = .fullScreen

        var presentingViewController = rootViewController
        while let presented = presentingViewController.presentedViewController {
            presentingViewController = presented
        }

        presentingViewController.present(webViewController, animated: true)
    }

    static func getCurrentInstance() -> WebViewController? {
        return currentInstance
    }
}

extension WebViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "closeWebView" {
            closeTapped()
        }
    }
}

extension WebViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        if shouldOpenInSystemBrowser(url: url) {
            AyetSDK.recordOfferClick()
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        } else {
            isNavigating = true
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isNavigating = false
        isReloading = false

        Logger.d("WebViewController", "Navigation finished")
        removePlaceholder()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isNavigating = false
        isReloading = false

        Logger.e("WebViewController", "Navigation failed: \(error.localizedDescription)")
    }
}

extension WebViewController: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            if shouldOpenInSystemBrowser(url: url) {
                AyetSDK.recordOfferClick()
                if UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url)
                } else {
                    webView.load(navigationAction.request)
                }
            } else {
                webView.load(navigationAction.request)
            }
        }
        return nil
    }
    
    private func shouldOpenInSystemBrowser(url: URL) -> Bool {
        guard let currentHost = self.url.host else { return false }
        let currentUrl = self.url
        
        if isRewardStatusUrl(url: url) {
            return false
        }
        
        if let urlHost = url.host, urlHost != currentHost {
            return true
        }
        
        switch url.scheme?.lowercased() {
        case "market", "play", "itms", "itms-apps":
            return true
        case "tel", "mailto", "sms":
            return true
        case "intent":
            return true
        default:
            break
        }
        
        return false
    }
    
    private func isRewardStatusUrl(url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        
        if host == "support.ayet.io" || host == "support.staging.ayet.io" {
            let path = url.path.lowercased()
            if path.starts(with: "/offers") {
                return true
            }
        }
        
        return false
    }
}

struct WebViewControllerRepresentable: UIViewControllerRepresentable {
    let url: URL
    let userAgent: String?
    let placeholderHtml: String?

    func makeUIViewController(context: Context) -> WebViewController {
        return WebViewController(url: url, userAgent: userAgent, placeholderHtml: placeholderHtml)
    }

    func updateUIViewController(_ uiViewController: WebViewController, context: Context) {
    }
}
