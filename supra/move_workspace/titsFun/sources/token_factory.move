// =============================================================================
// TOKEN FACTORY MODULE
// =============================================================================
module tits_fun::token_factory {
  use std::string::{Self, String};
  use std::signer;
  use supra_framework::coin::{Self, Coin, MintCapability, BurnCapability};
  use supra_framework::timestamp;
  
  struct PoolToken has key, store {}
  
  struct TokenCaps has key {
    mint_cap: MintCapability<PoolToken>,
    burn_cap: BurnCapability<PoolToken>,
    created_at: u64,
    pool_id: u64,
  }
  
  public fun create_pool_token(
    admin: &signer,
    pool_id: u64,
    initial_supply: u64
  ): (Coin<PoolToken>, MintCapability<PoolToken>, BurnCapability<PoolToken>) {
    let name = string::utf8(b"Pool Token");
    let symbol = string::utf8(b"POOL");
    
    let (burn_cap, freeze_cap, mint_cap) = coin::initialize<PoolToken>(
      admin,
      name,
      symbol,
      8,
      true,
    );
    
    coin::destroy_freeze_cap(freeze_cap);
    
    let initial_coins = coin::mint(initial_supply, &mint_cap);
    
    move_to(admin, TokenCaps {
      mint_cap,
      burn_cap,
      created_at: timestamp::now_seconds(),
      pool_id,
    });
    
    (initial_coins, mint_cap, burn_cap)
  }
}