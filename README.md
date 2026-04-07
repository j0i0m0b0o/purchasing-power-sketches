A useful primitive for cryptoeconomics would be a game that resolves into a purchasing power signal, so we try to build one.

## openHashSimple.sol

A game requester posts a fee to incentivize a purchasing power report. Anyone can report by posting a threshold and liquidity, which immediately starts the breaking game: anyone can try to break the reporter by finding a nonce that, combined with their address, the gameId, and the parent block hash captured at report time, hashes above the threshold. A reporter can also be replaced during the breaking game by posting a sufficiently lower threshold (governed by a replacement decay parameter), which returns the incumbent's liquidity and refreshes the settlement window.

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
