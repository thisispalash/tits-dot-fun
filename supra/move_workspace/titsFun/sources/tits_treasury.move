// =================== TREASURY MODULE ===================
module deployer_addr::treasury {
  use std::error;
  use std::signer;
  use std::vector;

  use supra_framework::account;
  use supra_framework::timestamp;
  use supra_framework::event;
  use supra_framework::coin::{Self, Coin};
  use deployer_addr::stable_coin::StableCoin;
  use deployer_addr::curve_launcher::CurveParams;
  use deployer_addr::pool_pair;

  // ================= STRUCTS =================
  struct Treasury has key {
    admin: address,
    total_coins_collected: u64,
    total_tokens_collected: u64,
    reserve_coins: Coin<StableCoin>,
    reserve_tokens: u64,
    collection_history: vector<Collection>,
    locked_pool_count: u64,
  }

  struct Collection has store {
    pool_id: u64,
    coins_amount: u64,
    tokens_amount: u64,
    timestamp: u64,
  }

  // ================= EVENTS =================
  #[event]
  struct FundsReceived has drop, store {
    pool_id: u64,
    coins_amount: u64,
    tokens_amount: u64,
    timestamp: u64,
  }

  #[event]
  struct FundsWithdrawn has drop, store {
    recipient: address,
    coins_amount: u64,
    tokens_amount: u64,
    timestamp: u64,
  }

  #[event]
  struct AutoPoolCreated has drop, store {
    pool_id: u64,
    scheduled_start: u64,
    timestamp: u64,
  }

  // ================= ERRORS =================
  const ENOT_ADMIN: u64 = 1;
  const EINSUFFICIENT_FUNDS: u64 = 2;

  // ================= INIT =================
  fun init_module(account: &signer) {
    let admin_addr = signer::address_of(account);
    move_to(account, Treasury {
      admin: admin_addr,
      total_coins_collected: 0,
      total_tokens_collected: 0,
      reserve_coins: coin::zero<StableCoin>(),
      reserve_tokens: 0,
      collection_history: vector::empty(),
      locked_pool_count: 0,
    });
  }

  // ================= PUBLIC FUNCTIONS =================
  public fun receive_all_locked_funds(
    coins: Coin<StableCoin>,
    tokens: u64,
    pool_id: u64,
  ) acquires Treasury {
    let treasury = borrow_global_mut<Treasury>(@deployer_addr);
    
    let coins_amount = coin::value(&coins);
    
    // 100% of funds go to admin immediately
    coin::deposit(treasury.admin, coins);
    
    treasury.total_coins_collected = treasury.total_coins_collected + coins_amount;
    treasury.total_tokens_collected = treasury.total_tokens_collected + tokens;
    treasury.locked_pool_count = treasury.locked_pool_count + 1;

    let collection = Collection {
      pool_id,
      coins_amount,
      tokens_amount: tokens,
      timestamp: timestamp::now_seconds(),
    };
    vector::push_back(&mut treasury.collection_history, collection);

    event::emit(FundsReceived {
      pool_id,
      coins_amount,
      tokens_amount: tokens,
      timestamp: timestamp::now_seconds(),
    });
  }

  // 4. Treasury creates new pools (auto-deploy after locked pools)
  public fun create_pool_from_treasury(
    pool_id: u64,
    token_name: String,
    token_symbol: String,
    params: CurveParams,
    start_time: u64,
  ) acquires Treasury {
    let treasury = borrow_global<Treasury>(@deployer_addr);
    
    // Treasury acts as the pool creator
    let treasury_signer = &create_signer_with_capability(&create_account_capability(treasury.admin));
    
    pool_pair::create_pool(
      treasury_signer,
      pool_id,
      token_name,
      token_symbol,
      params,
      start_time
    );

    event::emit(AutoPoolCreated {
      pool_id,
      scheduled_start: start_time,
      timestamp: timestamp::now_seconds(),
    });
  }

  public entry fun withdraw_remaining_funds(
    account: &signer,
    coins_amount: u64,
    tokens_amount: u64,
  ) acquires Treasury {
    let admin = signer::address_of(account);
    let treasury = borrow_global_mut<Treasury>(@deployer_addr);
    
    assert!(treasury.admin == admin, error::permission_denied(ENOT_ADMIN));
    assert!(coin::value(&treasury.reserve_coins) >= coins_amount, 
            error::insufficient_funds(EINSUFFICIENT_FUNDS));
    assert!(treasury.reserve_tokens >= tokens_amount, 
            error::insufficient_funds(EINSUFFICIENT_FUNDS));

    if (coins_amount > 0) {
      let withdrawal = coin::extract(&mut treasury.reserve_coins, coins_amount);
      coin::deposit(admin, withdrawal);
    };

    treasury.reserve_tokens = treasury.reserve_tokens - tokens_amount;

    event::emit(FundsWithdrawn {
      recipient: admin,
      coins_amount,
      tokens_amount,
      timestamp: timestamp::now_seconds(),
    });
  }

  // ================= VIEW FUNCTIONS =================
  #[view]
  public fun get_treasury_balance(): (u64, u64) acquires Treasury {
    let treasury = borrow_global<Treasury>(@deployer_addr);
    (coin::value(&treasury.reserve_coins), treasury.reserve_tokens)
  }

  #[view]
  public fun get_total_collected(): (u64, u64, u64) acquires Treasury {
    let treasury = borrow_global<Treasury>(@deployer_addr);
    (treasury.total_coins_collected, treasury.total_tokens_collected, treasury.locked_pool_count)
  }

  #[view]
  public fun get_collection_history(): vector<Collection> acquires Treasury {
    borrow_global<Treasury>(@deployer_addr).collection_history
  }
}