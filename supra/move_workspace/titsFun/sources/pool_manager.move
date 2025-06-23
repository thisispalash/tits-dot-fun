// =============================================================================
// POOL MANAGER MODULE
// =============================================================================
module tits_fun::pool_manager {
    
    use std::signer;
    use std::vector;
    use std::error;
    
    use supra_framework::coin::{Self, Coin};
    use supra_framework::supra_coin::SupraCoin;
    use supra_framework::timestamp;
    use supra_framework::event;
    
    use tits_fun::token_factory::{Self, PoolToken};
    use tits_fun::math_utils;
    
    struct Pool has key {
      id: u64,
      l_value: u64, // Candle size
      h_value: u128, // Height parameter
      x_reserve: u128, // SupraCoin reserve
      y_reserve: u128, // Pool token reserve
      start_time: u64,
      end_time: u64,
      is_locked: bool,
      total_trades: u64,
      total_deviation: u128,
      trades: vector<TradeData>,
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
    }
    
    #[event]
    struct TradeEvent has drop, store {
      pool_id: u64,
      trader: address,
      quantity: u128,
      side: bool,
      timestamp: u64,
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
    
    fun init_module(admin: &signer) {
      move_to(admin, PoolRegistry {
        pools: vector::empty<u64>(),
        current_pool_id: 0,
        admin: signer::address_of(admin),
      });
    }
    
    public entry fun create_pool(
      admin: &signer,
      l_value: u64,
      delay_seconds: u64
    ) acquires PoolRegistry {
      let admin_addr = signer::address_of(admin);
      let registry = borrow_global_mut<PoolRegistry>(admin_addr);
      
      let pool_id = registry.current_pool_id + 1;
      registry.current_pool_id = pool_id;
      
      // Calculate H value: H_{i+1} = H_i + sqrt(L), H_0 = 1
      let h_value = if (pool_id == 1) {
        1_000000000u128 // H_0 = 1 with precision
      } else {
        // For simplicity, using base formula
        1_000000000u128 + math_utils::sqrt((l_value as u128) * 1000000000u128)
      };
      
      let now = timestamp::now_seconds();
      let start_time = now + delay_seconds;
      let end_time = start_time + 24 * 3600; // 24 hours
      
      let pool = Pool {
        id: pool_id,
        l_value,
        h_value,
        x_reserve: 0,
        y_reserve: 1000000_000000u128, // 1M tokens with 8 decimals
        start_time,
        end_time,
        is_locked: false,
        total_trades: 0,
        total_deviation: 0,
        trades: vector::empty<TradeData>(),
      };
      
      vector::push_back(&mut registry.pools, pool_id);
      move_to(admin, pool);
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
    ) acquires Pool, PoolRegistry {
      let trader_addr = signer::address_of(trader);
      let pool = borrow_global_mut<Pool>(admin_addr);
      
      // Validations
      assert!(pool.id == pool_id, error::invalid_argument(EINVALID_POOL));
      assert!(!pool.is_locked, error::invalid_state(EPOOL_LOCKED));
      
      let now = timestamp::now_seconds();
      assert!(now >= pool.start_time && now <= pool.end_time, error::invalid_state(EPOOL_EXPIRED));
      assert!(delay <= 36 * 3600, error::invalid_argument(EINVALID_DELAY));
      
      let quantity_u128 = (quantity as u128);
      
      // Calculate output using bonded curve
      let curve_y = math_utils::calculate_curve_y(
        pool.x_reserve + quantity_u128,
        pool.h_value,
        (pool.l_value as u128)
      );
      
      // Calculate AMM output
      let out_tokens = if (side) {
        // Buying pool tokens with SupraCoin
        math_utils::calculate_amm_out(quantity_u128, pool.x_reserve, pool.y_reserve)
      } else {
        // Selling pool tokens for SupraCoin
        math_utils::calculate_amm_out(quantity_u128, pool.y_reserve, pool.x_reserve)
      };
      
      // Calculate deviation
      let deviation = if (pool.y_reserve > 0) {
        (out_tokens * 10000) / pool.y_reserve // basis points
      } else { 0 };
      
      // Update reserves
      if (side) {
        pool.x_reserve = pool.x_reserve + quantity_u128;
        pool.y_reserve = pool.y_reserve - out_tokens;
      } else {
        pool.x_reserve = pool.x_reserve - out_tokens;
        pool.y_reserve = pool.y_reserve + quantity_u128;
      };
      
      // Record trade
      let trade_data = TradeData {
        trader: trader_addr,
        quantity: quantity_u128,
        side,
        deviation,
        timestamp: now,
        candle_size,
        delay,
      };
      
      vector::push_back(&mut pool.trades, trade_data);
      pool.total_trades = pool.total_trades + 1;
      pool.total_deviation = pool.total_deviation + deviation;
      
      // Handle payment
      coin::deposit(admin_addr, supra_payment);
      
      // Emit event
      event::emit(TradeEvent {
        pool_id,
        trader: trader_addr,
        quantity: quantity_u128,
        side,
        timestamp: now,
      });
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
    public fun get_pool_deviation(admin: address, pool_id: u64): u128 acquires Pool {
      let pool = borrow_global<Pool>(admin);
      assert!(pool.id == pool_id, error::invalid_argument(EINVALID_POOL));
      
      math_utils::calculate_deviation(
        (pool.total_trades as u128),
        pool.total_deviation
      )
    }
    
    #[view]
    public fun is_pool_locked(admin: address, pool_id: u64): bool acquires Pool {
      let pool = borrow_global<Pool>(admin);
      pool.is_locked
    }
    
    // Function to determine winner (lowest deviation, most recent in case of tie)
    public fun determine_winner(admin: &signer, pool_id: u64): (address, u128) acquires Pool {
      let pool = borrow_global<Pool>(signer::address_of(admin));
      let trades = &pool.trades;
      let len = vector::length(trades);
      
      if (len == 0) {
        return (@0x0, 0)
      };
      
      let mut winner = @0x0;
      let mut min_deviation = 18446744073709551615u128; // Max u128
      let mut latest_timestamp = 0u64;
      
      let mut i = 0;
      while (i < len) {
        let trade = vector::borrow(trades, i);
        if (trade.deviation < min_deviation || 
          (trade.deviation == min_deviation && trade.timestamp > latest_timestamp)) {
          winner = trade.trader;
          min_deviation = trade.deviation;
          latest_timestamp = trade.timestamp;
        };
        i = i + 1;
      };
      
      (winner, min_deviation)
    }
}