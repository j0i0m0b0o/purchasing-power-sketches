// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// a useful primitive for cryptoeconomics would be a game that resolves into a purchasing power signal, so we try to build one:

/*  A game requester posts a fee to incentivize a purchasing power report. Anyone can report by posting a threshold, seed, and liquidity,
  which immediately starts the breaking game: anyone can try to break the reporter by finding a nonce that, combined with their address
  and the seed, hashes above the threshold. A reporter can also be replaced during the breaking game by posting a sufficiently lower
  threshold (governed by a replacement decay parameter), which returns the incumbent's liquidity and refreshes the settlement window.

  If broken, the reporter loses their posted liquidity, the escalated fee is retained and the remainder goes to the breaker, then a new
  round begins with escalated fee and liquidity requirements. If nobody breaks or replaces the reporter before the settlement window
  expires, the report stands and the reporter earns the fee plus their liquidity back. Escalation is capped at a configurable halt point.

  Comparing the winning threshold across sequential games gives a signal about how ETH's purchasing power changed over the interval, measured against computational cost. If the winning threshold rises from one game to the next,
  that suggests market participants were willing to burn more real world compute to win the staked ETH, implying stronger ETH purchasing power versus compute. If it falls, that suggests weaker purchasing power.

  This does not measure purchasing power in a universal sense. Computational cost is at least anchored to physical reality, which may make it more stable than measuring against another token.
*/

// There are open questions and comments, including but not limited to:
//- How to consume the signal?
//- How do censorship / block producer games factor in? Tightly coupled to how the signal is consumed.
//- Does griefing completely kill honest tight reporting incentives / result in an equilibrium honest threshold that is manipulable? Is there a better way to do the forced succession in this context?
//- On the other hand, nobody can know if they were griefed or someone just got lucky without enough statistical evidence
//- Manipulability is also in the context of how the signal is consumed
//  Overall, the purpose of this mechanism is not a perfect CPI oracle. We just want at least some tendril of reality, however messy, around which we can engineer.

