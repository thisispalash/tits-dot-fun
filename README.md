# tits dot [dot] fun
> Can you coordinate [read: collude] to draw curves on a chart?

See the [game mechanics](https://github.com/thisispalash/tits-dot-fun/discussions/2) overview.

<!-- 
## Vibe Code Max (easter egg)

Hey, so I am creating a game theoretic experiment on chain with the following mechanisms, I need to implement on Supra using Move and need help,

- There is a bonded curve, equation ~ y = 4*(H/L)*x(1-x/L), 0<=x<=L
- L \n { 96, 144, 288 }, ie, 15m candles, 10m, or 5m over 24h
- H_{i+1} = H_i + sqrt(L), H_0 = 1
- Trading is open and follows standard AMM, ie, x*y = (x+x') * y', out_tokens = y-y'
- x : Native SupraCoin, y : Pool Token, y_0 = 1000000_000000
- fees (per trade) = 2*gas_cost of txn
- deviation threshold = 6.9%
- deviation is calculated off-chain via the automation service, where (\sum (y-y') / y) / x <= threshold % 
- winner: has least deviation, in case of tie, most recent is winner
- each pool runs for 24h, or is locked (if crosses threshold).. In case of threshold crossing, all money in pool is sent to zero address (ie, burned)
- subsequent pools start 24h after current pool starting, plus any delays
- winner gets to decide next candle duration (hence L), and the delay in starting new pool
- if there is no winner, next candle duration is chosen at random and new pool is started by treasury with delay=0 
- finally, every trade comes in with four params ~ quantity, side, candle_size, delay (delay should be under 36h of current start_time, ie, max delay of 12h); if current trade is winner, store these values else discard

I am thinking I need the following modules (correct me if wrong),

- token_factory.move :: Creates a new token everyday
- pool_pair.move :: Actual token pair pool
- curve_launcher.move :: launches new pool
- tits_treasury.move :: the treasury contract that receives fees and starts new pools if needed
- math.move :: helps in performing sqrt and divisions

And the following automations,

- liquidator.move :: this one checks the threshold condition every block, and calls lock_pool() if invalidated
- launcher.move :: this one launches new pools when time is right -->