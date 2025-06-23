// =================== TREASURY MODULE (For Future Fees) ===================
module deployer_addr::treasury {
  use std::error;
  use std::signer;
  use std::vector;

  use supra_framework::account;
  use supra_framework::timestamp;
  use supra_framework::event;
  use supra_framework::coin::{Self, Coin};
  use supra_framework::supra_coin::SupraCoin;

  // ================= STRUCTS =================
  struct Treasury has key {
    admin: address,
    total_fees_collected: u64,
    reserve_coins: Coin<SupraCoin>,
    fee_history: vector<FeeCollection>,
  }

  struct FeeCollection has store {
    pool_id: u64,
    fee_amount: u64,
    fee_type: String, // "trading_fee", "creation_fee", etc.
    timestamp: u64,
  }

  // ================= EVENTS =================
  #[event]
  struct FeeCollected has drop, store {
    pool_id: u64,
    fee_amount: u64,
    fee_type: String,
    timestamp: u64,
  }

  #[event]
  struct FeeWithdrawn has drop, store {
    recipient: address,
    amount: u64,
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
      total_fees_collected: 0,
      reserve_coins: coin::zero<SupraCoin>(),
      fee_history: vector::empty(),
    });
  }

  // ================= PUBLIC FUNCTIONS =================
  public fun collect_fee(
    fee_coins: Coin<SupraCoin>,
    pool_id: u64,
    fee_type: String,
  ) acquires Treasury {
    let treasury = borrow_global_mut<Treasury>(@deployer_addr);
    
    let fee_amount = coin::value(&fee_coins);
    coin::merge(&mut treasury.reserve_coins, fee_coins);
    treasury.total_fees_collected = treasury.total_fees_collected + fee_amount;

    let fee_record = FeeCollection {
      pool_id,
      fee_amount,
      fee_type,
      timestamp: timestamp::now_seconds(),
    };
    vector::push_back(&mut treasury.fee_history, fee_record);

    event::emit(FeeCollected {
      pool_id,
      fee_amount,
      fee_type,
      timestamp: timestamp::now_seconds(),
    });
  }

  public entry fun withdraw_fees(
    account: &signer,
    amount: u64,
  ) acquires Treasury {
    let admin = signer::address_of(account);
    let treasury = borrow_global_mut<Treasury>(@deployer_addr);
    
    assert!(treasury.admin == admin, error::permission_denied(ENOT_ADMIN));
    assert!(coin::value(&treasury.reserve_coins) >= amount, 
            error::insufficient_funds(EINSUFFICIENT_FUNDS));

    let withdrawal = coin::extract(&mut treasury.reserve_coins, amount);
    coin::deposit(admin, withdrawal);

    event::emit(FeeWithdrawn {
      recipient: admin,
      amount,
      timestamp: timestamp::now_seconds(),
    });
  }

  // ================= VIEW FUNCTIONS =================
  #[view]
  public fun get_treasury_balance(): u64 acquires Treasury {
    let treasury = borrow_global<Treasury>(@deployer_addr);
    coin::value(&treasury.reserve_coins)
  }

  #[view]
  public fun get_total_fees_collected(): u64 acquires Treasury {
    borrow_global<Treasury>(@deployer_addr).total_fees_collected
  }

  #[view]
  public fun get_fee_history(): vector<FeeCollection> acquires Treasury {
    borrow_global<Treasury>(@deployer_addr).fee_history
  }
}