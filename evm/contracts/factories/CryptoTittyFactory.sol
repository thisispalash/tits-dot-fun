// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../CryptoTitty.sol";

contract CryptoTittyFactory is Ownable {
  CryptoTitty[] public deployedTokens;
  mapping(uint256 => address) public poolIdToToken;
  mapping(address => bool) public isDeployedToken;

  event TokenCreated(
    uint256 indexed poolId,
    address indexed tokenAddress,
    string name,
    string symbol,
    uint256 initialSupply,
    address creator,
    uint256 timestamp
  );

  constructor(address initialOwner) Ownable(initialOwner) {}

  function createToken(
    string memory name,
    string memory symbol,
    uint256 initialSupply,
    uint256 poolId
  ) external onlyOwner returns (address) {
    require(poolIdToToken[poolId] == address(0), "Pool ID already exists");

    CryptoTitty newToken = new CryptoTitty(
      name,
      symbol,
      initialSupply,
      poolId,
      msg.sender
    );

    address tokenAddress = address(newToken);

    deployedTokens.push(newToken);
    poolIdToToken[poolId] = tokenAddress;
    isDeployedToken[tokenAddress] = true;

    emit TokenCreated(
      poolId,
      tokenAddress,
      name,
      symbol,
      initialSupply,
      msg.sender,
      block.timestamp
    );

    return tokenAddress;
  }

  function getTokenByPoolId(uint256 poolId) external view returns (address) {
    return poolIdToToken[poolId];
  }

  function getAllDeployedTokens() external view returns (address[] memory) {
    address[] memory tokens = new address[](deployedTokens.length);
    for (uint256 i = 0; i < deployedTokens.length; i++) {
      tokens[i] = address(deployedTokens[i]);
    }
    return tokens;
  }

  function getDeployedTokenCount() external view returns (uint256) {
    return deployedTokens.length;
  }

  function isTokenDeployed(
    address tokenAddress
  ) external view returns (bool) {
    return isDeployedToken[tokenAddress];
  }
}
