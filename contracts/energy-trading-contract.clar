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
    (let ((rate (if (is-eq energy-type "solar")
                    SOLAR_RATE
                    (if (is-eq energy-type "wind")
                        WIND_RATE
                        (if (is-eq energy-type "hydro")
                            HYDRO_RATE
                            (if (is-eq energy-type "geothermal")
                                GEOTHERMAL_RATE
                                u1000000)))))) ;; Default rate 1 STX per kWh
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
                     reputation-score: new-reputation}))
            true)
        false))

;; Update consumer stats  
(define-private (update-consumer-stats (consumer principal) (energy-amount uint))
    (match (map-get? energy-consumers consumer)
        existing-consumer
        (let ((new-total (+ (get total-energy-purchased existing-consumer) energy-amount))
              (new-reputation (+ (get reputation-score existing-consumer) u1)))
            (map-set energy-consumers consumer
                (merge existing-consumer
                    {total-energy-purchased: new-total,
                     reputation-score: new-reputation}))
            true)
        ;; Create new consumer record
        (begin
            (map-set energy-consumers consumer
                {total-energy-purchased: energy-amount,
                 preferred-energy-types: (list),
                 reputation-score: u1})
            true)))

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

;; public functions

;; Register as energy producer
(define-public (register-as-producer (energy-types (list 10 (string-ascii 20))))
    (let ((caller tx-sender))
        (asserts! (> (len energy-types) u0) ERR_INVALID_AMOUNT)
        (map-set energy-producers caller
            {is-verified: true,
             energy-types: energy-types,
             total-energy-sold: u0,
             reputation-score: u0})
        (ok true)))

;; Register as energy consumer
(define-public (register-as-consumer)
    (let ((caller tx-sender))
        (map-set energy-consumers caller
            {total-energy-purchased: u0,
             preferred-energy-types: (list),
             reputation-score: u0})
        (ok true)))

;; Deposit energy units (for producers)
(define-public (deposit-energy (energy-type (string-ascii 20)) (amount uint))
    (let ((caller tx-sender)
          (current-balance (get-user-energy-balance caller energy-type)))
        (asserts! (is-valid-energy-type energy-type) ERR_INVALID_AMOUNT)
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (is-authorized-producer caller) ERR_NOT_AUTHORIZED)
        (update-user-energy-balance caller energy-type (+ current-balance amount))
        (ok true)))

;; Convert energy to STX (for producers)
(define-public (convert-energy-to-stx (energy-type (string-ascii 20)) (energy-amount uint))
    (let ((caller tx-sender)
          (current-energy-balance (get-user-energy-balance caller energy-type))
          (current-stx-balance (get-user-stx-balance caller))
          (stx-amount (calculate-stx-amount energy-type energy-amount))
          (trading-fee (calculate-trading-fee stx-amount))
          (net-stx-amount (- stx-amount trading-fee)))
        (asserts! (var-get trading-enabled) ERR_NOT_AUTHORIZED)
        (asserts! (is-valid-energy-type energy-type) ERR_INVALID_AMOUNT)
        (asserts! (>= current-energy-balance energy-amount) ERR_INSUFFICIENT_ENERGY)
        (asserts! (> energy-amount u0) ERR_INVALID_AMOUNT)
        (asserts! (is-authorized-producer caller) ERR_NOT_AUTHORIZED)
        
        ;; Update balances
        (update-user-energy-balance caller energy-type (- current-energy-balance energy-amount))
        (update-user-stx-balance caller (+ current-stx-balance net-stx-amount))
        
        ;; Update contract stats
        (var-set total-energy-traded (+ (var-get total-energy-traded) energy-amount))
        (var-set total-stx-volume (+ (var-get total-stx-volume) stx-amount))
        (var-set contract-stx-balance (+ (var-get contract-stx-balance) trading-fee))
        
        ;; Update producer stats
        (update-producer-stats caller energy-amount)
        
        (ok {stx-received: net-stx-amount, trading-fee: trading-fee})))

