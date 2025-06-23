// =============================================================================
// TREASURY MODULE
// =============================================================================
module tits_fun::treasury {
  use std::signer;
  use supra_framework::coin::{Self, Coin, transfer};
  use supra_framework::supra_coin::SupraCoin;
  use supra_framework::timestamp;
  
  struct Treasury has key {
    balance: u64,
    total_fees_collected: u64,
    admin: address,
    created_at: u64,
  }
  
  fun init_module(admin: &signer) {
    move_to(admin, Treasury {
      balance: 0,
      total_fees_collected: 0,
      admin: signer::address_of(admin),
      created_at: timestamp::now_seconds(),
    });
  }
  
  public entry fun collect_fees(
    admin: &signer,
    amount: u64,
    fee_coin: Coin<SupraCoin>
  ) acquires Treasury {
    let treasury = borrow_global_mut<Treasury>(signer::address_of(admin));
    treasury.balance = treasury.balance + amount;
    treasury.total_fees_collected = treasury.total_fees_collected + amount;
    
    coin::deposit(signer::address_of(admin), fee_coin);
  }
  
  public entry fun emergency_start_pool(
    admin: &signer,
    amount: u64
  ) acquires Treasury {
    let treasury = borrow_global_mut<Treasury>(signer::address_of(admin));
    assert!(treasury.balance >= amount, 1);
    
    treasury.balance = treasury.balance - amount;
    // Logic to start new pool would go here
  }
  
  #[view]
  public fun get_balance(admin: address): u64 acquires Treasury {
    borrow_global<Treasury>(admin).balance
  }
}