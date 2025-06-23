// =============================================================================
// MATH UTILITIES MODULE
// =============================================================================
module tits_fun::math_utils {
  use std::error;
  
  const EOVERFLOW: u64 = 1;
  const EINVALID_INPUT: u64 = 2;
  
  // Fixed point precision (10^8)
  const PRECISION: u128 = 100000000;
  
  // Square root using Newton's method
  public fun sqrt(x: u128): u128 {
    if (x == 0) return 0;
    
    let mut z = x;
    let mut y = (x + 1) / 2;
      
    while (y < z) {
      z = y;
      y = (x / y + y) / 2;
    };
    
    z
  }
  
  // Calculate bonded curve: y = 4*(H/L)*x(1-x/L)
  public fun calculate_curve_y(x: u128, h: u128, l: u128): u128 {
    assert!(x <= l, error::invalid_argument(EINVALID_INPUT));
    
    let numerator = 4 * h * x * (l - x);
    let denominator = l * l;
    
    (numerator * PRECISION) / (denominator * PRECISION / PRECISION)
  }
  
  // AMM invariant: x * y = k
  public fun calculate_amm_out(
    x_in: u128,
    x_reserve: u128, 
    y_reserve: u128
  ): u128 {
    let k = x_reserve * y_reserve;
    let new_x = x_reserve + x_in;
    let new_y = k / new_x;
      
    y_reserve - new_y
  }
  
  // Calculate percentage deviation
  public fun calculate_deviation(
    total_trades: u128,
    total_deviation: u128
  ): u128 {
    if (total_trades == 0) return 0;
    (total_deviation * 10000) / total_trades // basis points
  }
}