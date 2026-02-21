import Foundation
import Combine
import FirebaseFirestore

class DataService: ObservableObject {
    private let db = Firestore.firestore()
    
    // MARK: - Restaurants
    
    func fetchRestaurants(completion: @escaping ([Restaurant]) -> Void) {
        db.collection("restaurants").whereField("isActive", isEqualTo: true).getDocuments { snapshot, error in
            guard let documents = snapshot?.documents, error == nil else {
                print("Error fetching restaurants: \(error?.localizedDescription ?? "")")
                completion([])
                return
            }
            
            let restaurants = documents.compactMap { try? $0.data(as: Restaurant.self) }
            completion(restaurants)
        }
    }
    
    func getAllRestaurantsForAdmin(completion: @escaping ([Restaurant]) -> Void) {
        // Admin sees all (including inactive)
        db.collection("restaurants").getDocuments { snapshot, error in
            guard let documents = snapshot?.documents else { return }
            let restaurants = documents.compactMap { try? $0.data(as: Restaurant.self) }
            completion(restaurants)
        }
    }
    
    func fetchRestaurant(id: String, completion: @escaping (Restaurant?) -> Void) {
        db.collection("restaurants").document(id).getDocument { document, error in
            if let document = document, document.exists {
                let restaurant = try? document.data(as: Restaurant.self)
                completion(restaurant)
            } else {
                completion(nil)
            }
        }
    }

    // MARK: - Admin / Store Owner Operations
    
    func createRestaurant(restaurant: Restaurant, completion: @escaping (Error?) -> Void) {
        do {
            try db.collection("restaurants").document(restaurant.id).setData(from: restaurant, completion: completion)
        } catch {
            completion(error)
        }
    }

    /// Store owner creates their own restaurant and links it to their user profile.
    func createRestaurantForOwner(restaurant: Restaurant, ownerUid: String, completion: @escaping (Error?) -> Void) {
        var owned = restaurant
        // Ensure ownerId is set before saving
        if owned.ownerId == nil { owned = Restaurant(id: owned.id, name: owned.name, ownerId: ownerUid,
            description: owned.description, cuisineType: owned.cuisineType, imageUrl: owned.imageUrl,
            rating: owned.rating, deliveryTime: owned.deliveryTime, minOrderAmount: owned.minOrderAmount,
            menu: owned.menu, isActive: owned.isActive) }
        do {
            try db.collection("restaurants").document(owned.id).setData(from: owned) { [weak self] error in
                if let error { completion(error); return }
                // Link restaurant id to user profile
                self?.db.collection("users").document(ownerUid).updateData([
                    "managedRestaurantId": owned.id,
                    "role": UserRole.storeOwner.rawValue
                ], completion: completion)
            }
        } catch {
            completion(error)
        }
    }

    /// Full restaurant update — used by both admin and store owners
    func updateRestaurant(restaurant: Restaurant, completion: @escaping (Error?) -> Void) {
        do {
            try db.collection("restaurants").document(restaurant.id).setData(from: restaurant, merge: true, completion: completion)
        } catch {
            completion(error)
        }
    }
    
    func assignStoreOwner(uid: String, restaurantId: String, completion: @escaping (Error?) -> Void) {
        let userRef = db.collection("users").document(uid)
        
        userRef.updateData([
            "role": UserRole.storeOwner.rawValue,
            "managedRestaurantId": restaurantId
        ], completion: completion)
        
        // Also update restaurant to point to owner
        db.collection("restaurants").document(restaurantId).updateData([
            "ownerId": uid
        ])
    }
    
    func updateRestaurantMenu(restaurantId: String, menu: [MenuItem], completion: @escaping (Error?) -> Void) { // Fixed typo: 'menu' parameter was missing type or updateData call was implicit
         // Manual encoding for array of custom structs if needed, or re-save whole object
         // To stay simple, we can save the whole object or partial update if we encoded MenuItems to [[String:Any]]
         // Here we assume Restaurant model update
         // db.collection("restaurants").document(restaurantId).updateData(["menu": ...])
         
         // Easier to just fetch, update local, save back for this prototype
         // Or update specific field:
         do {
             let encodedMenu = try menu.map { try Firestore.Encoder().encode($0) }
             db.collection("restaurants").document(restaurantId).updateData([
                 "menu": encodedMenu
             ], completion: completion)
         } catch {
             completion(error)
         }
    }

