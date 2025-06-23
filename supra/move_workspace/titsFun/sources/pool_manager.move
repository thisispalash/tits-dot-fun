// =============================================================================
// POOL MANAGER MODULE
// =============================================================================
module tits_fun::pool_manager {
    
    use std::signer;
    use std::vector;
    use std::error;
    use std::string;
    
    use supra_framework::coin::{Self, Coin};
    use supra_framework::supra_coin::SupraCoin;
    use supra_framework::timestamp;
    use supra_framework::event;

    use supra_addr::supra_vrf;
    
    use tits_fun::token_factory;
    use tits_fun::math_utils;
    use tits_fun::tits_treasury;
    
    struct Pool has key {
      id: u64,
      l_value: u64, // Candle size
      h_value: u128, // Height parameter (fixed-point)
      x_reserve: u128, // SupraCoin reserve (fixed-point)
      y_reserve: u128, // Pool token reserve (fixed-point)
      token_address: address, // Resource account address for this pool's token
      start_time: u64,
      end_time: u64,
      is_locked: bool,
      total_trades: u64,
      trader_deviations: vector<TraderDeviation>,
      current_winner: address,
      winner_proposed_delay: u64,
      winner_proposed_candle_size: u64,
    }
    
    struct TraderDeviation has store {
      trader: address,
      deviation: u128, // basis points
      trade_count: u64,
      last_updated: u64,
    }
    
