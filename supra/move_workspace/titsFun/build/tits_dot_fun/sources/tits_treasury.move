// =============================================================================
// TREASURY MODULE
// =============================================================================
module tits_fun::tits_treasury {
  use std::signer;
  use std::error;
  use supra_framework::coin::{Self, Coin};
  use supra_framework::supra_coin::SupraCoin;
  use supra_framework::timestamp;
  use supra_framework::event;
  
  struct Treasury has key {
    balance: u64,
    total_fees_collected: u64,
    admin: address,
    created_at: u64,
    reserve_coins: Coin<SupraCoin>,
  }
  
  #[event]
  struct FeesWithdrawn has drop, store {
    amount: u64,
    admin: address,
    timestamp: u64,
    remaining_balance: u64,
  }
  
  #[event]
  struct TreasuryFunded has drop, store {
    amount: u64,
    funder: address,
    timestamp: u64,
    new_balance: u64,
  }
  
  #[event]
  struct EmergencyPoolFund has drop, store {
    amount: u64,
    pool_id: u64,
    timestamp: u64,
    remaining_balance: u64,
  }
  
  const EINSUFFICIENT_BALANCE: u64 = 1;
  const EUNAUTHORIZED: u64 = 2;
  
  fun init_module(admin: &signer) {
    move_to(admin, Treasury {
      balance: 0,
      total_fees_collected: 0,
      admin: signer::address_of(admin),
      created_at: timestamp::now_seconds(),
      reserve_coins: coin::zero<SupraCoin>(),
    });
  }
  
  // Called by pool manager to collect trading fees
  // No admin check needed - this is internal protocol function
  // No event emission to avoid spam
  public fun collect_fees(
    admin_addr: address,
    amount: u64,
    fee_coin: Coin<SupraCoin>
  ) acquires Treasury {
    let treasury = borrow_global_mut<Treasury>(admin_addr);
    
    treasury.balance = treasury.balance + amount;
    treasury.total_fees_collected = treasury.total_fees_collected + amount;
    
    // Properly deposit the fee coin to the treasury account
    coin::deposit(admin_addr, fee_coin);
  }
  
  // Admin function to withdraw fees from treasury
  public entry fun withdraw_fees(
    admin: &signer,
    amount: u64
  ) acquires Treasury {
    let admin_addr = signer::address_of(admin);
    let treasury = borrow_global_mut<Treasury>(admin_addr);
    
    // Verify admin
    assert!(treasury.admin == admin_addr, error::permission_denied(EUNAUTHORIZED));
    assert!(treasury.balance >= amount, error::invalid_state(EINSUFFICIENT_BALANCE));
    
    treasury.balance = treasury.balance - amount;
    
    // Withdraw coins from treasury account to admin
    let withdrawn_coin = coin::withdraw<SupraCoin>(admin, amount);
    coin::deposit(admin_addr, withdrawn_coin);
    
    event::emit(FeesWithdrawn {
      amount,
      admin: admin_addr,
      timestamp: timestamp::now_seconds(),
      remaining_balance: treasury.balance,
    });
  }
  
  // Function to fund new pools
  public entry fun initialize_pool_funding(
    admin: &signer,
    funding_amount: u64,
    pool_id: u64
  ) acquires Treasury {
    // NOTE: can remove this for now since admin_addr is same as pool_addr
    // let funding_coin = coin::withdraw<SupraCoin>(admin, funding_amount);
    let admin_addr = signer::address_of(admin);
    let treasury = borrow_global_mut<Treasury>(admin_addr);
    
    // Extract actual coins from treasury
    let funding_coins = coin::extract(&mut treasury.reserve_coins, funding_amount);
    
    // Deposit to admin account to fund the pool
    coin::deposit(signer::address_of(admin), funding_coins);
    
    // Update balance tracking
    treasury.balance = treasury.balance - funding_amount;
    
    event::emit(EmergencyPoolFund {
      amount: funding_amount,
      pool_id,
      timestamp: timestamp::now_seconds(),
      remaining_balance: treasury.balance,
    });
  }
  
  // Anyone can fund the treasury
  public entry fun fund_treasury(
    funder: &signer,
    admin_addr: address,  // Specify which treasury to fund
    amount: u64
  ) acquires Treasury {
    let funder_addr = signer::address_of(funder);
    let treasury = borrow_global_mut<Treasury>(admin_addr);
    
    // Withdraw the coins from the funder
    let funding_coin = coin::withdraw<SupraCoin>(funder, amount);

    // Deposit the funding coin to the treasury account
    coin::deposit(admin_addr, funding_coin);
    
    treasury.balance = treasury.balance + amount;
    
    event::emit(TreasuryFunded {
      amount,
      funder: funder_addr,
      timestamp: timestamp::now_seconds(),
      new_balance: treasury.balance,
    });
  }
  
  #[view]
  public fun get_balance(admin: address): u64 acquires Treasury {
    borrow_global<Treasury>(admin).balance
  }
  
  #[view]
  public fun get_total_fees_collected(admin: address): u64 acquires Treasury {
    borrow_global<Treasury>(admin).total_fees_collected
  }
  
  #[view]
  public fun get_admin(admin: address): address acquires Treasury {
    borrow_global<Treasury>(admin).admin
  }
}