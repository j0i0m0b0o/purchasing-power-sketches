// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title openHash
 * @notice A trust-minimized hash price oracle. It is a minimal reality-coupled game where the weirdness and distortions are ~ scale-invariant unlike many other oracle designs.
 * @dev This contract enables hash price discovery through economic incentives.
 *      Intended use is to compare the final surviving threshold, normalized by liquidity, across two games with otherwise equivalent GameParams.
 *      Participants are responsible for validating game instance parameters before participation
 *      and unsafe parameter sets including but not limited to settlementTime too high
 *      will result in lost funds.
 * @author OpenOracle Team
 * @custom:version 0.1
 */
contract openHashClaim {

    uint256 public nextGameId = 1;

    error InvalidInput(string);

    mapping (uint256 => HashGame) public hashGame;
    mapping (address => uint256) public tempHolding;

    struct HashGame {
        bytes32 threshold;
        bytes32 seed;
        bytes32 blockHash;

        address protocolFeeRecipient;
        uint96 reward;
        address reporter;
        uint96 initialLiquidity;

        uint96 liquidity;
        uint96 escalationHalt;
        uint24 protocolFee;
        uint24 replacementDecay;
        uint16 multiplier;
        bool timeType;
        bool active;
        bool finished;

        address claimer;
        uint48 settlementTime;
        uint48 reportTimestamp;
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
        uint48 settlementTime;
    }

    event GameCreated(uint256 indexed gameId, address indexed requester, GameParams gameParams);
    event InitialReport(uint256 indexed gameId, address indexed reporter, bytes32 threshold, bytes32 seed);
    event Claimed(uint256 indexed gameId, address indexed claimer, uint96 wager);
    event ReportBroken(uint256 indexed gameId, address indexed breaker, uint96 newLiquidity, uint96 newReward);
    event ReportReplaced(uint256 indexed gameId, address indexed newReporter, address indexed previousReporter, bytes32 threshold, bytes32 seed);
    event NewRound(uint256 indexed gameId, address indexed previousReporter, uint96 newLiquidity, uint96 newReward);
    event ReportSettled(uint256 indexed gameId, address indexed reporter, uint96 liquidity, bytes32 threshold);

    function requestGame(GameParams memory gameParams) payable external {
        if (msg.value != gameParams.fee) revert InvalidInput("msg.value");
        if (gameParams.multiplier <= 100) revert InvalidInput("multiplier must exceed 100");
        if (gameParams.escalationHalt <= gameParams.initialLiquidity) revert InvalidInput("escalation halt must exceed initial liquidity");
        if (gameParams.replacementDecay >= 10000) revert InvalidInput("replacement decay must be below 10000");
        if (gameParams.initialLiquidity < gameParams.fee * (gameParams.multiplier - 100) / 100) revert InvalidInput("liquidity must cover fee delta");
        if (gameParams.protocolFee > 1e7) revert InvalidInput("protocol fee too high");
        if (uint256(gameParams.escalationHalt) * gameParams.multiplier / 100 > type(uint96).max) revert InvalidInput("liquidity would overflow");
        if ((uint256(gameParams.fee) * gameParams.escalationHalt / gameParams.initialLiquidity) * gameParams.multiplier / 100 > type(uint96).max) revert InvalidInput("reward would overflow");

        uint256 gameId = nextGameId++;
        HashGame storage h = hashGame[gameId];

        h.protocolFeeRecipient = gameParams.protocolFeeRecipient;
        h.reward = gameParams.fee;
        h.initialLiquidity = gameParams.initialLiquidity;
        h.liquidity = gameParams.initialLiquidity;
        h.protocolFee = gameParams.protocolFee;
        h.multiplier = gameParams.multiplier;
        h.escalationHalt = gameParams.escalationHalt;
        h.timeType = gameParams.timeType;
        h.settlementTime = gameParams.settlementTime;
        h.replacementDecay = gameParams.replacementDecay;

        emit GameCreated(gameId, msg.sender, gameParams);
    }

    function report(uint256 gameId, bytes32 threshold, bytes32 seed) payable external {
        HashGame storage h = hashGame[gameId];
        if (gameId == 0 || gameId >= nextGameId) revert InvalidInput("game does not exist");
        if (h.active) revert InvalidInput("breaking game active");
        if (h.finished) revert InvalidInput("finished");
        if (msg.value != h.liquidity) revert InvalidInput("msg.value wrong");

        uint256 currentTime = h.timeType ? block.timestamp : block.number;

        h.active = true;
        h.seed = seed;
        h.reporter = msg.sender;
        h.threshold = threshold;
        h.reportTimestamp = uint48(currentTime);
        h.blockHash = blockhash(block.number - 1);

        emit InitialReport(gameId, msg.sender, threshold, seed);
    }

    function claim(uint256 gameId) external payable {
        HashGame storage h = hashGame[gameId];
        if (!h.active) revert InvalidInput("not active");
        if (h.finished) revert InvalidInput("finished");
        if (h.claimer != address(0)) revert InvalidInput("claimed");

        uint256 currentTime = h.timeType ? block.timestamp : block.number;
        if (currentTime > h.settlementTime + h.reportTimestamp) revert InvalidInput("break time over");

        uint96 wager = uint96(uint256(h.reward) * (h.multiplier - 100) / 100);
        if (msg.value != wager) revert InvalidInput("wrong wager");

        h.claimer = msg.sender;

        emit Claimed(gameId, msg.sender, wager);
    }

    function disproveClaim(uint256 gameId) external {
        HashGame storage h = hashGame[gameId];
        if (!h.active) revert InvalidInput("not active");
        if (h.finished) revert InvalidInput("finished");
        if (h.claimer == address(0)) revert InvalidInput("not claimed");

        uint256 currentTime = h.timeType ? block.timestamp : block.number;
        if (currentTime <= h.settlementTime + h.reportTimestamp) revert InvalidInput("claim time not over");

        address payable previousReporter = payable(h.reporter);
        uint256 previousBalance = h.liquidity;
        uint256 oldReward = h.reward;
        uint96 wager = uint96(uint256(oldReward) * (h.multiplier - 100) / 100);
        uint96 nextLiquidity = uint96(uint256(h.liquidity) * h.multiplier / 100);

        if (nextLiquidity > h.escalationHalt) {
            h.reward = uint96(uint256(h.reward) * h.escalationHalt / h.liquidity);
            h.liquidity = h.escalationHalt;
        } else {
            h.reward = uint96(uint256(h.reward) * h.multiplier / 100);
            h.liquidity = nextLiquidity;
        }

        uint256 actualFeeDelta = h.reward - oldReward;
        uint256 protocolExcess = wager - actualFeeDelta;

        h.active = false;
        h.reporter = address(0);
        h.threshold = bytes32(0);
        h.seed = bytes32(0);
        h.reportTimestamp = 0;
        h.blockHash = bytes32(0);
        h.claimer = address(0);

        if (protocolExcess > 0) tempHolding[h.protocolFeeRecipient] += protocolExcess;

        _sendEth(previousReporter, previousBalance);

        emit NewRound(gameId, previousReporter, h.liquidity, h.reward);
    }

    function breakReporter(uint256 gameId, uint256 nonce) external {
        HashGame storage h = hashGame[gameId];
        if (!h.active) revert InvalidInput("not active");
        if (h.finished) revert InvalidInput("finished");
        if (h.claimer != address(0) && h.claimer != msg.sender) revert InvalidInput("not claimer");

        uint256 currentTime = h.timeType ? block.timestamp : block.number;
        if (currentTime > h.settlementTime + h.reportTimestamp) revert InvalidInput("break time over");

        bytes32 hash = keccak256(abi.encode(nonce, msg.sender, h.seed, h.blockHash));

        if (uint256(hash) > uint256(h.threshold)) {
            uint96 oldReward = h.reward;
            uint96 nextLiquidity = uint96(uint256(h.liquidity) * h.multiplier / 100);
            uint96 currentLiquidity = h.liquidity;
            if (nextLiquidity > h.escalationHalt) {
                h.reward = uint96(uint256(h.reward) * h.escalationHalt / h.liquidity);
                h.liquidity = h.escalationHalt;
            } else {
                h.reward = uint96(uint256(h.reward) * h.multiplier / 100);
                h.liquidity = nextLiquidity;
            }
            uint256 remainder = currentLiquidity - (h.reward - oldReward);
            uint256 protocolFee = h.protocolFee * remainder / 1e7;
            remainder = remainder - protocolFee;

            if (h.claimer == msg.sender) remainder += uint256(oldReward) * (h.multiplier - 100) / 100;

            h.active = false;
            h.reporter = address(0);
            h.threshold = bytes32(0);
            h.seed = bytes32(0);
            h.reportTimestamp = 0;
            h.blockHash = bytes32(0);
            h.claimer = address(0);

            tempHolding[h.protocolFeeRecipient] += protocolFee;
            _sendEth(payable(msg.sender), remainder);

            emit ReportBroken(gameId, msg.sender, h.liquidity, h.reward);
        } else {
            revert InvalidInput("hash below threshold");
        }
    }

    function replaceReporter(uint256 gameId, bytes32 threshold, bytes32 seed) external payable {
        HashGame storage h = hashGame[gameId];
        if (!h.active) revert InvalidInput("not active");
        if (h.finished) revert InvalidInput("finished");
        if (h.claimer != address(0)) revert InvalidInput("claimed");

        uint256 currentTime = h.timeType ? block.timestamp : block.number;
        if (currentTime > h.settlementTime + h.reportTimestamp) revert InvalidInput("break time over");

        if (uint256(threshold) >= h.replacementDecay * (uint256(h.threshold) / 10000)) revert InvalidInput("minimum replacement increment");
        if (msg.value != h.liquidity) revert InvalidInput("msg.value wrong");

        address payable previousReporter = payable(h.reporter);
        uint256 previousBalance = h.liquidity;

        h.reportTimestamp = uint48(currentTime);
        h.reporter = msg.sender;
        h.threshold = threshold;
        h.seed = seed;
        h.blockHash = blockhash(block.number - 1);

        _sendEth(previousReporter, previousBalance);

        emit ReportReplaced(gameId, msg.sender, previousReporter, threshold, seed);
    }

    function settle(uint256 gameId) external {
        HashGame storage h = hashGame[gameId];
        if (!h.active) revert InvalidInput("not active");
        if (h.finished) revert InvalidInput("finished");
        if (h.claimer != address(0)) revert InvalidInput("claimed");

        uint256 currentTime = h.timeType ? block.timestamp : block.number;
        if (currentTime <= h.settlementTime + h.reportTimestamp) revert InvalidInput("settlement time not reached");

        address payable reporter = payable(h.reporter);
        uint256 payout = h.liquidity + h.reward;
        h.finished = true;
        h.active = false;
        _sendEth(reporter, payout);

        emit ReportSettled(gameId, reporter, h.liquidity, h.threshold);
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
