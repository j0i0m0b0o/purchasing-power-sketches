// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// many things not complete in this contract. there are also likely bugs. just a skeleton of an idea. it also might not work.

// a useful primitive for cryptoeconomics would be a game that resolves into a purchasing power signal, so we try to build one.
//
// There are open questions and comments, including but not limited to:
//- How to consume the signal? 
//- How do censorship / block producer games factor in? Tightly coupled to how the signal is consumed.
//- Does griefing completely kill honest tight reporting incentives / result in an equilibrium honest threshold that is manipulable? Is there a better way to do the forced succession in this context?
//- On the other hand, nobody can know if they were griefed or someone just got lucky without enough statistical evidence
//- Manipulability is also in the context of how the signal is consumed
//  Overall, the purpose of this mechanism is not a perfect CPI oracle. We just want at least some tendril of reality, however messy, around which we can engineer.

contract openHash {

    uint256 public nextGameId = 1;

    error InvalidInput(string);

    mapping (uint256 => HashGame) hashGame;
    mapping (address => uint256) tempHolding;

    struct HashGame {
        address protocolFeeRecipient; // earns the protocolFee
        uint96 fee; // winning reporter earns this
        uint96 initialLiquidity; // reporters must post this amount in the first round
        uint96 currentLiquidity; // reporters must post this in the current round
        uint24 protocolFee; // this is taken out of liquidity on each break
        uint16 multiplier; // how much the game grows each round if a report is broken or a seed isnt revealed. at 1.5x multiplier, fee * 1.5 is taken out of the liquidity
        uint96 escalationHalt; // game stops growing each round 
        uint24 replacementDecay;
        uint16 replacementPayoutFraction;

        address breakGameReporter;
        bytes32 breakGameThreshold;
        bytes32 breakGameSeed;
        address selectionReporter;
        bytes32 selectionThreshold;
        bool timeType;
        bool initialReporterSelectionActive;
        bool breakingGameActive;
        bool finished;

        uint256 settlementTime;
        uint256 reportTimestamp;

        uint256 selectionTime;
        uint256 seedRevealTime;

        uint256 selectionWindow;
        uint256 seedRevealWindow;

        uint256 selectionBalance;
        uint256 breakGameBalance;

    }

    struct GameParams {
        address protocolFeeRecipient;
        uint96 fee;
        uint96 initialLiquidity;
        uint24 protocolFee;
        uint16 multiplier;
        uint96 escalationHalt;
        bool timeType;
        uint256 selectionTime;
        uint256 seedRevealTime;
        uint24 replacementDecay;
        uint16 replacementPayoutFraction;
        uint256 settlementTime;
    }

    function requestGame(GameParams memory gameParams) payable external {
        if (msg.value != gameParams.fee) revert InvalidInput("msg.value");
        if (gameParams.multiplier <= 100) revert InvalidInput("multiplier must exceed 100");
        if (gameParams.initialLiquidity < gameParams.fee * gameParams.multiplier / 100) revert InvalidInput("liquidity must cover escalated fee");
        uint256 gameId = nextGameId++;
        HashGame storage h = hashGame[gameId];

        h.protocolFeeRecipient = gameParams.protocolFeeRecipient;
        h.fee = gameParams.fee;
        h.initialLiquidity = gameParams.initialLiquidity;
        h.protocolFee = gameParams.protocolFee;
        h.multiplier = gameParams.multiplier;
        h.escalationHalt = gameParams.escalationHalt;
        h.initialReporterSelectionActive = true;
        h.timeType = gameParams.timeType;
        h.currentLiquidity = gameParams.initialLiquidity;

        h.selectionWindow = gameParams.selectionTime;
        h.seedRevealWindow = gameParams.seedRevealTime;
        h.settlementTime = gameParams.settlementTime;

        h.replacementDecay = gameParams.replacementDecay;
        h.replacementPayoutFraction = gameParams.replacementPayoutFraction;
    }

    function participateInSelection(uint256 gameId, bytes32 threshold) payable external {
        HashGame storage h = hashGame[gameId];
        if (!h.initialReporterSelectionActive) revert InvalidInput("selection not active");
        if (h.finished) revert InvalidInput("finished");
        if (h.breakingGameActive) revert InvalidInput("breaking game active");

        if (msg.value != h.currentLiquidity) revert InvalidInput("msg.value wrong");
        if (h.selectionReporter != address(0) && uint256(threshold) >= uint256(h.selectionThreshold)) revert InvalidInput("doesn't replace");

        uint256 currentTime = h.timeType ? block.timestamp : block.number;
        if (h.selectionTime != 0 && currentTime > h.selectionTime) revert InvalidInput("selection time over");

        if (h.selectionReporter != address(0)) {
            _sendEth(payable(h.selectionReporter), h.selectionBalance);
        }

        h.selectionBalance = msg.value;
        h.selectionThreshold = threshold;
        h.selectionReporter = msg.sender;
        
        if (h.selectionTime == 0) {
        h.selectionTime = h.selectionWindow + currentTime;
        h.seedRevealTime = h.seedRevealWindow + h.selectionTime;
        }

    }

    function provideSeed(bytes32 seed, uint256 gameId) external {
        HashGame storage h = hashGame[gameId];
        if (msg.sender != h.selectionReporter) revert InvalidInput("not the reporter");
        if (h.breakGameSeed != bytes32(0)) revert InvalidInput("seed already provided");
        if (h.seedRevealTime < (h.timeType ? block.timestamp : block.number)) revert InvalidInput("seed reveal time over");

        uint256 currentTime = h.timeType ? block.timestamp : block.number;
        if (currentTime < h.selectionTime) revert InvalidInput("seed reveal too early");
        if (!h.initialReporterSelectionActive) revert InvalidInput("selection not active");
        if (h.breakingGameActive) revert InvalidInput("breaking game active");
        if (h.finished) revert InvalidInput("finished");

        h.initialReporterSelectionActive = false;
        h.breakingGameActive = true;
        h.breakGameSeed = seed;
        h.breakGameReporter = msg.sender;
        h.breakGameThreshold = h.selectionThreshold;
        h.breakGameBalance = h.selectionBalance;
        h.selectionBalance = 0;
        h.selectionReporter = address(0);
        h.selectionThreshold = bytes32(0);
        h.reportTimestamp = currentTime;
        h.selectionTime = 0;
        h.seedRevealTime = 0;
    }

    // some incentive to do this perhaps?
    function seedNotProvided(uint256 gameId) external {
        HashGame storage h = hashGame[gameId];
        if (h.breakingGameActive) revert InvalidInput("breaking game active");
        if (!h.initialReporterSelectionActive) revert InvalidInput("selection not active");
        if (h.finished) revert InvalidInput("finished");
        if (h.selectionReporter == address(0)) revert InvalidInput("no selection reporter");

        if (h.initialReporterSelectionActive && h.seedRevealTime < (h.timeType ? block.timestamp : block.number)) {
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

            //obviously need to prevent underflow in the game creation revert checks
            uint256 remainder = h.selectionBalance - h.fee;
            _sendEth(payable(h.selectionReporter), remainder);

            h.selectionTime = 0;
            h.seedRevealTime = 0;

            //zero out everything else
            h.selectionReporter = address(0);
            h.selectionThreshold = bytes32(0);
            h.selectionBalance = 0;
        } else {
            revert InvalidInput("ineligible");
        }
    }

    function breakReporter(uint256 gameId, uint256 nonce) external {
        HashGame storage h = hashGame[gameId];
        if (!h.breakingGameActive) revert InvalidInput("not active");
        if (h.finished) revert InvalidInput("finished");
        if (h.initialReporterSelectionActive) revert InvalidInput("selection active");

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
            //need underflow protection in game creation
            uint256 remainder = h.breakGameBalance - h.fee;
            _sendEth(payable(msg.sender), remainder);

            h.breakingGameActive = false;
            h.initialReporterSelectionActive = true;

            //zero out everything else
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

        uint256 transferReq = h.currentLiquidity + h.currentLiquidity * h.replacementPayoutFraction / 10000;
        if (msg.value != transferReq) revert InvalidInput("didnt transfer enough");

        _sendEth(payable(h.breakGameReporter), msg.value);

        h.reportTimestamp = currentTime;
        h.breakGameReporter = msg.sender;
        h.breakGameThreshold = threshold;
        h.breakGameSeed = seed;
    }

    function settle(uint256 gameId) external {
        HashGame storage h = hashGame[gameId];
        if (!h.breakingGameActive) revert InvalidInput("not active");
        if (h.finished) revert InvalidInput("finished");
        if (h.initialReporterSelectionActive) revert InvalidInput("selection active");
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
        if (amount == 0) return; // Gas optimization: skip zero transfers

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
