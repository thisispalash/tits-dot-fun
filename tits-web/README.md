# tits dot [dot] fun
> The web interface, no mobile

## Routes

<!-- on complete -> :ballot_box_with_check: -->
| Completed | Route | What it is |
| :---: | :---: | --- |
| :black_square_button: | [`/`](https://titsdot.fun/) | Landing Page |
| :black_square_button: | [`/g`](https://titsdot.fun/g) | Lander for all daily games |
| :black_square_button: | `/g/[network]` | Daily pool for `[network]` |
| :black_square_button: | `/g/network/[pool_id]` | Historic action in `[pool_id]` on `[network]` |
| :black_square_button: | [`/art`](https://titsdot.fun/art) | NFT sales |
| :black_square_button: | [`/secondary`](https://titsdot.fun/secondary) | Zora Coin trading |
| :black_square_button: | [`/mechanics`](https://titsdot.fun/mechanics) | Mechanics overview, ie, docs |
| :black_square_button: | [`/pitch`](https://titsdot.fun/pitch) | Pitch for the project, for investors and partners |

### Mobile
> _todo_

Mobile is tricky since every action within the game is an onchain action. One option is to disable 
all onchain games but leave the simulator open. Other "Web2" stuff can remain as well, but anything
onchain will likely be blocked.
