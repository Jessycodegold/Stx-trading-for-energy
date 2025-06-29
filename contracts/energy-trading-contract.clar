
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
