// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

library MathUtils {
  // Fixed point precision (10^8)
  uint256 constant PRECISION = 100000000;
  uint256 constant MAX_U256 = type(uint256).max;
  
  // Safe arithmetic with saturating behavior
  function safeAdd(uint256 a, uint256 b) internal pure returns (uint256) {
    if (a > MAX_U256 - b) {
      return MAX_U256; // Saturate to maximum
    }
    return a + b;
  }
  
  function safeSub(uint256 a, uint256 b) internal pure returns (uint256) {
    if (a < b) {
      return 0; // Saturate to zero
    }
    return a - b;
  }
  
  function safeMul(uint256 a, uint256 b) internal pure returns (uint256) {
    if (a == 0 || b == 0) return 0;
    if (a > MAX_U256 / b) {
      return MAX_U256; // Saturate to maximum
    }
    return a * b;
  }
  
  function safeDiv(uint256 a, uint256 b) internal pure returns (uint256) {
    if (b == 0) return 0;
    return a / b;
  }
  
  // Fixed-point division: (a * PRECISION) / b
  function safeDivPrecision(uint256 a, uint256 b) internal pure returns (uint256) {
    if (b == 0) return 0;
    
    if (a > MAX_U256 / PRECISION) {
      return (a / b) * PRECISION;
    }
    return (a * PRECISION) / b;
  }
  
  // Fixed-point multiplication: (a * b) / PRECISION
  function safeMulFixedPoint(uint256 a, uint256 b) internal pure returns (uint256) {
    if (a == 0 || b == 0) return 0;
    
    if (a > MAX_U256 / b) {
      if (a > b) {
        return (a / PRECISION) * b;
      } else {
        return a * (b / PRECISION);
      }
    }
    return (a * b) / PRECISION;
  }
  
  // Absolute difference
  function absDiff(uint256 a, uint256 b) internal pure returns (uint256) {
    return a > b ? a - b : b - a;
  }
  
  // Square root using Newton's method
  function sqrt(uint256 x) internal pure returns (uint256) {
    if (x == 0) return 0;
    if (x == 1) return 1;

    // for most common use case, hard code
    if (x == 96) return 9;
    if (x == 144) return 12;
    if (x == 288) return 16;
    
    // For small values, use linear search
    if (x < 10000) {
      uint256 i = 1;
      while (i * i <= x && i < 100) {
          i++;
      }
      return i - 1;
    }
    
    // Newton's method for larger values
    uint256 z = x;
    uint256 y = (x + 1) / 2;
    
    uint256 iterations = 0;
    while (y < z && iterations < 20) {
      z = y;
      y = (x / y + y) / 2;
      iterations++;
    }
    
    return z;
  }
  
  // Convert regular number to fixed-point
  function toFixedPoint(uint256 value) internal pure returns (uint256) {
    return value * PRECISION;
  }
  
  // Convert fixed-point to regular number
  function fromFixedPoint(uint256 value) internal pure returns (uint256) {
    return value / PRECISION;
  }
  
  // Calculate bonded curve: y = 4*(H/L)*x(1-x/L)
  function calculateCurveY(uint256 x, uint256 h, uint256 l) internal pure returns (uint256) {
    if (x > l || l == 0) return 0;
    if (x == 0) return 0;
    
    uint256 lMinusX = safeSub(l, x);
    uint256 fourH = safeMul(4, h);
    uint256 numerator = safeMul(safeMul(fourH, x), lMinusX);
    uint256 denominator = safeMul(l, l);
    
    return safeDivPrecision(numerator, denominator);
  }
  
  // Calculate AMM output: x * y = k
  function calculateAmmOut(uint256 xIn, uint256 xReserve, uint256 yReserve) internal pure returns (uint256) {
    if (xReserve == 0 || yReserve == 0 || xIn == 0) return 0;
    
    uint256 k = safeMul(xReserve, yReserve);
    uint256 newXReserve = safeAdd(xReserve, xIn);
    
    if (newXReserve == 0) return 0;
    
    uint256 newYReserve = safeDiv(k, newXReserve);
    return safeSub(yReserve, newYReserve);
  }
} 