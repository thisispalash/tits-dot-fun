// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";


// ZoraFactory interface (always on Base)
interface IZoraFactory {
    function deploy(
        address payoutRecipient,
        address[] memory owners,
        string memory uri,
        string memory name,
        string memory symbol,
        bytes memory poolConfig,
        address platformReferrer,
        address postDeployHook,
        bytes calldata postDeployHookData,
        bytes32 coinSalt
    ) external payable returns (address coin, bytes memory postDeployHookDataOut);
}


/**
 * @title TTCoiner
 * @author @thisispalash
 * @notice This contract creates commemorative Coins on Base for pools completed on any supported network.
 * @dev Upgradeable contract that lives on Base and creates coins using ZoraFactory for pools from multiple chains.
 */
contract TTCoiner is 
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    // Role definitions
    bytes32 public constant COIN_CREATOR_ROLE = keccak256("COIN_CREATOR_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant NETWORK_MANAGER_ROLE = keccak256("NETWORK_MANAGER_ROLE");

    // Network information struct (for tracking origin networks)
    struct NetworkInfo {
        string name;           // Network name (e.g., "base", "ethereum", "supra")
        uint256 chainId;       // Chain ID (0 for non-EVM networks)
        bool isEVM;            // Whether this is an EVM-compatible network
        bool isActive;         // Whether this network is active for pool tracking
        string displayName;    // Human-readable display name
    }

    // Coin information struct
    struct CoinInfo {
        address coinAddress;        // Address of the coin on Base
        address payoutRecipient;    // Winner of the pool
        string name;
        string symbol;
        string uri;
        uint256 createdAt;
        uint256 originNetworkId;    // Network where the original pool was
        address creator;            // Who called createCoin
        uint256 poolId;             // Pool ID from the origin network
    }

    // State variables
    IZoraFactory public zoraFactory;        // ZoraFactory on Base
    address public defaultPlatformReferrer; // Platform referrer for all coins
    bytes public defaultPoolConfig;         // Default pool configuration
    uint256 public nextCoinId;              // Global coin ID counter
    uint256 public nextNetworkId;           // Network ID counter
    string public VERSION;
    
    // Network management
    mapping(uint256 => NetworkInfo) public networks;
    mapping(string => uint256) public networkNameToId;
    
    // Coin tracking
    mapping(uint256 => CoinInfo) public coins;
    mapping(address => uint256) public coinAddressToId;
    mapping(uint256 => mapping(uint256 => uint256)) public poolToCoinId; // networkId => poolId => coinId

    // Events
    event CoinCreated(
        uint256 indexed coinId,
        address indexed coinAddress,
        address indexed payoutRecipient,
        string name,
        string symbol,
        address creator,
        uint256 originNetworkId,
        uint256 poolId
    );
    
    event NetworkAdded(uint256 indexed networkId, string name, uint256 chainId, bool isEVM);
    event NetworkUpdated(uint256 indexed networkId, string name, bool isActive);
    event ZoraFactoryUpdated(address indexed oldFactory, address indexed newFactory);
    event DefaultsUpdated(address platformReferrer, bytes poolConfig);

    // Custom errors
    error InvalidNetwork();
    error NetworkNotActive();
    error InvalidPayoutRecipient();
    error CoinCreationFailed();
    error NetworkAlreadyExists();
    error PoolAlreadyCoined();
    error InvalidZoraFactory();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initialize the contract
     * @param _zoraFactory ZoraFactory address on Base
     * @param _defaultPoolConfig Default pool configuration
     * @param _admin Address to be granted admin role
     */
    function initialize(
        address _zoraFactory,
        bytes memory _defaultPoolConfig,
        address _admin
    ) public initializer {
        if (_zoraFactory == address(0)) revert InvalidZoraFactory();
        if (_admin == address(0)) revert InvalidPayoutRecipient();

        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        zoraFactory = IZoraFactory(_zoraFactory);
        defaultPlatformReferrer = address(this);
        defaultPoolConfig = _defaultPoolConfig;
        nextCoinId = 1;
        nextNetworkId = 1;
        VERSION = "0.1.0";

        // Grant roles to admin
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(COIN_CREATOR_ROLE, _admin);
        _grantRole(UPGRADER_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
        _grantRole(NETWORK_MANAGER_ROLE, _admin);
    }

    /**
     * @dev Create a commemorative coin for a completed pool from any network
     * @param payoutRecipient Address to receive creator rewards (winner of the pool)
     * @param originNetworkId Network ID where the original pool was located
     * @param poolId The ID of the pool, on the specific network, that completed
     * @return coinId The unique global ID of the created coin
     * @return coinAddress The address of the created coin on Base
     */
    function createCoin(
        address payoutRecipient,
        uint256 originNetworkId,
        uint256 poolId
    ) external payable onlyRole(COIN_CREATOR_ROLE) nonReentrant whenNotPaused returns (uint256 coinId, address coinAddress) {
        if (payoutRecipient == address(0)) revert InvalidPayoutRecipient();
        
        NetworkInfo storage network = networks[originNetworkId];
        if (bytes(network.name).length == 0 || !network.isActive) revert NetworkNotActive();
        
        // Check if this pool already has a coin
        if (poolToCoinId[originNetworkId][poolId] != 0) revert PoolAlreadyCoined();

        // Get the current coin ID
        coinId = nextCoinId;

        // Generate coin parameters using the simple format
        (string memory name, string memory symbol, string memory uri) = _generateCoinParameters(originNetworkId, poolId, coinId);
        
        // Set up owners array (the payout recipient and the contract itself)
        address[] memory owners = new address[](2);
        owners[0] = payoutRecipient;
        owners[1] = address(this);

        // Generate unique salt based on coin ID, network, and pool
        bytes32 coinSalt = keccak256(abi.encodePacked(coinId, originNetworkId, poolId));
        
        // Create the coin through ZoraFactory on Base
        try zoraFactory.deploy{value: msg.value}(
            payoutRecipient,
            owners,
            uri,
            name,
            symbol,
            defaultPoolConfig,
            defaultPlatformReferrer,
            address(0), // No post deploy hook for now
            "",         // No post deploy hook data
            coinSalt
        ) returns (address coin, bytes memory) {
            coinAddress = coin;
        } catch {
            revert CoinCreationFailed();
        }

        // Store coin information
        coins[coinId] = CoinInfo({
            coinAddress: coinAddress,
            payoutRecipient: payoutRecipient,
            name: name,
            symbol: symbol,
            uri: uri,
            createdAt: block.timestamp,
            originNetworkId: originNetworkId,
            creator: msg.sender,
            poolId: poolId
        });

        // Map address to ID and pool to coin
        coinAddressToId[coinAddress] = coinId;
        poolToCoinId[originNetworkId][poolId] = coinId;

        // Increment for next coin
        nextCoinId++;

        emit CoinCreated(coinId, coinAddress, payoutRecipient, name, symbol, msg.sender, originNetworkId, poolId);
    }

    /**
     * @dev Generate coin parameters using the standardized format
     * @param originNetworkId The network ID where the pool was
     * @param poolId The pool ID
     * @param coinId The coin ID
     * @return name Generated coin name: "TT {pool_id} on {network}"
     * @return symbol Generated coin symbol: "TT{coin_id}" with 5 places
     * @return uri Generated metadata URI: "https://titsdot.fun/g/{network}/{pool_id}.json"
     */
    function _generateCoinParameters(uint256 originNetworkId, uint256 poolId, uint256 coinId) internal view returns (string memory name, string memory symbol, string memory uri) {
        NetworkInfo storage network = networks[originNetworkId];
        
        // Generate name: "TT {pool_id} on {network}"
        name = string(abi.encodePacked(
            "TT ",
            _toString(poolId),
            " on ",
            network.displayName
        ));
        
        // Generate symbol: "TT{coin_id}" with 5 places (e.g., TT00001, TT00042)
        symbol = string(abi.encodePacked(
            "TT",
            _toStringWithPadding(coinId, 5)
        ));
        
        // Generate URI: "https://titsdot.fun/g/{network}/{pool_id}.json"
        uri = string(abi.encodePacked(
            "https://titsdot.fun/g/",
            network.name,
            "/",
            _toString(poolId),
            ".json"
        ));
    }

    /**
     * @dev Add a new network configuration for tracking pools
     * @param name Network name (e.g., "base", "ethereum", "supra")
     * @param chainId Chain ID (0 for non-EVM)
     * @param isEVM Whether this is an EVM network
     * @param displayName Human-readable display name
     */
    function addNetwork(
        string memory name,
        uint256 chainId,
        bool isEVM,
        string memory displayName
    ) external onlyRole(NETWORK_MANAGER_ROLE) {
        if (networkNameToId[name] != 0) revert NetworkAlreadyExists();
        
        uint256 networkId = nextNetworkId;
        
        networks[networkId] = NetworkInfo({
            name: name,
            chainId: chainId,
            isEVM: isEVM,
            isActive: true,
            displayName: displayName
        });
        
        networkNameToId[name] = networkId;
        nextNetworkId++;
        
        emit NetworkAdded(networkId, name, chainId, isEVM);
    }

    /**
     * @dev Update network active status
     * @param networkId Network ID to update
     * @param isActive New active status
     */
    function updateNetworkStatus(uint256 networkId, bool isActive) external onlyRole(NETWORK_MANAGER_ROLE) {
        NetworkInfo storage network = networks[networkId];
        if (bytes(network.name).length == 0) revert InvalidNetwork();
        
        network.isActive = isActive;
        emit NetworkUpdated(networkId, network.name, isActive);
    }

    /**
     * @dev Update ZoraFactory address
     * @param _zoraFactory New ZoraFactory address
     */
    function updateZoraFactory(address _zoraFactory) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_zoraFactory == address(0)) revert InvalidZoraFactory();
        
        address oldFactory = address(zoraFactory);
        zoraFactory = IZoraFactory(_zoraFactory);
        
        emit ZoraFactoryUpdated(oldFactory, _zoraFactory);
    }

    /**
     * @dev Update default configuration
     * @param _platformReferrer New default platform referrer
     * @param _poolConfig New default pool configuration
     */
    function updateDefaults(address _platformReferrer, bytes memory _poolConfig) external onlyRole(DEFAULT_ADMIN_ROLE) {
        defaultPlatformReferrer = _platformReferrer;
        defaultPoolConfig = _poolConfig;
        
        emit DefaultsUpdated(_platformReferrer, _poolConfig);
    }

    /**
     * @dev Convert uint256 to string with zero padding
     * @param value The number to convert
     * @param places Number of places to pad to
     * @return Padded string representation
     */
    function _toStringWithPadding(uint256 value, uint256 places) internal pure returns (string memory) {
        string memory str = _toString(value);
        bytes memory strBytes = bytes(str);
        
        if (strBytes.length >= places) {
            return str;
        }
        
        bytes memory result = new bytes(places);
        uint256 padding = places - strBytes.length;
        
        // Fill with zeros
        for (uint256 i = 0; i < padding; i++) {
            result[i] = "0";
        }
        
        // Copy the actual number
        for (uint256 i = 0; i < strBytes.length; i++) {
            result[padding + i] = strBytes[i];
        }
        
        return string(result);
    }

    /**
     * @dev Convert uint256 to string
     */
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        
        return string(buffer);
    }

    // View functions

    /**
     * @dev Get coin information by ID
     */
    function getCoinInfo(uint256 coinId) external view returns (CoinInfo memory) {
        return coins[coinId];
    }

    /**
     * @dev Get coin ID by address
     */
    function getCoinId(address coinAddress) external view returns (uint256) {
        return coinAddressToId[coinAddress];
    }

    /**
     * @dev Get coin ID by network and pool ID
     */
    function getCoinIdByPool(uint256 networkId, uint256 poolId) external view returns (uint256) {
        return poolToCoinId[networkId][poolId];
    }

    /**
     * @dev Get network information by ID
     */
    function getNetworkInfo(uint256 networkId) external view returns (NetworkInfo memory) {
        return networks[networkId];
    }

    /**
     * @dev Get network ID by name
     */
    function getNetworkId(string memory networkName) external view returns (uint256) {
        return networkNameToId[networkName];
    }

    /**
     * @dev Get current coin ID (next to be assigned)
     */
    function getCurrentCoinId() external view returns (uint256) {
        return nextCoinId;
    }

    // Admin functions

    /**
     * @dev Pause the contract
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @dev Unpause the contract
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @dev Withdraw contract balance (emergency function)
     * @param to Address to withdraw to
     */
    function withdraw(address payable to) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (to == address(0)) revert InvalidPayoutRecipient();
        
        uint256 balance = address(this).balance;
        (bool success, ) = to.call{value: balance}("");
        require(success, "Withdrawal failed");
    }

    /**
     * @dev Required by UUPSUpgradeable
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    /**
     * @dev Receive function to accept ETH
     */
    receive() external payable {}
}