;; Deposit STX to contract (for consumers)
(define-public (deposit-stx (amount uint))
    (let ((caller tx-sender)
          (current-balance (get-user-stx-balance caller)))
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (try! (transfer-stx-from-user caller amount))
        (update-user-stx-balance caller (+ current-balance amount))
        (var-set contract-stx-balance (+ (var-get contract-stx-balance) amount))
        (ok true)))

;; Convert STX to energy (for consumers)
(define-public (convert-stx-to-energy (energy-type (string-ascii 20)) (stx-amount uint))
    (let ((caller tx-sender)
          (current-stx-balance (get-user-stx-balance caller))
          (current-energy-balance (get-user-energy-balance caller energy-type))
          (energy-rate (get-energy-rate energy-type))
          (energy-amount (/ (* stx-amount u1000) energy-rate)) ;; Convert STX to kWh
          (trading-fee (calculate-trading-fee stx-amount))
          (total-stx-needed (+ stx-amount trading-fee)))
        (asserts! (var-get trading-enabled) ERR_NOT_AUTHORIZED)
        (asserts! (is-valid-energy-type energy-type) ERR_INVALID_AMOUNT)
        (asserts! (>= current-stx-balance total-stx-needed) ERR_INSUFFICIENT_BALANCE)
        (asserts! (> stx-amount u0) ERR_INVALID_AMOUNT)
        
        ;; Update balances
        (update-user-stx-balance caller (- current-stx-balance total-stx-needed))
        (update-user-energy-balance caller energy-type (+ current-energy-balance energy-amount))
        
        ;; Update contract stats
        (var-set total-energy-traded (+ (var-get total-energy-traded) energy-amount))
        (var-set total-stx-volume (+ (var-get total-stx-volume) stx-amount))
        (var-set contract-stx-balance (+ (var-get contract-stx-balance) trading-fee))
        
        ;; Update consumer stats
        (update-consumer-stats caller energy-amount)
        
        (ok {energy-received: energy-amount, trading-fee: trading-fee})))

;; Create energy trade listing
(define-public (create-trade (energy-type (string-ascii 20)) (energy-amount uint) (stx-price uint))
    (let ((caller tx-sender)
          (current-energy-balance (get-user-energy-balance caller energy-type))
          (trade-id (get-next-trade-id))
          (expires-at (+ block-height TRADE_EXPIRY_BLOCKS)))
        (asserts! (var-get trading-enabled) ERR_NOT_AUTHORIZED)
        (asserts! (is-valid-energy-type energy-type) ERR_INVALID_AMOUNT)
        (asserts! (is-valid-trade-amount energy-amount) ERR_INVALID_AMOUNT)
        (asserts! (>= current-energy-balance energy-amount) ERR_INSUFFICIENT_ENERGY)
        (asserts! (> stx-price u0) ERR_INVALID_AMOUNT)
        (asserts! (is-authorized-producer caller) ERR_NOT_AUTHORIZED)
        
        ;; Lock energy for trade
        (update-user-energy-balance caller energy-type (- current-energy-balance energy-amount))
        
        ;; Create trade record
        (map-set active-trades trade-id
            {seller: caller,
             buyer: none,
             energy-type: energy-type,
             energy-amount: energy-amount,
             stx-price: stx-price,
             created-at: block-height,
             expires-at: expires-at,
             is-completed: false})
        
        (ok trade-id)))

