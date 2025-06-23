// =============================================================================
// POOL MANAGER MODULE
// =============================================================================
module tits_fun::pool_manager {
    
    use std::signer;
    use std::vector;
    use std::error;
    use std::option::{Self, Option};
    
    use supra_framework::coin::{Self, Coin};
    use supra_framework::supra_coin::SupraCoin;
    use supra_framework::timestamp;
    use supra_framework::event;
    
    use tits_fun::token_factory::{Self, PoolToken};
    use tits_fun::math_utils;
    use tits_fun::tits_treasury;
    
    struct Pool has key {
      id: u64,
      l_value: u64, // Candle size
      h_value: u128, // Height parameter (fixed-point)
      x_reserve: u128, // SupraCoin reserve (fixed-point)
      y_reserve: u128, // Pool token reserve (fixed-point)
      start_time: u64,
      end_time: u64,
      is_locked: bool,
      total_trades: u64,
      trader_deviations: vector<TraderDeviation>,
      winner_gas_paid: u64,
    }
    
    struct TraderDeviation has store {
      trader: address,
      deviation: u128, // basis points
      trade_count: u64,
      last_updated: u64,
    }
    
    struct TradeData has store {
      trader: address,
      quantity: u128,
      side: bool, // true = buy, false = sell
      deviation: u128,
      timestamp: u64,
      candle_size: u64,
      delay: u64,
    }
    
    struct PoolRegistry has key {
      pools: vector<u64>,
      current_pool_id: u64,
      admin: address,
      previous_h_values: vector<u128>, // Track H values (fixed-point)
    }
    
    #[event]
    struct TradeEvent has drop, store {
      pool_id: u64,
      trader: address,
      quantity: u128,
      side: bool,
      timestamp: u64,
      deviation: u128,
    }
    
    #[event]
    struct PoolLocked has drop, store {
      pool_id: u64,
      reason: vector<u8>,
      timestamp: u64,
    }
    
    const EINVALID_POOL: u64 = 1;
    const EPOOL_LOCKED: u64 = 2;
    const EPOOL_EXPIRED: u64 = 3;
    const EINVALID_DELAY: u64 = 4;
    const EINSUFFICIENT_TREASURY: u64 = 5;
    const EZERO_RESERVES: u64 = 7;
    
    fun init_module(admin: &signer) {
      move_to(admin, PoolRegistry {
        pools: vector::empty<u64>(),
        current_pool_id: 0,
        admin: signer::address_of(admin),
        previous_h_values: vector::empty<u128>(),
      });
    }
    
    public entry fun create_pool(
      admin: &signer,
      l_value: u64,
      delay_seconds: u64,
      winner_gas_paid: u64
    ) acquires PoolRegistry {
      let admin_addr = signer::address_of(admin);
      let registry = borrow_global_mut<PoolRegistry>(admin_addr);
      
      let pool_id = registry.current_pool_id + 1;
      registry.current_pool_id = pool_id;
      
      // Calculate H value: H_{i+1} = sqrt(H_i) * sqrt(L), H_0 = 1
      let h_value = if (pool_id == 1) {
        let h_0 = math_utils::to_fixed_point(1); // H_0 = 1 in fixed-point
        vector::push_back(&mut registry.previous_h_values, h_0);
        h_0
      } else {
        let previous_h = *vector::borrow(&registry.previous_h_values, (pool_id - 2) as u64);
        let sqrt_l = math_utils::sqrt(l_value as u128); // sqrt of regular number
        let sqrt_l_fixed = math_utils::to_fixed_point(sqrt_l); // convert to fixed-point
        let sqrt_h = math_utils::sqrt(previous_h as u128); // sqrt of regular number
        let sqrt_h_fixed = math_utils::to_fixed_point(previous_h); // convert to fixed-point
        let new_h = math_utils::safe_mul(sqrt_h_fixed, sqrt_l_fixed);
        vector::push_back(&mut registry.previous_h_values, new_h);
        new_h
      };
      
      // Calculate initial x_reserve: 2 * winner_gas_paid from treasury
      let initial_x_reserve = math_utils::to_fixed_point(math_utils::safe_mul(winner_gas_paid as u128, 2));
      
      // Verify treasury has sufficient funds (treasury works in regular numbers)
      let treasury_balance = treasury::get_balance(admin_addr);
      let required_amount = winner_gas_paid * 2;
      assert!(treasury_balance >= required_amount, error::invalid_state(EINSUFFICIENT_TREASURY));
      
      let now = timestamp::now_seconds();
      let start_time = now + delay_seconds;
      let end_time = start_time + 24 * 3600; // 24 hours
      
      let pool = Pool {
        id: pool_id,
        l_value,
        h_value,
        x_reserve: initial_x_reserve,
        y_reserve: math_utils::to_fixed_point(1000000), // 1M tokens in fixed-point
        start_time,
        end_time,
        is_locked: false,
        total_trades: 0,
        trader_deviations: vector::empty<TraderDeviation>(),
        winner_gas_paid,
      };
      
      vector::push_back(&mut registry.pools, pool_id);
      move_to(admin, pool);
      
      // Deduct from treasury (treasury works in regular numbers)
      treasury::emergency_start_pool(admin, required_amount, pool_id);
    }
    
