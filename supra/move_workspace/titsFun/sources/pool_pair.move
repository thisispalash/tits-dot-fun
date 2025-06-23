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
    reserve_token: Coin<PoolToken>,
    trades: vector<TradePoint>,
    trader_scores: vector<TraderScore>,
    winner: address,
    total_volume: u64,
    last_price: u64,
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
    score: u64, // Lower is better
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
    price: u64,
    curve_deviation: u64,
    timestamp: u64,
  }

  #[event]
  struct PoolLocked has drop, store {
    pool_id: u64,
    reason: String,
    final_deviation: u64,
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
    params: CurveParams,
    start_time: u64,
  ) {
    let creator = signer::address_of(account);
    
    // Create unique pool token
    let token_name = string::utf8(b"Curve Pool Token #");
    string::append(&mut token_name, string::utf8(b"1")); // Would use pool_id
    let token_symbol = string::utf8(b"CPT");
    
    let initial_supply = 1000000_00000000; // 1M tokens with 8 decimals
    let (mint_cap, burn_cap) = token_factory::create_pool_token(
      account,
      pool_id,
      token_name,
      token_symbol,
      initial_supply,
    );

    // Mint initial token supply
    let initial_tokens = token_factory::mint_tokens(&mint_cap, initial_supply);

    let pool = Pool {
      id: pool_id,
      params,
      start_time,
      end_time: start_time + params.pool_duration,
      is_active: false,
      is_locked: false,
      creator,
      total_supply: initial_supply,
      reserve_coin: coin::zero<StableCoin>(),
      reserve_token: initial_tokens,
      trades: vector::empty(),
      trader_scores: vector::empty(),
      winner: @0x0,
      total_volume: 0,
      last_price: 0,
    };

    move_to(account, pool);

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
    pool_addr: address,
    coin_amount: u64,
  ) acquires Pool {
    let trader = signer::address_of(account);
    let pool = borrow_global_mut<Pool>(pool_addr);
    
    // Validation checks
    assert!(pool.is_active, error::permission_denied(EPOOL_NOT_ACTIVE));
    assert!(!pool.is_locked, error::permission_denied(EPOOL_LOCKED));
    assert!(timestamp::now_seconds() >= pool.start_time, error::permission_denied(EPOOL_NOT_STARTED));
    assert!(timestamp::now_seconds() <= pool.end_time, error::permission_denied(EPOOL_ENDED));
    assert!(coin_amount > 0, error::invalid_argument(EINVALID_AMOUNT));

    // Calculate tokens to receive
    let tokens_out = calculate_buy_amount(pool, coin_amount);
    assert!(tokens_out > 0, error::invalid_argument(EINVALID_AMOUNT));
    assert!(coin::value(&pool.reserve_token) >= tokens_out, error::insufficient_funds(EINSUFFICIENT_LIQUIDITY));

    // Execute trade
    let payment = coin::withdraw<StableCoin>(account, coin_amount);
    coin::merge(&mut pool.reserve_coin, payment);
    
    let tokens_to_send = coin::extract(&mut pool.reserve_token, tokens_out);
    coin::deposit(trader, tokens_to_send);
    
    pool.total_volume = pool.total_volume + coin_amount;

    // Calculate position and deviation
    let current_x = calculate_position_x(pool);
    let expected_y = calculate_curve_y(&pool.params, current_x);
    let actual_y = calculate_current_price(pool);
    let deviation = calculate_deviation(expected_y, actual_y);
    
    pool.last_price = actual_y;

    // Record trade
    let trade_point = TradePoint {
      x: current_x,
      y: actual_y,
      timestamp: timestamp::now_seconds(),
      deviation,
      trader,
    };
    vector::push_back(&mut pool.trades, trade_point);

    // Update trader score
    update_trader_score(pool, trader, deviation, coin_amount);

    // Check threshold
    if (deviation > (pool.params.threshold_percent as u64)) {
      lock_pool(pool);
    };

    event::emit(Trade {
      pool_id: pool.id,
      trader,
      is_buy: true,
      amount_in: coin_amount,
      amount_out: tokens_out,
      price: actual_y,
      curve_deviation: deviation,
      timestamp: timestamp::now_seconds(),
    });
  }

  public entry fun sell_tokens(
    account: &signer,
    pool_addr: address,
    token_amount: u64,
  ) acquires Pool {
    let trader = signer::address_of(account);
    let pool = borrow_global_mut<Pool>(pool_addr);
    
    // Validation checks
    assert!(pool.is_active, error::permission_denied(EPOOL_NOT_ACTIVE));
    assert!(!pool.is_locked, error::permission_denied(EPOOL_LOCKED));
    assert!(timestamp::now_seconds() >= pool.start_time, error::permission_denied(EPOOL_NOT_STARTED));
    assert!(timestamp::now_seconds() <= pool.end_time, error::permission_denied(EPOOL_ENDED));
    assert!(token_amount > 0, error::invalid_argument(EINVALID_AMOUNT));

    // Calculate coins to receive
    let coins_out = calculate_sell_amount(pool, token_amount);
    assert!(coins_out > 0, error::invalid_argument(EINVALID_AMOUNT));
    assert!(coin::value(&pool.reserve_coin) >= coins_out, error::insufficient_funds(EINSUFFICIENT_LIQUIDITY));

    // Execute trade
    let tokens_payment = coin::withdraw<PoolToken>(account, token_amount);
    coin::merge(&mut pool.reserve_token, tokens_payment);
    
    let coins_to_send = coin::extract(&mut pool.reserve_coin, coins_out);
    coin::deposit(trader, coins_to_send);
    
    pool.total_volume = pool.total_volume + coins_out;

    // Calculate position and deviation
    let current_x = calculate_position_x(pool);
    let expected_y = calculate_curve_y(&pool.params, current_x);
    let actual_y = calculate_current_price(pool);
    let deviation = calculate_deviation(expected_y, actual_y);
    
    pool.last_price = actual_y;

    // Record trade
    let trade_point = TradePoint {
      x: current_x,
      y: actual_y,
      timestamp: timestamp::now_seconds(),
      deviation,
      trader,
    };
    vector::push_back(&mut pool.trades, trade_point);

    // Update trader score
    update_trader_score(pool, trader, deviation, coins_out);

    // Check threshold
    if (deviation > (pool.params.threshold_percent as u64)) {
      lock_pool(pool);
    };

    event::emit(Trade {
      pool_id: pool.id,
      trader,
      is_buy: false,
      amount_in: token_amount,
      amount_out: coins_out,
      price: actual_y,
      curve_deviation: deviation,
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
  fun calculate_curve_y(params: &CurveParams, x: u64): u64 {
    let h = params.height;
    let l = params.length;
    
    if (x > l) return 0;
    
    // y = 4*H/L * x * (1 - x/L) for parabola
    // Avoiding division issues by rearranging
    let numerator = 4 * h * x * (l - x);
    numerator / (l * l)
  }

  fun calculate_buy_amount(pool: &Pool, coin_amount: u64): u64 {
    // Constant product formula: x * y = k
    let k = coin::value(&pool.reserve_coin) * coin::value(&pool.reserve_token);
    let new_coin_reserve = coin::value(&pool.reserve_coin) + coin_amount;
    
    if (new_coin_reserve == 0) return 0;
    
    let new_token_reserve = k / new_coin_reserve;
    let current_token_reserve = coin::value(&pool.reserve_token);
    
    if (current_token_reserve > new_token_reserve) {
      current_token_reserve - new_token_reserve
    } else {
      0
    }
  }

  fun calculate_sell_amount(pool: &Pool, token_amount: u64): u64 {
    let k = coin::value(&pool.reserve_coin) * coin::value(&pool.reserve_token);
    let new_token_reserve = coin::value(&pool.reserve_token) + token_amount;
    
    if (new_token_reserve == 0) return 0;
    
    let new_coin_reserve = k / new_token_reserve;
    let current_coin_reserve = coin::value(&pool.reserve_coin);
    
    if (current_coin_reserve > new_coin_reserve) {
      current_coin_reserve - new_coin_reserve
    } else {
      0
    }
  }

  fun calculate_position_x(pool: &Pool): u64 {
    let elapsed = timestamp::now_seconds() - pool.start_time;
    let total_duration = pool.end_time - pool.start_time;
    
    if (total_duration == 0) return 0;
    
    (elapsed * pool.params.length) / total_duration
  }

  fun calculate_current_price(pool: &Pool): u64 {
    let token_reserve = coin::value(&pool.reserve_token);
    if (token_reserve == 0) return 0;
    
    coin::value(&pool.reserve_coin) / token_reserve
  }

  fun calculate_deviation(expected: u64, actual: u64): u64 {
    if (expected == 0) return 100; // Max deviation if expected is 0
    
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
        score.score = score.total_deviation / score.trade_count; // Average deviation
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
      if (score.score < best_score && score.trade_count >= 3) { // Minimum 3 trades
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

  fun lock_pool(pool: &mut Pool) {
    pool.is_locked = true;
    pool.is_active = false;
    
    // Transfer remaining funds to treasury
    let remaining_coins = coin::extract_all(&mut pool.reserve_coin);
    let remaining_tokens = coin::value(&pool.reserve_token);
    
    treasury::receive_locked_funds(remaining_coins, remaining_tokens, pool.id);
    
    event::emit(PoolLocked {
      pool_id: pool.id,
      reason: string::utf8(b"Deviation threshold exceeded"),
      final_deviation: pool.last_price,
      timestamp: timestamp::now_seconds(),
    });
  }

  // ================= VIEW FUNCTIONS =================
  #[view]
  public fun get_pool_info(pool_addr: address): (u64, bool, bool, u64, u64, u64, address) acquires Pool {
    let pool = borrow_global<Pool>(pool_addr);
    (
      pool.id,
      pool.is_active,
      pool.is_locked,
      coin::value(&pool.reserve_token),
      coin::value(&pool.reserve_coin),
      pool.total_volume,
      pool.winner
    )
  }

  #[view]
  public fun get_current_price(pool_addr: address): u64 acquires Pool {
    let pool = borrow_global<Pool>(pool_addr);
    calculate_current_price(pool)
  }

  #[view]
  public fun get_curve_position(pool_addr: address): (u64, u64, u64) acquires Pool {
    let pool = borrow_global<Pool>(pool_addr);
    let x = calculate_position_x(pool);
    let expected_y = calculate_curve_y(&pool.params, x);
    let actual_y = calculate_current_price(pool);
    (x, expected_y, actual_y)
  }

  #[view]
  public fun get_trader_scores(pool_addr: address): vector<TraderScore> acquires Pool {
    borrow_global<Pool>(pool_addr).trader_scores
  }
}