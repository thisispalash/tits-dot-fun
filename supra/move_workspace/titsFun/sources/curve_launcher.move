// =================== CURVE_LAUNCHER MODULE ===================
module deployer_addr::curve_launcher {
  use std::error;
  use std::signer;
  use std::string::{Self, String};
  use std::vector;

  use supra_framework::account;
  use supra_framework::timestamp;
  use supra_framework::event;
  use supra_framework::coin::{Self, Coin};
  use supra_framework::supra_coin::SupraCoin;  // Only native token
  
  use supra_addr::supra_vrf;
  use deployer_addr::pool_pair;
  use deployer_addr::treasury; // Keep for future fees

  // ================= CONSTANTS =================
  const POOL_DURATION_SECONDS: u64 = 86400; // 24 hours
  const MINUTES_PER_DAY: u64 = 1440;
  const INITIAL_HEIGHT: u64 = 100;

  // ================= STRUCTS =================
  struct LauncherData has key {
    admin: address,
    current_pool_id: u64,
    last_pool_start: u64,
    current_height: u64,        // H_{i+1} = H_i * sqrt(L)
    active_pools: vector<u64>,
    completed_pools: vector<u64>,
    burned_pools: vector<u64>,  // Track pools that were burned
  }

  struct CurveParams has store, copy, drop {
    height: u64,              // H parameter 
    length: u64,              // L ∈ {96, 144, 288}
    ticker_duration: u8,      // 5, 10, or 15 minutes
    threshold_percent: u8,    // Not used on-chain anymore (off-chain calculation)
  }

  struct PendingVRF has key {
    pool_id: u64,
    caller: address,
    scheduled_start: u64,
  }

  // ================= EVENTS =================
  #[event]
  struct PoolCreated has drop, store {
    pool_id: u64,
    token_name: String,
    token_symbol: String,
    params: CurveParams,
    start_time: u64,
    creator: address,
  }

  #[event]
  struct PoolCompleted has drop, store {
    pool_id: u64,
    winner: address,
    was_locked: bool,
    was_burned: bool,
    final_volume: u64,
    next_height: u64,
  }

  #[event]
  struct PoolBurned has drop, store {
    pool_id: u64,
    burned_amount: u64,
    reason: String,
    timestamp: u64,
  }

  // ================= ERRORS =================
  const ENOT_ADMIN: u64 = 1;
  const EPOOL_NOT_FOUND: u64 = 2;
  const ETOO_EARLY: u64 = 3;
  const EINVALID_PARAMS: u64 = 4;
  const EINVALID_TIMING: u64 = 5;
  const ENOT_AUTOMATION: u64 = 6;

  // ================= INIT =================
  fun init_module(account: &signer) {
    let admin_addr = signer::address_of(account);

    move_to(account, LauncherData {
      admin: admin_addr,
      current_pool_id: 0,
      last_pool_start: 0,
      current_height: INITIAL_HEIGHT,
      active_pools: vector::empty(),
      completed_pools: vector::empty(),
      burned_pools: vector::empty(),
    });
  }

