// =================== POOL_PAIR MODULE ===================
module deployer_addr::pool_pair {
  use std::error;
  use std::signer;
  use std::string::{Self, String};
  use std::vector;

  use supra_framework::account;
  use supra_framework::timestamp;
  use supra_framework::event;
  use supra_framework::coin::{Self, Coin};
  
  use deployer_addr::curve_launcher::CurveParams;
  use deployer_addr::treasury;
  use deployer_addr::stable_coin::StableCoin;
  use deployer_addr::token_factory::{Self, PoolToken};

  // ================= CONSTANTS =================
  const POOL_DURATION_SECONDS: u64 = 86400; // 24 hours
  const INITIAL_LIQUIDITY: u64 = 1000000_00000000; // 1M tokens with 8 decimals

  // ================= STRUCTS =================
  struct Pool has key {
    id: u64,
    params: CurveParams,
    start_time: u64,
    end_time: u64,
    is_active: bool,
    is_locked: bool,
    creator: address,
    total_supply: u64,
    reserve_coin: Coin<StableCoin>,
    reserve_token: u64, // Virtual token reserve
    trades: vector<TradePoint>,
    trader_scores: vector<TraderScore>,
    winner: address,
    total_volume: u64,
    last_deviation_check: u64, // Last candle when we checked deviation
  }

  struct TradePoint has store, copy, drop {
    x: u64,
    y: u64,
    timestamp: u64,
    deviation: u64,
    trader: address,
  }

  struct TraderScore has store, copy, drop {
    trader: address,
    total_deviation: u64,
    trade_count: u64,
    volume: u64,
    score: u64, // Lower = better (average deviation)
  }

  struct PoolToken has key {
    name: String,
    symbol: String,
    decimals: u8,
    total_supply: u64,
  }

  // ================= EVENTS =================
  #[event]
  struct PoolCreated has drop, store {
    pool_id: u64,
    params: CurveParams,
    start_time: u64,
    creator: address,
  }

  #[event]
  struct Trade has drop, store {
    pool_id: u64,
    trader: address,
    is_buy: bool,
    amount_in: u64,
    amount_out: u64,
    current_price: u64,
    expected_price: u64,
    deviation: u64,
    candle_number: u64,
    timestamp: u64,
  }

  #[event]
  struct PoolLocked has drop, store {
    pool_id: u64,
    reason: String,
    final_deviation: u64,
    candle_number: u64,
    timestamp: u64,
  }

  #[event]
  struct PoolFinalized has drop, store {
    pool_id: u64,
    winner: address,
    final_score: u64,
    total_volume: u64,
    timestamp: u64,
  }

  // ================= ERRORS =================
  const EPOOL_NOT_ACTIVE: u64 = 1;
  const EPOOL_LOCKED: u64 = 2;
  const EINSUFFICIENT_LIQUIDITY: u64 = 3;
  const ETHRESHOLD_EXCEEDED: u64 = 4;
  const EINVALID_AMOUNT: u64 = 5;
  const EPOOL_NOT_STARTED: u64 = 6;
  const EPOOL_ENDED: u64 = 7;

  // ================= PUBLIC FUNCTIONS =================
  public fun create_pool(
    account: &signer,
    pool_id: u64,
    token_name: String,
    token_symbol: String,
    params: CurveParams,
    start_time: u64,
  ) {
    let creator = signer::address_of(account);
    
    let pool = Pool {
      id: pool_id,
      params,
      start_time,
      end_time: start_time + POOL_DURATION_SECONDS,
      is_active: false,
      is_locked: false,
      creator,
      total_supply: 1000000,
      reserve_coin: coin::zero<StableCoin>(),
      reserve_token: INITIAL_LIQUIDITY, // Start with virtual tokens
      trades: vector::empty(),
      trader_scores: vector::empty(),
      winner: @0x0,
      total_volume: 0,
      last_deviation_check: 0,
    };

    move_to(account, pool);
    
    move_to(account, PoolToken {
      name: token_name,
      symbol: token_symbol,
      decimals: 8,
      total_supply: INITIAL_LIQUIDITY,
    });

    event::emit(PoolCreated {
      pool_id,
      params,
      start_time,
      creator,
    });
  }

