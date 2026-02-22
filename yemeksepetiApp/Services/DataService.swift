import Foundation
import Combine

/// Thin adapter layer — routes all calls to the SQL API services.
/// FirebaseFirestore has been fully removed.
///
/// @MainActor ensures all published-property mutations happen on the main thread,
/// eliminating the need for DispatchQueue.main.async boilerplate throughout.
@MainActor
class DataService: ObservableObject {
    private let restaurantAPI = RestaurantAPIService()
    private let adminAPI      = AdminAPIService()
    private let userAPI       = UserAPIService()

    /// In-memory card store (Cards API not yet on backend)
    private var cardStore: [String: [SavedCard]] = [:]

    // MARK: - Restaurants

    func fetchRestaurants(completion: @escaping ([Restaurant]) -> Void) {
        Task {
            let list = (try? await restaurantAPI.fetchActive()) ?? []
            completion(list)
        }
    }

    func getAllRestaurantsForAdmin(completion: @escaping ([Restaurant]) -> Void) {
        Task {
            let list = (try? await adminAPI.fetchAllRestaurants()) ?? []
            completion(list)
        }
    }

    func fetchRestaurant(id: String, completion: @escaping (Restaurant?) -> Void) {
        Task {
            let r = try? await restaurantAPI.fetchDetail(id: id)
            completion(r)
        }
    }

    func createRestaurant(restaurant: Restaurant, completion: @escaping (Error?) -> Void) {
        Task {
            do {
                _ = try await restaurantAPI.createRestaurant(restaurant)
                completion(nil)
            } catch {
                completion(error)
            }
        }
    }

    func createRestaurantForOwner(restaurant: Restaurant, ownerUid: String, completion: @escaping (Error?) -> Void) {
        Task {
            do {
                _ = try await restaurantAPI.createRestaurant(restaurant)
                try await adminAPI.updateUserRole(uid: ownerUid, role: .storeOwner)
                completion(nil)
            } catch {
                completion(error)
            }
        }
    }

    func updateRestaurant(restaurant: Restaurant, completion: @escaping (Error?) -> Void) {
        Task {
            do {
                _ = try await restaurantAPI.updateRestaurant(restaurant)
                completion(nil)
            } catch {
                completion(error)
            }
        }
    }

    func assignStoreOwner(uid: String, restaurantId: String, completion: @escaping (Error?) -> Void) {
        Task {
            do {
                try await adminAPI.updateUserRole(uid: uid, role: .storeOwner)
                completion(nil)
            } catch {
                completion(error)
            }
        }
    }

    func updateRestaurantMenu(restaurantId: String, menu: [MenuItem], completion: @escaping (Error?) -> Void) {
        Task {
            do {
                for item in menu {
                    try await restaurantAPI.upsertMenuItem(restaurantId: restaurantId, item: item)
                }
                completion(nil)
            } catch {
                completion(error)
            }
        }
    }

    func deleteRestaurant(restaurantId: String, completion: @escaping (Error?) -> Void) {
        Task {
            do {
                try await adminAPI.deleteRestaurant(id: restaurantId)
                completion(nil)
            } catch {
                completion(error)
            }
        }
    }

    // MARK: - User Profile

    func updateUserProfile(uid: String, data: [String: Any], completion: @escaping (Error?) -> Void) {
        Task {
            do {
                _ = try await userAPI.updateMyProfile(
                    displayName: data["displayName"] as? String,
                    city: data["city"] as? String,
                    phone: data["phone"] as? String
                )
                completion(nil)
            } catch {
                completion(error)
            }
        }
    }

    // MARK: - Addresses

    func fetchAddresses(uid: String, completion: @escaping ([UserAddress]) -> Void) {
        Task {
            let list = (try? await userAPI.fetchAddresses()) ?? []
            completion(list)
        }
    }

    /// Save an address: tries PUT (update) first, falls back to POST (create) only on 404.
    func saveAddress(uid: String, address: UserAddress, completion: @escaping (Error?) -> Void) {
        Task {
            do {
                _ = try await userAPI.updateAddress(address)
                completion(nil)
            } catch APIError.notFound {
                // Address doesn't exist on server yet — create it
                do {
                    _ = try await userAPI.createAddress(address)
                    completion(nil)
                } catch {
                    completion(error)
                }
            } catch {
                completion(error)
            }
        }
    }

    func deleteAddress(uid: String, addressId: String, completion: @escaping (Error?) -> Void) {
        Task {
            do {
                try await userAPI.deleteAddress(id: addressId)
                completion(nil)
            } catch {
                completion(error)
            }
        }
    }

    // MARK: - Cards (in-memory)

    func fetchCards(uid: String, completion: @escaping ([SavedCard]) -> Void) {
        completion(cardStore[uid] ?? [])
    }

    func saveCard(uid: String, card: SavedCard, completion: @escaping (Error?) -> Void) {
        var cards = cardStore[uid] ?? []
        if let idx = cards.firstIndex(where: { $0.id == card.id }) { cards[idx] = card }
        else { cards.append(card) }
        cardStore[uid] = cards
        completion(nil)
    }

    func deleteCard(uid: String, cardId: String, completion: @escaping (Error?) -> Void) {
        cardStore[uid]?.removeAll { $0.id == cardId }
        completion(nil)
    }

    // MARK: - Coupons (stub — no backend endpoint yet)

    func fetchCoupons(uid: String, completion: @escaping ([DiscountCoupon]) -> Void) {
        completion([])
    }

    func saveCoupon(uid: String, coupon: DiscountCoupon, completion: @escaping (Error?) -> Void) {
        completion(nil)
    }

    // MARK: - Notification Preferences (stub)

    func fetchNotificationPreferences(uid: String, completion: @escaping (NotificationPreferences) -> Void) {
        completion(NotificationPreferences())
    }

    func saveNotificationPreferences(uid: String, prefs: NotificationPreferences, completion: @escaping (Error?) -> Void) {
        completion(nil)
    }
}