  // ================= PUBLIC FUNCTIONS =================
  public entry fun create_new_pool(
      account: &signer,
      ticker_duration: u8,      // 5, 10, or 15
      threshold_percent: u8,    // Kept for compatibility
      start_delay: u64,
  ) acquires LauncherData {
    let launcher = borrow_global_mut<LauncherData>(@deployer_addr);
    
    // Validate parameters
    assert!(ticker_duration == 5 || ticker_duration == 10 || ticker_duration == 15, 
            error::invalid_argument(EINVALID_PARAMS));

    launcher.current_pool_id = launcher.current_pool_id + 1;
    let pool_id = launcher.current_pool_id;
    
    // Calculate L from user selection: L ∈ {96, 144, 288}
    let candle_count = MINUTES_PER_DAY / (ticker_duration as u64);
    
    let token_name = generate_token_name(pool_id);
    let token_symbol = generate_token_symbol(pool_id);

    let params = CurveParams {
      height: launcher.current_height,  // Current H
      length: candle_count,             // L ∈ {96, 144, 288}
      ticker_duration,                  
      threshold_percent,                // Stored but not used on-chain
    };

    let pool_start = if (launcher.last_pool_start == 0) {
      timestamp::now_seconds() + start_delay
    } else {
      // User-defined timing with 12h window validation
      let proposed_start = timestamp::now_seconds() + start_delay;
      let pool_end_time = launcher.last_pool_start + POOL_DURATION_SECONDS;
      let max_allowed_start = pool_end_time + (12 * 3600); // 12h after pool end
      
      assert!(proposed_start <= max_allowed_start, error::invalid_argument(EINVALID_TIMING));
      proposed_start
    };
    
    pool_pair::create_pool(account, pool_id, token_name, token_symbol, params, pool_start);
    
    vector::push_back(&mut launcher.active_pools, pool_id);
    launcher.last_pool_start = pool_start;

    // TODO: Future pool creation fee
    // let creation_fee = 100_00000000; // 100 SupraCoin
    // let fee_coins = coin::withdraw<SupraCoin>(account, creation_fee);
    // treasury::collect_fee(fee_coins, pool_id, string::utf8(b"creation_fee"));

    event::emit(PoolCreated {
      pool_id,
      token_name,
      token_symbol,
      params,
      start_time: pool_start,
      creator: signer::address_of(account),
    });
  }

  // Called by automation service when off-chain deviation calculation exceeds threshold
  public entry fun external_lock_pool(
    account: &signer,
    pool_id: u64,
    deviation_reason: String,
  ) acquires LauncherData {
    // TODO: Add automation service address validation
    // assert!(signer::address_of(account) == @automation_service, error::permission_denied(ENOT_AUTOMATION));
    
    let launcher = borrow_global_mut<LauncherData>(@deployer_addr);
    
    let (found, index) = vector::index_of(&launcher.active_pools, &pool_id);
    assert!(found, error::not_found(EPOOL_NOT_FOUND));
    
    // Lock and burn the pool (creates deflationary pressure on SupraCoin)
    let burned_amount = pool_pair::lock_and_burn_pool(account, pool_id);
    
    vector::remove(&mut launcher.active_pools, index);
    vector::push_back(&mut launcher.burned_pools, pool_id);
    
    // Update H for next pool: H_{i+1} = H_i * sqrt(L)
    let pool_params = pool_pair::get_pool_params(pool_id);
    let sqrt_l = integer_sqrt(pool_params.length);
    launcher.current_height = launcher.current_height * sqrt_l;

    event::emit(PoolBurned {
      pool_id,
      burned_amount,
      reason: deviation_reason,
      timestamp: timestamp::now_seconds(),
    });

    // Schedule automatic new pool creation 24h later
    let next_start = launcher.last_pool_start + POOL_DURATION_SECONDS;
    move_to(account, PendingVRF { 
      pool_id, 
      caller: signer::address_of(account),
      scheduled_start: next_start,
    });
    
    supra_vrf::rng_request(
      account,
      signer::address_of(account),
      string::utf8(b"curve_launcher"),
      string::utf8(b"handle_random_params"),
      2,
      pool_id,
      1
    );
  }

  public entry fun complete_pool(account: &signer, pool_id: u64) acquires LauncherData {
    let launcher = borrow_global_mut<LauncherData>(@deployer_addr);
    
    let (found, index) = vector::index_of(&launcher.active_pools, &pool_id);
    assert!(found, error::not_found(EPOOL_NOT_FOUND));
    vector::remove(&mut launcher.active_pools, index);
    
    vector::push_back(&mut launcher.completed_pools, pool_id);
    
    let (winner, was_locked, volume, pool_params) = pool_pair::finalize_pool(account, pool_id);
    
    // Update H for next pool: H_{i+1} = H_i * sqrt(L)
    let sqrt_l = integer_sqrt(pool_params.length);
    launcher.current_height = launcher.current_height * sqrt_l;
      
    event::emit(PoolCompleted {
      pool_id,
      winner,
      was_locked,
      was_burned: false,
      final_volume: volume,
      next_height: launcher.current_height,
    });

    // No automatic scheduling for successful pools - user decides timing
  }

