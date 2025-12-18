import Foundation
import UIKit

@MainActor
public class AyetSDK {
    private static let TAG = "AyetSDK"
    
    public enum Gender: String {
        case male = "MALE"
        case female = "FEMALE"
        case nonBinary = "NON_BINARY"
    }
    
    public static let shared = AyetSDK()
    
    private var placementId: Int?
    private var externalIdentifier: String?
    
    private var age: Int?
    private var gender: Gender?
    
    private var trackingCustom1: String?
    private var trackingCustom2: String?
    private var trackingCustom3: String?
    private var trackingCustom4: String?
    private var trackingCustom5: String?
    
    private var deviceUuid: String?
    private var isInitialized: Bool = false
    
    private var initTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var initResponse: SdkInitResponse?
    private var lastInitTime: TimeInterval = 0
    private let INIT_TIMEOUT_MINUTES = 60
    private let SYNC_DELAY_MS: UInt64 = 2000
    
    private var offerwallBaseUrl: String = "https://offerwall.ayet.io"
    private var rewardStatusBaseUrl: String = "https://support.ayet.io"
    private var surveywallBaseUrl: String = "https://surveys.ayet.io"
    
    private var hasClickedOffer: Bool = false
    
    private init() {
        setupAppLifecycleObservers()
    }
    
    public func setDebug(_ enabled: Bool) {
        Logger.setDebugEnabled(enabled)
        Logger.d(AyetSDK.TAG, "Debug mode set to \(enabled)")
    }

    public nonisolated func setLogHandler(_ handler: LogHandler?) {
        Logger.setLogHandler(handler)
    }
    
    public func setBaseUrl(_ url: String) {
        HttpHelper.setBaseUrl(url)
    }
    
    public func setOfferwallBaseUrl(_ url: String) {
        offerwallBaseUrl = url
        Logger.d(AyetSDK.TAG, "Offerwall base URL set to \(url)")
    }
    
    public func setRewardStatusBaseUrl(_ url: String) {
        rewardStatusBaseUrl = url
        Logger.d(AyetSDK.TAG, "Reward status base URL set to \(url)")
    }
    
    public func setSurveywallBaseUrl(_ url: String) {
        surveywallBaseUrl = url
        Logger.d(AyetSDK.TAG, "Surveywall base URL set to \(url)")
    }
    
    public func initialize(placementId: Int, externalIdentifier: String) {
        WebHelper.ensureUserAgent()
        self.placementId = placementId
        self.externalIdentifier = externalIdentifier
        HttpHelper.setBundleId(Bundle.main.bundleIdentifier ?? "")
        scheduleInit()
    }
    
    public func setAge(_ age: Int) {
        self.age = age
        Logger.d(AyetSDK.TAG, "Age set to: \(age)")
        scheduleBatchedSync()
    }
    
    public func setGender(_ gender: Gender) {
        self.gender = gender
        Logger.d(AyetSDK.TAG, "Gender set to: \(gender.rawValue)")
        scheduleBatchedSync()
    }
    
    public func setTrackingCustom1(_ value: String) {
        trackingCustom1 = value
        Logger.d(AyetSDK.TAG, "setTrackingCustom1: \(value)")
    }
    
    public func setTrackingCustom2(_ value: String) {
        trackingCustom2 = value
        Logger.d(AyetSDK.TAG, "setTrackingCustom2: \(value)")
    }
    
    public func setTrackingCustom3(_ value: String) {
        trackingCustom3 = value
        Logger.d(AyetSDK.TAG, "setTrackingCustom3: \(value)")
    }
    
    public func setTrackingCustom4(_ value: String) {
        trackingCustom4 = value
        Logger.d(AyetSDK.TAG, "setTrackingCustom4: \(value)")
    }
    
    public func setTrackingCustom5(_ value: String) {
        trackingCustom5 = value
        Logger.d(AyetSDK.TAG, "setTrackingCustom5: \(value)")
    }
    
