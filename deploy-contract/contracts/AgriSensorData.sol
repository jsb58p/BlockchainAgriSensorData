// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title AgriSensorData
 * @dev Immutable storage of IoT sensor data with role-based access control.
 * Features:
 * - Sensor readings stored permanently on-chain
 * - Role-based permissions for devices, farmers, researchers
 * - Batch submissions for IoT gateways
 * - Query functions for historical data
 * - Crop lifecycle tracking
 * - Supply chain traceability
 */
contract AgriSensorData is AccessControl, Pausable {
    // Role definitions
    bytes32 public constant DEVICE_ROLE = keccak256("DEVICE_ROLE");
    bytes32 public constant FARMER_ROLE = keccak256("FARMER_ROLE");
    bytes32 public constant SUPPLY_CHAIN_ROLE = keccak256("SUPPLY_CHAIN_ROLE");
    bytes32 public constant RESEARCHER_ROLE = keccak256("RESEARCHER_ROLE");

    // Security parameters
    uint256 public constant SUBMISSION_COOLDOWN = 60; // seconds between submissions
    uint256 public constant MAX_BATCH_SIZE = 100; // max readings per batch

    // Custom errors
    error UnauthorizedDevice();
    error InvalidSensorData();
    error ArrayLengthMismatch();
    error DuplicateDataHash();
    error ReadingNotFound();

    // Sensor reading structure
    struct SensorReading {
        uint256 timestamp;
        address deviceId;
        uint256 farmId;
        int16 temperature;      // in 0.1°C (e.g., 255 = 25.5°C)
        uint16 soilMoisture;    // percentage 0-1000 (0.1% precision)
        uint16 humidity;        // percentage 0-1000 (0.1% precision)
        bytes32 dataHash;       // for verification
    }

    // Crop lifecycle event structure
    struct CropEvent {
        uint256 farmId;
        string eventType;       // "SEED", "FERTILIZE", "IRRIGATE", "HARVEST"
        uint256 timestamp;
        string notes;
        bytes32 linkedDataHash; // optional link to sensor data
    }

    // Supply chain stage structure
    struct SupplyChainStage {
        uint256 productId;
        string stage;           // "FARM", "TRANSPORT", "STORAGE", "RETAIL"
        uint256 timestamp;
        address recorder;
        string location;
        bytes32 linkedDataHash; // link to sensor data (e.g., transport temp)
    }

    // Storage
    SensorReading[] public readings;
    CropEvent[] public cropEvents;
    SupplyChainStage[] public supplyChainStages;

    mapping(bytes32 => bool) public dataHashes;             // prevent duplicate submissions
    mapping(uint256 => uint256[]) public farmToReadings;    // farmId => reading indices
    mapping(uint256 => uint256[]) public farmToCropEvents;  // farmId => crop event indices
    mapping(uint256 => uint256[]) public productToStages;   // productId => supply chain indices
    mapping(address => uint256) public lastSubmissionTime;  // device => last submission timestamp

    // Events
    event SensorDataSubmitted(
        uint256 indexed readingId,
        address indexed deviceId,
        uint256 indexed farmId,
        uint256 timestamp
    );

    event CropEventRecorded(
        uint256 indexed eventId,
        uint256 indexed farmId,
        string eventType,
        uint256 timestamp
    );

    event SupplyChainStageRecorded(
        uint256 indexed stageId,
        uint256 indexed productId,
        string stage,
        uint256 timestamp
    );

    event AnomalyDetected(
        uint256 indexed readingId,
        address indexed deviceId,
        string anomalyType
    );

    /**
     * @dev Constructor grants admin role to deployer
     */
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(DEVICE_ROLE, msg.sender);
        _grantRole(FARMER_ROLE, msg.sender);
        _grantRole(RESEARCHER_ROLE, msg.sender);
        _grantRole(SUPPLY_CHAIN_ROLE, msg.sender);
    }

    /**
     * @dev Submit a single sensor reading
     * @param farmId The farm identifier
     * @param temperature Temperature in 0.1°C
     * @param soilMoisture Soil moisture 0-1000 (0.1% precision)
     * @param humidity Humidity 0-1000 (0.1% precision)
     */
    function submitSensorData(
        uint256 farmId,
        int16 temperature,
        uint16 soilMoisture,
        uint16 humidity
    ) external onlyRole(DEVICE_ROLE) whenNotPaused {
        // Rate limiting check
        if (block.timestamp < lastSubmissionTime[msg.sender] + SUBMISSION_COOLDOWN) {
            revert("Cooldown period active");
        }
        lastSubmissionTime[msg.sender] = block.timestamp;
        // Validate data ranges
        if (soilMoisture > 1000 || humidity > 1000) revert InvalidSensorData();

        // Compute hash for verification
        bytes32 hash = keccak256(abi.encodePacked(
            block.timestamp,
            msg.sender,
            farmId,
            temperature,
            soilMoisture,
            humidity
        ));

        // Check for duplicates
        if (dataHashes[hash]) revert DuplicateDataHash();
        dataHashes[hash] = true;

        // Store reading
        uint256 readingId = readings.length;
        readings.push(SensorReading({
            timestamp: block.timestamp,
            deviceId: msg.sender,
            farmId: farmId,
            temperature: temperature,
            soilMoisture: soilMoisture,
            humidity: humidity,
            dataHash: hash
        }));

        farmToReadings[farmId].push(readingId);

        emit SensorDataSubmitted(readingId, msg.sender, farmId, block.timestamp);

        // Basic anomaly detection
        _checkAnomalies(readingId, temperature, soilMoisture, humidity);
    }

    /**
     * @dev Submit batch sensor readings (for IoT gateways)
     * @param farmIds Array of farm identifiers
     * @param temperatures Array of temperatures
     * @param moistures Array of soil moisture values
     * @param humidities Array of humidity values
     */
    function submitBatch(
        uint256[] calldata farmIds,
        int16[] calldata temperatures,
        uint16[] calldata moistures,
        uint16[] calldata humidities
    ) external onlyRole(DEVICE_ROLE) whenNotPaused {
        uint256 len = farmIds.length;
        
        // Batch size limit
        if (len > MAX_BATCH_SIZE) {
            revert("Batch size exceeds maximum");
        }
        
        if (len != temperatures.length || len != moistures.length || len != humidities.length) {
            revert ArrayLengthMismatch();
        }
        
        // Rate limiting check
        if (block.timestamp < lastSubmissionTime[msg.sender] + SUBMISSION_COOLDOWN) {
            revert("Cooldown period active");
        }
        lastSubmissionTime[msg.sender] = block.timestamp;

        for (uint256 i = 0; i < len; ) {
            if (moistures[i] > 1000 || humidities[i] > 1000) revert InvalidSensorData();

            bytes32 hash = keccak256(abi.encodePacked(
                block.timestamp,
                msg.sender,
                farmIds[i],
                temperatures[i],
                moistures[i],
                humidities[i],
                i // include index to prevent duplicate hashes in same batch
            ));

            if (dataHashes[hash]) revert DuplicateDataHash();
            dataHashes[hash] = true;

            uint256 readingId = readings.length;
            readings.push(SensorReading({
                timestamp: block.timestamp,
                deviceId: msg.sender,
                farmId: farmIds[i],
                temperature: temperatures[i],
                soilMoisture: moistures[i],
                humidity: humidities[i],
                dataHash: hash
            }));

            farmToReadings[farmIds[i]].push(readingId);

            emit SensorDataSubmitted(readingId, msg.sender, farmIds[i], block.timestamp);

            _checkAnomalies(readingId, temperatures[i], moistures[i], humidities[i]);

            unchecked { ++i; }
        }
    }

    /**
     * @dev Record a crop lifecycle event
     * @param farmId The farm identifier
     * @param eventType Type of event (SEED, FERTILIZE, etc.)
     * @param notes Additional notes
     * @param linkedDataHash Optional hash linking to sensor data
     */
    function recordCropEvent(
        uint256 farmId,
        string calldata eventType,
        string calldata notes,
        bytes32 linkedDataHash
    ) external onlyRole(FARMER_ROLE) whenNotPaused {
        uint256 eventId = cropEvents.length;
        cropEvents.push(CropEvent({
            farmId: farmId,
            eventType: eventType,
            timestamp: block.timestamp,
            notes: notes,
            linkedDataHash: linkedDataHash
        }));

        farmToCropEvents[farmId].push(eventId);

        emit CropEventRecorded(eventId, farmId, eventType, block.timestamp);
    }

    /**
     * @dev Record a supply chain stage
     * @param productId Unique product identifier
     * @param stage Stage name (FARM, TRANSPORT, STORAGE, RETAIL)
     * @param location Location description
     * @param linkedDataHash Optional hash linking to sensor data
     */
    function recordSupplyChainStage(
        uint256 productId,
        string calldata stage,
        string calldata location,
        bytes32 linkedDataHash
    ) external onlyRole(SUPPLY_CHAIN_ROLE) whenNotPaused {
        uint256 stageId = supplyChainStages.length;
        supplyChainStages.push(SupplyChainStage({
            productId: productId,
            stage: stage,
            timestamp: block.timestamp,
            recorder: msg.sender,
            location: location,
            linkedDataHash: linkedDataHash
        }));

        productToStages[productId].push(stageId);

        emit SupplyChainStageRecorded(stageId, productId, stage, block.timestamp);
    }

    /**
     * @dev Get all sensor readings for a farm
     * @param farmId The farm identifier
     * @return Array of reading indices
     */
    function getReadingsByFarm(uint256 farmId) external view returns (uint256[] memory) {
        return farmToReadings[farmId];
    }

    /**
     * @dev Get crop events for a farm
     * @param farmId The farm identifier
     * @return Array of event indices
     */
    function getCropEventsByFarm(uint256 farmId) external view returns (uint256[] memory) {
        return farmToCropEvents[farmId];
    }

    /**
     * @dev Get supply chain stages for a product
     * @param productId The product identifier
     * @return Array of stage indices
     */
    function getSupplyChainStages(uint256 productId) external view returns (uint256[] memory) {
        return productToStages[productId];
    }

    /**
     * @dev Get total number of readings
     */
    function getTotalReadings() external view returns (uint256) {
        return readings.length;
    }

    /**
     * @dev Get total number of crop events
     */
    function getTotalCropEvents() external view returns (uint256) {
        return cropEvents.length;
    }

    /**
     * @dev Get total number of supply chain stages
     */
    function getTotalSupplyChainStages() external view returns (uint256) {
        return supplyChainStages.length;
    }

    /**
     * @dev Verify a sensor reading's integrity
     * @param readingId The reading index
     * @return valid Whether the hash matches
     * @return storedHash The stored hash
     */
    function verifyReading(uint256 readingId) 
        external 
        view 
        returns (bool valid, bytes32 storedHash) 
    {
        if (readingId >= readings.length) revert ReadingNotFound();
        
        SensorReading memory reading = readings[readingId];
        storedHash = reading.dataHash;
        
        // Note: Can't recompute exact hash without original index for batch submissions
        // This is a simplified verification
        valid = dataHashes[storedHash];
    }

    /**
     * @dev Internal function for basic anomaly detection
     */
    function _checkAnomalies(
        uint256 readingId,
        int16 temperature,
        uint16 soilMoisture,
        uint16 humidity
    ) internal {
        // Example thresholds (configurable in production)
        if (temperature < -100 || temperature > 600) { // -10°C to 60°C
            emit AnomalyDetected(readingId, msg.sender, "EXTREME_TEMPERATURE");
        }
        if (soilMoisture < 50 || soilMoisture > 950) {
            emit AnomalyDetected(readingId, msg.sender, "EXTREME_SOIL_MOISTURE");
        }
        if (humidity > 950) {
            emit AnomalyDetected(readingId, msg.sender, "EXTREME_HUMIDITY");
        }
    }

    /**
     * @dev Pause all contract operations (emergency stop)
     * Only admin can pause
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @dev Unpause contract operations
     * Only admin can unpause
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}
