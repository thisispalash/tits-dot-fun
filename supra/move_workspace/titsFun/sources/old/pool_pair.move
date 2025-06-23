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
  use supra_framework::supra_coin::SupraCoin;  // Only native token now
  
  use deployer_addr::curve_launcher::CurveParams;
  use deployer_addr::treasury; // For potential future fees

  // ================= CONSTANTS =================
  const POOL_DURATION_SECONDS: u64 = 86400;
  const INITIAL_COIN_LIQUIDITY: u64 = 1000_00000000;    // 1000 SupraCoin
  const INITIAL_TOKEN_LIQUIDITY: u64 = 1000000_00000000; // 1M pool tokens

  // ================= STRUCTS =================
  struct Pool has key {
      id: u64,
      params: CurveParams,
      start_time: u64,
      end_time: u64,
      is_active: bool,
      is_locked: bool,
      creator: address,
      // AMM Reserves - all SupraCoin now
      reserve_coin: Coin<SupraCoin>,  
      reserve_token: u64,             // Virtual pool tokens
      // Trading data for off-chain analysis
      trade_history: vector<TradeData>,
      trader_scores: vector<TraderScore>,
      winner: address,
      total_volume: u64,
  }

  struct TradeData has store, copy, drop {
      timestamp: u64,
      price: u64,
      volume: u64,
      is_buy: bool,
      trader: address,
  }

  struct TraderScore has store, copy, drop {
      trader: address,
      total_deviation: u64,
      trade_count: u64,
      volume: u64,
      score: u64,
  }

  struct PoolToken has key {
      name: String,
      symbol: String,
      decimals: u8,
      total_supply: u64,
  }

  // ================= EVENTS =================
  #[event]
  struct Trade has drop, store {
      pool_id: u64,
      trader: address,
      is_buy: bool,
      amount_in: u64,
      amount_out: u64,
      price: u64,
      timestamp: u64,
  }

  #[event]
  struct PoolLocked has drop, store {
      pool_id: u64,
      burned_amount: u64,
      reason: String,
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
  const EINVALID_AMOUNT: u64 = 5;
  const EPOOL_NOT_STARTED: u64 = 6;
  const EPOOL_NOT_FOUND: u64 = 7;

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
      
      // Initialize with non-zero reserves using SupraCoin
      let initial_coins = coin::withdraw<SupraCoin>(account, INITIAL_COIN_LIQUIDITY);
      
      let pool = Pool {
          id: pool_id,
          params,
          start_time,
          end_time: start_time + POOL_DURATION_SECONDS,
          is_active: true,
          is_locked: false,
          creator,
          reserve_coin: initial_coins,
          reserve_token: INITIAL_TOKEN_LIQUIDITY,
          trade_history: vector::empty(),
          trader_scores: vector::empty(),
          winner: @0x0,
          total_volume: 0,
      };

      move_to(account, pool);
      
      move_to(account, PoolToken {
          name: token_name,
          symbol: token_symbol,
          decimals: 8,
          total_supply: INITIAL_TOKEN_LIQUIDITY,
      });
  }

  public fun create_pool_from_system(
      pool_id: u64,
      token_name: String,
      token_symbol: String,
      params: CurveParams,
      start_time: u64,
  ) {
      // System creates pool - will need mechanism to fund initial liquidity
      let pool = Pool {
          id: pool_id,
          params,
          start_time,
          end_time: start_time + POOL_DURATION_SECONDS,
          is_active: true,
          is_locked: false,
          creator: @deployer_addr,
          reserve_coin: coin::zero<SupraCoin>(), // TODO: Need initial funding mechanism
          reserve_token: INITIAL_TOKEN_LIQUIDITY,
          trade_history: vector::empty(),
          trader_scores: vector::empty(),
          winner: @0x0,
          total_volume: 0,
      };

      move_to(@deployer_addr, pool);
      
      move_to(@deployer_addr, PoolToken {
          name: token_name,
          symbol: token_symbol,
          decimals: 8,
          total_supply: INITIAL_TOKEN_LIQUIDITY,
      });
  }

  public entry fun buy_tokens(
      account: &signer,
      pool_id: u64,
      coin_amount: u64,
  ) acquires Pool {
      let trader = signer::address_of(account);
      
      // Find the pool - check multiple possible locations
      let pool_addr = find_pool_address(pool_id);
      let pool = borrow_global_mut<Pool>(pool_addr);
      
      assert!(pool.id == pool_id, error::invalid_argument(EPOOL_NOT_ACTIVE));
      assert!(!pool.is_locked, error::permission_denied(EPOOL_LOCKED));
      assert!(timestamp::now_seconds() >= pool.start_time, error::permission_denied(EPOOL_NOT_STARTED));
      assert!(timestamp::now_seconds() <= pool.end_time, error::permission_denied(EPOOL_NOT_ACTIVE));
      
      // AMM: x*y = (x+x')*y', out = y-y'
      let current_x = coin::value(&pool.reserve_coin);
      let current_y = pool.reserve_token;
      
      if (current_x == 0 || current_y == 0) {
          // Handle initial liquidity case
          assert!(false, error::insufficient_funds(EINSUFFICIENT_LIQUIDITY));
      };
      
      let k = current_x * current_y;
      let new_x = current_x + coin_amount;
      let calculated_y = k / new_x;
      let tokens_out = current_y - calculated_y;
      
      assert!(tokens_out > 0, error::invalid_argument(EINVALID_AMOUNT));
      assert!(pool.reserve_token >= tokens_out, error::insufficient_funds(EINSUFFICIENT_LIQUIDITY));

      // Execute trade
      let payment = coin::withdraw<SupraCoin>(account, coin_amount);
      coin::merge(&mut pool.reserve_coin, payment);
      pool.reserve_token = pool.reserve_token - tokens_out;
      pool.total_volume = pool.total_volume + coin_amount;

      // Record trade data for off-chain analysis
      let current_price = calculate_current_price(pool);
      let trade_data = TradeData {
          timestamp: timestamp::now_seconds(),
          price: current_price,
          volume: coin_amount,
          is_buy: true,
          trader,
      };
      vector::push_back(&mut pool.trade_history, trade_data);

      // TODO: Future fee collection
      // let fee = coin_amount / 1000; // 0.1% fee
      // if (fee > 0) {
      //     let fee_coins = coin::extract(&mut pool.reserve_coin, fee);
      //     treasury::collect_fee(fee_coins, pool_id, string::utf8(b"trading_fee"));
      // };

      event::emit(Trade {
          pool_id,
          trader,
          is_buy: true,
          amount_in: coin_amount,
          amount_out: tokens_out,
          price: current_price,
          timestamp: timestamp::now_seconds(),
      });
  }

  public entry fun sell_tokens(
      account: &signer, 
      pool_id: u64,
      token_amount: u64,
  ) acquires Pool {
      let trader = signer::address_of(account);
      let pool_addr = find_pool_address(pool_id);
      let pool = borrow_global_mut<Pool>(pool_addr);
      
      assert!(pool.id == pool_id, error::invalid_argument(EPOOL_NOT_ACTIVE));
      assert!(!pool.is_locked, error::permission_denied(EPOOL_LOCKED));
      assert!(timestamp::now_seconds() >= pool.start_time, error::permission_denied(EPOOL_NOT_STARTED));
      assert!(timestamp::now_seconds() <= pool.end_time, error::permission_denied(EPOOL_NOT_ACTIVE));

      // AMM: x*y = (x+x')*y', out = y-y'
      let current_x = coin::value(&pool.reserve_coin);
      let current_y = pool.reserve_token;
      
      if (current_x == 0 || current_y == 0) {
          assert!(false, error::insufficient_funds(EINSUFFICIENT_LIQUIDITY));
      };
      
      let k = current_x * current_y;
      let new_y = current_y + token_amount;
      let calculated_x = k / new_y;
      let coins_out = current_x - calculated_x;
      
      assert!(coins_out > 0, error::invalid_argument(EINVALID_AMOUNT));
      assert!(coin::value(&pool.reserve_coin) >= coins_out, error::insufficient_funds(EINSUFFICIENT_LIQUIDITY));

      // Execute trade
      pool.reserve_token = pool.reserve_token + token_amount;
      let payout = coin::extract(&mut pool.reserve_coin, coins_out);
      coin::deposit(trader, payout);
      pool.total_volume = pool.total_volume + coins_out;

      // Record trade data
      let current_price = calculate_current_price(pool);
      let trade_data = TradeData {
          timestamp: timestamp::now_seconds(),
          price: current_price,
          volume: coins_out,
          is_buy: false,
          trader,
      };
      vector::push_back(&mut pool.trade_history, trade_data);

      event::emit(Trade {
          pool_id,
          trader,
          is_buy: false,
          amount_in: token_amount,
          amount_out: coins_out,
          price: current_price,
          timestamp: timestamp::now_seconds(),
      });
  }

  // Called by automation service to lock and burn pool
  public fun lock_and_burn_pool(
      account: &signer,
      pool_id: u64,
  ): u64 acquires Pool {
      let pool_addr = find_pool_address(pool_id);
      let pool = borrow_global_mut<Pool>(pool_addr);
      assert!(pool.id == pool_id, error::invalid_argument(EPOOL_NOT_ACTIVE));
      
      pool.is_locked = true;
      pool.is_active = false;
      
      // Burn all remaining funds to @0x0 (deflationary pressure on SupraCoin)
      let remaining_coins = coin::extract_all(&mut pool.reserve_coin);
      let burned_amount = coin::value(&remaining_coins);
      
      // Send to @0x0 (effectively burning SupraCoin)
      coin::deposit(@0x0, remaining_coins);
      pool.reserve_token = 0;
      
      event::emit(PoolLocked {
          pool_id,
          burned_amount,
          reason: string::utf8(b"Deviation threshold exceeded"),
          timestamp: timestamp::now_seconds(),
      });
      
      burned_amount
  }

  public fun finalize_pool(
      account: &signer,
      pool_id: u64,
  ): (address, bool, u64, CurveParams) acquires Pool {
      let pool_addr = find_pool_address(pool_id);
      let pool = borrow_global_mut<Pool>(pool_addr);
      assert!(pool.id == pool_id, error::invalid_argument(EPOOL_NOT_ACTIVE));
      
      pool.is_active = false;
      
      // Winner determination logic
      if (!pool.is_locked && vector::length(&pool.trader_scores) > 0) {
          pool.winner = find_best_trader(&pool.trader_scores);
      };

      event::emit(PoolFinalized {
          pool_id,
          winner: pool.winner,
          final_score: 0, // TODO: Calculate final score
          total_volume: pool.total_volume,
          timestamp: timestamp::now_seconds(),
      });
      
      (pool.winner, pool.is_locked, pool.total_volume, pool.params)
  }

  // ================= HELPER FUNCTIONS =================
  fun find_pool_address(pool_id: u64): address {
      // Simple implementation - in practice, you'd maintain a registry
      // For now, assume pools are at @deployer_addr
      @deployer_addr
  }

  fun calculate_current_price(pool: &Pool): u64 {
      if (pool.reserve_token == 0) return 0;
      coin::value(&pool.reserve_coin) / pool.reserve_token
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

  // ================= VIEW FUNCTIONS =================
  #[view]
  public fun get_pool_params(pool_id: u64): CurveParams acquires Pool {
      let pool_addr = find_pool_address(pool_id);
      let pool = borrow_global<Pool>(pool_addr);
      pool.params
  }

  #[view]
  public fun get_trade_history(pool_id: u64): vector<TradeData> acquires Pool {
      let pool_addr = find_pool_address(pool_id);
      borrow_global<Pool>(pool_addr).trade_history
  }

  #[view]
  public fun get_pool_info(pool_id: u64): (u64, bool, bool, u64, u64, u64, address) acquires Pool {
      let pool_addr = find_pool_address(pool_id);
      let pool = borrow_global<Pool>(pool_addr);
      (
          pool.id,
          pool.is_active,
          pool.is_locked,
          pool.reserve_token,
          coin::value(&pool.reserve_coin),
          pool.total_volume,
          pool.winner
      )
  }

  #[view]
  public fun calculate_expected_price_for_candle(pool_id: u64, candle: u64): u64 acquires Pool {
      let pool_addr = find_pool_address(pool_id);
      let pool = borrow_global<Pool>(pool_addr);
      
      // Formula: y = 4 * (H/L) * x * (1 - x/L)
      let h = pool.params.height;
      let l = pool.params.length;
      
      if (candle >= l) return 0;
      
      let term1 = (4 * h) / l;
      let term2 = candle;
      let term3 = l - candle;
      
      (term1 * term2 * term3) / l
  }
}