  public fun create_pool_from_launcher(
    pool_id: u64,
    params: CurveParams,
    start_time: u64,
  ) {
    // Create system account for launcher-created pools
    let launcher_addr = @deployer_addr;
    // This would need proper resource account creation in practice
  }

  public entry fun activate_pool(account: &signer, pool_id: u64) acquires Pool {
    let pool = borrow_global_mut<Pool>(signer::address_of(account));
    assert!(pool.id == pool_id, error::invalid_argument(EPOOL_NOT_ACTIVE));
    assert!(timestamp::now_seconds() >= pool.start_time, error::permission_denied(EPOOL_NOT_STARTED));
    
    pool.is_active = true;
  }

  public entry fun buy_tokens(
    account: &signer,
    pool_id: u64,
    coin_amount: u64,
  ) acquires Pool {
    let trader = signer::address_of(account);
    let pool = borrow_global_mut<Pool>(trader);
    
    assert!(pool.id == pool_id, error::invalid_argument(EPOOL_NOT_ACTIVE));
    assert!(!pool.is_locked, error::permission_denied(EPOOL_LOCKED));
    assert!(timestamp::now_seconds() >= pool.start_time, error::permission_denied(EPOOL_NOT_STARTED));
    assert!(timestamp::now_seconds() <= pool.end_time, error::permission_denied(EPOOL_ENDED));
    
    // STEP 1: CONTINUOUS TIME - Execute AMM trade
    let tokens_out = calculate_buy_amount(pool, coin_amount);
    assert!(tokens_out > 0, error::invalid_argument(EINVALID_AMOUNT));
    assert!(pool.reserve_token >= tokens_out, error::insufficient_funds(EINSUFFICIENT_LIQUIDITY));

    // Execute the trade
    let payment = coin::withdraw<StableCoin>(account, coin_amount);
    coin::merge(&mut pool.reserve_coin, payment);
    pool.reserve_token = pool.reserve_token - tokens_out;
    pool.total_volume = pool.total_volume + coin_amount;

    // STEP 2: CANDLE TIME - Check deviation at candle boundaries
    let current_candle = get_current_candle(pool);
    let expected_price = calculate_expected_price_for_candle(pool, current_candle);
    let actual_price = calculate_current_price(pool);
    let deviation = calculate_deviation(expected_price, actual_price);

    // Update trader score
    update_trader_score(pool, trader, deviation, coin_amount);

    // Check if we need to evaluate deviation (only at candle boundaries)
    if (current_candle > pool.last_deviation_check) {
      pool.last_deviation_check = current_candle;
      
      // Check if deviation exceeds threshold - LOCK POOL
      if (deviation > (pool.params.threshold_percent as u64)) {
        lock_pool_and_transfer_all(pool);
        
        event::emit(PoolLocked {
          pool_id,
          reason: string::utf8(b"Deviation threshold exceeded on buy"),
          final_deviation: deviation,
          candle_number: current_candle,
          timestamp: timestamp::now_seconds(),
        });
        
        return // Exit early, pool is locked
      };
    };

    event::emit(Trade {
      pool_id,
      trader,
      is_buy: true,
      amount_in: coin_amount,
      amount_out: tokens_out,
      current_price: actual_price,
      expected_price,
      deviation,
      candle_number: current_candle,
      timestamp: timestamp::now_seconds(),
    });
  }

