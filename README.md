A useful primitive for cryptoeconomics would be a game that resolves into a purchasing power signal, so we try to build one.

## openHashSimple.sol

A game requester posts a fee to incentivize a purchasing power report. Anyone can report by posting a threshold, seed, and liquidity, which immediately starts the breaking game: anyone can try to break the reporter by finding a nonce that, combined with their address and the seed, hashes above the threshold. A reporter can also be replaced during the breaking game by posting a sufficiently lower threshold (governed by a replacement decay parameter), which returns the incumbent's liquidity and refreshes the settlement window.

If broken, the reporter loses their posted liquidity, the escalated fee is retained and the remainder goes to the breaker, then a new round begins with escalated fee and liquidity requirements with a fresh timer. If nobody breaks or replaces the reporter before the settlement window expires, the report stands and the reporter earns the fee plus their liquidity back. Escalation is capped at a configurable halt point. Any replacements reset the game timer.

## openHashSketch.sol

A game requester posts a fee to incentivize a purchasing power report. In the first phase, reporters compete during a selection window by committing to hash thresholds. Lower thresholds win, meaning the reporter accepts being easier to challenge. The winning reporter reveals a seed, which starts the breaking game: anyone can try to break the reporter by finding a nonce that, combined with their address and the seed, hashes above the threshold.

If broken, the reporter loses their posted liquidity, the escalated fee is retained and the remainder goes to the breaker, then a new selection round begins with escalated fee and liquidity requirements. If the reporter never reveals their seed, anyone can trigger escalation, and the reporter gets back their liquidity minus the escalated fee, which funds the next larger selection round. Alternatively, a reporter can be replaced during the breaking game by posting a sufficiently lower threshold along with a premium payment to the incumbent, which refreshes the settlement window. If nobody breaks or replaces the reporter before the settlement window expires, the report stands and the reporter earns the fee plus their liquidity back. Escalation is capped at a configurable halt point.

## Signal

Comparing the winning threshold across sequential games normalized by final round size gives a signal about how ETH's purchasing power changed over the interval, measured against computational cost. If the winning threshold rises from one game to the next, that suggests market participants were willing to burn more real world compute to win the staked ETH, implying stronger ETH purchasing power versus compute. If it falls, that suggests weaker purchasing power.

This does not measure purchasing power in a universal sense. Computational cost is at least anchored to physical reality, which may make it more stable than measuring against another token.

## Open Questions / Comments

- How to consume the signal?
- How do censorship / block producer games factor in? Tightly coupled to how the signal is consumed.
- Does griefing completely kill honest tight reporting incentives / result in an equilibrium honest threshold that is manipulable? Is there a better way to do the forced succession in this context?
- On the other hand, nobody can know if they were griefed or someone just got lucky without enough statistical evidence
- Manipulability is also in the context of how the signal is consumed

Overall, the purpose of this mechanism is not a perfect CPI oracle. We just want at least some tendril of reality, however messy, around which we can engineer.
