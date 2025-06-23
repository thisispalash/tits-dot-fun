// Deviation Checker (Automation)
module tits_fun::tits_deviation {
  use tits_fun::pool_manager;
  use supra_framework::timestamp;
  
  // This would be called by Supra's automation service
  public entry fun check_deviation_threshold(
    admin: &signer,
    pool_id: u64
  ) {
    let deviation = pool_manager::get_pool_deviation(
      signer::address_of(admin), 
      pool_id
    );
    
    // 690 basis points = 6.9%
    if (deviation > 690) {
      pool_manager::lock_pool(
          admin,
          pool_id,
          b"Deviation threshold exceeded"
      );
    };
  }
}