contract openHash2 {

    uint256 public nextGameId = 1;

    error InvalidInput(string);

    mapping (uint256 => HashGame) hashGame;
    mapping (address => uint256) tempHolding;

    struct HashGame {
        address protocolFeeRecipient;
        uint96 fee;
        uint96 initialLiquidity;
        uint96 currentLiquidity;
        uint24 protocolFee;
        uint16 multiplier;
        uint96 escalationHalt;
        uint24 replacementDecay;

        address breakGameReporter;
        bytes32 breakGameThreshold;
        bytes32 breakGameSeed;
        bool timeType;
        bool breakingGameActive;
        bool finished;

        uint256 settlementTime;
        uint256 reportTimestamp;

        uint256 breakGameBalance;
    }

    struct GameParams {
        address protocolFeeRecipient;
        uint96 fee;
        uint96 initialLiquidity;
        uint24 protocolFee;
        uint16 multiplier;
        uint96 escalationHalt;
        uint24 replacementDecay;
        bool timeType;
        uint256 settlementTime;
    }

    function requestGame(GameParams memory gameParams) payable external {
        if (msg.value != gameParams.fee) revert InvalidInput("msg.value");
        if (gameParams.multiplier <= 100) revert InvalidInput("multiplier must exceed 100");
        if (gameParams.escalationHalt <= gameParams.initialLiquidity) revert InvalidInput("escalation halt must exceed initial liquidity");
        if (gameParams.initialLiquidity < gameParams.fee * gameParams.multiplier / 100) revert InvalidInput("liquidity must cover escalated fee");
        uint256 gameId = nextGameId++;
        HashGame storage h = hashGame[gameId];

        h.protocolFeeRecipient = gameParams.protocolFeeRecipient;
        h.fee = gameParams.fee;
        h.initialLiquidity = gameParams.initialLiquidity;
        h.protocolFee = gameParams.protocolFee;
        h.multiplier = gameParams.multiplier;
        h.escalationHalt = gameParams.escalationHalt;
        h.timeType = gameParams.timeType;
        h.currentLiquidity = gameParams.initialLiquidity;
        h.settlementTime = gameParams.settlementTime;
        h.replacementDecay = gameParams.replacementDecay;
    }

    function report(uint256 gameId, bytes32 threshold, bytes32 seed) payable external {
        HashGame storage h = hashGame[gameId];
        if (h.breakingGameActive) revert InvalidInput("breaking game active");
        if (h.finished) revert InvalidInput("finished");
        if (msg.value != h.currentLiquidity) revert InvalidInput("msg.value wrong");

        uint256 currentTime = h.timeType ? block.timestamp : block.number;

        h.breakingGameActive = true;
        h.breakGameSeed = seed;
        h.breakGameReporter = msg.sender;
        h.breakGameThreshold = threshold;
        h.breakGameBalance = msg.value;
        h.reportTimestamp = currentTime;
    }

    function breakReporter(uint256 gameId, uint256 nonce) external {
        HashGame storage h = hashGame[gameId];
        if (!h.breakingGameActive) revert InvalidInput("not active");
        if (h.finished) revert InvalidInput("finished");

        uint256 currentTime = h.timeType ? block.timestamp : block.number;
        if (currentTime > h.settlementTime + h.reportTimestamp) revert InvalidInput("break time over");

        bytes32 hash = keccak256(abi.encode(nonce, msg.sender, h.breakGameSeed));

        if (uint256(hash) > uint256(h.breakGameThreshold)) {
            if (h.initialLiquidity == h.currentLiquidity) {
                _sendEth(payable(h.protocolFeeRecipient), h.fee);
            }
            uint96 nextLiquidity = h.currentLiquidity * h.multiplier / 100;
            if (nextLiquidity > h.escalationHalt) {
                h.fee = h.fee * h.escalationHalt / h.currentLiquidity;
                h.currentLiquidity = h.escalationHalt;
            } else {
                h.fee = h.multiplier * h.fee / 100;
                h.currentLiquidity = nextLiquidity;
            }
            uint256 remainder = h.breakGameBalance - h.fee;
            _sendEth(payable(msg.sender), remainder);

            h.breakingGameActive = false;

            h.breakGameReporter = address(0);
            h.breakGameThreshold = bytes32(0);
            h.breakGameSeed = bytes32(0);
            h.breakGameBalance = 0;
            h.reportTimestamp = 0;
        } else {
            revert InvalidInput("hash below threshold");
        }
    }

    function replaceReporter(uint256 gameId, bytes32 threshold, bytes32 seed) external payable {
        HashGame storage h = hashGame[gameId];
        if (!h.breakingGameActive) revert InvalidInput("not active");
        if (h.finished) revert InvalidInput("finished");

        uint256 currentTime = h.timeType ? block.timestamp : block.number;
        if (currentTime > h.settlementTime + h.reportTimestamp) revert InvalidInput("break time over");

        if (uint256(threshold) >= h.replacementDecay * uint256(h.breakGameThreshold) / 10000) revert InvalidInput("minimum replacement increment");
        if (msg.value != h.currentLiquidity) revert InvalidInput("msg.value wrong");

        _sendEth(payable(h.breakGameReporter), h.breakGameBalance);

        h.reportTimestamp = currentTime;
        h.breakGameReporter = msg.sender;
        h.breakGameThreshold = threshold;
        h.breakGameSeed = seed;
        h.breakGameBalance = msg.value;
    }

    function settle(uint256 gameId) external {
        HashGame storage h = hashGame[gameId];
        if (!h.breakingGameActive) revert InvalidInput("not active");
        if (h.finished) revert InvalidInput("finished");
        uint256 currentTime = h.timeType ? block.timestamp : block.number;
        if (currentTime <= h.settlementTime + h.reportTimestamp) revert InvalidInput("settlement time not reached");

        _sendEth(payable(h.breakGameReporter), h.currentLiquidity + h.fee);
        h.finished = true;
        h.breakingGameActive = false;
    }

    /**
     * @dev Internal function to send ETH to a recipient
     */
    function _sendEth(address payable recipient, uint256 amount) internal {
        if (amount == 0) return;

        (bool success,) = recipient.call{value: amount, gas: 40000}("");
        if (!success) {
            tempHolding[recipient] += amount;
        }
    }

    function getTempHolding() external {
        uint256 amount = tempHolding[msg.sender];
        if (amount == 0) revert InvalidInput("no balance");
        tempHolding[msg.sender] = 0;
        (bool success,) = payable(msg.sender).call{value: amount}("");
        if (!success) revert InvalidInput("transfer failed");
    }

}
