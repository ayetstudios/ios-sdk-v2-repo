import Foundation

internal struct SdkInitResponse {
    let userStatus: String
    let device: DeviceInfo
    let user: UserInfo
    let adslots: [Adslot]
    let placeholderOw: String?
    let placeholderSw: String?
    let placeholderRs: String?
    let keepaliveDuration: Int
    let keepaliveInterval: Int
    
    static func fromJson(_ json: [String: Any]) -> SdkInitResponse? {
        guard let deviceObj = json["device"] as? [String: Any],
              let userObj = json["user"] as? [String: Any],
              let adslotArray = json["adslots"] as? [[String: Any]] else {
            return nil
        }
        
        let adslots = adslotArray.compactMap { slotObj -> Adslot? in
            guard let id = slotObj["id"] as? Int else { return nil }
            return Adslot(
                id: id,
                name: slotObj["name"] as? String ?? "",
                type: slotObj["type"] as? String ?? ""
            )
        }
        
        let device = DeviceInfo(
            uuid: deviceObj["uuid"] as? String ?? "",
            legacyIdentifier: deviceObj["legacy_identifier"] as? String
        )
        
        let user = UserInfo(
            id: userObj["id"] as? Int64 ?? 0,
            externalIdentifier: userObj["external_identifier"] as? String ?? "",
            publisherId: userObj["publisher_id"] as? Int ?? 0,
            publisherPlacementId: userObj["publisher_placement_id"] as? Int ?? 0,
            currencyGranted: userObj["currency_granted"] as? Int ?? 0
        )
        
        return SdkInitResponse(
            userStatus: json["user_status"] as? String ?? "",
            device: device,
            user: user,
            adslots: adslots,
            placeholderOw: json["placeholder_ow"] as? String,
            placeholderSw: json["placeholder_sw"] as? String,
            placeholderRs: json["placeholder_rs"] as? String,
            keepaliveDuration: json["keepaliveDuration"] as? Int ?? 0,
            keepaliveInterval: json["keepaliveInterval"] as? Int ?? 0
        )
    }
}

internal struct DeviceInfo {
    let uuid: String
    let legacyIdentifier: String?
}

internal struct UserInfo {
    let id: Int64
    let externalIdentifier: String
    let publisherId: Int
    let publisherPlacementId: Int
    let currencyGranted: Int
}

internal struct Adslot {
    let id: Int
    let name: String
    let type: String
}
