;; BikeSharing System Contract
;; A community-owned bike sharing system with maintenance tracking and usage incentives

;; Define the bike NFT token
(define-non-fungible-token Bike uint)

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-bike-not-available (err u101))
(define-constant err-bike-not-rented (err u102))
(define-constant err-insufficient-deposit (err u103))
(define-constant err-invalid-duration (err u104))
(define-constant err-maintenance-required (err u105))

;; Bike rental fee and deposit amounts
(define-constant RENTAL_FEE_PER_HOUR u100)  ;; 100 microSTX per hour
(define-constant BIKE_DEPOSIT u1000)        ;; 1000 microSTX deposit

;; Data variables
(define-data-var total-bikes uint u0)
(define-data-var available-bikes uint u0)
(define-data-var total-revenue uint u0)
(define-data-var maintenance-threshold uint u50)  ;; Bikes need maintenance after 50 rides

;; Maps for tracking bike data
(define-map BikeData
  { bikeId: uint }
  { 
    isAvailable: bool, 
    currentRenter: (optional principal), 
    rentalStartTime: (optional uint), 
    totalRides: uint, 
    lastMaintenance: uint,
    location: (string-ascii 100)
  }
)

(define-map UserRentals
  { user: principal }
  { 
    activeBikeId: (optional uint), 
    totalRentals: uint, 
    totalSpent: uint,
    loyaltyPoints: uint
  }
)

(define-map MaintenanceLog
  { bikeId: uint }
  { 
    lastMaintenanceDate: uint, 
    maintenanceType: (string-ascii 50), 
    cost: uint,
    notes: (string-ascii 200)
  }
)

;; Helper function to initialize a single bike
(define-private (initialize-single-bike (bikeId uint))
  (begin
    (try! (nft-mint? Bike bikeId contract-owner))
    (map-set BikeData { bikeId: bikeId }
             { 
               isAvailable: true, 
               currentRenter: none, 
               rentalStartTime: none, 
               totalRides: u0, 
               lastMaintenance: u0,
               location: "Station A"
             })
    (map-set MaintenanceLog { bikeId: bikeId }
             { 
               lastMaintenanceDate: u0, 
               maintenanceType: "Initial Setup", 
               cost: u0,
               notes: "Bike deployed to system"
             })
    (ok true)
  )
)

;; Initialize bikes one by one (owner must call this function multiple times)
(define-public (add-bike (bikeId uint) (initialLocation (string-ascii 100)))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (try! (nft-mint? Bike bikeId contract-owner))
    (map-set BikeData { bikeId: bikeId }
             { 
               isAvailable: true, 
               currentRenter: none, 
               rentalStartTime: none, 
               totalRides: u0, 
               lastMaintenance: u0,
               location: initialLocation
             })
    (map-set MaintenanceLog { bikeId: bikeId }
             { 
               lastMaintenanceDate: u0, 
               maintenanceType: "Initial Setup", 
               cost: u0,
               notes: "Bike deployed to system"
             })
    (var-set total-bikes (+ (var-get total-bikes) u1))
    (var-set available-bikes (+ (var-get available-bikes) u1))
    (ok bikeId)
  )
)

;; Alternative: Initialize multiple bikes with individual calls
(define-public (initialize-bike-batch (bikeIds (list 10 uint)))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (let ((results (map initialize-single-bike bikeIds)))
      (var-set total-bikes (+ (var-get total-bikes) (len bikeIds)))
      (var-set available-bikes (+ (var-get available-bikes) (len bikeIds)))
      (ok (len bikeIds))
    )
  )
)

;; Function 1: Rent a bike
(define-public (rent-bike (bikeId uint) (duration uint))
  (let
    (
      (bikeData (map-get? BikeData { bikeId: bikeId }))
      (userData (default-to 
                  { activeBikeId: none, totalRentals: u0, totalSpent: u0, loyaltyPoints: u0 }
                  (map-get? UserRentals { user: tx-sender })))
      (rentalCost (* RENTAL_FEE_PER_HOUR duration))
      (totalRequired (+ rentalCost BIKE_DEPOSIT))
    )
    (begin
      ;; Check if bike exists and is available
      (asserts! (is-some bikeData) err-bike-not-available)
      (asserts! (get isAvailable (unwrap-panic bikeData)) err-bike-not-available)
      
      ;; Check if user has sufficient STX
      (asserts! (>= (stx-get-balance tx-sender) totalRequired) err-insufficient-deposit)
      
      ;; Check if duration is valid
      (asserts! (and (> duration u0) (< duration u25)) err-invalid-duration)  ;; Max 24 hours
      
      ;; Transfer rental fee and deposit
      (try! (stx-transfer? totalRequired tx-sender (as-contract tx-sender)))
      
      ;; Update bike data
      (map-set BikeData { bikeId: bikeId }
               { 
                 isAvailable: false, 
                 currentRenter: (some tx-sender), 
                 rentalStartTime: (some stacks-block-height), 
                 totalRides: (+ (get totalRides (unwrap-panic bikeData)) u1), 
                 lastMaintenance: (get lastMaintenance (unwrap-panic bikeData)),
                 location: (get location (unwrap-panic bikeData))
               })
      
      ;; Update available bikes count
      (var-set available-bikes (- (var-get available-bikes) u1))
      
      ;; Update user data
      (map-set UserRentals { user: tx-sender }
               { 
                 activeBikeId: (some bikeId), 
                 totalRentals: (+ (get totalRentals userData) u1), 
                 totalSpent: (+ (get totalSpent userData) rentalCost),
                 loyaltyPoints: (+ (get loyaltyPoints userData) duration)
               })
      
      ;; Update total revenue
      (var-set total-revenue (+ (var-get total-revenue) rentalCost))
      
      ;; Check if bike needs maintenance
      (if (>= (get totalRides (unwrap-panic bikeData)) (var-get maintenance-threshold))
          (print "Bike needs maintenance!")
          (print "Bike rented successfully"))
      
      (ok { 
        bikeId: bikeId, 
        rentalCost: rentalCost, 
        deposit: BIKE_DEPOSIT, 
        duration: duration,
        startTime: stacks-block-height
      })
    )
  )
)