  public entry fun sell_tokens(
    account: &signer,
    pool_id: u64,
    token_amount: u64,
  ) acquires Pool {
    let trader = signer::address_of(account);
    let pool = borrow_global_mut<Pool>(trader);
    
    assert!(pool.id == pool_id, error::invalid_argument(EPOOL_NOT_ACTIVE));
    assert!(!pool.is_locked, error::permission_denied(EPOOL_LOCKED));
    assert!(timestamp::now_seconds() >= pool.start_time, error::permission_denied(EPOOL_NOT_STARTED));
    assert!(timestamp::now_seconds() <= pool.end_time, error::permission_denied(EPOOL_ENDED));

    // STEP 1: CONTINUOUS TIME - Execute AMM trade
    let coins_out = calculate_sell_amount(pool, token_amount);
    assert!(coins_out > 0, error::invalid_argument(EINVALID_AMOUNT));
    assert!(coin::value(&pool.reserve_coin) >= coins_out, error::insufficient_funds(EINSUFFICIENT_LIQUIDITY));

    // Execute the trade
    pool.reserve_token = pool.reserve_token + token_amount;
    let payout = coin::extract(&mut pool.reserve_coin, coins_out);
    coin::deposit(trader, payout);
    pool.total_volume = pool.total_volume + coins_out;

    // STEP 2: CANDLE TIME - Check deviation
    let current_candle = get_current_candle(pool);
    let expected_price = calculate_expected_price_for_candle(pool, current_candle);
    let actual_price = calculate_current_price(pool);
    let deviation = calculate_deviation(expected_price, actual_price);

    update_trader_score(pool, trader, deviation, coins_out);

    if (current_candle > pool.last_deviation_check) {
      pool.last_deviation_check = current_candle;
      
      if (deviation > (pool.params.threshold_percent as u64)) {
        lock_pool_and_transfer_all(pool);
        
        event::emit(PoolLocked {
          pool_id,
          reason: string::utf8(b"Deviation threshold exceeded on sell"),
          final_deviation: deviation,
          candle_number: current_candle,
          timestamp: timestamp::now_seconds(),
        });
        
        return
      };
    };

    event::emit(Trade {
      pool_id,
      trader,
      is_buy: false,
      amount_in: token_amount,
      amount_out: coins_out,
      current_price: actual_price,
      expected_price,
      deviation,
      candle_number: current_candle,
      timestamp: timestamp::now_seconds(),
    });
  }

  public fun finalize_pool(
    account: &signer,
    pool_id: u64,
  ): (address, bool, u64) acquires Pool {
    let pool = borrow_global_mut<Pool>(signer::address_of(account));
    assert!(pool.id == pool_id, error::invalid_argument(EPOOL_NOT_ACTIVE));
    
    pool.is_active = false;
    
    if (!pool.is_locked && vector::length(&pool.trader_scores) > 0) {
      pool.winner = find_best_trader(&pool.trader_scores);
    };

    event::emit(PoolFinalized {
      pool_id,
      winner: pool.winner,
      final_score: if (pool.winner != @0x0) get_trader_final_score(&pool.trader_scores, pool.winner) else 0,
      total_volume: pool.total_volume,
      timestamp: timestamp::now_seconds(),
    });
    
    (pool.winner, pool.is_locked, pool.total_volume)
  }

  // ================= HELPER FUNCTIONS =================
  fun get_current_candle(pool: &Pool): u64 {
    let elapsed_seconds = timestamp::now_seconds() - pool.start_time;
    let elapsed_minutes = elapsed_seconds / 60;
    let candle_duration = pool.params.ticker_duration as u64;
    let current_candle = elapsed_minutes / candle_duration;
    
    // Ensure we don't exceed total candles
    if (current_candle >= pool.params.length) {
      pool.params.length - 1
    } else {
      current_candle
    }
  }

  fun calculate_expected_price_for_candle(pool: &Pool, candle: u64): u64 {
    let h = pool.params.height;
    let l = pool.params.length;
    
    if (candle >= l) return 0;
    
    let numerator = 4 * h * candle * (l - candle);
    numerator / (l * l)
  }

  fun calculate_buy_amount(pool: &Pool, coin_amount: u64): u64 {
    let coin_reserve = coin::value(&pool.reserve_coin);
    let token_reserve = pool.reserve_token;
    
    if (coin_reserve == 0 || token_reserve == 0) {
      // Initial trade - simple 1:1 ratio
      return coin_amount
    };
    
    let k = coin_reserve * token_reserve;
    let new_coin_reserve = coin_reserve + coin_amount;
    let new_token_reserve = k / new_coin_reserve;
    
    if (token_reserve > new_token_reserve) {
      token_reserve - new_token_reserve
    } else {
      0
    }
  }

