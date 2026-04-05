// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

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
        if (gameParams.replacementDecay >= 10000) revert InvalidInput("replacement decay must be below 10000");
        if (gameParams.initialLiquidity < gameParams.fee * (gameParams.multiplier - 100) / 100) revert InvalidInput("liquidity must cover fee delta");
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
        if (gameId == 0 || gameId >= nextGameId) revert InvalidInput("game does not exist");
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
            uint96 oldFee = h.fee;
            uint96 nextLiquidity = h.currentLiquidity * h.multiplier / 100;
            if (nextLiquidity > h.escalationHalt) {
                h.fee = h.fee * h.escalationHalt / h.currentLiquidity;
                h.currentLiquidity = h.escalationHalt;
            } else {
                h.fee = h.multiplier * h.fee / 100;
                h.currentLiquidity = nextLiquidity;
            }
            uint256 remainder = h.breakGameBalance - (h.fee - oldFee);

            h.breakingGameActive = false;
            h.breakGameReporter = address(0);
            h.breakGameThreshold = bytes32(0);
            h.breakGameSeed = bytes32(0);
            h.breakGameBalance = 0;
            h.reportTimestamp = 0;

            _sendEth(payable(msg.sender), remainder);
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

        address payable previousReporter = payable(h.breakGameReporter);
        uint256 previousBalance = h.breakGameBalance;

        h.reportTimestamp = currentTime;
        h.breakGameReporter = msg.sender;
        h.breakGameThreshold = threshold;
        h.breakGameSeed = seed;
        h.breakGameBalance = msg.value;

        _sendEth(previousReporter, previousBalance);
    }

    function settle(uint256 gameId) external {
        HashGame storage h = hashGame[gameId];
        if (!h.breakingGameActive) revert InvalidInput("not active");
        if (h.finished) revert InvalidInput("finished");
        uint256 currentTime = h.timeType ? block.timestamp : block.number;
        if (currentTime <= h.settlementTime + h.reportTimestamp) revert InvalidInput("settlement time not reached");

        address payable reporter = payable(h.breakGameReporter);
        uint256 payout = h.currentLiquidity + h.fee;
        h.finished = true;
        h.breakingGameActive = false;
        _sendEth(reporter, payout);
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