;; Function 2: Return a bike
(define-public (return-bike (bikeId uint) (newLocation (string-ascii 100)) (maintenanceNotes (optional (string-ascii 200))))
  (let
    (
      (bikeData (unwrap! (map-get? BikeData { bikeId: bikeId }) err-bike-not-available))
      (userData (unwrap! (map-get? UserRentals { user: tx-sender }) err-bike-not-rented))
      (rentalStartTime (unwrap! (get rentalStartTime bikeData) err-bike-not-rented))
      (currentTime stacks-block-height)
      (rentalDuration (- currentTime rentalStartTime))
      (actualCost (* RENTAL_FEE_PER_HOUR rentalDuration))
      (depositRefund (if (> BIKE_DEPOSIT actualCost) (- BIKE_DEPOSIT actualCost) u0))
    )
    (begin
      ;; Check if bike is rented by current user
      (asserts! (is-eq (unwrap-panic (get currentRenter bikeData)) tx-sender) err-bike-not-rented)
      
      ;; Update bike data
      (map-set BikeData { bikeId: bikeId }
               { 
                 isAvailable: true, 
                 currentRenter: none, 
                 rentalStartTime: none, 
                 totalRides: (get totalRides bikeData), 
                 lastMaintenance: (get lastMaintenance bikeData),
                 location: newLocation
               })
      
      ;; Update available bikes count
      (var-set available-bikes (+ (var-get available-bikes) u1))
      
      ;; Update user data
      (map-set UserRentals { user: tx-sender }
               { 
                 activeBikeId: none, 
                 totalRentals: (get totalRentals userData), 
                 totalSpent: (get totalSpent userData),
                 loyaltyPoints: (get loyaltyPoints userData)
               })
      
      ;; Refund deposit (minus actual rental cost)
      (if (> depositRefund u0)
          (begin
            (try! (as-contract (stx-transfer? depositRefund tx-sender tx-sender)))
            (print "Deposit refunded"))
          (print "No refund - rental cost exceeded deposit"))
      
      ;; Update maintenance log if notes provided
      (match maintenanceNotes
        notes (begin
                (map-set MaintenanceLog { bikeId: bikeId }
                         { 
                           lastMaintenanceDate: currentTime, 
                           maintenanceType: "User Report", 
                           cost: u0,
                           notes: notes
                         })
                true)
        true)
      
      ;; Check if bike needs maintenance after this ride
      (if (>= (get totalRides bikeData) (var-get maintenance-threshold))
          (begin
            (print "Bike marked for maintenance!")
            (map-set BikeData { bikeId: bikeId }
                     { 
                       isAvailable: false, 
                       currentRenter: none, 
                       rentalStartTime: none, 
                       totalRides: (get totalRides bikeData), 
                       lastMaintenance: currentTime,
                       location: newLocation
                     })
            (var-set available-bikes (- (var-get available-bikes) u1))
            true)
          (begin
            (print "Bike returned successfully")
            true))
      
      (ok { 
        bikeId: bikeId, 
        actualCost: actualCost, 
        depositRefund: depositRefund, 
        rentalDuration: rentalDuration,
        returnTime: currentTime
      })
    )
  )
)

;; Owner function to perform maintenance on a bike
(define-public (perform-maintenance (bikeId uint) (maintenanceType (string-ascii 50)) (cost uint) (notes (string-ascii 200)))
  (let ((bikeData (unwrap! (map-get? BikeData { bikeId: bikeId }) err-bike-not-available)))
    (begin
      (asserts! (is-eq tx-sender contract-owner) err-owner-only)
      
      ;; Update bike data - reset rides counter and mark as available
      (map-set BikeData { bikeId: bikeId }
               { 
                 isAvailable: true, 
                 currentRenter: none, 
                 rentalStartTime: none, 
                 totalRides: u0,  ;; Reset after maintenance
                 lastMaintenance: stacks-block-height,
                 location: (get location bikeData)
               })
      
      ;; Update maintenance log
      (map-set MaintenanceLog { bikeId: bikeId }
               { 
                 lastMaintenanceDate: stacks-block-height, 
                 maintenanceType: maintenanceType, 
                 cost: cost,
                 notes: notes
               })
      
      ;; Make bike available again if it wasn't
      (if (not (get isAvailable bikeData))
          (begin
            (var-set available-bikes (+ (var-get available-bikes) u1))
            (print "Bike is now available after maintenance"))
          (print "Bike was already available"))
      
      (ok true)
    )
  )
)

;; Read-only functions for getting system information
(define-read-only (get-bike-status (bikeId uint))
  (ok (map-get? BikeData { bikeId: bikeId })))

(define-read-only (get-user-rental-info (user principal))
  (ok (map-get? UserRentals { user: user })))

(define-read-only (get-system-stats)
  (ok { 
    totalBikes: (var-get total-bikes),
    availableBikes: (var-get available-bikes),
    totalRevenue: (var-get total-revenue),
    maintenanceThreshold: (var-get maintenance-threshold)
  }))

(define-read-only (get-maintenance-log (bikeId uint))
  (ok (map-get? MaintenanceLog { bikeId: bikeId })))

;; Get all available bikes (returns a filtered list - note: this is a simplified approach)
(define-read-only (get-available-bikes-count)
  (ok (var-get available-bikes)))