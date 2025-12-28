// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract WormyPitStop is ReentrancyGuard, Ownable {
    error MaxPitStopReached(address user);

    event PitStopProgress(
        address indexed user,
        uint64 dayIndex,
        uint8 step
    );

    event MaxPitStopUpdated(uint8 oldValue, uint8 newValue);

    struct PitState {
        uint64 day;
        uint8 count;
    }

    mapping(address => PitState) private pitStates;

    uint8 public maxPitStopPerDay;

    constructor(
        address _initialOwner,
        uint8 _initialMax
    ) Ownable(_initialOwner) {
        require(_initialOwner != address(0), "owner=0");
        require(_initialMax > 0, "max=0");

        maxPitStopPerDay = _initialMax;
    }

    function _today() internal view returns (uint64) {
        return uint64(block.timestamp / 1 days);
    }

    function pitStop() external nonReentrant {
        uint64 today = _today();
        PitState storage ps = pitStates[msg.sender];

        if (ps.day < today) {
            ps.day = today;
            ps.count = 0;
        }

        if (ps.count >= maxPitStopPerDay) {
            revert MaxPitStopReached(msg.sender);
        }

        unchecked {
            ps.count += 1;
        }

        emit PitStopProgress(
            msg.sender,
            today,
            ps.count
        );
    }

    function setMaxPitStopPerDay(uint8 newMax) external onlyOwner {
        require(newMax > 0, "max=0");
        uint8 old = maxPitStopPerDay;
        maxPitStopPerDay = newMax;
        emit MaxPitStopUpdated(old, newMax);
    }

    function getPitStatus(address user) external view returns (
        uint64 day,
        uint8 completed,
        uint8 maxPerDay
    ) {
        PitState memory ps = pitStates[user];
        return (ps.day, ps.count, maxPitStopPerDay);
    }
}
