# Security & Authorization Documentation

## Overview

The AgriSensorData smart contract implements role-based access control (RBAC) to ensure that only authorized entities can perform sensitive operations. All authorization rules are enforced on-chain via OpenZeppelin's AccessControl module.

---

## Authorization Model

### Role Definitions

The contract defines five roles with distinct permissions:

| Role | Purpose | Key Permissions |
|------|---------|-----------------|
| `DEFAULT_ADMIN_ROLE` | System administrator | Grant/revoke all roles, full contract control |
| `DEVICE_ROLE` | IoT sensors and gateways | Submit sensor readings (single + batch) |
| `FARMER_ROLE` | Farm operators | Record crop lifecycle events (seed, fertilize, harvest) |
| `RESEARCHER_ROLE` | Data analysts | Read access to historical data (future: restricted queries) |
| `SUPPLY_CHAIN_ROLE` | Logistics providers | Record supply chain stages (transport, storage, retail) |

### Role Assignment

- **Deployer receives all roles** upon contract deployment (constructor)
- **Admin can grant roles** to new addresses via `grantRole(bytes32 role, address account)`
- **Admin can revoke roles** via `revokeRole(bytes32 role, address account)`
- **Non-admins cannot grant/revoke roles** (enforced by AccessControl)

---

## Enforced Authorization Rules

### 1. Sensor Data Submission
```solidity
function submitSensorData(...) external onlyRole(DEVICE_ROLE)
function submitBatch(...) external onlyRole(DEVICE_ROLE)
```
- **Rule**: Only addresses with `DEVICE_ROLE` can submit sensor readings
- **Enforcement**: On-chain via modifier
- **Test Coverage**: `test_RevertUnauthorizedDevice()`

### 2. Crop Event Recording
```solidity
function recordCropEvent(...) external onlyRole(FARMER_ROLE)
```
- **Rule**: Only addresses with `FARMER_ROLE` can record crop events
- **Enforcement**: On-chain via modifier
- **Test Coverage**: `test_RevertUnauthorizedFarmer()`

### 3. Supply Chain Recording
```solidity
function recordSupplyChainStage(...) external onlyRole(SUPPLY_CHAIN_ROLE)
```
- **Rule**: Only addresses with `SUPPLY_CHAIN_ROLE` can record supply chain stages
- **Enforcement**: On-chain via modifier
- **Test Coverage**: `test_RevertUnauthorizedSupplyChain()`

### 4. Role Management
```solidity
function grantRole(...) external onlyRole(DEFAULT_ADMIN_ROLE)
function revokeRole(...) external onlyRole(DEFAULT_ADMIN_ROLE)
```
- **Rule**: Only admin can grant or revoke roles
- **Enforcement**: Inherited from OpenZeppelin AccessControl
- **Test Coverage**: `test_NonAdminCannotGrantRole()`, `test_AdminCanRevokeRole()`

---

## Trust Assumptions

### Critical Trust Points

1. **Deployer/Admin Trust**
   - The deployer receives all roles initially
   - **Assumption**: Deployer is trusted to only grant roles to legitimate entities
   - **Risk**: Malicious admin could grant roles to attackers
   - **Mitigation**: Consider multi-sig admin or DAO governance for production

2. **Device Trust**
   - Devices with `DEVICE_ROLE` can submit any sensor data
   - **Assumption**: Devices are physically secure and authenticated before role grant
   - **Risk**: Compromised device could submit false data
   - **Mitigation**: Off-chain device authentication before role assignment

3. **Data Integrity**
   - Contract prevents duplicate submissions via hash checking
   - **Assumption**: Duplicate hash detection prevents replay attacks
   - **Risk**: Similar (but not identical) readings won't be caught
   - **Mitigation**: Current implementation includes block index in batch hashes

4. **Farmer Trust**
   - Farmers can record any crop event for any farm ID
   - **Assumption**: Farmers only record events for their own farms
   - **Risk**: No on-chain validation of farm ownership
   - **Mitigation**: Off-chain identity verification before role grant

5. **Supply Chain Trust**
   - Supply chain actors can record stages for any product ID
   - **Assumption**: Actors only record legitimate stages
   - **Risk**: No verification of product ownership or custody
   - **Mitigation**: Off-chain verification of custody chain

### Data Immutability

- **All data is immutable** once recorded on-chain
- **No deletion or editing** of sensor readings, crop events, or supply chain stages
- **Benefit**: Tamper-proof audit trail
- **Risk**: Incorrect data cannot be removed (only corrected with new entries)

---

## Input Validation

### Enforced Constraints

1. **Soil Moisture**: 0-1000 (0.0% to 100.0% with 0.1% precision)
2. **Humidity**: 0-1000 (0.0% to 100.0% with 0.1% precision)
3. **Temperature**: int16 range (-3276.8°C to +3276.7°C with 0.1°C precision)
4. **Batch Submission**: All arrays must have matching lengths
5. **Duplicate Prevention**: Same data hash cannot be submitted twice

### Not Validated

- **Farm ID**: No validation that farm exists or caller owns it
- **Product ID**: No validation that product exists
- **Temperature reasonableness**: Allows extreme values outside typical agricultural range
- **Timestamp**: Uses block.timestamp (manipulatable by miners within ~15 seconds)

---

## Anomaly Detection

### Current Implementation

