;; energy-trading-contract
;; A decentralized energy trading platform that allows energy producers to convert
;; energy units into cryptocurrency tokens (STX) and enables energy consumers to
;; purchase energy using STX tokens with real-time price conversion.

;; constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_INSUFFICIENT_BALANCE (err u101))
(define-constant ERR_INSUFFICIENT_ENERGY (err u102))
(define-constant ERR_INVALID_AMOUNT (err u103))
(define-constant ERR_USER_NOT_FOUND (err u104))
(define-constant ERR_INVALID_RATE (err u105))
(define-constant ERR_TRADE_NOT_FOUND (err u106))
(define-constant ERR_TRADE_EXPIRED (err u107))
(define-constant ERR_ALREADY_PROCESSED (err u108))

;; Energy unit to STX conversion rates (in micro STX per kWh)
(define-constant SOLAR_RATE u1200000) ;; 1.2 STX per kWh
(define-constant WIND_RATE u1100000)  ;; 1.1 STX per kWh
(define-constant HYDRO_RATE u1300000) ;; 1.3 STX per kWh
(define-constant GEOTHERMAL_RATE u1250000) ;; 1.25 STX per kWh

;; Trading fee (1% = 100 basis points)
(define-constant TRADING_FEE_BASIS_POINTS u100)
(define-constant BASIS_POINTS_DIVISOR u10000)

;; Time constants (blocks)
(define-constant TRADE_EXPIRY_BLOCKS u144) ;; ~24 hours

;; data maps and vars
;; User energy balances by energy type
(define-map user-energy-balances 
    {user: principal, energy-type: (string-ascii 20)} 
    {balance: uint})

;; User STX balances in the contract
(define-map user-stx-balances principal uint)

;; Energy producer registry
(define-map energy-producers principal 
    {
        is-verified: bool,
        energy-types: (list 10 (string-ascii 20)),
        total-energy-sold: uint,
        reputation-score: uint
    })

;; Energy consumer registry  
(define-map energy-consumers principal
    {
        total-energy-purchased: uint,
        preferred-energy-types: (list 5 (string-ascii 20)),
        reputation-score: uint
    })

;; Active trades
(define-map active-trades uint
    {
        seller: principal,
        buyer: (optional principal),
        energy-type: (string-ascii 20),
        energy-amount: uint,
        stx-price: uint,
        created-at: uint,
        expires-at: uint,
        is-completed: bool
    })

;; Contract statistics
(define-data-var total-trades uint u0)
(define-data-var total-energy-traded uint u0)
(define-data-var total-stx-volume uint u0)
(define-data-var contract-stx-balance uint u0)
(define-data-var current-trade-id uint u0)

;; Admin settings
(define-data-var trading-enabled bool true)
(define-data-var min-trade-amount uint u100) ;; Minimum 1 kWh in units

;; private functions

;; Calculate STX amount for energy conversion
(define-private (calculate-stx-amount (energy-type (string-ascii 20)) (energy-amount uint))
    (let ((rate (get-energy-rate energy-type)))
        (/ (* energy-amount rate) u1000))) ;; Convert from kWh to STX (rate is in micro-STX)

;; Get energy rate by type
(define-private (get-energy-rate (energy-type (string-ascii 20)))
    (if (is-eq energy-type "solar")
        SOLAR_RATE
        (if (is-eq energy-type "wind")
            WIND_RATE
            (if (is-eq energy-type "hydro")
                HYDRO_RATE
                (if (is-eq energy-type "geothermal")
                    GEOTHERMAL_RATE
                    u1000000))))) ;; Default rate 1 STX per kWh

;; Calculate trading fee
(define-private (calculate-trading-fee (amount uint))
    (/ (* amount TRADING_FEE_BASIS_POINTS) BASIS_POINTS_DIVISOR))

;; Validate energy type
(define-private (is-valid-energy-type (energy-type (string-ascii 20)))
    (or (is-eq energy-type "solar")
        (or (is-eq energy-type "wind")
            (or (is-eq energy-type "hydro")
                (is-eq energy-type "geothermal")))))

;; Get user energy balance
(define-private (get-user-energy-balance (user principal) (energy-type (string-ascii 20)))
    (default-to u0 (get balance (map-get? user-energy-balances {user: user, energy-type: energy-type}))))

;; Get user STX balance
(define-private (get-user-stx-balance (user principal))
    (default-to u0 (map-get? user-stx-balances user)))

;; Update user energy balance
(define-private (update-user-energy-balance (user principal) (energy-type (string-ascii 20)) (new-balance uint))
    (map-set user-energy-balances 
        {user: user, energy-type: energy-type} 
        {balance: new-balance}))

;; Update user STX balance
(define-private (update-user-stx-balance (user principal) (new-balance uint))
    (map-set user-stx-balances user new-balance))

;; Check if user is authorized producer
(define-private (is-authorized-producer (user principal))
    (match (map-get? energy-producers user)
        producer (get is-verified producer)
        false))

;; Update producer stats
(define-private (update-producer-stats (producer principal) (energy-amount uint))
    (match (map-get? energy-producers producer)
        existing-producer
        (let ((new-total (+ (get total-energy-sold existing-producer) energy-amount))
              (new-reputation (+ (get reputation-score existing-producer) u1)))
            (map-set energy-producers producer
                (merge existing-producer 
                    {total-energy-sold: new-total, 
                     reputation-score: new-reputation})))
        (ok true)))

;; Update consumer stats  
(define-private (update-consumer-stats (consumer principal) (energy-amount uint))
    (match (map-get? energy-consumers consumer)
        existing-consumer
        (let ((new-total (+ (get total-energy-purchased existing-consumer) energy-amount))
              (new-reputation (+ (get reputation-score existing-consumer) u1)))
            (map-set energy-consumers consumer
                (merge existing-consumer
                    {total-energy-purchased: new-total,
                     reputation-score: new-reputation})))
        ;; Create new consumer record
        (map-set energy-consumers consumer
            {total-energy-purchased: energy-amount,
             preferred-energy-types: (list),
             reputation-score: u1})))

;; Generate new trade ID
(define-private (get-next-trade-id)
    (let ((current-id (var-get current-trade-id)))
        (var-set current-trade-id (+ current-id u1))
        (+ current-id u1)))

;; Check if trade is expired
(define-private (is-trade-expired (trade-id uint))
    (match (map-get? active-trades trade-id)
        trade (>= block-height (get expires-at trade))
        true))

;; Validate trade amount
(define-private (is-valid-trade-amount (amount uint))
    (>= amount (var-get min-trade-amount)))

;; Transfer STX from contract to user
(define-private (transfer-stx-to-user (recipient principal) (amount uint))
    (as-contract (stx-transfer? amount tx-sender recipient)))

;; Transfer STX from user to contract
(define-private (transfer-stx-from-user (sender principal) (amount uint))
    (stx-transfer? amount sender (as-contract tx-sender)))
