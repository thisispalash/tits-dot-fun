// =================== STABLECOIN MODULE ===================
module deployer_addr::stable_coin {
  use std::error;
  use std::signer;
  use std::string::{Self, String};

  use supra_framework::account;
  use supra_framework::event;
  use supra_framework::coin::{Self, BurnCapability, FreezeCapability, MintCapability};

  // ================= STRUCTS =================
  struct StableCoin has key {}

  struct StableCoinCaps has key {
    mint_cap: MintCapability<StableCoin>,
    freeze_cap: FreezeCapability<StableCoin>,
    burn_cap: BurnCapability<StableCoin>,
  }

  // ================= EVENTS =================
  #[event]
  struct StableCoinMinted has drop, store {
    to: address,
    amount: u64,
    timestamp: u64,
  }

  // ================= ERRORS =================
  const ENOT_ADMIN: u64 = 1;

  // ================= INIT =================
  fun init_module(account: &signer) {
    let (burn_cap, freeze_cap, mint_cap) = coin::initialize<StableCoin>(
      account,
      string::utf8(b"Stable USD"),
      string::utf8(b"SUSD"),
      8,
      true,
    );

    move_to(account, StableCoinCaps {
      mint_cap,
      freeze_cap, 
      burn_cap,
    });
  }

  // ================= PUBLIC FUNCTIONS =================
  public entry fun mint(
    account: &signer,
    to: address,
    amount: u64,
  ) acquires StableCoinCaps {
    let caps = borrow_global<StableCoinCaps>(signer::address_of(account));
    let coins = coin::mint(amount, &caps.mint_cap);
    coin::deposit(to, coins);

    event::emit(StableCoinMinted {
      to,
      amount,
      timestamp: supra_framework::timestamp::now_seconds(),
    });
  }

  public entry fun faucet(account: &signer) acquires StableCoinCaps {
    let to = signer::address_of(account);
    let caps = borrow_global<StableCoinCaps>(@deployer_addr);
    let coins = coin::mint(10000_00000000, &caps.mint_cap); // 10k tokens
    coin::deposit(to, coins);

    event::emit(StableCoinMinted {
      to,
      amount: 10000_00000000,
      timestamp: supra_framework::timestamp::now_seconds(),
    });
  }
}