    public entry fun trade(
      trader: &signer,
      admin_addr: address,
      pool_id: u64,
      quantity: u64,
      side: bool, // true = buy, false = sell
      candle_size: u64,
      delay: u64,
      supra_payment: Coin<SupraCoin>
    ) acquires Pool {
      let trader_addr = signer::address_of(trader);
      let pool = borrow_global_mut<Pool>(admin_addr);
      
      // Validations
      assert!(pool.id == pool_id, error::invalid_argument(EINVALID_POOL));
      assert!(!pool.is_locked, error::invalid_state(EPOOL_LOCKED));
      
      let now = timestamp::now_seconds();
      assert!(now >= pool.start_time && now <= pool.end_time, error::invalid_state(EPOOL_EXPIRED));
      assert!(delay <= 12 * 3600, error::invalid_argument(EINVALID_DELAY));
      
      let quantity_fixed = math_utils::to_fixed_point(quantity as u128); // Convert to fixed-point
      
      // Ensure reserves are not zero
      assert!(pool.x_reserve > 0 && pool.y_reserve > 0, error::invalid_state(EZERO_RESERVES));
      
      // Calculate AMM output (what we actually execute) - all in fixed-point
      let amm_output = if (side) {
        // Buying pool tokens with SupraCoin
        math_utils::calculate_amm_out(quantity_fixed, pool.x_reserve, pool.y_reserve)
      } else {
        // Selling pool tokens for SupraCoin  
        math_utils::calculate_amm_out(quantity_fixed, pool.y_reserve, pool.x_reserve)
      };
      
      // Calculate bonded curve expected output (for deviation calculation)
      let curve_expected = if (side) {
        // For buy: how many tokens should we get according to bonded curve
        let new_x_regular = math_utils::from_fixed_point(math_utils::safe_add(pool.x_reserve, quantity_fixed));
        let h_regular = math_utils::from_fixed_point(pool.h_value);
        math_utils::calculate_curve_y(new_x_regular, h_regular, pool.l_value as u128)
      } else {
        // For sell: we're selling pool tokens, so compare the SupraCoin we should get
        // Use current position on bonded curve as reference
        let current_x_regular = math_utils::from_fixed_point(pool.x_reserve);
        let h_regular = math_utils::from_fixed_point(pool.h_value);
        math_utils::calculate_curve_y(current_x_regular, h_regular, pool.l_value as u128)
      };
      
      // Calculate deviation: |AMM_output - Curve_expected| / Curve_expected * 10000 (basis points)
      let deviation = if (curve_expected > 0) {
        let diff = math_utils::abs_diff(amm_output, curve_expected);
        math_utils::safe_div_to_fixed_point(math_utils::safe_mul(diff, 10000), curve_expected)
      } else { 0 };
      
      // Update reserves based on AMM execution (all in fixed-point)
      if (side) {
        pool.x_reserve = math_utils::safe_add(pool.x_reserve, quantity_fixed);
        pool.y_reserve = math_utils::safe_sub(pool.y_reserve, amm_output);
      } else {
        pool.x_reserve = math_utils::safe_sub(pool.x_reserve, amm_output);
        pool.y_reserve = math_utils::safe_add(pool.y_reserve, quantity_fixed);
      };
      
      // Update trader deviation (averaging approach)
      let deviation_bp = math_utils::from_fixed_point(deviation); // Convert to regular for storage
      update_trader_deviation(pool, trader_addr, deviation_bp);
      
      pool.total_trades = pool.total_trades + 1;
      
      // Collect fees (extract 1% fee from payment)
      let payment_value = coin::value(&supra_payment);
      let fee_amount = payment_value / 100; // 1% fee
      let (fee_coin, remaining_coin) = coin::extract(&mut supra_payment, fee_amount);
      
      // Send fee to treasury
      treasury::collect_fees(admin_addr, fee_amount, fee_coin);
      
      // Handle remaining payment
      coin::deposit(admin_addr, remaining_coin);
      coin::deposit(admin_addr, supra_payment); // Handle the original coin
      
      // Emit event
      event::emit(TradeEvent {
        pool_id,
        trader: trader_addr,
        quantity: quantity as u128,
        side,
        timestamp: now,
        deviation: deviation_bp,
      });
    }
    