The contract includes basic on-chain anomaly detection:
```solidity
function _checkAnomalies(uint256 readingId, int16 temperature, uint16 soilMoisture, uint16 humidity)
```

**Thresholds**:
- Temperature: -10°C to 60°C
- Soil Moisture: 5% to 95%
- Humidity: < 95%

**Behavior**: Emits `AnomalyDetected` event but does NOT reject the reading

**Limitation**: Detection is informational only; no automatic remediation

---

## Known Security Limitations

### 1. No Rate Limiting
- Devices can submit unlimited readings per block
- **Risk**: Spam attacks, storage bloat
- **Mitigation**: Gas costs provide economic disincentive

### 2. Centralized Admin Control
- Single admin address controls all role grants
- **Risk**: Single point of failure, admin key compromise
- **Mitigation**: Use multi-sig wallet or DAO governance in production

### 3. No Farm/Product Ownership Verification
- No on-chain proof that a farmer owns a farm ID
- No on-chain proof that a supply chain actor has custody
- **Risk**: Data can be recorded for entities the caller doesn't control
- **Mitigation**: Off-chain identity and ownership verification

### 4. Timestamp Manipulation
- Uses `block.timestamp` which miners can manipulate ±15 seconds
- **Risk**: Slight timestamp inaccuracy
- **Mitigation**: Acceptable for agricultural use cases (minute-level precision sufficient)

### 5. No Data Privacy
- All data is publicly readable on-chain
- **Risk**: Competitive information disclosure
- **Mitigation**: Consider encrypted data or off-chain storage with on-chain hashes

### 6. Gas Cost Variability
- Batch submissions can be expensive during high network congestion
- **Risk**: Unpredictable costs for IoT gateways
- **Mitigation**: Use L2 solutions or sidechains for production

---

## Security Testing Coverage

### Authorization Tests (6 tests)
- ✅ Unauthorized device cannot submit sensor data
- ✅ Unauthorized farmer cannot record crop events
- ✅ Unauthorized actor cannot record supply chain stages
- ✅ Non-admin cannot grant roles
- ✅ Admin can grant roles
- ✅ Admin can revoke roles (and revoked roles lose access)

### Input Validation Tests (4 tests)
- ✅ Invalid soil moisture rejected (>100%)
- ✅ Invalid humidity rejected (>100%)
- ✅ Batch array length mismatch rejected
- ✅ Batch with invalid data in middle rejected (atomicity)

### Edge Cases (3 tests)
- ✅ Negative temperatures allowed
- ✅ Extreme negative temperatures (-20°C) handled correctly
- ✅ Duplicate data hash rejected

### Anomaly Detection (2 tests)
- ✅ Extreme temperature triggers anomaly event
- ✅ Extreme soil moisture triggers anomaly event

**Total**: 24 tests, 100% pass rate

---

## Future Security Enhancements

### Recommended for Production

1. **Multi-Sig Admin**
   - Replace single admin with multi-signature wallet
   - Require 2-of-3 or 3-of-5 approval for role grants

2. **DAO Governance**
   - Device role grants require on-chain voting
   - Community-driven trust model (per User Story #5)

3. **Verifiable Credentials (VC)**
   - Require devices to present cryptographic credentials
   - Off-chain verification before role grant

4. **Farm/Product Registry**
   - On-chain mapping of farm IDs to owner addresses
   - Enforce that only farm owners can record events for their farms

5. **Rate Limiting**
   - Cooldown period between submissions per device
   - Maximum readings per time window

6. **Economic Incentives**
   - Require devices to stake tokens
   - Slash stake for anomalous data

7. **Automated Remediation**
   - Pause device role automatically when anomalies detected
   - Require admin review to restore access

8. **Privacy Layer**
   - Encrypt sensitive data off-chain
   - Store only hashes on-chain (zero-knowledge proofs for verification)

---

## Audit Recommendations

Before production deployment:

1. **Professional Security Audit**
   - Review role assignment logic
   - Test for reentrancy (unlikely but verify)
   - Verify AccessControl implementation

2. **Penetration Testing**
   - Attempt unauthorized role grants
   - Test duplicate hash collision scenarios
   - Verify batch atomicity edge cases

3. **Gas Optimization Review**
   - Optimize storage for large-scale deployments
   - Consider batch size limits

4. **Formal Verification**
   - Prove role enforcement correctness
   - Verify immutability guarantees

---

## Incident Response Plan

### If Admin Key Compromised
1. Deploy new contract immediately
2. Notify all role holders via off-chain channels
3. Migrate to multi-sig admin in new deployment

### If Device Key Compromised
1. Admin revokes `DEVICE_ROLE` from compromised address
2. Review recent submissions from that device
3. Emit correction events if fraudulent data detected

### If Fraudulent Data Detected
1. Emit `AnomalyDetected` event manually if needed
2. Record correction in notes field of new entry
3. Revoke role of offending party
4. Data remains immutable (historical record)

---

## Compliance Notes

- **GDPR**: No personal data stored on-chain (only addresses and sensor readings)
- **Data Retention**: Immutable storage means infinite retention
- **Right to Erasure**: Not possible with blockchain (design limitation)
- **Audit Trail**: Complete, immutable, publicly verifiable

---


**Last Updated**: November 3, 2025  
**Contract Version**: AgriSensorData v1.0  
**Solidity Version**: 0.8.20  
**Dependencies**: OpenZeppelin Contracts v5.x