    public func setExternalIdentifier(_ identifier: String) {
        if isInitialized {
            Logger.d(AyetSDK.TAG, "Warning: Cannot change External ID after SDK is initialized")
            return
        }
        self.externalIdentifier = identifier
        Logger.d(AyetSDK.TAG, "External identifier set to: \(identifier)")
    }
    
    public func getExternalIdentifier() -> String? {
        return externalIdentifier
    }
    
    public func checkIsInitialized() -> Bool {
        return isInitialized
    }
    
    private func scheduleInit(forced: Bool = false) {
        initTask?.cancel()
        initTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            
            let currentTime = Date().timeIntervalSince1970
            let timeSinceLastInit = currentTime - lastInitTime
            let timeoutSeconds = Double(INIT_TIMEOUT_MINUTES * 60)
            
            if !forced && lastInitTime > 0 && timeSinceLastInit < timeoutSeconds {
                Logger.d(AyetSDK.TAG, "init: skipping - last init was \(Int(timeSinceLastInit)) seconds ago")
                return
            }
            
            if forced {
                Logger.d(AyetSDK.TAG, "init: forced sync")
            }
            
            guard let placement = placementId,
                  let external = externalIdentifier, !external.isEmpty else {
                Logger.e(AyetSDK.TAG, "init: placementId or externalIdentifier missing")
                return
            }
            
            await WebHelper.ensureClientHints(baseUrl: offerwallBaseUrl)
            
            let deviceInfo = DeviceInfoHelper.collectDeviceInfo()
            
            let localAge = self.age
            let localGender = self.gender
            let localDeviceUuid = self.deviceUuid
            
            var body: [String: Any] = [:]
            body["placement_id"] = placement
            body["external_identifier"] = external
            body["is_partitioned"] = WebHelper.isPartitioned
            
            if let userAgent = WebHelper.webViewUserAgent {
                body["user_agent"] = userAgent
            }
            
            if let clientHints = WebHelper.clientHints {
                body["client_hints"] = clientHints
            }
            
            if let uuid = localDeviceUuid {
                body["device_uuid"] = uuid
            }
            
            body["device_info"] = deviceInfo
            
            if let age = localAge {
                body["age"] = age
            }
            
            if let gender = localGender {
                body["gender"] = gender.rawValue
            }
            
            guard let jsonData = try? JSONSerialization.data(withJSONObject: body, options: []) else {
                Logger.e(AyetSDK.TAG, "Failed to serialize init request body")
                return
            }
            
            if let response = await HttpHelper.postData("/rest/v1/sdk/init", bodyData: jsonData) {
                do {
                    if let jsonData = response.data(using: .utf8),
                       let json = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] {
                        
                        let status = json["status"] as? String
                        
                        if status == "error" {
                            let errorMessage = json["error"] as? String ?? "Unknown error"
                            Logger.e(AyetSDK.TAG, "SDK initialization failed: \(errorMessage)")
                            return
                        }
                        
                        if let parsed = SdkInitResponse.fromJson(json) {
                            initResponse = parsed
                            deviceUuid = parsed.device.uuid
                            lastInitTime = currentTime
                            
                            Logger.d(AyetSDK.TAG, "init response: \(parsed)")
                            Logger.d(AyetSDK.TAG, "device UUID: \(parsed.device.uuid)")
                            Logger.d(AyetSDK.TAG, "Available adslots by type:")
                            
                            let slotsByType = Dictionary(grouping: parsed.adslots, by: { $0.type })
                            for (type, slots) in slotsByType {
                                let slotNames = slots.map { "\($0.name) (adslot ID: \($0.id))" }.joined(separator: ", ")
                                Logger.d(AyetSDK.TAG, "  \(type): \(slotNames)")
                            }
                            
                            self.isInitialized = true
                        }
                    }
                } catch {
                    Logger.e(AyetSDK.TAG, "Failed to parse init response", error)
                }
            }
        }
    }
    
    private func scheduleBatchedSync() {
        syncTask?.cancel()
        syncTask = Task {
            try? await Task.sleep(nanoseconds: SYNC_DELAY_MS * 1_000_000)
            
            guard !Task.isCancelled else {
                Logger.d(AyetSDK.TAG, "scheduleBatchedSync: cancelled")
                return
            }
            
            Logger.d(AyetSDK.TAG, "scheduleBatchedSync: triggering forced sync after \(SYNC_DELAY_MS)ms delay")
            scheduleInit(forced: true)
        }
    }
    
    public func showOfferwall(adSlotId: Int) async {
        Logger.d(AyetSDK.TAG, "showOfferwall called with adSlotId: \(adSlotId)")
        
        if let initTask = initTask {
            _ = await initTask.result
        }
        
        guard let matched = initResponse?.adslots.first(where: { $0.id == adSlotId }) else {
            Logger.e(AyetSDK.TAG, "showOfferwall: unknown iOS offerwall adslot \(adSlotId)")
            return
        }
        
        if matched.type != "offerwall" {
            Logger.e(AyetSDK.TAG, "showOfferwall: adslot \(adSlotId) is not an offerwall type")
            return
        }
        
        await launchOfferwall(adSlotId: adSlotId)
    }
    
    public func showOfferwall(adSlotName: String) async {
        Logger.d(AyetSDK.TAG, "showOfferwall called with adSlotName: \(adSlotName)")
        
        if let adSlotId = Int(adSlotName) {
            await showOfferwall(adSlotId: adSlotId)
            return
        }
        
        if let initTask = initTask {
            _ = await initTask.result
        }
        
        guard let matched = initResponse?.adslots.first(where: { $0.name == adSlotName }) else {
            Logger.e(AyetSDK.TAG, "showOfferwall: unknown iOS offerwall adslot \(adSlotName)")
            return
        }
        
        if matched.type != "offerwall" {
            Logger.e(AyetSDK.TAG, "showOfferwall: adslot \(adSlotName) is not an offerwall type")
            return
        }
        
        await launchOfferwall(adSlotId: matched.id)
    }
    
    public func showRewardStatus() async {
        Logger.d(AyetSDK.TAG, "showRewardStatus called")
        
        if let initTask = initTask {
            _ = await initTask.result
        }
        
        await launchRewardStatus()
    }
    
    public func showSurveywall(adSlotId: Int) async {
        Logger.d(AyetSDK.TAG, "showSurveywall called with adSlotId: \(adSlotId)")
        
        if let initTask = initTask {
            _ = await initTask.result
        }
        
        guard let matched = initResponse?.adslots.first(where: { $0.id == adSlotId }) else {
            Logger.e(AyetSDK.TAG, "showSurveywall: unknown iOS surveywall adslot \(adSlotId)")
            return
        }
        
        if matched.type != "web_surveywall" {
            Logger.e(AyetSDK.TAG, "showSurveywall: adslot \(adSlotId) is not a web_surveywall type")
            return
        }
        
        await launchSurveywall(adSlotId: adSlotId)
    }
    
    public func showSurveywall(adSlotName: String) async {
        Logger.d(AyetSDK.TAG, "showSurveywall called with adSlotName: \(adSlotName)")
        
        if let adSlotId = Int(adSlotName) {
            await showSurveywall(adSlotId: adSlotId)
            return
        }
        
        if let initTask = initTask {
            _ = await initTask.result
        }
        
        guard let matched = initResponse?.adslots.first(where: { $0.name == adSlotName }) else {
            Logger.e(AyetSDK.TAG, "showSurveywall: unknown iOS surveywall adslot \(adSlotName)")
            return
        }
        
        if matched.type != "web_surveywall" {
            Logger.e(AyetSDK.TAG, "showSurveywall: adslot \(adSlotName) is not a web_surveywall type")
            return
        }
        
        await launchSurveywall(adSlotId: matched.id)
    }
    
    private func launchOfferwall(adSlotId: Int) async {
        guard let external = externalIdentifier, !external.isEmpty else {
            Logger.e(AyetSDK.TAG, "showOfferwall: externalIdentifier missing")
            return
        }
        
        var urlBuilder = offerwallBaseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        urlBuilder += "/offers?adSlot=\(adSlotId)"
        urlBuilder += "&external_identifier=\(external)"
        urlBuilder += "&iosSdk=true"
    
        if let custom1 = trackingCustom1 {
            urlBuilder += "&custom_1=\(custom1)"
        }
        if let custom2 = trackingCustom2 {
            urlBuilder += "&custom_2=\(custom2)"
        }
        if let custom3 = trackingCustom3 {
            urlBuilder += "&custom_3=\(custom3)"
        }
        if let custom4 = trackingCustom4 {
            urlBuilder += "&custom_4=\(custom4)"
        }
        if let custom5 = trackingCustom5 {
            urlBuilder += "&custom_5=\(custom5)"
        }
        
        Logger.d(AyetSDK.TAG, "showOfferwall url: \(urlBuilder)")
        
        guard let url = URL(string: urlBuilder) else {
            Logger.e(AyetSDK.TAG, "Failed to create URL from: \(urlBuilder)")
            return
        }
        
        let placeholder = initResponse?.placeholderOw
        
        await MainActor.run {
            WebViewController.present(
                url: url,
                userAgent: WebHelper.webViewUserAgent,
                placeholderHtml: placeholder
            )
        }
    }
    
    private func launchRewardStatus() async {
        guard let external = externalIdentifier, !external.isEmpty,
              let placement = placementId else {
            Logger.e(AyetSDK.TAG, "showRewardStatus: externalIdentifier or placementId missing")
            return
        }
        
        var urlBuilder = rewardStatusBaseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        urlBuilder += "/offers?externalIdentifier=\(external.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? external)"
        urlBuilder += "&placementId=\(placement)"
        urlBuilder += "&iosSdk=true"
        
        Logger.d(AyetSDK.TAG, "showRewardStatus url: \(urlBuilder)")
        
        guard let url = URL(string: urlBuilder) else {
            Logger.e(AyetSDK.TAG, "Failed to create URL from: \(urlBuilder)")
            return
        }
        
        let placeholder = initResponse?.placeholderRs
        
        await MainActor.run {
            WebViewController.present(
                url: url,
                userAgent: WebHelper.webViewUserAgent,
                placeholderHtml: placeholder
            )
        }
    }
    
    public func getOffers(adSlotId: Int) async -> String? {
        Logger.d(AyetSDK.TAG, "getOffers called with adSlotId: \(adSlotId)")
        
        if let initTask = initTask {
            _ = await initTask.result
        }
        
        guard let matched = initResponse?.adslots.first(where: { $0.id == adSlotId }) else {
            Logger.e(AyetSDK.TAG, "getOffers: unknown iOS offerwall API adslot \(adSlotId)")
            return nil
        }
        
        if matched.type != "offerwall_api" {
            Logger.e(AyetSDK.TAG, "getOffers: adslot \(adSlotId) is not an offerwall_api type")
            return nil
        }
        
        return await fetchOffers(adSlotId: adSlotId)
    }
    
    public func getOffers(adSlotName: String) async -> String? {
        Logger.d(AyetSDK.TAG, "getOffers called with adSlotName: \(adSlotName)")
        
        if let adSlotId = Int(adSlotName) {
            return await getOffers(adSlotId: adSlotId)
        }
        
        if let initTask = initTask {
            _ = await initTask.result
        }
        
        guard let matched = initResponse?.adslots.first(where: { $0.name == adSlotName }) else {
            Logger.e(AyetSDK.TAG, "getOffers: unknown iOS offerwall API adslot \(adSlotName)")
            return nil
        }
        
        if matched.type != "offerwall_api" {
            Logger.e(AyetSDK.TAG, "getOffers: adslot \(adSlotName) is not an offerwall_api type")
            return nil
        }
        
        return await fetchOffers(adSlotId: matched.id)
    }
    
    private func launchSurveywall(adSlotId: Int) async {
        guard let external = externalIdentifier, !external.isEmpty else {
            Logger.e(AyetSDK.TAG, "showSurveywall: externalIdentifier missing")
            return
        }
        
        var urlBuilder = surveywallBaseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        urlBuilder += "/surveys?adSlot=\(adSlotId)"
        urlBuilder += "&external_identifier=\(external)"
        urlBuilder += "&iosSdk=true"
        
        Logger.d(AyetSDK.TAG, "showSurveywall url: \(urlBuilder)")
        
        guard let url = URL(string: urlBuilder) else {
            Logger.e(AyetSDK.TAG, "Failed to create URL from: \(urlBuilder)")
            return
        }
        
        let placeholder = initResponse?.placeholderSw
        
        await MainActor.run {
            WebViewController.present(
                url: url,
                userAgent: WebHelper.webViewUserAgent,
                placeholderHtml: placeholder
            )
        }
    }
    
    private func fetchOffers(adSlotId: Int) async -> String? {
        guard let external = externalIdentifier, !external.isEmpty else {
            Logger.e(AyetSDK.TAG, "fetchOffers: externalIdentifier missing")
            return nil
        }
        
        do {
            var params: [String: String] = [:]
            params["external_identifier"] = external
            params["include_mobile_offers"] = "true"
            
            if let userAgent = WebHelper.webViewUserAgent {
                params["user_agent"] = userAgent
            }
            
            if let clientHints = WebHelper.clientHints {
                params["client_hints"] = "\(clientHints)"
            }
            
            if let custom1 = trackingCustom1 {
                params["custom_1"] = custom1
            }
            if let custom2 = trackingCustom2 {
                params["custom_2"] = custom2
            }
            if let custom3 = trackingCustom3 {
                params["custom_3"] = custom3
            }
            if let custom4 = trackingCustom4 {
                params["custom_4"] = custom4
            }
            if let custom5 = trackingCustom5 {
                params["custom_5"] = custom5
            }
            
            let response = await HttpHelper.get("/rest/v1/sdk/feed/\(adSlotId)", params: params)
            Logger.d(AyetSDK.TAG, "fetchOffers full response: \(response ?? "nil")")
            
            if let response = response {
                do {
                    if let jsonData = response.data(using: .utf8),
                       let json = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] {
                        
                        let status = json["status"] as? String
                        
                        switch status {
                        case "error":
                            let errorMessage = json["error"] as? String ?? "Unknown error"
                            Logger.e(AyetSDK.TAG, "fetchOffers API error: \(errorMessage)")
                            return nil
                            
                        case "success":
                            if let offersArray = json["offers"] as? [[String: Any]] {
                                Logger.d(AyetSDK.TAG, "fetchOffers extracted \(offersArray.count) offers")
                                let offersData = try JSONSerialization.data(withJSONObject: offersArray, options: [])
                                return String(data: offersData, encoding: .utf8)
                            } else {
                                Logger.e(AyetSDK.TAG, "fetchOffers: success response but no offers array")
                                return nil
                            }
                            
                        default:
                            Logger.e(AyetSDK.TAG, "fetchOffers: unknown status '\(status ?? "nil")' in response")
                            return nil
                        }
                    }
                } catch {
                    Logger.e(AyetSDK.TAG, "fetchOffers: failed to parse JSON response", error)
                    return nil
                }
            }
            
            return nil
        } catch {
            Logger.e(AyetSDK.TAG, "fetchOffers failed", error)
            return nil
        }
    }
    
    internal static func recordOfferClick() {
        shared.hasClickedOffer = true
    }
    
    private func setupAppLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    @objc private func appWillEnterForeground() {
        Task { @MainActor in
            await handleAppRestored()
        }
    }
    
    private func handleAppRestored() async {
        if WebHelper.isPartitioned && hasClickedOffer {
            hasClickedOffer = false
            scheduleInit(forced: true)
            if let initTask = initTask {
                _ = await initTask.result
            }

            if let webViewController = WebViewController.getCurrentInstance() {
                webViewController.reloadContent()
            }
        } else {
            hasClickedOffer = false
        }
    }
}
