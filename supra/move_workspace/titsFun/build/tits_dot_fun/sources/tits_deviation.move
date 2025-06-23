// Deviation Checker (Automation)
module tits_fun::tits_deviation {
  use std::signer;
  use tits_fun::pool_manager;
  use supra_framework::timestamp;
  
  // This is called after every trade/block
  public entry fun check_pool_status(
    admin: &signer,
  ) {
    let admin_addr = signer::address_of(admin);
    
    // Check if there's an active pool
    if (!pool_manager::has_active_pool(admin_addr)) {
      // No active pool - check if we should launch queued pool
      let (queued_start_time, queued_delay, queued_candle_size, queued_winner) = 
        pool_manager::get_queued_pool_info(admin_addr);
      
      let now = timestamp::now_seconds();
      if (queued_start_time > 0 && now >= queued_start_time) {
        // Launch the queued pool
        let l_value = (24 * 60) / queued_candle_size;
        pool_manager::create_pool(admin, l_value, queued_delay);
        
        // Clear the queue
        pool_manager::clear_queue(admin);
      };
      return
    };
    
    // There's an active pool - check its status
    let current_pool_id = pool_manager::get_current_active_pool_id(admin_addr);
    let (l_value, h_value, x_reserve, y_reserve, token_address, is_locked) = 
      pool_manager::get_pool_info(admin_addr, current_pool_id);
    
    if (is_locked) {
      return // Pool already locked
    };
    
    let now = timestamp::now_seconds();
    
    // Check if pool has expired (24h)
    let pool_start_time = pool_manager::get_pool_start_time(admin_addr, current_pool_id);
    if (now >= pool_start_time + 24 * 3600) {
      // Pool expired - determine winner and queue next pool
      let (winner, min_deviation) = pool_manager::determine_winner(admin, current_pool_id);
      let (winner_delay, winner_candle_size) = pool_manager::get_winner_proposal(admin_addr, current_pool_id);
      
      // Queue next pool with winner's parameters
      pool_manager::queue_next_pool(admin, winner, winner_delay, winner_candle_size, pool_start_time);
      
      // Mark pool as completed (remove from active pools)
      pool_manager::complete_pool(admin, current_pool_id);
      return
    };
    
    // Check deviation threshold
    let max_deviation = pool_manager::get_max_trader_deviation(admin_addr, current_pool_id);
    
    // 690 basis points = 6.9%
    if (max_deviation > 690) {
      // Lock pool and trigger VRF for random next pool parameters
      pool_manager::lock_pool(admin, current_pool_id, b"Deviation threshold exceeded");
      
      // Note: Next pool will be queued by VRF callback with random parameters
    };
  }
}