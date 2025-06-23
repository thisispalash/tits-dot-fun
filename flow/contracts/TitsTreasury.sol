// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";

contract TitsTreasury is Ownable {
  uint256 public balance;
  uint256 public totalFeesCollected;
  uint256 public createdAt;
  
  // Events
  event FeesWithdrawn(
    uint256 amount,
    address admin,
    uint256 timestamp,
    uint256 remainingBalance
  );
  
  event TreasuryFunded(
    uint256 amount,
    address funder,
    uint256 timestamp,
    uint256 newBalance
  );
  
  event EmergencyPoolFund(
    uint256 amount,
    uint256 poolId,
    uint256 timestamp,
    uint256 remainingBalance
  );
  
  constructor(address initialOwner) Ownable(initialOwner) {
    createdAt = block.timestamp;
  }
  
  // Collect fees from pools
  function collectFees(uint256 amount) external payable {
    require(msg.value >= amount, "Insufficient payment");
    balance += amount;
    totalFeesCollected += amount;
  }
  
  // Admin function to withdraw fees
  function withdrawFees(uint256 amount) external onlyOwner {
    require(balance >= amount, "Insufficient balance");
    balance -= amount;
    
    payable(owner()).transfer(amount);
    
    emit FeesWithdrawn(
      amount,
      owner(),
      block.timestamp,
      balance
    );
  }
  
  // Fund new pools
  function initializePoolFunding(uint256 fundingAmount, uint256 poolId) external onlyOwner {
    require(balance >= fundingAmount, "Insufficient balance");
    balance -= fundingAmount;
    
    payable(owner()).transfer(fundingAmount);
    
    emit EmergencyPoolFund(
      fundingAmount,
      poolId,
      block.timestamp,
      balance
    );
  }
  
  // Anyone can fund the treasury
  function fundTreasury() external payable {
    require(msg.value > 0, "Must send some value");
    balance += msg.value;
    
    emit TreasuryFunded(
      msg.value,
      msg.sender,
      block.timestamp,
      balance
    );
  }
  
  // View functions
  function getBalance() external view returns (uint256) {
    return balance;
  }
  
  function getTotalFeesCollected() external view returns (uint256) {
    return totalFeesCollected;
  }
  
  function getAdmin() external view returns (address) {
    return owner();
  }
  
  // Receive function
  receive() external payable {
    balance += msg.value;
  }
} 