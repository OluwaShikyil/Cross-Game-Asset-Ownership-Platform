(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-listed (err u102))
(define-constant err-invalid-price (err u103))
(define-constant err-asset-locked (err u104))
(define-constant err-unauthorized (err u105))
(define-constant err-rental-not-found (err u106))
(define-constant err-rental-expired (err u107))
(define-constant err-rental-active (err u108))
(define-constant err-invalid-duration (err u109))

(define-non-fungible-token game-asset uint)

(define-map asset-details
  { asset-id: uint }
  {
    name: (string-ascii 50),
    game-id: (string-ascii 50),
    asset-type: (string-ascii 20),
    creator: principal,
    current-owner: principal,
    is-locked: bool,
    created-at: uint
  }
)

(define-map marketplace-listings
  { asset-id: uint }
  {
    price: uint,
    seller: principal,
    listed-at: uint
  }
)

(define-map supported-games
  { game-id: (string-ascii 50) }
  {
    name: (string-ascii 50),
    is-active: bool,
    integration-date: uint
  }
)

(define-data-var last-asset-id uint u0)
(define-data-var platform-fee uint u25)

(define-map rental-listings
  { asset-id: uint }
  {
    daily-rate: uint,
    max-duration: uint,
    owner: principal,
    listed-at: uint
  }
)

(define-map active-rentals
  { asset-id: uint }
  {
    renter: principal,
    start-block: uint,
    end-block: uint,
    daily-rate: uint
  }
)

(define-public (mint-game-asset (name (string-ascii 50)) (game-id (string-ascii 50)) (asset-type (string-ascii 20)))
  (let
    (
      (asset-id (+ (var-get last-asset-id) u1))
      (owner tx-sender)
    )
    (try! (nft-mint? game-asset asset-id tx-sender))
    (map-set asset-details
      { asset-id: asset-id }
      {
        name: name,
        game-id: game-id,
        asset-type: asset-type,
        creator: owner,
        current-owner: owner,
        is-locked: false,
        created-at: burn-block-height
      }
    )
    (var-set last-asset-id asset-id)
    (ok asset-id)
  )
)

(define-public (transfer-asset (asset-id uint) (recipient principal))
  (let
    (
      (asset-info (unwrap! (map-get? asset-details { asset-id: asset-id }) err-not-found))
      (sender tx-sender)
    )
    (asserts! (is-eq (get current-owner asset-info) sender) err-unauthorized)
    (asserts! (not (get is-locked asset-info)) err-asset-locked)
    (try! (nft-transfer? game-asset asset-id sender recipient))
    (map-set asset-details
      { asset-id: asset-id }
      (merge asset-info { current-owner: recipient })
    )
    (ok true)
  )
)

(define-public (list-asset (asset-id uint) (price uint))
  (let
    (
      (asset-info (unwrap! (map-get? asset-details { asset-id: asset-id }) err-not-found))
      (sender tx-sender)
    )
    (asserts! (> price u0) err-invalid-price)
    (asserts! (is-eq (get current-owner asset-info) sender) err-unauthorized)
    (asserts! (not (get is-locked asset-info)) err-asset-locked)
    (map-set marketplace-listings
      { asset-id: asset-id }
      {
        price: price,
        seller: sender,
        listed-at: burn-block-height
      }
    )
    (ok true)
  )
)

(define-public (unlist-asset (asset-id uint))
  (let
    (
      (listing (unwrap! (map-get? marketplace-listings { asset-id: asset-id }) err-not-found))
      (sender tx-sender)
    )
    (asserts! (is-eq (get seller listing) sender) err-unauthorized)
    (map-delete marketplace-listings { asset-id: asset-id })
    (ok true)
  )
)

(define-public (purchase-asset (asset-id uint))
  (let
    (
      (listing (unwrap! (map-get? marketplace-listings { asset-id: asset-id }) err-not-found))
      (buyer tx-sender)
      (price (get price listing))
      (seller (get seller listing))
    )
    (try! (nft-transfer? game-asset asset-id seller buyer))
    (map-set asset-details
      { asset-id: asset-id }
      (merge (unwrap-panic (map-get? asset-details { asset-id: asset-id })) { current-owner: buyer })
    )
    (let 
      (
        (platform-fee-amount (/ (* price (var-get platform-fee)) u1000))
        (seller-amount (- price platform-fee-amount))
      )
      (try! (stx-transfer? platform-fee-amount buyer contract-owner))
      (try! (stx-transfer? seller-amount buyer seller))
    )
    (map-delete marketplace-listings { asset-id: asset-id })
    (ok true)
  )
)