    // Helper function to update trader deviation with averaging
    fun update_trader_deviation(pool: &mut Pool, trader: address, new_deviation: u128) {
      let traders = &mut pool.trader_deviations;
      let len = vector::length(traders);
      let mut found = false;
      
      let mut i = 0;
      while (i < len) {
        let trader_dev = vector::borrow_mut(traders, i);
        if (trader_dev.trader == trader) {
          // Average: (existing_deviation + current_deviation) / 2
          trader_dev.deviation = (trader_dev.deviation + new_deviation) / 2;
          trader_dev.trade_count = trader_dev.trade_count + 1;
          trader_dev.last_updated = timestamp::now_seconds();
          found = true;
          break
        };
        i = i + 1;
      };
      
      if (!found) {
        let new_trader_dev = TraderDeviation {
          trader,
          deviation: new_deviation,
          trade_count: 1,
          last_updated: timestamp::now_seconds(),
        };
        vector::push_back(traders, new_trader_dev);
      };
    }
    
    public entry fun lock_pool(
      admin: &signer,
      pool_id: u64,
      reason: vector<u8>
    ) acquires Pool {
      let pool = borrow_global_mut<Pool>(signer::address_of(admin));
      assert!(pool.id == pool_id, error::invalid_argument(EINVALID_POOL));
      
      pool.is_locked = true;
      
      event::emit(PoolLocked {
        pool_id,
        reason,
        timestamp: timestamp::now_seconds(),
      });
    }
    
    #[view]
    public fun get_pool_info(admin: address, pool_id: u64): (u64, u128, u128, u128, bool) acquires Pool {
      let pool = borrow_global<Pool>(admin);
      assert!(pool.id == pool_id, error::invalid_argument(EINVALID_POOL));
      (pool.l_value, pool.h_value, pool.x_reserve, pool.y_reserve, pool.is_locked)
    }
    
    #[view]
    public fun is_pool_locked(admin: address, pool_id: u64): bool acquires Pool {
      let pool = borrow_global<Pool>(admin);
      pool.is_locked
    }
    
    // Function to determine winner (lowest deviation, most recent in case of tie)
    public fun determine_winner(admin: &signer, pool_id: u64): (address, u128) acquires Pool {
      let pool = borrow_global<Pool>(signer::address_of(admin));
      let trader_deviations = &pool.trader_deviations;
      let len = vector::length(trader_deviations);
      
      if (len == 0) {
        return (@0x0, 0)
      };
      
      let mut winner = @0x0;
      let mut min_deviation = 18446744073709551615u128; // Max u128
      let mut latest_timestamp = 0u64;
      
      let mut i = 0;
      while (i < len) {
        let trader_dev = vector::borrow(trader_deviations, i);
        if (trader_dev.deviation < min_deviation || 
            (trader_dev.deviation == min_deviation && trader_dev.last_updated > latest_timestamp)) {
          winner = trader_dev.trader;
          min_deviation = trader_dev.deviation;
          latest_timestamp = trader_dev.last_updated;
        };
        i = i + 1;
      };
      
      (winner, min_deviation)
    }
    
    #[view]
    public fun get_trader_deviation(admin: address, pool_id: u64, trader: address): u128 acquires Pool {
      let pool = borrow_global<Pool>(admin);
      assert!(pool.id == pool_id, error::invalid_argument(EINVALID_POOL));
      
      let trader_deviations = &pool.trader_deviations;
      let len = vector::length(trader_deviations);
      
      let mut i = 0;
      while (i < len) {
        let trader_dev = vector::borrow(trader_deviations, i);
        if (trader_dev.trader == trader) {
          return trader_dev.deviation
        };
        i = i + 1;
      };
      
      0 // Return 0 if trader not found
    }
}