    // unused, kept for now
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
      // Queue for next pool
      queued_pool_start_time: u64,
      queued_pool_delay: u64,
      queued_pool_candle_size: u64,
      queued_pool_winner: address, // @0x0 if locked, actual winner if time expired
    }
    
    struct PendingVRF has key {
      pool_id: u64,
      caller: address,
      reason: vector<u8>,
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
    
    #[event]
    struct PoolCreated has drop, store {
      pool_id: u64,
      token_address: address,
      l_value: u64,
      h_value: u128,
      start_time: u64,
      end_time: u64,
      creator: address,
      timestamp: u64,
    }
    
    #[event]
    struct NewWinnerDetected has drop, store {
      pool_id: u64,
      winner: address,
      deviation: u128,
      proposed_delay: u64,
      proposed_candle_size: u64,
      timestamp: u64,
    }
    
    #[event] 
    struct PoolWinnerFinalized has drop, store {
      pool_id: u64,
      winner: address,
      final_deviation: u128,
      next_pool_delay: u64,
      next_pool_candle_size: u64,
      timestamp: u64,
    }
    
    #[event]
    struct PoolLockedWithRandomParams has drop, store {
      pool_id: u64,
      reason: vector<u8>,
      random_candle_size: u64,
      random_delay: u64,
      random_l_value: u64,
      timestamp: u64,
    }
    
    const EINVALID_POOL: u64 = 1;
    const EPOOL_LOCKED: u64 = 2;
    const EPOOL_EXPIRED: u64 = 3;
    const EINVALID_DELAY: u64 = 4;
    const EINSUFFICIENT_TREASURY: u64 = 5;
    const EZERO_RESERVES: u64 = 7;
    
    // Fee configuration
    const FEE_BASIS_POINTS: u64 = 10; // 0.1% = 10 basis points
    
    // Add new error constant
    const EINVALID_CANDLE_SIZE: u64 = 8;
    
    fun init_module(admin: &signer) {
      move_to(admin, PoolRegistry {
        pools: vector::empty<u64>(),
        current_pool_id: 0,
        admin: signer::address_of(admin),
        previous_h_values: vector::empty<u128>(),
        queued_pool_start_time: 0,
        queued_pool_delay: 0,
        queued_pool_candle_size: 0,
        queued_pool_winner: @0x0,
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
      
      // Calculate H value: H_{i+1} = sqrt(H_i) * sqrt(L), H_0 = 1
      let prev_h_value = if (pool_id == 1) {
        let h_0 = math_utils::to_fixed_point(1); // H_0 = 1 in fixed-point
        vector::push_back(&mut registry.previous_h_values, h_0);
        h_0
      } else {
        *vector::borrow(&registry.previous_h_values, (pool_id - 2))
      };
      
      // Common calculation: H_{i+1} = sqrt(H_i) * sqrt(L)
      let sqrt_l = math_utils::sqrt((l_value as u128)); // Fix: cast to u128
      let sqrt_l_fixed = math_utils::to_fixed_point(sqrt_l); // convert to fixed-point
      let sqrt_h_regular = math_utils::from_fixed_point(prev_h_value); // convert back to regular for sqrt
      let sqrt_h = math_utils::sqrt(sqrt_h_regular); // sqrt of regular number
      let sqrt_h_fixed = math_utils::to_fixed_point(sqrt_h); // convert to fixed-point
      let h_value = math_utils::safe_mul_fixed_point(sqrt_h_fixed, sqrt_l_fixed);
      vector::push_back(&mut registry.previous_h_values, h_value);
      
      // Create new token for this pool (each pool gets its own token!)
      let initial_token_supply = 1000000; // 1M tokens
      let (token_address, initial_tokens) = token_factory::create_pool_token(
        admin, 
        pool_id, 
        initial_token_supply
      );
      
      // Calculate initial x_reserve: 1 Supra from treasury
      let initial_x_reserve = math_utils::to_fixed_point(1_000_000_000); // 1 Supra in octas (1e9)
      
      // Verify treasury has sufficient funds (treasury works in regular numbers)
      let treasury_balance = tits_treasury::get_balance(admin_addr);
      let required_amount = 1_000_000_000; // 1 Supra in octas
      assert!(treasury_balance >= required_amount, error::invalid_state(EINSUFFICIENT_TREASURY));
      
      let now = timestamp::now_seconds();
      let start_time = now + delay_seconds;
      let end_time = start_time + 24 * 3600; // 24 hours
      
      let pool = Pool {
        id: pool_id,
        l_value,
        h_value,
        x_reserve: initial_x_reserve,
        y_reserve: math_utils::to_fixed_point((initial_token_supply as u128)), // Fix: cast to u128
        token_address, // Store the resource account address
        start_time,
        end_time,
        is_locked: false,
        total_trades: 0,
        trader_deviations: vector::empty<TraderDeviation>(),
        current_winner: @0x0,
        winner_proposed_delay: 0,
        winner_proposed_candle_size: 0,
      };
      
      vector::push_back(&mut registry.pools, pool_id);
      move_to(admin, pool);
      
      // Deduct from treasury (treasury works in regular numbers)
      tits_treasury::initialize_pool_funding(admin, required_amount, pool_id);
      
      // Store the initial tokens in the admin account (pool liquidity)
      coin::deposit(admin_addr, initial_tokens);
      
      // Emit pool creation event
      event::emit(PoolCreated {
        pool_id,
        token_address,
        l_value,
        h_value,
        start_time,
        end_time,
        creator: admin_addr,
        timestamp: now,
      });
    }
    
    public entry fun trade(
      trader: &signer,
      admin_addr: address,
      pool_id: u64,
      quantity: u64,
      side: bool, // true = buy, false = sell
      delay: u64,
      candle_size: u64,        // Proposed candle size for next pool
      supra_payment: Coin<SupraCoin>
    ) acquires Pool {
      let trader_addr = signer::address_of(trader);
      let pool = borrow_global_mut<Pool>(admin_addr);
      
      // Validations
      assert!(pool.id == pool_id, error::invalid_argument(EINVALID_POOL));
      assert!(!pool.is_locked, error::invalid_state(EPOOL_LOCKED));
      validate_candle_size(candle_size); // Add validation
      
      let now = timestamp::now_seconds();
      assert!(now >= pool.start_time && now <= pool.end_time, error::invalid_state(EPOOL_EXPIRED));
      assert!(delay <= 12 * 3600, error::invalid_argument(EINVALID_DELAY));
      
      let quantity_fixed = math_utils::to_fixed_point((quantity as u128)); // Fix: cast to u128
      
      // Ensure reserves are not zero
      assert!(pool.x_reserve > 0 && pool.y_reserve > 0, error::invalid_state(EZERO_RESERVES));
      
      // Calculate actual candle_size from current pool's L for current calculations
      let current_candle_size = (24 * 60) / pool.l_value;
      
      // Calculate current candle number based on time elapsed
      let time_elapsed = now - pool.start_time;
      let candle_duration = current_candle_size * 60; // convert to seconds
      let current_candle = if (time_elapsed < candle_duration) {
        0 // No complete candle yet
      } else {
        time_elapsed / candle_duration
      };
      
      // Use next candle number for expectation (current + 1)
      let next_candle = ((current_candle + 1) as u128); // Fix: cast to u128
      
      // Calculate bonded curve expected price for next candle
      let h_regular = math_utils::from_fixed_point(pool.h_value);
      let curve_expected = math_utils::calculate_curve_y(
        next_candle,          // x = next candle number
        h_regular,            // H value (regular number)
        (pool.l_value as u128) // Fix: cast to u128
      );
      
      // Calculate AMM output based on trade direction
      let (input_reserve, output_reserve, amm_output) = if (side) {
        // BUY: SupraCoin -> Pool tokens
        (pool.x_reserve, pool.y_reserve, math_utils::calculate_amm_out(quantity_fixed, pool.x_reserve, pool.y_reserve))
      } else {
        // SELL: Pool tokens -> SupraCoin  
        (pool.y_reserve, pool.x_reserve, math_utils::calculate_amm_out(quantity_fixed, pool.y_reserve, pool.x_reserve))
      };
      
      // Calculate deviation (common for both sides)
      let deviation = if (curve_expected > 0) {
        let diff = math_utils::abs_diff(amm_output, curve_expected);
        math_utils::safe_div_precision(math_utils::safe_mul(diff, 10000), curve_expected)
      } else { 0 };
      
      // Update reserves based on trade direction
      if (side) {
        // BUY: Add SupraCoin, subtract pool tokens
        pool.x_reserve = math_utils::safe_add(pool.x_reserve, quantity_fixed);
        pool.y_reserve = math_utils::safe_sub(pool.y_reserve, amm_output);
      } else {
        // SELL: Subtract SupraCoin, add pool tokens
        pool.x_reserve = math_utils::safe_sub(pool.x_reserve, amm_output);
        pool.y_reserve = math_utils::safe_add(pool.y_reserve, quantity_fixed);
      };
      
      // Execute payment and token transfers
      let amm_output_regular = math_utils::from_fixed_point(amm_output);
      if (side) {
        execute_buy_trade(trader_addr, admin_addr, supra_payment, (amm_output_regular as u64), pool.token_address); // Fix: pass correct params
      } else {
        execute_sell_trade(trader_addr, admin_addr, supra_payment, (amm_output_regular as u64)); // Fix: pass correct params
      };
      
      // Update trader deviation
      let deviation_bp = math_utils::from_fixed_point(deviation);
      update_trader_deviation(pool, trader_addr, deviation_bp);
      
      // Check if this trader is now the winner
      let (current_winner, min_deviation) = get_current_winner(pool);
      let previous_winner = pool.current_winner;
      let is_new_winner = current_winner != previous_winner && current_winner == trader_addr;
      
      // Update current winner in pool
      pool.current_winner = current_winner;
      pool.winner_proposed_delay = delay;
      pool.winner_proposed_candle_size = candle_size;
      
      if (is_new_winner) {
        // Emit event for automation to pick up
        event::emit(NewWinnerDetected {
          pool_id,
          winner: trader_addr,
          deviation: min_deviation,
          proposed_delay: delay,
          proposed_candle_size: candle_size,
          timestamp: timestamp::now_seconds(),
        });
      };
      
      pool.total_trades = pool.total_trades + 1;
      
      // Emit event
      event::emit(TradeEvent {
        pool_id,
        trader: trader_addr,
        quantity: (quantity as u128), // Fix: cast to u128
        side,
        timestamp: now,
        deviation: math_utils::from_fixed_point(deviation),
      });
    }
    
    // Fix: Remove admin parameter, correct coin::extract usage
    fun execute_buy_trade(
      trader_addr: address,
      admin_addr: address,
      supra_payment: Coin<SupraCoin>,
      amm_output_regular: u64, // Fix: use u64
      token_address: address
    ) {
      // Handle SupraCoin payment with fees
      let payment_value = coin::value(&supra_payment);
      let fee_amount = (payment_value * FEE_BASIS_POINTS) / 10000;
      let fee_coin = coin::extract(&mut supra_payment, fee_amount); // Fix: coin::extract returns single value
      
      // Send fee to treasury and deposit net payment
      tits_treasury::collect_fees(admin_addr, fee_amount, fee_coin);
      coin::deposit(admin_addr, supra_payment); // supra_payment now contains net amount
      
      // Mint and transfer pool tokens to trader
      let pool_tokens = token_factory::mint_tokens(token_address, amm_output_regular); // Fix: remove admin param
      coin::deposit(trader_addr, pool_tokens);
    }
    
    // Fix: Remove admin parameter, correct types
    fun execute_sell_trade(
      trader_addr: address,
      admin_addr: address,
      supra_payment: Coin<SupraCoin>,
      amm_output_regular: u64 // Fix: use u64
    ) {
      // Calculate fees and net output
      let fee_amount = (amm_output_regular * FEE_BASIS_POINTS) / 10000;
      let net_output = amm_output_regular - fee_amount;
      
      // Transfer SupraCoin to trader and fee to treasury
      let output_coin = coin::withdraw<SupraCoin>(&mut coin::zero<SupraCoin>(), net_output); // Fix: create from zero
      coin::deposit(trader_addr, output_coin);
      
      let fee_coin = coin::withdraw<SupraCoin>(&mut coin::zero<SupraCoin>(), fee_amount); // Fix: create from zero
      tits_treasury::collect_fees(admin_addr, fee_amount, fee_coin);
      
      // Handle pool token input (this still needs proper design)
      coin::deposit(admin_addr, supra_payment);
    }
    
    // Add validation function
    fun validate_candle_size(candle_size: u64) {
      let valid_sizes = vector::empty<u64>();
      vector::push_back(&mut valid_sizes, 5);
      vector::push_back(&mut valid_sizes, 10);
      vector::push_back(&mut valid_sizes, 15);
      
      assert!(vector::contains(&valid_sizes, &candle_size), error::invalid_argument(EINVALID_CANDLE_SIZE));
    }
    
    // Helper function to update trader deviation with averaging
    fun update_trader_deviation(pool: &mut Pool, trader: address, new_deviation: u128) {
      let traders = &mut pool.trader_deviations;
      let len = vector::length(traders);
      let found = false;
      
      let i = 0;
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
      
      // Set up VRF request for random parameters
      move_to(admin, PendingVRF { 
        pool_id, 
        caller: signer::address_of(admin),
        reason,
      });
      
      // Request random number for candle_size selection
      supra_vrf::rng_request(
        admin,
        signer::address_of(admin),
        string::utf8(b"pool_manager"),
        string::utf8(b"handle_random_pool_params"),
        1,  // rng_count - asking for 1 random number
        pool_id,  // client_seed
        1
      );
    }
    
    // VRF callback function
    public entry fun handle_random_pool_params(
      caller: &signer,
      nonce: u64,
      message: vector<u8>,
      signature: vector<u8>,
      caller_address: address,
      rng_count: u8,
      client_seed: u64,
    ) acquires PendingVRF, Pool, PoolRegistry {
      let random_numbers = supra_vrf::verify_callback(
        nonce, message, signature, caller_address, rng_count, client_seed
      );
      
      let pending = move_from<PendingVRF>(caller_address);
      
      // Generate random selection from {0, 1, 2} for {5m, 10m, 15m}
      let random_value = *vector::borrow(&random_numbers, 0);
      let candle_idx = random_value % 3; // 0, 1, or 2
      
      let random_candle_size = if (candle_idx == 0) {
        5  // 5 minutes
      } else if (candle_idx == 1) {
        10 // 10 minutes
      } else {
        15 // 15 minutes
      };
      
      let random_delay = 0; // Always 0 for locked pools
      let random_l_value = (24 * 60) / random_candle_size;
      
      // Get the locked pool's start time to schedule next pool
      let pool = borrow_global<Pool>(caller_address);
      queue_next_pool(caller, @0x0, random_delay, random_candle_size, pool.start_time);
      
      // Remove from active pools
      complete_pool(caller, pending.pool_id);
      
      // Emit event for automation to create next pool with random parameters
      event::emit(PoolLockedWithRandomParams {
        pool_id: pending.pool_id,
        reason: pending.reason,
        random_candle_size,
        random_delay,
        random_l_value,
        timestamp: timestamp::now_seconds(),
      });
    }
    
    #[view]
    public fun get_pool_info(admin: address, pool_id: u64): (u64, u128, u128, u128, address, bool) acquires Pool {
      let pool = borrow_global<Pool>(admin);
      assert!(pool.id == pool_id, error::invalid_argument(EINVALID_POOL));
      (pool.l_value, pool.h_value, pool.x_reserve, pool.y_reserve, pool.token_address, pool.is_locked)
    }
    
    #[view]
    public fun get_pool_token_address(admin: address, pool_id: u64): address acquires Pool {
      let pool = borrow_global<Pool>(admin);
      assert!(pool.id == pool_id, error::invalid_argument(EINVALID_POOL));
      pool.token_address
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
      
      let winner = @0x0;
      let min_deviation = 18446744073709551615u128; // Max u128
      let latest_timestamp = 0u64;
      
      let i = 0;
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
      
      let i = 0;
      while (i < len) {
        let trader_dev = vector::borrow(trader_deviations, i);
        if (trader_dev.trader == trader) {
          return trader_dev.deviation
        };
        i = i + 1;
      };
      
      0 // Return 0 if trader not found
    }
    
    // Queue next pool with winner's parameters or random parameters
    public fun queue_next_pool(
      admin: &signer,
      winner: address,
      delay: u64,
      candle_size: u64,
      current_pool_start: u64
    ) acquires PoolRegistry {
      let registry = borrow_global_mut<PoolRegistry>(signer::address_of(admin));
      registry.queued_pool_start_time = current_pool_start + 24 * 3600; // 24h after current pool start
      registry.queued_pool_delay = delay;
      registry.queued_pool_candle_size = candle_size;
      registry.queued_pool_winner = winner;
    }
    
    #[view]
    public fun get_queued_pool_info(admin: address): (u64, u64, u64, address) acquires PoolRegistry {
      let registry = borrow_global<PoolRegistry>(admin);
      (registry.queued_pool_start_time, registry.queued_pool_delay, registry.queued_pool_candle_size, registry.queued_pool_winner)
    }
    
    #[view]
    public fun has_active_pool(admin: address): bool acquires PoolRegistry {
      let registry = borrow_global<PoolRegistry>(admin);
      !vector::is_empty(&registry.pools)
    }
    
    #[view]
    public fun get_current_active_pool_id(admin: address): u64 acquires PoolRegistry {
      let registry = borrow_global<PoolRegistry>(admin);
      if (vector::is_empty(&registry.pools)) {
        0
      } else {
        *vector::borrow(&registry.pools, vector::length(&registry.pools) - 1)
      }
    }

    public fun clear_queue(admin: &signer) acquires PoolRegistry {
      let registry = borrow_global_mut<PoolRegistry>(signer::address_of(admin));
      registry.queued_pool_start_time = 0;
      registry.queued_pool_delay = 0;
      registry.queued_pool_candle_size = 0;
      registry.queued_pool_winner = @0x0;
    }

    public fun complete_pool(admin: &signer, pool_id: u64) acquires PoolRegistry {
      let registry = borrow_global_mut<PoolRegistry>(signer::address_of(admin));
      let (found, index) = vector::index_of(&registry.pools, &pool_id);
      if (found) {
        vector::remove(&mut registry.pools, index);
      };
    }

    #[view]
    public fun get_pool_start_time(admin: address, pool_id: u64): u64 acquires Pool {
      let pool = borrow_global<Pool>(admin);
      pool.start_time
    }

    #[view] 
    public fun get_winner_proposal(admin: address, pool_id: u64): (u64, u64) acquires Pool {
      let pool = borrow_global<Pool>(admin);
      (pool.winner_proposed_delay, pool.winner_proposed_candle_size)
    }

    #[view]
    public fun get_max_trader_deviation(admin: address, pool_id: u64): u128 acquires Pool {
      let pool = borrow_global<Pool>(admin);
      let trader_deviations = &pool.trader_deviations;
      let len = vector::length(trader_deviations);
      
      if (len == 0) return 0;
      
      let max_deviation = 0u128;
      let i = 0;
      while (i < len) {
        let trader_dev = vector::borrow(trader_deviations, i);
        if (trader_dev.deviation > max_deviation) {
          max_deviation = trader_dev.deviation;
        };
        i = i + 1;
      };
      max_deviation
    }

    // Helper function to get current winner from pool
    fun get_current_winner(pool: &Pool): (address, u128) {
      let trader_deviations = &pool.trader_deviations;
      let len = vector::length(trader_deviations);
      
      if (len == 0) {
        return (@0x0, 0)
      };
      
      let winner = @0x0;
      let min_deviation = 18446744073709551615u128; // Max u128
      let latest_timestamp = 0u64;
      
      let i = 0;
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
    
    // Helper function to get previous winner (before this update)
    fun get_previous_winner(pool: &Pool): address {
      pool.current_winner
    }
}