(define-public (toggle-asset-lock (asset-id uint))
  (let
    (
      (asset-info (unwrap! (map-get? asset-details { asset-id: asset-id }) err-not-found))
      (sender tx-sender)
    )
    (asserts! (is-eq (get current-owner asset-info) sender) err-unauthorized)
    (map-set asset-details
      { asset-id: asset-id }
      (merge asset-info { is-locked: (not (get is-locked asset-info)) })
    )
    (ok true)
  )
)

(define-public (list-asset-for-rent (asset-id uint) (daily-rate uint) (max-duration uint))
  (let
    (
      (asset-info (unwrap! (map-get? asset-details { asset-id: asset-id }) err-not-found))
      (sender tx-sender)
    )
    (asserts! (> daily-rate u0) err-invalid-price)
    (asserts! (> max-duration u0) err-invalid-duration)
    (asserts! (is-eq (get current-owner asset-info) sender) err-unauthorized)
    (asserts! (not (get is-locked asset-info)) err-asset-locked)
    (asserts! (is-none (map-get? active-rentals { asset-id: asset-id })) err-rental-active)
    (map-set rental-listings
      { asset-id: asset-id }
      {
        daily-rate: daily-rate,
        max-duration: max-duration,
        owner: sender,
        listed-at: burn-block-height
      }
    )
    (ok true)
  )
)

(define-public (unlist-rental (asset-id uint))
  (let
    (
      (listing (unwrap! (map-get? rental-listings { asset-id: asset-id }) err-rental-not-found))
      (sender tx-sender)
    )
    (asserts! (is-eq (get owner listing) sender) err-unauthorized)
    (map-delete rental-listings { asset-id: asset-id })
    (ok true)
  )
)

(define-public (rent-asset (asset-id uint) (duration uint))
  (let
    (
      (listing (unwrap! (map-get? rental-listings { asset-id: asset-id }) err-rental-not-found))
      (renter tx-sender)
      (daily-rate (get daily-rate listing))
      (owner (get owner listing))
      (end-block (+ burn-block-height (* duration u144)))
      (total-cost (* daily-rate duration))
    )
    (asserts! (> duration u0) err-invalid-duration)
    (asserts! (<= duration (get max-duration listing)) err-invalid-duration)
    (asserts! (is-none (map-get? active-rentals { asset-id: asset-id })) err-rental-active)
    (let
      (
        (platform-fee-amount (/ (* total-cost (var-get platform-fee)) u1000))
        (owner-amount (- total-cost platform-fee-amount))
      )
      (try! (stx-transfer? platform-fee-amount renter contract-owner))
      (try! (stx-transfer? owner-amount renter owner))
    )
    (map-set active-rentals
      { asset-id: asset-id }
      {
        renter: renter,
        start-block: burn-block-height,
        end-block: end-block,
        daily-rate: daily-rate
      }
    )
    (ok true)
  )
)

(define-public (terminate-rental (asset-id uint))
  (let
    (
      (rental (unwrap! (map-get? active-rentals { asset-id: asset-id }) err-rental-not-found))
      (sender tx-sender)
    )
    (asserts! (or 
      (is-eq sender (get renter rental))
      (>= burn-block-height (get end-block rental))
    ) err-unauthorized)
    (map-delete active-rentals { asset-id: asset-id })
    (ok true)
  )
)

(define-read-only (get-rental-status (asset-id uint))
  (match (map-get? active-rentals { asset-id: asset-id })
    rental
      (if (>= burn-block-height (get end-block rental))
        (ok { status: "expired", rental: (some rental) })
        (ok { status: "active", rental: (some rental) })
      )
    (ok { status: "available", rental: none })
  )
)

(define-read-only (get-rental-listing (asset-id uint))
  (ok (map-get? rental-listings { asset-id: asset-id }))
)

(define-read-only (is-rented-by (asset-id uint) (user principal))
  (match (map-get? active-rentals { asset-id: asset-id })
    rental
      (and 
        (is-eq (get renter rental) user)
        (< burn-block-height (get end-block rental))
      )
    false
  )
)