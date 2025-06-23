// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./libraries/MathUtils.sol";
import "./CryptoTitty.sol";

contract TittyPool is Ownable {
  using MathUtils for uint256;
  
  struct TraderDeviation {
    address trader;
    uint256 deviation; // basis points
    uint256 tradeCount;
    uint256 lastUpdated;
  }
  
  struct PoolInfo {
    uint256 poolId;
    uint256 lValue; // Candle size
    uint256 hValue; // Height parameter (fixed-point)
    uint256 xReserve; // Native token reserve (fixed-point)
    uint256 yReserve; // Pool token reserve (fixed-point)
    address tokenAddress;
    uint256 startTime;
    uint256 endTime;
    bool isLocked;
    uint256 totalTrades;
    address currentWinner;
    uint256 winnerProposedDelay;
    uint256 winnerProposedCandleSize;
  }
  
  // Events
  event TradeEvent(
    uint256 indexed poolId,
    address indexed trader,
    uint256 quantity,
    bool side,
    uint256 timestamp,
    uint256 deviation
  );
  
  event PoolLocked(
    uint256 indexed poolId,
    string reason,
    uint256 timestamp
  );
  
  event NewWinnerDetected(
    uint256 indexed poolId,
    address indexed winner,
    uint256 deviation,
    uint256 proposedDelay,
    uint256 proposedCandleSize,
    uint256 timestamp
  );
  
  event PoolWinnerFinalized(
    uint256 indexed poolId,
    address indexed winner,
    uint256 finalDeviation,
    uint256 nextPoolDelay,
    uint256 nextPoolCandleSize,
    uint256 timestamp
  );
  
  // State variables
  PoolInfo public poolInfo;
  mapping(address => TraderDeviation) public traderDeviations;
  address[] public traders;
  
  // Constants
  uint256 constant FEE_BASIS_POINTS = 10; // 0.1% = 10 basis points
  uint256 constant DEVIATION_THRESHOLD = 690; // 6.9% in basis points
  uint256 constant MAX_DELAY = 12 hours;
  uint256 constant POOL_DURATION = 24 hours;
  uint256 constant INITIAL_TOKEN_SUPPLY = 1000000 * 10**18; // 1M tokens
  
  // Valid candle sizes
  uint256[] public validCandleSizes = [96, 144, 288];
  
  constructor(
    address initialOwner,
    uint256 _poolId,
    uint256 _lValue,
    uint256 _hValue,
    address _tokenAddress,
    uint256 _startTime
  ) Ownable(initialOwner) {
    require(_lValue == 96 || _lValue == 144 || _lValue == 288, "Invalid L value");
    
    poolInfo = PoolInfo({
      poolId: _poolId,
      lValue: _lValue,
      hValue: _hValue,
      xReserve: MathUtils.toFixedPoint(1 ether), // 1 native token
      yReserve: MathUtils.toFixedPoint(INITIAL_TOKEN_SUPPLY),
      tokenAddress: _tokenAddress,
      startTime: _startTime,
      endTime: _startTime + POOL_DURATION,
      isLocked: false,
      totalTrades: 0,
      currentWinner: address(0),
      winnerProposedDelay: 0,
      winnerProposedCandleSize: 0
    });
  }
  
  function trade(
    uint256 quantity,
    bool side, // true = buy, false = sell
    uint256 delay,
    uint256 candleSize
  ) external payable {
    require(!poolInfo.isLocked, "Pool is locked");
    require(block.timestamp >= poolInfo.startTime && block.timestamp <= poolInfo.endTime, "Pool not active");
    require(delay <= MAX_DELAY, "Delay too long");
    require(isValidCandleSize(candleSize), "Invalid candle size");
    
    address trader = msg.sender;
    
    // Calculate current candle and expected price
    uint256 currentCandleSize = (24 * 60) / poolInfo.lValue; // minutes
    uint256 timeElapsed = block.timestamp - poolInfo.startTime;
    uint256 candleDuration = currentCandleSize * 60; // seconds
    uint256 currentCandle = timeElapsed < candleDuration ? 0 : timeElapsed / candleDuration;
    uint256 nextCandle = currentCandle + 1;
    
    // Calculate bonded curve expected price
    uint256 hRegular = MathUtils.fromFixedPoint(poolInfo.hValue);
    uint256 curveExpected = MathUtils.calculateCurveY(nextCandle, hRegular, poolInfo.lValue);

    uint256 ammOutput;
    
    // Handle token transfers
    if (side) {
      // BUY: Native token -> Pool tokens
      require(msg.value >= quantity, "Insufficient payment");
      
      uint256 inputAmountFixed = MathUtils.toFixedPoint(quantity);
      ammOutput = MathUtils.calculateAmmOut(inputAmountFixed, poolInfo.xReserve, poolInfo.yReserve);
      
      // Update reserves
      poolInfo.xReserve = MathUtils.safeAdd(poolInfo.xReserve, inputAmountFixed);
      poolInfo.yReserve = MathUtils.safeSub(poolInfo.yReserve, ammOutput);
      
      // Transfer tokens
      uint256 ammOutputRegular = MathUtils.fromFixedPoint(ammOutput);
      CryptoTitty(poolInfo.tokenAddress).mint(trader, ammOutputRegular);
      
      // Calculate deviation
      uint256 deviation = calculateDeviation(ammOutput, curveExpected);
      updateTraderDeviation(trader, deviation);
      
    } else {
      // SELL: Pool tokens -> Native token
      uint256 inputAmountFixed = MathUtils.toFixedPoint(quantity);
      ammOutput = MathUtils.calculateAmmOut(inputAmountFixed, poolInfo.yReserve, poolInfo.xReserve);
      
      // Update reserves
      poolInfo.xReserve = MathUtils.safeSub(poolInfo.xReserve, ammOutput);
      poolInfo.yReserve = MathUtils.safeAdd(poolInfo.yReserve, inputAmountFixed);
      
      // Transfer tokens
      CryptoTitty(poolInfo.tokenAddress).burn(quantity);
      uint256 ammOutputRegular = MathUtils.fromFixedPoint(ammOutput);
      payable(trader).transfer(ammOutputRegular);
      
      // Calculate deviation
      uint256 deviation = calculateDeviation(ammOutput, curveExpected);
      updateTraderDeviation(trader, deviation);
    }
    
    // Check for new winner
    checkForNewWinner(trader, delay, candleSize);
    
    poolInfo.totalTrades++;
    
    emit TradeEvent(
      poolInfo.poolId,
      trader,
      quantity,
      side,
      block.timestamp,
      MathUtils.fromFixedPoint(calculateDeviation(ammOutput, curveExpected))
    );
  }
  
  function lockPool(string memory reason) external onlyOwner {
    require(!poolInfo.isLocked, "Pool already locked");
    poolInfo.isLocked = true;
    
    // Burn all tokens in the pool
    uint256 poolBalance = CryptoTitty(poolInfo.tokenAddress).balanceOf(address(this));
    if (poolBalance > 0) {
      CryptoTitty(poolInfo.tokenAddress).burn(poolBalance);
    }
    
    emit PoolLocked(poolInfo.poolId, reason, block.timestamp);
  }
  
  function finalizeWinner() external onlyOwner {
    require(block.timestamp > poolInfo.endTime, "Pool not ended");
    require(!poolInfo.isLocked, "Pool is locked");
    
    address winner = poolInfo.currentWinner;
    if (winner != address(0)) {
      emit PoolWinnerFinalized(
        poolInfo.poolId,
        winner,
        traderDeviations[winner].deviation,
        poolInfo.winnerProposedDelay,
        poolInfo.winnerProposedCandleSize,
        block.timestamp
      );
    }
  }
  
  // Internal functions
  function calculateDeviation(uint256 actual, uint256 expected) internal pure returns (uint256) {
    if (expected == 0) return 0;
    uint256 diff = MathUtils.absDiff(actual, expected);
    return MathUtils.safeDivPrecision(diff * 10000, expected);
  }
  
  function updateTraderDeviation(address trader, uint256 deviation) internal {
    TraderDeviation storage traderDev = traderDeviations[trader];
    
    if (traderDev.trader == address(0)) {
      // New trader
      traderDev.trader = trader;
      traders.push(trader);
    }
    
    // Update deviation (lower is better)
    if (traderDev.deviation == 0 || deviation < traderDev.deviation) {
      traderDev.deviation = deviation;
    }
    
    traderDev.tradeCount++;
    traderDev.lastUpdated = block.timestamp;
  }
  
  function checkForNewWinner(address trader, uint256 delay, uint256 candleSize) internal {
    address currentWinner = getCurrentWinner();
    
    if (currentWinner != poolInfo.currentWinner && currentWinner == trader) {
      poolInfo.currentWinner = currentWinner;
      poolInfo.winnerProposedDelay = delay;
      poolInfo.winnerProposedCandleSize = candleSize;
      
      emit NewWinnerDetected(
        poolInfo.poolId,
        trader,
        traderDeviations[trader].deviation,
        delay,
        candleSize,
        block.timestamp
      );
    }
  }
  
  function getCurrentWinner() internal view returns (address) {
    address winner = address(0);
    uint256 minDeviation = type(uint256).max;
    uint256 latestTime = 0;
    
    for (uint256 i = 0; i < traders.length; i++) {
      address trader = traders[i];
      TraderDeviation memory dev = traderDeviations[trader];
        
      if (dev.deviation < minDeviation || 
        (dev.deviation == minDeviation && dev.lastUpdated > latestTime)) {
        winner = trader;
        minDeviation = dev.deviation;
        latestTime = dev.lastUpdated;
      }
    }
    
    return winner;
  }
  
  function isValidCandleSize(uint256 candleSize) internal view returns (bool) {
    for (uint256 i = 0; i < validCandleSizes.length; i++) {
      if (validCandleSizes[i] == candleSize) {
        return true;
      }
    }
    return false;
  }
  
  // View functions
  function getTraderDeviation(address trader) external view returns (TraderDeviation memory) {
    return traderDeviations[trader];
  }
  
  function getAllTraders() external view returns (address[] memory) {
    return traders;
  }
  
  function getCurrentWinnerInfo() external view returns (address, uint256, uint256) {
    address winner = getCurrentWinner();
    if (winner != address(0)) {
      return (winner, traderDeviations[winner].deviation, traderDeviations[winner].lastUpdated);
    }
    return (address(0), 0, 0);
  }
  
  // Receive function for native token
  receive() external payable {}
}