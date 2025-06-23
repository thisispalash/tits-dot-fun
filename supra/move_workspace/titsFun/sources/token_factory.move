// =============================================================================
// TOKEN FACTORY MODULE
// =============================================================================
module tits_fun::token_factory {
  use std::string::{Self, String};
  use std::signer;
  use std::vector;
  use std::bcs;
  use supra_framework::coin::{Self, Coin, MintCapability, BurnCapability, FreezeCapability};
  use supra_framework::timestamp;
  use supra_framework::event;
  use supra_framework::account;
  use supra_framework::resource_account;
  
  // Generic token struct - each pool will have its own instance
  struct PoolToken has key, store {}
  
  // Stored at the resource account address for each pool
  struct TokenCaps has key {
    mint_cap: MintCapability<PoolToken>,
    freeze_cap: FreezeCapability<PoolToken>,
    burn_cap: BurnCapability<PoolToken>,
    pool_id: u64,
    initial_supply: u64,
    resource_account_addr: address,
    created_at: u64,
  }
  
  // Stored at the main admin address to track all pools
  struct PoolRegistry has key {
    created_pools: vector<PoolInfo>,
    admin: address,
  }
  
  struct PoolInfo has store, copy {
    pool_id: u64,
    token_address: address,  // The resource account address
    name: String,
    symbol: String,
    created_at: u64,
  }
  
  #[event]
  struct TokenCreated has drop, store {
    pool_id: u64,
    token_address: address,
    name: String,
    symbol: String,
    initial_supply: u64,
    creator: address,
    timestamp: u64,
  }
  
  const ETOKEN_ALREADY_EXISTS: u64 = 1;
  const ETOKEN_NOT_FOUND: u64 = 2;
  const EINVALID_POOL: u64 = 3;
  
  fun init_module(admin: &signer) {
    move_to(admin, PoolRegistry {
      created_pools: vector::empty<PoolInfo>(),
      admin: signer::address_of(admin),
    });
  }
  
  public fun create_pool_token(
    admin: &signer,
    pool_id: u64,
    initial_supply: u64
  ): (address, Coin<PoolToken>) acquires PoolRegistry {
    let admin_addr = signer::address_of(admin);
    
    // Generate unique seed for this pool
    let seed = b"CRYPTO_TITTY_";
    let pool_id_bytes = bcs::to_bytes(&pool_id);
    vector::append(&mut seed, pool_id_bytes);
    
    // Create resource account for this specific pool
    let (resource_signer, resource_signer_cap) = account::create_resource_account(admin, seed);
    let token_address = signer::address_of(&resource_signer);
    
    // Generate pool-specific name and symbol
    let pool_id_str = u64_to_padded_string(pool_id);
    let name = string::utf8(b"Crypto Titty ");
    string::append(&mut name, pool_id_str);
    
    let symbol = string::utf8(b"T");
    string::append(&mut symbol, pool_id_str);
    
    // Initialize the coin type at the resource account
    let (burn_cap, freeze_cap, mint_cap) = coin::initialize<PoolToken>(
      &resource_signer,
      name,
      symbol,
      8, // 8 decimals
      true,
    );
    
    // Store capabilities at the resource account
    move_to(&resource_signer, TokenCaps {
      mint_cap,
      freeze_cap,
      burn_cap,
      pool_id,
      initial_supply,
      resource_account_addr: token_address,
      created_at: timestamp::now_seconds(),
    });
    
    // Mint initial supply
    let initial_tokens = coin::mint(initial_supply, &mint_cap);
    
    // Update registry at admin address
    let registry = borrow_global_mut<PoolRegistry>(admin_addr);
    vector::push_back(&mut registry.created_pools, PoolInfo {
      pool_id,
      token_address,
      name,
      symbol,
      created_at: timestamp::now_seconds(),
    });
    
    // Emit event
    event::emit(TokenCreated {
      pool_id,
      token_address,
      name,
      symbol,
      initial_supply,
      creator: admin_addr,
      timestamp: timestamp::now_seconds(),
    });
    
    (token_address, initial_tokens)
  }
  
  public fun mint_tokens(
    token_address: address,
    amount: u64
  ): Coin<PoolToken> acquires TokenCaps {
    let caps = borrow_global<TokenCaps>(token_address);
    coin::mint(amount, &caps.mint_cap)
  }
  
  // Burn tokens for a specific pool
  public fun burn_tokens(
    admin: &signer,
    token_address: address,
    tokens: Coin<PoolToken>
  ) acquires TokenCaps {
    let caps = borrow_global<TokenCaps>(token_address);
    coin::burn(tokens, &caps.burn_cap);
  }
  
  // Helper function to convert u64 to padded string
  fun u64_to_padded_string(value: u64): String {
    if (value < 10) {
      let result = string::utf8(b"00");
      let digit = ((value as u8) + 48);
      string::append(&mut result, string::utf8(vector::singleton(digit)));
      result
    } else if (value < 100) {
      let result = string::utf8(b"0");
      let tens = ((value / 10) as u8) + 48;
      let ones = ((value % 10) as u8) + 48;
      string::append(&mut result, string::utf8(vector::singleton(tens)));
      string::append(&mut result, string::utf8(vector::singleton(ones)));
      result
    } else {
      let hundreds = ((value / 100) as u8) + 48;
      let tens = (((value % 100) / 10) as u8) + 48;
      let ones = ((value % 10) as u8) + 48;
      let result = string::utf8(vector::singleton(hundreds));
      string::append(&mut result, string::utf8(vector::singleton(tens)));
      string::append(&mut result, string::utf8(vector::singleton(ones)));
      result
    }
  }
  
  // View functions
  #[view]
  public fun get_pool_token_address(admin: address, pool_id: u64): address acquires PoolRegistry {
    let registry = borrow_global<PoolRegistry>(admin);
    let pools = &registry.created_pools;
    let len = vector::length(pools);
    
    let i = 0;
    while (i < len) {
      let pool_info = vector::borrow(pools, i);
      if (pool_info.pool_id == pool_id) {
        return pool_info.token_address
      };
      i = i + 1;
    };
    
    @0x0 // Not found
  }
  
  #[view]
  public fun get_all_pools(admin: address): vector<PoolInfo> acquires PoolRegistry {
    *&borrow_global<PoolRegistry>(admin).created_pools
  }
}