    func deleteRestaurant(restaurantId: String, completion: @escaping (Error?) -> Void) {
        db.collection("restaurants").document(restaurantId).delete(completion: completion)
    }

    // MARK: - User Profile

    func updateUserProfile(uid: String, data: [String: Any], completion: @escaping (Error?) -> Void) {
        db.collection("users").document(uid).updateData(data) { error in
            DispatchQueue.main.async { completion(error) }
        }
    }

    // MARK: - Addresses

    func fetchAddresses(uid: String, completion: @escaping ([UserAddress]) -> Void) {
        db.collection("users").document(uid).collection("addresses")
            .getDocuments { snapshot, _ in
                let addresses = snapshot?.documents.compactMap { try? $0.data(as: UserAddress.self) } ?? []
                DispatchQueue.main.async { completion(addresses.sorted { $0.isDefault && !$1.isDefault }) }
            }
    }

    func saveAddress(uid: String, address: UserAddress, completion: @escaping (Error?) -> Void) {
        do {
            try db.collection("users").document(uid).collection("addresses")
                .document(address.id).setData(from: address, completion: completion)
        } catch { completion(error) }
    }

    func deleteAddress(uid: String, addressId: String, completion: @escaping (Error?) -> Void) {
        db.collection("users").document(uid).collection("addresses")
            .document(addressId).delete(completion: completion)
    }

    // MARK: - Saved Cards

    func fetchCards(uid: String, completion: @escaping ([SavedCard]) -> Void) {
        db.collection("users").document(uid).collection("cards")
            .getDocuments { snapshot, _ in
                let cards = snapshot?.documents.compactMap { try? $0.data(as: SavedCard.self) } ?? []
                DispatchQueue.main.async { completion(cards) }
            }
    }

    func saveCard(uid: String, card: SavedCard, completion: @escaping (Error?) -> Void) {
        do {
            try db.collection("users").document(uid).collection("cards")
                .document(card.id).setData(from: card, completion: completion)
        } catch { completion(error) }
    }

    func deleteCard(uid: String, cardId: String, completion: @escaping (Error?) -> Void) {
        db.collection("users").document(uid).collection("cards")
            .document(cardId).delete(completion: completion)
    }

    // MARK: - Coupons

    func fetchCoupons(uid: String, completion: @escaping ([DiscountCoupon]) -> Void) {
        db.collection("users").document(uid).collection("coupons")
            .getDocuments { snapshot, _ in
                let coupons = snapshot?.documents.compactMap { try? $0.data(as: DiscountCoupon.self) } ?? []
                DispatchQueue.main.async { completion(coupons.sorted { !$0.isUsed && $1.isUsed }) }
            }
    }

    func saveCoupon(uid: String, coupon: DiscountCoupon, completion: @escaping (Error?) -> Void) {
        do {
            try db.collection("users").document(uid).collection("coupons")
                .document(coupon.id).setData(from: coupon, completion: completion)
        } catch { completion(error) }
    }

    // MARK: - Notification Preferences

    func fetchNotificationPreferences(uid: String, completion: @escaping (NotificationPreferences) -> Void) {
        db.collection("users").document(uid).getDocument { document, _ in
            var prefs = NotificationPreferences()
            if let data = document?.data()?["notificationPreferences"] as? [String: Any] {
                prefs = NotificationPreferences(
                    orderUpdates:    data["orderUpdates"] as? Bool ?? true,
                    promotions:      data["promotions"] as? Bool ?? true,
                    newRestaurants:  data["newRestaurants"] as? Bool ?? false,
                    emailDigest:     data["emailDigest"] as? Bool ?? true
                )
            }
            DispatchQueue.main.async { completion(prefs) }
        }
    }

    func saveNotificationPreferences(uid: String, prefs: NotificationPreferences, completion: @escaping (Error?) -> Void) {
        let data: [String: Any] = [
            "notificationPreferences": [
                "orderUpdates":   prefs.orderUpdates,
                "promotions":     prefs.promotions,
                "newRestaurants": prefs.newRestaurants,
                "emailDigest":    prefs.emailDigest
            ]
        ]
        db.collection("users").document(uid).updateData(data) { error in
            DispatchQueue.main.async { completion(error) }
        }
    }
}
