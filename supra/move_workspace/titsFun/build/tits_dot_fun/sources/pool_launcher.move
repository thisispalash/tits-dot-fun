// Pool Launcher (Automation)
module tits_fun::pool_launcher {
  use std::signer;
  use tits_fun::pool_manager;
  use tits_fun::tits_deviation;
  use supra_framework::timestamp;
  
  // Main automation entry point - called every block
  public entry fun run_automation(
    admin: &signer,
  ) {
    // This calls the comprehensive check that handles all scenarios
    tits_deviation::check_pool_status(admin);
  }
  
  // Legacy function - can be removed or kept for manual launches
  public entry fun launch_scheduled_pool(
    admin: &signer,
  ) {
    let admin_addr = signer::address_of(admin);
    let (queued_start_time, queued_delay, queued_candle_size, queued_winner) = 
      pool_manager::get_queued_pool_info(admin_addr);
    
    let now = timestamp::now_seconds();
    if (queued_start_time > 0 && now >= queued_start_time) {
      let l_value = (24 * 60) / queued_candle_size;
      pool_manager::create_pool(admin, l_value, queued_delay);
      pool_manager::clear_queue(admin);
    };
  }
}