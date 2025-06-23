// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CryptoTitty is ERC20, Ownable {
  uint256 public poolId;
  uint256 public createdAt;
  
  constructor(
    string memory name,
    string memory symbol,
    uint256 initialSupply,
    uint256 _poolId,
    address initialOwner
  ) ERC20(name, symbol) Ownable(initialOwner) {
    poolId = _poolId;
    createdAt = block.timestamp;
    
    if (initialSupply > 0) {
      _mint(initialOwner, initialSupply);
    }
  }
  
  function mint(address to, uint256 amount) external onlyOwner {
    _mint(to, amount);
  }
  
  function burn(uint256 amount) external {
    _burn(msg.sender, amount);
  }
}