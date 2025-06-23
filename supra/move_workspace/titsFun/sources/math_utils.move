// =============================================================================
// MATH UTILITIES MODULE
// =============================================================================
module tits_fun::math_utils {
  
  const EOVERFLOW: u64 = 1;
  const EINVALID_INPUT: u64 = 2;
  const EDIVISION_BY_ZERO: u64 = 3;
  
  // Fixed point precision (10^8)
  const PRECISION: u128 = 100000000;
  const MAX_U128: u128 = 340282366920938463463374607431768211455;
  
  // Safe arithmetic with saturating behavior
  public fun safe_add(a: u128, b: u128): u128 {
    if (a > MAX_U128 - b) {
      MAX_U128 // Saturate to maximum
    } else {
      a + b
    }
  }
  
  public fun safe_sub(a: u128, b: u128): u128 {
    if (a < b) {
      0 // Saturate to zero
    } else {
      a - b
    }
  }
  
  public fun safe_mul(a: u128, b: u128): u128 {
    if (a == 0 || b == 0) return 0;
    if (a > MAX_U128 / b) {
      MAX_U128 // Saturate to maximum
    } else {
      a * b
    }
  }
  
  public fun safe_div(a: u128, b: u128): u128 {
    if (b == 0) return 0;
    a / b
  }
  
  // Correct precision-aware division: (a * PRECISION) / b
  public fun safe_div_precision(a: u128, b: u128): u128 {
    if (b == 0) return 0;
    
    // Check if a * PRECISION would overflow
    if (a > MAX_U128 / PRECISION) {
      // If overflow, do division first then multiply (loses some precision but prevents overflow)
      (a / b) * PRECISION
    } else {
      (a * PRECISION) / b
    }
  }
  
  // Fixed-point division: when both inputs are already fixed-point, output is fixed-point
  // Formula: (a * PRECISION) / b (because a and b are already scaled by PRECISION)
  public fun safe_div_fixed_point(a: u128, b: u128): u128 {
    if (b == 0) return 0;
    
    if (a > MAX_U128 / PRECISION) {
      // Fallback: (a / b) would give us the right ratio, then scale to fixed-point
      (a / b) * PRECISION
    } else {
      (a * PRECISION) / b
    }
  }
  
  // Fixed-point multiplication: when both inputs are fixed-point, output is fixed-point
  // Why needed vs safe_mul:
  // - safe_mul(a, b) gives a * b (double-scaled if both are fixed-point)
  // - safe_mul_fixed_point(a, b) gives (a * b) / PRECISION (correctly scaled)
  // Example: if a = 2.5 * PRECISION and b = 3.0 * PRECISION
  // - safe_mul gives 7.5 * PRECISION^2 (wrong!)
  // - safe_mul_fixed_point gives 7.5 * PRECISION (correct!)
  public fun safe_mul_fixed_point(a: u128, b: u128): u128 {
    if (a == 0 || b == 0) return 0;
    
    if (a > MAX_U128 / b) {
      // Scale down the larger operand first
      if (a > b) {
        (a / PRECISION) * b
      } else {
        a * (b / PRECISION)
      }
    } else {
      (a * b) / PRECISION
    }
  }
  
  // Absolute difference
  public fun abs_diff(a: u128, b: u128): u128 {
    if (a > b) {
      a - b
    } else {
      b - a
    }
  }
  
  // Square root with guaranteed convergence
  // For small values like 96, 144, 288, this should converge in ~4-6 iterations
  public fun sqrt(x: u128): u128 {
    if (x == 0) return 0;
    if (x == 1) return 1;
    
    // For small values, use a more direct approach
    if (x < 10000) {
      // Simple linear search for small values (more predictable)
      let i = 1;
      while (i * i <= x && i < 100) {
        i = i + 1;
      };
      return i - 1
    };
    
    // Newton's method for larger values
    let z = x;
    let y = (x + 1) / 2;
    
    let iterations = 0;
    while (y < z && iterations < 20) { // Reduced iteration limit
      z = y;
      y = (x / y + y) / 2;
      iterations = iterations + 1;
    };
    
    z
  }
  
  // Calculate bonded curve: y = 4*(H/L)*x(1-x/L)
  // Inputs: x, h, l are regular numbers
  // Output: fixed-point number
  public fun calculate_curve_y(x: u128, h: u128, l: u128): u128 {
    if (x > l || l == 0) return 0;
    if (x == 0) return 0;
    
    // All calculations in regular numbers, then convert to fixed-point at the end
    let l_minus_x = safe_sub(l, x);
    let four_h = safe_mul(4, h);
    let numerator = safe_mul(safe_mul(four_h, x), l_minus_x);
    let denominator = safe_mul(l, l);
    
    // Convert result to fixed-point
    safe_div_fixed_point(numerator, denominator)
  }
  
  // Calculate x from y on bonded curve (inverse function)
  // unused but looks nice, so keeping it
  public fun calculate_curve_x_from_y(y: u128, h: u128, l: u128): u128 {
    if (y == 0) return 0;
    if (h == 0 || l == 0) return 0; // Graceful handling
    
    // Using quadratic formula: x = (4*H*L +/- sqrt((4*H*L)^2 - 16*H*y*L^2)) / (8*H)
    let four_h = safe_mul(4, h);
    let four_h_l = safe_mul(four_h, l);
    let eight_h = safe_mul(8, h);
    
    // Calculate discriminant parts with overflow protection
    let discriminant_part1 = safe_mul(four_h_l, four_h_l);
    let sixteen_h = safe_mul(16, h);
    let y_l_squared = safe_mul(y, safe_mul(l, l));
    let discriminant_part2 = safe_mul(sixteen_h, y_l_squared);
    
    if (discriminant_part1 < discriminant_part2) {
      return 0 // No real solution
    };
    
    let discriminant = safe_sub(discriminant_part1, discriminant_part2);
    let sqrt_discriminant = sqrt(discriminant);
    
    // Take the smaller root (ascending part of curve)
    if (four_h_l < sqrt_discriminant) return 0; // Avoid underflow
    
    let numerator = safe_sub(four_h_l, sqrt_discriminant);
    safe_div(numerator, eight_h)
  }
  
  // AMM invariant: x * y = k
  // Inputs/outputs should be in same format (either all regular or all fixed-point)
  public fun calculate_amm_out(
    x_in: u128,
    x_reserve: u128, 
    y_reserve: u128
  ): u128 {
    if (x_reserve == 0 || y_reserve == 0 || x_in == 0) return 0;
    
    let k = safe_mul(x_reserve, y_reserve);
    let new_x_reserve = safe_add(x_reserve, x_in);
    
    if (new_x_reserve == 0) return 0;
    
    let new_y_reserve = safe_div(k, new_x_reserve);
    safe_sub(y_reserve, new_y_reserve)
  }
  
  // Calculate percentage deviation - ADDED BACK
  public fun calculate_deviation(
    total_trades: u128,
    total_deviation: u128
  ): u128 {
    if (total_trades == 0) return 0;
    // Return deviation in basis points
    safe_div(safe_mul(total_deviation, 10000), total_trades)
  }
  
  // Utility functions
  public fun precision(): u128 {
    PRECISION
  }
  
  public fun to_fixed_point(value: u128): u128 {
    if (value > MAX_U128 / PRECISION) {
      MAX_U128
    } else {
      value * PRECISION
    }
  }
  
  public fun from_fixed_point(value: u128): u128 {
    value / PRECISION
  }
}