  fun calculate_sell_amount(pool: &Pool, token_amount: u64): u64 {
    let coin_reserve = coin::value(&pool.reserve_coin);
    let token_reserve = pool.reserve_token;
    
    if (coin_reserve == 0 || token_reserve == 0) return 0;
    
    let k = coin_reserve * token_reserve;
    let new_token_reserve = token_reserve + token_amount;
    let new_coin_reserve = k / new_token_reserve;
    
    if (coin_reserve > new_coin_reserve) {
      coin_reserve - new_coin_reserve
    } else {
      0
    }
  }

  fun calculate_current_price(pool: &Pool): u64 {
    if (pool.reserve_token == 0) return 0;
    coin::value(&pool.reserve_coin) / pool.reserve_token
  }

  fun calculate_deviation(expected: u64, actual: u64): u64 {
    if (expected == 0) return 100; // Max deviation
    
    if (actual > expected) {
      ((actual - expected) * 100) / expected
    } else {
      ((expected - actual) * 100) / expected
    }
  }

  fun update_trader_score(pool: &mut Pool, trader: address, deviation: u64, volume: u64) {
    let scores = &mut pool.trader_scores;
    let i = 0;
    let len = vector::length(scores);
    let found = false;
    
    while (i < len && !found) {
      let score = vector::borrow_mut(scores, i);
      if (score.trader == trader) {
        score.total_deviation = score.total_deviation + deviation;
        score.trade_count = score.trade_count + 1;
        score.volume = score.volume + volume;
        score.score = score.total_deviation / score.trade_count;
        found = true;
      };
      i = i + 1;
    };
    
    if (!found) {
      let new_score = TraderScore {
        trader,
        total_deviation: deviation,
        trade_count: 1,
        volume,
        score: deviation,
      };
      vector::push_back(scores, new_score);
    };
  }

  fun find_best_trader(scores: &vector<TraderScore>): address {
    if (vector::is_empty(scores)) return @0x0;
    
    let best_trader = @0x0;
    let best_score = 18446744073709551615u64; // Max u64
    let i = 0;
    let len = vector::length(scores);
    
    while (i < len) {
      let score = vector::borrow(scores, i);
      if (score.score < best_score && score.trade_count >= 3) {
        best_score = score.score;
        best_trader = score.trader;
      };
      i = i + 1;
    };
    
    best_trader
  }

  fun get_trader_final_score(scores: &vector<TraderScore>, trader: address): u64 {
    let i = 0;
    let len = vector::length(scores);
    
    while (i < len) {
      let score = vector::borrow(scores, i);
      if (score.trader == trader) {
        return score.score
      };
      i = i + 1;
    };
    
    0
  }

  fun lock_pool_and_transfer_all(pool: &mut Pool) {
    pool.is_locked = true;
    pool.is_active = false;
    
    // Transfer ALL funds to treasury (100% to admin)
    let remaining_coins = coin::extract_all(&mut pool.reserve_coin);
    let remaining_tokens = pool.reserve_token;
    pool.reserve_token = 0;
    
    treasury::receive_all_locked_funds(remaining_coins, remaining_tokens, pool.id);
  }

  // ================= VIEW FUNCTIONS =================
  #[view]
  public fun get_pool_info(pool_addr: address): (u64, bool, bool, u64, u64, u64, address, u64) acquires Pool {
    let pool = borrow_global<Pool>(pool_addr);
    (
      pool.id,
      pool.is_active,
      pool.is_locked,
      pool.reserve_token,
      coin::value(&pool.reserve_coin),
      pool.total_volume,
      pool.winner,
      get_current_candle(pool)
    )
  }

  #[view]
  public fun get_expected_price_for_current_candle(pool_addr: address): u64 acquires Pool {
    let pool = borrow_global<Pool>(pool_addr);
    let current_candle = get_current_candle(pool);
    calculate_expected_price_for_candle(pool, current_candle)
  }

  #[view]
  public fun get_current_deviation(pool_addr: address): u64 acquires Pool {
    let pool = borrow_global<Pool>(pool_addr);
    let current_candle = get_current_candle(pool);
    let expected = calculate_expected_price_for_candle(pool, current_candle);
    let actual = calculate_current_price(pool);
    calculate_deviation(expected, actual)
  }
}