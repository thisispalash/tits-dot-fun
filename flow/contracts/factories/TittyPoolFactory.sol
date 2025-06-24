// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../TittyPool.sol";
import "../CryptoTitty.sol";
import "../libraries/MathUtils.sol";

contract TittyPoolFactory is Ownable {
  using MathUtils for uint256;
  
  TittyPool[] public deployedPools;
  mapping(uint256 => address) public poolIdToAddress;
  mapping(address => bool) public isDeployedPool;
  
  // Valid candle sizes
  uint256[] public validCandleSizes = [96, 144, 288];
  
  // Events
  event PoolCreated(
    uint256 indexed poolId,
    address indexed poolAddress,
    address indexed tokenAddress,
    uint256 lValue,
    uint256 hValue,
    uint256 startTime,
    uint256 endTime,
    address creator,
    uint256 timestamp
  );
  
  event PoolLockedWithRandomParams(
    uint256 indexed poolId,
    string reason,
    uint256 randomCandleSize,
    uint256 randomDelay,
    uint256 randomLValue,
    uint256 timestamp
  );
  
  constructor(address initialOwner) Ownable(initialOwner) {}
  
  // Public function to create pool
  function createPool(
    uint256 lValue,
    uint256 delaySeconds
  ) external onlyOwner returns (address) {
    return _createPool(lValue, delaySeconds);
  }
  
  // Internal function that does the actual pool creation
  function _createPool(
    uint256 lValue,
    uint256 delaySeconds
  ) internal returns (address) {
    require(lValue == 96 || lValue == 144 || lValue == 288, "Invalid L value");
    require(delaySeconds <= 12 hours, "Delay too long");
    
    uint256 poolId = deployedPools.length + 1;
    require(poolIdToAddress[poolId] == address(0), "Pool ID already exists");
    
    // Calculate H value: H_{i+1} = sqrt(H_i) * sqrt(L), H_0 = 1
    uint256 hValue;
    if (poolId == 1) {
      hValue = MathUtils.toFixedPoint(1); // H_0 = 1
    } else {
      // For simplicity, we'll use a simplified H calculation
      // In production, you'd want to track previous H values
      uint256 sqrtL = MathUtils.sqrt(lValue);
      hValue = MathUtils.toFixedPoint(sqrtL);
    }
    
    // Create token for this pool
    string memory poolIdStr = uintToString(poolId);
    string memory name = string(abi.encodePacked("Crypto Titty ", poolIdStr));
    string memory symbol = string(abi.encodePacked("T", poolIdStr));
    
    CryptoTitty token = new CryptoTitty(
      name,
      symbol,
      1000000 * 10**18, // 1M tokens
      poolId,
      address(this)
    );
    
    // Calculate start time
    uint256 startTime = block.timestamp + delaySeconds;
    
    // Create pool
    TittyPool pool = new TittyPool(
      address(this),
      poolId,
      lValue,
      hValue,
      address(token),
      startTime
    );
    
    address poolAddress = address(pool);
    
    // Transfer token ownership to pool
    token.transferOwnership(poolAddress);
    
    // Transfer initial liquidity to pool
    token.mint(poolAddress, 1000000 * 10**18);
    
    // Register pool
    deployedPools.push(pool);
    poolIdToAddress[poolId] = poolAddress;
    isDeployedPool[poolAddress] = true;
    
    emit PoolCreated(
      poolId,
      poolAddress,
      address(token),
      lValue,
      hValue,
      startTime,
      startTime + 24 hours,
      msg.sender,
      block.timestamp
    );
    
    return poolAddress;
  }
  
  function createPoolWithWinner(
    uint256 lValue,
    uint256 delaySeconds,
    address winner,
    uint256 winnerDeviation
  ) external onlyOwner returns (address) {
    require(lValue == 96 || lValue == 144 || lValue == 288, "Invalid L value");
    require(delaySeconds <= 12 hours, "Delay too long");
    
    return _createPool(lValue, delaySeconds);
  }
  
  function createPoolWithRandomParams(
    string memory reason
  ) external onlyOwner returns (address) {
    // Generate random parameters
    uint256 randomLValue = validCandleSizes[uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao))) % 3];
    uint256 randomDelay = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao))) % (12 hours);
    
    emit PoolLockedWithRandomParams(
      deployedPools.length + 1,
      reason,
      randomLValue,
      randomDelay,
      randomLValue,
      block.timestamp
    );
    
    return _createPool(randomLValue, randomDelay);
  }
  
  // Helper function to convert uint to string
  function uintToString(uint256 value) internal pure returns (string memory) {
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
  function getPoolByPoolId(uint256 poolId) external view returns (address) {
    return poolIdToAddress[poolId];
  }
  
  function getAllDeployedPools() external view returns (address[] memory) {
    address[] memory poolAddresses = new address[](deployedPools.length);
    for (uint256 i = 0; i < deployedPools.length; i++) {
      poolAddresses[i] = address(deployedPools[i]);
    }
    return poolAddresses;
  }
  
  function getDeployedPoolCount() external view returns (uint256) {
    return deployedPools.length;
  }
  
  function isPoolDeployed(address poolAddress) external view returns (bool) {
    return isDeployedPool[poolAddress];
  }
} 