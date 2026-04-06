A useful primitive for cryptoeconomics would be a game that resolves into a purchasing power signal, so we try to build one.

## openHashSimple.sol

A game requester posts a fee to incentivize a purchasing power report. Anyone can report by posting a threshold and liquidity, which immediately starts the breaking game: anyone can try to break the reporter by finding a nonce that, combined with their address, the gameId, and the parent block hash captured at report time, hashes above the threshold. A reporter can also be replaced during the breaking game by posting a sufficiently lower threshold (governed by a replacement decay parameter), which returns the incumbent's liquidity and refreshes the settlement window.

### Why no seed, and why the block hash is frozen across replacements

The natural looking design would let each reporter (initial and replacement) commit a fresh seed that goes into the break hash. That breaks incentive compatibility: a reporter watching the mempool can front run an incoming break by calling replaceReporter themselves, which rotates the seed and invalidates the in-flight breaker's nonce. The dodge is cheap and the breaker's work is wasted.

Instead, there is no seed at all. The break hash is `keccak(nonce, breaker, gameId, blockHash)`, where `blockHash` is the parent hash captured once at the initial report and intentionally not refreshed on replacement. Domain separation across games comes from gameId, across rounds from blockHash, across breakers from the sender. With the blockHash frozen, any honest pending break stays valid against the replacement reporter's (necessarily lower) threshold, so self-replace front running can't dodge it. The reporter loses no useful entropy by not picking a seed. As long as a nonce finding a hash solution wasn't already calculated before and can be re-used, the work still has to be done by a breaker.

If broken, the reporter loses their posted liquidity, the escalated fee is retained and the remainder goes to the breaker, then a new round begins with escalated fee and liquidity requirements with a fresh timer. If nobody breaks or replaces the reporter before the settlement window expires, the report stands and the reporter earns the fee plus their liquidity back. Escalation is capped at a configurable halt point. Any replacements reset the game timer.

## Signal

Comparing the winning threshold across sequential games normalized by final round size gives a signal about how ETH's purchasing power changed over the interval, measured against computational cost. If the winning threshold rises from one game to the next, that suggests market participants were willing to burn more real world compute to win the staked ETH, implying stronger ETH purchasing power versus compute. If it falls, that suggests weaker purchasing power.

This does not measure purchasing power in a universal sense. Computational cost is at least anchored to physical reality, which may make it more stable than measuring against another token.

The key thing to understand is this game is weird, and distorted. But the distortions and weirdness are scale-invariant. When nearly all the rest of crypto mechanism design breaks down under the weight of its own incentives at scale, scale-invariant weirdness is a very nice property.

The question then is: can any mechanism produce a purchasing power signal better than this one at scale? If so, then show it. If a better mechanism cannot be found, then this is what the universe gives us given the irreducible geometry of the problem, and we have to engineer around the weirdness.

## Open Questions / Comments
- How to consume the signal?
- How do censorship / block producer games factor in? Tightly coupled to how the signal is consumed.
- Does griefing completely kill honest tight reporting incentives / result in an equilibrium honest threshold that is manipulable? Is there a better way to do the forced succession in this context?
- On the other hand, nobody can know if they were griefed or someone just got lucky without enough statistical evidence
- Manipulability is measured in the context of how the signal is consumed

Overall, the purpose of this mechanism is not a perfect CPI oracle. We just want at least some tendril of reality, however messy, around which we can engineer.