  public entry fun handle_random_params(
    nonce: u64,
    message: vector<u8>,
    signature: vector<u8>,
    caller_address: address,
    rng_count: u8,
    client_seed: u64,
  ) acquires LauncherData, PendingVRF {
    let random_numbers = supra_vrf::verify_callback(
      nonce, message, signature, caller_address, rng_count, client_seed
    );
    
    let pending = move_from<PendingVRF>(caller_address);
    let launcher = borrow_global_mut<LauncherData>(@deployer_addr);
    
    assert!(timestamp::now_seconds() >= pending.scheduled_start, error::permission_denied(ETOO_EARLY));
    
    // Generate random parameters
    let ticker_idx = *vector::borrow(&random_numbers, 0) % 3;
    let ticker_duration = if (ticker_idx == 0) 5 else if (ticker_idx == 1) 10 else 15;
    let threshold = (*vector::borrow(&random_numbers, 1) % 20) + 10; // 10-30%
    
    launcher.current_pool_id = launcher.current_pool_id + 1;
    let pool_id = launcher.current_pool_id;
    
    let candle_count = MINUTES_PER_DAY / (ticker_duration as u64);
    let token_name = generate_token_name(pool_id);
    let token_symbol = generate_token_symbol(pool_id);

    let params = CurveParams {
      height: launcher.current_height,
      length: candle_count,
      ticker_duration,
      threshold_percent: (threshold as u8),
    };

    let pool_start = pending.scheduled_start;
    
    // Create pool directly (no treasury needed)
    pool_pair::create_pool_from_system(pool_id, token_name, token_symbol, params, pool_start);
    vector::push_back(&mut launcher.active_pools, pool_id);
    launcher.last_pool_start = pool_start;

    event::emit(PoolCreated {
      pool_id,
      token_name,
      token_symbol,
      params,
      start_time: pool_start,
      creator: @deployer_addr,
    });
  }

  // ================= HELPER FUNCTIONS =================
  fun integer_sqrt(x: u64): u64 {
    if (x == 0) return 0;
    if (x == 1) return 1;
    
    let mut z = x / 2 + 1;
    let mut y = x;
    while (z < y) {
      y = z;
      z = (x / z + z) / 2;
    };
    y
  }

  fun generate_token_name(pool_id: u64): String {
    let base = string::utf8(b"Curve Pool ");
    let id_str = u64_to_string(pool_id);
    string::append(&mut base, id_str);
    base
  }

  fun generate_token_symbol(pool_id: u64): String {
    let base = string::utf8(b"CURVE");
    let id_str = format_pool_id(pool_id);
    string::append(&mut base, id_str);
    base
  }

  fun format_pool_id(pool_id: u64): String {
    if (pool_id < 10) {
      let result = string::utf8(b"00");
      string::append(&mut result, u64_to_string(pool_id));
      result
    } else if (pool_id < 100) {
      let result = string::utf8(b"0");
      string::append(&mut result, u64_to_string(pool_id));
      result
    } else {
      u64_to_string(pool_id)
    }
  }

  fun u64_to_string(num: u64): String {
    if (num == 0) return string::utf8(b"0");
    
    let digits = vector::empty<u8>();
    let temp = num;
    
    while (temp > 0) {
      let digit = ((temp % 10) as u8) + 48;
      vector::push_back(&mut digits, digit);
      temp = temp / 10;
    };
    
    vector::reverse(&mut digits);
    string::utf8(digits)
  }

  // ================= VIEW FUNCTIONS =================
  #[view]
  public fun get_active_pools(): vector<u64> acquires LauncherData {
    borrow_global<LauncherData>(@deployer_addr).active_pools
  }

  #[view]
  public fun get_current_pool_id(): u64 acquires LauncherData {
    borrow_global<LauncherData>(@deployer_addr).current_pool_id
  }

  #[view]
  public fun get_current_height(): u64 acquires LauncherData {
    borrow_global<LauncherData>(@deployer_addr).current_height
  }

  #[view]
  public fun get_burned_pools(): vector<u64> acquires LauncherData {
    borrow_global<LauncherData>(@deployer_addr).burned_pools
  }

  #[view]
  public fun get_total_burned_amount(): u64 acquires LauncherData {
    // This would require tracking burned amounts - can be added later
    0
  }
}
