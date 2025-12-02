import Foundation

internal class HttpHelper {
    private static let TAG = "HttpHelper"
    private static let DEFAULT_BASE_URL = "https://www.ayetstudios.com"
    
    private nonisolated(unsafe) static var baseUrl: String = DEFAULT_BASE_URL
    private nonisolated(unsafe) static var bundleId: String = ""
    private nonisolated(unsafe) static var userAgent: String = "AyetSDK-iOS"
    
    static func setBaseUrl(_ url: String) {
        baseUrl = url
        Logger.d(TAG, "Base URL set to \(url)")
    }
    
    static func setBundleId(_ id: String) {
        bundleId = id
        Logger.d(TAG, "Bundle ID (Package Name) set to: \(id)")
    }
    
    static func setUserAgent(_ agent: String) {
        userAgent = agent
        Logger.d(TAG, "User agent set to \(agent)")
    }
    
    static func post(_ path: String, body: [String: Any]) async -> String? {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: body, options: [])
            return await postData(path, bodyData: jsonData)
        } catch {
            Logger.e(TAG, "Failed to serialize body to JSON", error)
            return nil
        }
    }
    
    static func postData(_ path: String, bodyData: Data) async -> String? {
        guard let url = URL(string: baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path) else {
            Logger.e(TAG, "Invalid URL: \(baseUrl + path)")
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(bundleId, forHTTPHeaderField: "X-Package-Name")
        request.httpBody = bodyData
        
        do {
            let bodyString = String(data: bodyData, encoding: .utf8) ?? "invalid"
            Logger.d(TAG, "POST \(url) body=\(bodyString)")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                let result = String(data: data, encoding: .utf8)
                Logger.d(TAG, "Response code=\(httpResponse.statusCode) body=\(result ?? "")")
                return result
            }
            
            return nil
        } catch {
            Logger.e(TAG, "HTTP request failed", error)
            return nil
        }
    }
    
    static func get(_ path: String, params: [String: String] = [:]) async -> String? {
        var urlString = baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path
        
        if !params.isEmpty {
            let queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
            var components = URLComponents(string: urlString)
            components?.queryItems = queryItems
            urlString = components?.url?.absoluteString ?? urlString
        }
        
        guard let url = URL(string: urlString) else {
            Logger.e(TAG, "Invalid URL: \(urlString)")
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(bundleId, forHTTPHeaderField: "X-Package-Name")
        
        do {
            Logger.d(TAG, "GET \(url)")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                let result = String(data: data, encoding: .utf8)
                Logger.d(TAG, "Response code=\(httpResponse.statusCode) body=\(result ?? "")")
                return result
            }
            
            return nil
        } catch {
            Logger.e(TAG, "HTTP request failed", error)
            return nil
        }
    }
}
