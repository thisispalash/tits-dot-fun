// =================== TOKEN FACTORY MODULE ===================
module deployer_addr::token_factory {
  use std::error;
  use std::signer;
  use std::string::{Self, String};

  use supra_framework::account;
  use supra_framework::event;
  use supra_framework::coin::{Self, BurnCapability, FreezeCapability, MintCapability};

  // ================= STRUCTS =================
  struct PoolToken has key {}

  struct TokenCaps has key {
    mint_cap: MintCapability<PoolToken>,
    freeze_cap: FreezeCapability<PoolToken>,
    burn_cap: BurnCapability<PoolToken>,
    pool_id: u64,
    initial_supply: u64,
  }

  struct TokenRegistry has key {
    next_token_id: u64,
    created_tokens: vector<u64>,
  }

  // ================= EVENTS =================
  #[event]
  struct TokenCreated has drop, store {
    pool_id: u64,
    name: String,
    symbol: String,
    initial_supply: u64,
    creator: address,
    timestamp: u64,
  }

  // ================= ERRORS =================
  const ETOKEN_ALREADY_EXISTS: u64 = 1;
  const ETOKEN_NOT_FOUND: u64 = 2;

  // ================= INIT =================
  fun init_module(account: &signer) {
    move_to(account, TokenRegistry {
      next_token_id: 1,
      created_tokens: vector::empty(),
    });
  }

  // ================= PUBLIC FUNCTIONS =================
  public fun create_pool_token(
    account: &signer,
    pool_id: u64,
    name: String,
    symbol: String,
    initial_supply: u64,
  ): (MintCapability<PoolToken>, BurnCapability<PoolToken>) acquires TokenRegistry {
    let creator = signer::address_of(account);
    
    let (burn_cap, freeze_cap, mint_cap) = coin::initialize<PoolToken>(
      account,
      name,
      symbol,
      8,
      true,
    );

    // Store caps for this specific pool
    move_to(account, TokenCaps {
      mint_cap,
      freeze_cap,
      burn_cap,
      pool_id,
      initial_supply,
    });

    // Update registry
    let registry = borrow_global_mut<TokenRegistry>(@deployer_addr);
    vector::push_back(&mut registry.created_tokens, pool_id);
    registry.next_token_id = registry.next_token_id + 1;

    event::emit(TokenCreated {
      pool_id,
      name,
      symbol,
      initial_supply,
      creator,
      timestamp: supra_framework::timestamp::now_seconds(),
    });

    // Return capabilities for immediate use
    let caps = borrow_global<TokenCaps>(creator);
    (&caps.mint_cap, &caps.burn_cap)
  }

  public fun mint_tokens(
    mint_cap: &MintCapability<PoolToken>,
    amount: u64,
  ): coin::Coin<PoolToken> {
    coin::mint(amount, mint_cap)
  }

  public fun burn_tokens(
    burn_cap: &BurnCapability<PoolToken>,
    tokens: coin::Coin<PoolToken>,
  ) {
    coin::burn(tokens, burn_cap)
  }

  // ================= VIEW FUNCTIONS =================
  #[view]
  public fun get_created_tokens(): vector<u64> acquires TokenRegistry {
    borrow_global<TokenRegistry>(@deployer_addr).created_tokens
  }
}