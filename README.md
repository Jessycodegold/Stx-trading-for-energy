# Energy Trading Smart Contract

A decentralized energy trading platform built on Stacks blockchain that enables energy producers to convert energy units into STX cryptocurrency and allows energy consumers to purchase energy using STX tokens with real-time price conversion.

## 📋 Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Contract Architecture](#contract-architecture)
- [Energy Types & Rates](#energy-types--rates)
- [Getting Started](#getting-started)
- [Usage Examples](#usage-examples)
- [API Reference](#api-reference)
- [Testing](#testing)
- [Deployment](#deployment)
- [Contributing](#contributing)

## 🌟 Overview

This smart contract facilitates peer-to-peer energy trading on the Stacks blockchain, connecting renewable energy producers with consumers through a transparent, decentralized marketplace. The platform supports multiple energy types including solar, wind, hydro, and geothermal energy.

### Key Benefits

- **Decentralized Trading**: No intermediaries in energy transactions
- **Multi-Energy Support**: Solar, wind, hydro, and geothermal energy types
- **Transparent Pricing**: Fixed conversion rates with minimal trading fees
- **Reputation System**: Track trading history and build trust
- **Real-time Conversion**: Instant energy-to-STX conversions

## ✨ Features

### For Energy Producers
- Register as verified energy producer
- Deposit energy units to the platform
- Convert energy directly to STX tokens
- Create energy trade listings
- Track sales history and reputation

### For Energy Consumers
- Register as energy consumer
- Deposit STX tokens to the platform
- Convert STX to energy units
- Purchase energy from active trades
- Track purchase history

### Platform Features
- Real-time energy-to-STX conversion rates
- Trading fee system (1% of transaction value)
- Trade expiration system (24 hours)
- Emergency controls for platform security
- Comprehensive analytics and statistics

## 🏗️ Contract Architecture

### Data Maps
- `user-energy-balances`: Tracks energy balances by user and energy type
- `user-stx-balances`: Tracks STX balances within the contract
- `energy-producers`: Registry of verified energy producers
- `energy-consumers`: Registry of energy consumers
- `active-trades`: Current active energy trade listings

### Key Variables
- `total-trades`: Total number of completed trades
- `total-energy-traded`: Total energy units traded
- `total-stx-volume`: Total STX volume traded
- `contract-stx-balance`: Contract's STX balance for fees
- `trading-enabled`: Global trading toggle

## ⚡ Energy Types & Rates

| Energy Type | Rate (STX per kWh) | Micro-STX Rate |
|-------------|-------------------|----------------|
| Solar       | 1.2               | 1,200,000      |
| Wind        | 1.1               | 1,100,000      |
| Hydro       | 1.3               | 1,300,000      |
| Geothermal  | 1.25              | 1,250,000      |

## 🚀 Getting Started

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) installed
- [Node.js](https://nodejs.org/) for testing
- Stacks wallet for deployment

### Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd stx-trading-for-energy
```

2. Install dependencies:
```bash
clarinet install
```

3. Check contract syntax:
```bash
clarinet check
```

4. Run tests:
```bash
clarinet test
```

## 💡 Usage Examples

### Producer Registration & Energy Deposit

```clarity
;; Register as producer
(contract-call? .energy-trading-contract register-as-producer (list "solar" "wind"))

;; Deposit energy units
(contract-call? .energy-trading-contract deposit-energy "solar" u1000)

;; Convert energy to STX
(contract-call? .energy-trading-contract convert-energy-to-stx "solar" u500)
```

### Consumer Registration & Energy Purchase

```clarity
;; Register as consumer
(contract-call? .energy-trading-contract register-as-consumer)

;; Deposit STX to contract
(contract-call? .energy-trading-contract deposit-stx u1000000)

;; Convert STX to energy
(contract-call? .energy-trading-contract convert-stx-to-energy "solar" u600000)
```

### Creating and Purchasing Trades

```clarity
;; Create trade listing (producer)
(contract-call? .energy-trading-contract create-trade "solar" u1000 u1200000)

;; Purchase energy from trade (consumer)
(contract-call? .energy-trading-contract purchase-energy u1)
```

## 📚 API Reference

### Public Functions

#### Producer Functions
- `register-as-producer(energy-types)` - Register as energy producer
- `deposit-energy(energy-type, amount)` - Deposit energy units
- `convert-energy-to-stx(energy-type, energy-amount)` - Convert energy to STX
- `create-trade(energy-type, energy-amount, stx-price)` - Create trade listing
- `cancel-trade(trade-id)` - Cancel active trade

#### Consumer Functions
- `register-as-consumer()` - Register as energy consumer
- `deposit-stx(amount)` - Deposit STX to contract
- `convert-stx-to-energy(energy-type, stx-amount)` - Convert STX to energy
- `purchase-energy(trade-id)` - Purchase energy from trade

#### General Functions
- `withdraw-stx(amount)` - Withdraw STX from contract
- `batch-deposit-energy(energy-type, amount)` - Batch deposit energy

#### Admin Functions
- `toggle-trading()` - Toggle platform trading
- `set-min-trade-amount(new-amount)` - Set minimum trade amount
- `withdraw-contract-fees(amount)` - Withdraw platform fees
- `emergency-pause()` - Emergency trading pause

### Read-Only Functions

#### Balance Queries
- `get-energy-balance(user, energy-type)` - Get user's energy balance
- `get-stx-balance(user)` - Get user's STX balance
- `get-conversion-rate(energy-type)` - Get energy conversion rate

#### Trade Information
- `get-trade-details(trade-id)` - Get trade details
- `get-active-trade(trade-id)` - Get active trade info
- `preview-energy-to-stx(energy-type, energy-amount)` - Preview conversion
- `preview-stx-to-energy(energy-type, stx-amount)` - Preview reverse conversion

#### User Information
- `get-producer-info(producer)` - Get producer information
- `get-consumer-info(consumer)` - Get consumer information
- `get-user-trading-summary(user)` - Get user trading summary

#### Platform Statistics
- `get-contract-stats()` - Get contract statistics
- `get-trading-statistics()` - Get trading statistics
- `get-platform-health()` - Get platform health metrics

### Error Codes

| Code | Constant | Description |
|------|----------|-------------|
| 100  | ERR_NOT_AUTHORIZED | Not authorized to perform action |
| 101  | ERR_INSUFFICIENT_BALANCE | Insufficient STX balance |
| 102  | ERR_INSUFFICIENT_ENERGY | Insufficient energy balance |
| 103  | ERR_INVALID_AMOUNT | Invalid amount provided |
| 104  | ERR_USER_NOT_FOUND | User not found in registry |
| 105  | ERR_INVALID_RATE | Invalid conversion rate |
| 106  | ERR_TRADE_NOT_FOUND | Trade not found |
| 107  | ERR_TRADE_EXPIRED | Trade has expired |
| 108  | ERR_ALREADY_PROCESSED | Trade already processed |

## 🧪 Testing

Run the test suite:

```bash
clarinet test
```

### Test Coverage
- Producer registration and energy deposits
- Consumer registration and STX deposits
- Energy-to-STX conversions
- STX-to-energy conversions
- Trade creation and execution
- Error handling and edge cases
- Admin functions
- Read-only function validation

## 📦 Deployment

### Testnet Deployment

1. Configure your deployment settings in `settings/Devnet.toml`
2. Deploy the contract:
```bash
clarinet deploy --testnet
```

### Mainnet Deployment

1. Configure mainnet settings
2. Deploy with proper security measures:
```bash
clarinet deploy --mainnet
```

## 🔧 Configuration

### Contract Constants
- `SOLAR_RATE`: 1,200,000 micro-STX per kWh
- `WIND_RATE`: 1,100,000 micro-STX per kWh  
- `HYDRO_RATE`: 1,300,000 micro-STX per kWh
- `GEOTHERMAL_RATE`: 1,250,000 micro-STX per kWh
- `TRADING_FEE_BASIS_POINTS`: 100 (1%)
- `TRADE_EXPIRY_BLOCKS`: 144 (~24 hours)

### Customization
These rates can be adjusted by modifying the constants in the contract and redeploying.

## 📊 Analytics

The contract provides comprehensive analytics including:
- Total trades executed
- Total energy traded (kWh)
- Total STX volume
- Average trade size
- User reputation scores
- Platform health metrics

## 🔒 Security Features

- **Access Control**: Producer/consumer registration required
- **Balance Validation**: Sufficient balance checks
- **Trade Expiration**: Automatic trade expiry
- **Emergency Controls**: Admin emergency pause functionality
- **Fee Management**: Transparent fee structure
- **Data Validation**: Input validation for all parameters

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

### Development Guidelines
- Follow Clarity best practices
- Add comprehensive tests
- Update documentation
- Maintain backward compatibility

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 📞 Support

For support and questions:
- Open an issue on GitHub
- Contact the development team
- Check the documentation wiki

## 🗺️ Roadmap

### Future Enhancements
- [ ] Multi-signature admin controls
- [ ] Advanced trading algorithms
- [ ] Energy storage contracts
- [ ] Carbon credit integration
- [ ] Mobile app integration
- [ ] Advanced analytics dashboard
- [ ] Automated energy matching
- [ ] Integration with IoT devices

---

**Built with ❤️ for the decentralized energy future**
