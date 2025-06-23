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
  use supra_framework::supra_coin::SupraCoin;
  
  use supra_addr::supra_vrf;
  use deployer_addr::pool_pair;
  use deployer_addr::treasury;
  use deployer_addr::token_factory;

  // ================= STRUCTS =================
  struct LauncherData has key {
    admin: address,
    current_pool_id: u64,
    next_pool_start: u64,
    active_pools: vector<u64>,
    completed_pools: vector<u64>,
    default_params: CurveParams,
  }

  struct CurveParams has store, copy, drop {
    height: u64,          // H parameter for parabola
    length: u64,          // L parameter for parabola  
    ticker_duration: u8,   // 5, 10, or 15 minutes
    threshold_percent: u8, // Deviation threshold (default 10%)
    pool_duration: u64,    // Pool active duration (24 hours)
  }

  struct PoolInfo has store {
    id: u64,
    params: CurveParams,
    start_time: u64,
    end_time: u64,
    winner: address,
    is_locked: bool,
    total_volume: u64,
  }

  struct PendingVRF has key {
    pool_id: u64,
    caller: address,
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
    final_volume: u64,
  }

  // ================= ERRORS =================
  const ENOT_ADMIN: u64 = 1;
  const EPOOL_NOT_FOUND: u64 = 2;
  const ETOO_EARLY: u64 = 3;
  const EINVALID_PARAMS: u64 = 4;

  // ================= INIT =================
  fun init_module(account: &signer) {
    let admin_addr = signer::address_of(account);
    let default_params = CurveParams {
      height: 100,
      length: 100,
      ticker_duration: 5,
      threshold_percent: 10,
      pool_duration: 86400, // 24 hours
    };

    move_to(account, LauncherData {
      admin: admin_addr,
      current_pool_id: 0,
      next_pool_start: timestamp::now_seconds() + 60, // Start in 1 minute
      active_pools: vector::empty(),
      completed_pools: vector::empty(),
      default_params,
    });
  }

    // ================= PUBLIC FUNCTIONS =================
  public entry fun create_new_pool(
      account: &signer,
      height: u64,
      length: u64,
      ticker_duration: u8,
      threshold_percent: u8,
      start_delay: u64, // seconds from now
  ) acquires LauncherData {
    let launcher = borrow_global_mut<LauncherData>(@deployer_addr);
    
    // Validate parameters
    assert!(ticker_duration == 5 || ticker_duration == 10 || ticker_duration == 15, 
            error::invalid_argument(EINVALID_PARAMS));
    assert!(threshold_percent > 0 && threshold_percent <= 50, 
            error::invalid_argument(EINVALID_PARAMS));
    assert!(start_delay <= 86400, error::invalid_argument(EINVALID_PARAMS)); // Max 24h delay

    launcher.current_pool_id = launcher.current_pool_id + 1;
    let pool_id = launcher.current_pool_id;
    
    // Generate incremental token name and symbol
    let token_name = generate_token_name(pool_id);
    let token_symbol = generate_token_symbol(pool_id);

    let params = CurveParams {
      height,
      length,
      ticker_duration,
      threshold_percent,
      pool_duration: 86400,
    };

    let pool_start = timestamp::now_seconds() + start_delay;
    
    // Create the trading pool with incremental token
    pool_pair::create_pool(account, pool_id, token_name, token_symbol, params, pool_start);
    
    vector::push_back(&mut launcher.active_pools, pool_id);
    launcher.next_pool_start = pool_start + 86400;

    event::emit(PoolCreated {
      pool_id,
      token_name,
      token_symbol,
      params,
      start_time: pool_start,
      creator: signer::address_of(account),
    });
  }

  public entry fun complete_pool(account: &signer, pool_id: u64) acquires LauncherData {
    let launcher = borrow_global_mut<LauncherData>(@deployer_addr);
    
    // Remove from active pools
    let (found, index) = vector::index_of(&launcher.active_pools, &pool_id);
    assert!(found, error::not_found(EPOOL_NOT_FOUND));
    vector::remove(&mut launcher.active_pools, index);
    
    // Add to completed pools
    vector::push_back(&mut launcher.completed_pools, pool_id);
    
    let (winner, was_locked, volume) = pool_pair::finalize_pool(account, pool_id);
      
    event::emit(PoolCompleted {
      pool_id,
      winner,
      was_locked,
      final_volume: volume,
    });

    // If pool was locked (no winner), request VRF for new pool parameters
    if (was_locked) {
      move_to(account, PendingVRF { pool_id, caller: signer::address_of(account) });
      supra_vrf::rng_request(
        account,
        signer::address_of(account),
        string::utf8(b"curve_launcher"),
        string::utf8(b"handle_random_params"),
        3, // Need 3 random numbers: height, length, ticker_duration
        pool_id, // Use pool_id as seed
        1
      );
    }
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
    
    let _pending = move_from<PendingVRF>(caller_address);
    let launcher = borrow_global_mut<LauncherData>(@deployer_addr);
    
    // Generate random parameters from VRF
    let height = (*vector::borrow(&random_numbers, 0) % 150) + 50; // 50-200 range
    let length = (*vector::borrow(&random_numbers, 1) % 150) + 50; // 50-200 range  
    let ticker_idx = *vector::borrow(&random_numbers, 2) % 3;
    let ticker_duration = if (ticker_idx == 0) 5 else if (ticker_idx == 1) 10 else 15;
    
    launcher.current_pool_id = launcher.current_pool_id + 1;
    let pool_id = launcher.current_pool_id;
    
    // Generate incremental token name and symbol
    let token_name = generate_token_name(pool_id);
    let token_symbol = generate_token_symbol(pool_id);

    let params = CurveParams {
      height,
      length,
      ticker_duration,
      threshold_percent: 10, // Keep default threshold
      pool_duration: 86400,
    };

    let pool_start = launcher.next_pool_start;
    
    pool_pair::create_pool_from_launcher(pool_id, token_name, token_symbol, params, pool_start);
    vector::push_back(&mut launcher.active_pools, pool_id);
    launcher.next_pool_start = pool_start + 86400;

    event::emit(PoolCreated {
      pool_id,
      token_name,
      token_symbol,
      params,
      start_time: pool_start,
      creator: caller_address,
    });
  }

  // ================= HELPER FUNCTIONS =================
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
    // Format as 3-digit number: 001, 002, etc.
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
      let digit = ((temp % 10) as u8) + 48; // Convert to ASCII
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
}
