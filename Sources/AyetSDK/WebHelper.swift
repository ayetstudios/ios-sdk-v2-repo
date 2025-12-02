import Foundation
import WebKit

@MainActor
internal class WebHelper {
    private static let TAG = "WebHelper"
    
    static var webViewUserAgent: String?
    static var clientHints: [String: Any]?
    static var isPartitioned: Bool = true
    
    private static var webView: WKWebView?
    
    static func ensureUserAgent() {
        if webViewUserAgent == nil {
            webViewUserAgent = WKWebView().value(forKey: "userAgent") as? String
            Logger.d(TAG, "Detected default WebView UA: \(webViewUserAgent ?? "nil")")
            if let userAgent = webViewUserAgent {
                HttpHelper.setUserAgent(userAgent)
            }
        }
    }
    
    static func ensureClientHints(baseUrl: String) async {
        if clientHints != nil && webViewUserAgent != nil { return }
        
        return await withCheckedContinuation { continuation in
            var hasResumed = false
            let configuration = WKWebViewConfiguration()
            let webView = WKWebView(frame: .zero, configuration: configuration)
            self.webView = webView
            
            let html = """
                <html><body><script>
                (async function(){
                    try {
                        let ch = {};

                        if (navigator.userAgentData && navigator.userAgentData.getHighEntropyValues) {
                            ch = await navigator.userAgentData.getHighEntropyValues([
                                'architecture','bitness','brands','mobile','model','platform','platformVersion','uaFullVersion','fullVersionList','wow64'
                            ]);
                        }

                        const result = {
                            ua: navigator.userAgent,
                            ch: ch,
                            isPartitioned: true
                        };

                        window.webkit.messageHandlers.clientHints.postMessage(JSON.stringify(result));
                    } catch(e) {
                        window.webkit.messageHandlers.clientHints.postMessage(JSON.stringify({
                            ua: navigator.userAgent,
                            ch: {},
                            isPartitioned: true
                        }));
                    }
                })();
                </script></body></html>
                """
            
            let messageHandler = ClientHintsMessageHandler { [weak webView] data in
                DispatchQueue.main.async {
                    guard !hasResumed else { 
                        Logger.d(TAG, "Client hints handler called but already resumed")
                        return 
                    }
                    
                    do {
                        if let jsonData = data.data(using: .utf8),
                           let json = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] {
                            
                            Logger.d(TAG, "Client hints raw result: \(data)")
                            
                            let ua = json["ua"] as? String ?? ""
                            let ch = json["ch"] as? [String: Any] ?? [:]
                            let partitioned = json["isPartitioned"] as? Bool ?? true
                            
                            Logger.d(TAG, "Client hints parsed - UA length: \(ua.count), CH keys: \(ch.keys.count)")
                            
                            webViewUserAgent = ua
                            clientHints = ch
                            isPartitioned = partitioned
                            
                            if !ua.isEmpty {
                                HttpHelper.setUserAgent(ua)
                            }
                            
                            Logger.d(TAG, "Final UA: \(ua)")
                            Logger.d(TAG, "Final CH: \(ch)")
                        }
                    } catch {
                        Logger.e(TAG, "Failed to parse client hints", error)
                    }
                    
                    webView?.removeFromSuperview()
                    self.webView = nil
                    hasResumed = true
                    continuation.resume()
                }
            }
            
            configuration.userContentController.add(messageHandler, name: "clientHints")
            
            webView.loadHTMLString(html, baseURL: URL(string: baseUrl))
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                guard !hasResumed else { return }
                
                if self.webView != nil {
                    Logger.e(TAG, "Client hints collection timeout")
                    webView.removeFromSuperview()
                    self.webView = nil
                    hasResumed = true
                    continuation.resume()
                }
            }
        }
    }
}

private class ClientHintsMessageHandler: NSObject, WKScriptMessageHandler {
    let callback: (String) -> Void
    
    init(callback: @escaping (String) -> Void) {
        self.callback = callback
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let data = message.body as? String {
            callback(data)
        }
    }
}
