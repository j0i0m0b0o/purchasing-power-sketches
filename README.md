A useful primitive for cryptoeconomics would be a game that resolves into a purchasing power signal, so we try to build one.

## openHashSimple.sol

A game requester posts a fee to incentivize a purchasing power report. Anyone can report by posting a threshold, seed, and liquidity, which immediately starts the breaking game: anyone can try to break the reporter by finding a nonce that, combined with their address and the seed, hashes above the threshold. A reporter can also be replaced during the breaking game by posting a sufficiently lower threshold (governed by a replacement decay parameter), which returns the incumbent's liquidity and refreshes the settlement window.

If broken, the reporter loses their posted liquidity, the escalated fee is retained and the remainder goes to the breaker, then a new round begins with escalated fee and liquidity requirements with a fresh timer. If nobody breaks or replaces the reporter before the settlement window expires, the report stands and the reporter earns the fee plus their liquidity back. Escalation is capped at a configurable halt point. Any replacements reset the game timer.

## openHashClaim.sol

If the game size is so large that you cannot quickly source enough hash rate to break a reporter, you need longer settlement times (amount of time over which a report can be broken). These types of games can create a source of distortion in openHashSimple: breakers attempting to break a report don't know how many others are working on the same problem at the same time. A small probability of competition can push expected value negative when compute cost is a meaningful fraction of the prize. Rational breakers may refuse to attempt unless they're confident they're solo, which introduces systematic under-participation. Reporters anticipate this and post thresholds lower than the true compute-vs-ETH indifference point, because they know the effective break rate from honest breakers is dampened by uncertainty. The settled threshold ends up reflecting the hidden composition of the active miner population at game time, which is an extra source of variance that isn't measuring anything about ETH's purchasing power versus compute.

openHashClaim.sol adds an optional claim layer on top of the base game. A breaker stakes a wager equal to the next round's reward escalation delta to lock exclusive break access for the remainder of the current settlement window. While a claim is active, only the claimer can break, and replacement and settlement are blocked. If the claimer successfully breaks, the wager is returned as part of the break payout. If they fail to break before the window expires, anyone can call newRound: the reporter gets their liquidity back, the wager funds the escalation of the next round's reward, and a new round begins at the escalated level. At the escalation halt where there is nothing to escalate to, the wager routes to the protocol fee recipient instead. The race path from openHashSimple remains available when no claim is active.

Under the claim path the breaker's expected value improves because they know they have exclusive access.

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
- Manipulability is also in the context of how the signal is consumed

Overall, the purpose of this mechanism is not a perfect CPI oracle. We just want at least some tendril of reality, however messy, around which we can engineer.
