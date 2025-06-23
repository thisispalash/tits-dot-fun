// =============================================================================
// GAME STATE MODULE
// =============================================================================
module your_addr::game_state {
  use std::vector;
  use std::signer;
  use supra_framework::timestamp;
  
  struct GameConfig has key {
    candle_sizes: vector<u64>, // [96, 144, 288]
    deviation_threshold: u128, // 690 basis points (6.9%)
    max_delay: u64, // 36 hours in seconds
    pool_duration: u64, // 24 hours in seconds
  }
  
  struct WinnerData has store {
    addr: address,
    pool_id: u64,
    deviation: u128,
    timestamp: u64,
    next_candle_size: u64,
    next_delay: u64,
  }
  
  struct GameState has key {
    current_pool_id: u64,
    winners: vector<WinnerData>,
    next_candle_size: u64,
    next_pool_delay: u64,
    treasury: address,
  }
  
  fun init_module(admin: &signer) {
    let candle_sizes = vector::empty<u64>();
    vector::push_back(&mut candle_sizes, 96);
    vector::push_back(&mut candle_sizes, 144);
    vector::push_back(&mut candle_sizes, 288);
    
    move_to(admin, GameConfig {
      candle_sizes,
      deviation_threshold: 690, // 6.9% in basis points
      max_delay: 36 * 3600, // 36 hours
      pool_duration: 24 * 3600, // 24 hours
    });
    
    move_to(admin, GameState {
      current_pool_id: 0,
      winners: vector::empty<WinnerData>(),
      next_candle_size: 96, // Default to 15m candles
      next_pool_delay: 0,
      treasury: signer::address_of(admin),
    });
  }
  
  public fun record_winner(
    admin: &signer,
    winner: address,
    pool_id: u64,
    deviation: u128,
    next_candle_size: u64,
    next_delay: u64
  ) acquires GameState {
    let state = borrow_global_mut<GameState>(signer::address_of(admin));
    
    let winner_data = WinnerData {
      addr: winner,
      pool_id,
      deviation,
      timestamp: timestamp::now_seconds(),
      next_candle_size,
      next_delay,
    };
    
    vector::push_back(&mut state.winners, winner_data);
    state.next_candle_size = next_candle_size;
    state.next_pool_delay = next_delay;
  }
  
  #[view]
  public fun get_next_candle_size(admin: address): u64 acquires GameState {
    borrow_global<GameState>(admin).next_candle_size
  }
  
  #[view]
  public fun get_next_delay(admin: address): u64 acquires GameState {
    borrow_global<GameState>(admin).next_pool_delay
  }
}