;; Purchase energy from trade listing
(define-public (purchase-energy (trade-id uint))
    (let ((caller tx-sender)
          (current-stx-balance (get-user-stx-balance caller)))
        (asserts! (var-get trading-enabled) ERR_NOT_AUTHORIZED)
        (match (map-get? active-trades trade-id)
            trade
            (let ((stx-price (get stx-price trade))
                  (energy-amount (get energy-amount trade))
                  (energy-type (get energy-type trade))
                  (seller (get seller trade))
                  (trading-fee (calculate-trading-fee stx-price))
                  (total-stx-needed (+ stx-price trading-fee))
                  (seller-stx-balance (get-user-stx-balance seller))
                  (buyer-energy-balance (get-user-energy-balance caller energy-type)))
                (asserts! (not (get is-completed trade)) ERR_ALREADY_PROCESSED)
                (asserts! (not (is-trade-expired trade-id)) ERR_TRADE_EXPIRED)
                (asserts! (not (is-eq caller seller)) ERR_NOT_AUTHORIZED)
                (asserts! (>= current-stx-balance total-stx-needed) ERR_INSUFFICIENT_BALANCE)
                
                ;; Transfer STX from buyer to seller
                (update-user-stx-balance caller (- current-stx-balance total-stx-needed))
                (update-user-stx-balance seller (+ seller-stx-balance stx-price))
                
                ;; Transfer energy to buyer
                (update-user-energy-balance caller energy-type (+ buyer-energy-balance energy-amount))
                
                ;; Mark trade as completed
                (map-set active-trades trade-id (merge trade {buyer: (some caller), is-completed: true}))
                
                ;; Update contract stats
                (var-set total-trades (+ (var-get total-trades) u1))
                (var-set total-energy-traded (+ (var-get total-energy-traded) energy-amount))
                (var-set total-stx-volume (+ (var-get total-stx-volume) stx-price))
                (var-set contract-stx-balance (+ (var-get contract-stx-balance) trading-fee))
                
                ;; Update user stats
                (update-producer-stats seller energy-amount)
                (update-consumer-stats caller energy-amount)
                
                (ok true))
            ERR_TRADE_NOT_FOUND)))

;; Withdraw STX from contract
(define-public (withdraw-stx (amount uint))
    (let ((caller tx-sender)
          (current-balance (get-user-stx-balance caller)))
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (>= current-balance amount) ERR_INSUFFICIENT_BALANCE)
        (try! (transfer-stx-to-user caller amount))
        (update-user-stx-balance caller (- current-balance amount))
        (var-set contract-stx-balance (- (var-get contract-stx-balance) amount))
        (ok true)))

;; Cancel active trade
(define-public (cancel-trade (trade-id uint))
    (let ((caller tx-sender))
        (match (map-get? active-trades trade-id)
            trade
            (let ((seller (get seller trade))
                  (energy-amount (get energy-amount trade))
                  (energy-type (get energy-type trade))
                  (seller-energy-balance (get-user-energy-balance seller energy-type)))
                (asserts! (is-eq caller seller) ERR_NOT_AUTHORIZED)
                (asserts! (not (get is-completed trade)) ERR_ALREADY_PROCESSED)
                
                ;; Return energy to seller
                (update-user-energy-balance seller energy-type (+ seller-energy-balance energy-amount))
                
                ;; Mark trade as cancelled by updating the record
                (map-set active-trades trade-id
                    {seller: (get seller trade),
                     buyer: (get buyer trade),
                     energy-type: (get energy-type trade),
                     energy-amount: (get energy-amount trade),
                     stx-price: (get stx-price trade),
                     created-at: (get created-at trade),
                     expires-at: (get expires-at trade),
                     is-completed: true})
                
                (ok true))
            ERR_TRADE_NOT_FOUND)))

;; Admin function to toggle trading
(define-public (toggle-trading)
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (var-set trading-enabled (not (var-get trading-enabled)))
        (ok (var-get trading-enabled))))

;; Admin function to set minimum trade amount
(define-public (set-min-trade-amount (new-amount uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (> new-amount u0) ERR_INVALID_AMOUNT)
        (var-set min-trade-amount new-amount)
        (ok true)))

;; Admin function to withdraw contract fees
(define-public (withdraw-contract-fees (amount uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (>= (var-get contract-stx-balance) amount) ERR_INSUFFICIENT_BALANCE)
        (try! (transfer-stx-to-user CONTRACT_OWNER amount))
        (var-set contract-stx-balance (- (var-get contract-stx-balance) amount))
        (ok true)))

;; Batch energy deposit for producers (simplified)
(define-public (batch-deposit-energy (energy-type (string-ascii 20)) (amount uint))
    (let ((caller tx-sender)
          (current-balance (get-user-energy-balance caller energy-type)))
        (asserts! (is-authorized-producer caller) ERR_NOT_AUTHORIZED)
        (asserts! (is-valid-energy-type energy-type) ERR_INVALID_AMOUNT)
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (update-user-energy-balance caller energy-type (+ current-balance amount))
        (ok true)))

