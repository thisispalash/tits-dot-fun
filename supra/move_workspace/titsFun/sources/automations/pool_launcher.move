// Pool Launcher (Automation)
module tits_fun::pool_launcher {
  use tits_fun::pool_manager;
  use tits_fun::game_state;
  use supra_framework::timestamp;
  
  // This would be called by Supra's automation service
  public entry fun launch_scheduled_pool(admin: &signer) {
    let candle_size = game_state::get_next_candle_size(signer::address_of(admin));
    let delay = game_state::get_next_delay(signer::address_of(admin));
    
    pool_manager::create_pool(admin, candle_size, delay);
  }
}