;; Emergency function to pause all trading
(define-public (emergency-pause)
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (var-set trading-enabled false)
        (ok true)))

;; Read-only functions

;; Get user's energy balance
(define-read-only (get-energy-balance (user principal) (energy-type (string-ascii 20)))
    (get-user-energy-balance user energy-type))

;; Get user's STX balance in contract
(define-read-only (get-stx-balance (user principal))
    (get-user-stx-balance user))

;; Get energy conversion rate
(define-read-only (get-conversion-rate (energy-type (string-ascii 20)))
    (get-energy-rate energy-type))

;; Get trade details
(define-read-only (get-trade-details (trade-id uint))
    (map-get? active-trades trade-id))

;; Get producer information
(define-read-only (get-producer-info (producer principal))
    (map-get? energy-producers producer))

;; Get consumer information
(define-read-only (get-consumer-info (consumer principal))
    (map-get? energy-consumers consumer))

;; Get contract statistics
(define-read-only (get-contract-stats)
    {total-trades: (var-get total-trades),
     total-energy-traded: (var-get total-energy-traded),
     total-stx-volume: (var-get total-stx-volume),
     contract-stx-balance: (var-get contract-stx-balance),
     trading-enabled: (var-get trading-enabled),
     min-trade-amount: (var-get min-trade-amount)})

;; Calculate conversion preview
(define-read-only (preview-energy-to-stx (energy-type (string-ascii 20)) (energy-amount uint))
    (let ((stx-amount (calculate-stx-amount energy-type energy-amount))
          (trading-fee (calculate-trading-fee stx-amount)))
        {gross-stx: stx-amount,
         trading-fee: trading-fee,
         net-stx: (- stx-amount trading-fee)}))

;; Calculate reverse conversion preview
(define-read-only (preview-stx-to-energy (energy-type (string-ascii 20)) (stx-amount uint))
    (let ((energy-rate (get-energy-rate energy-type))
          (energy-amount (/ (* stx-amount u1000) energy-rate))
          (trading-fee (calculate-trading-fee stx-amount)))
        {energy-amount: energy-amount,
         trading-fee: trading-fee,
         total-stx-cost: (+ stx-amount trading-fee)}))

;; Get specific active trade by ID
(define-read-only (get-active-trade (trade-id uint))
    (match (map-get? active-trades trade-id)
        trade (if (and (not (get is-completed trade)) (not (is-trade-expired trade-id)))
                  (some trade)
                  none)
        none))

;; Get simplified trading statistics
(define-read-only (get-trading-statistics)
    {current-trade-id: (var-get current-trade-id),
     total-completed-trades: (var-get total-trades),
     total-energy-traded: (var-get total-energy-traded),
     total-stx-volume: (var-get total-stx-volume)})

;; Get user's trading history summary
(define-read-only (get-user-trading-summary (user principal))
    (let ((producer-info (map-get? energy-producers user))
          (consumer-info (map-get? energy-consumers user)))
        {producer-stats: producer-info,
         consumer-stats: consumer-info,
         stx-balance: (get-user-stx-balance user)}))

;; Validate multiple energy types
(define-read-only (validate-energy-types (energy-types (list 10 (string-ascii 20))))
    (fold validate-energy-type energy-types true))

;; Helper function to validate energy type
(define-private (validate-energy-type (energy-type (string-ascii 20)) (acc bool))
    (and acc (is-valid-energy-type energy-type)))

;; Get platform health metrics
(define-read-only (get-platform-health)
    {active-producers: (var-get total-trades), ;; Simplified metric
     active-consumers: (var-get total-trades), ;; Simplified metric
     total-energy-traded: (var-get total-energy-traded),
     total-stx-volume: (var-get total-stx-volume),
     average-trade-size: (if (> (var-get total-trades) u0)
                           (/ (var-get total-energy-traded) (var-get total-trades))
                           u0),
     contract-version: "1.0.0"})
