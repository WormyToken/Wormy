// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract WormyLock {
    using SafeMath for uint256;

    struct VestingSchedule {
        uint256 startTime;
        uint256 duration;
        uint256 totalAmount;
        uint256 claimedAmount;
        bool revoked;
    }

    IERC20 public immutable token;
    address public immutable owner;

    mapping(address => VestingSchedule) public vestingSchedules;

    event TokensVested(address indexed beneficiary, uint256 amount);
    event TokensReleased(address indexed beneficiary, uint256 amount);
    event TokensRevoked(address indexed beneficiary, uint256 amount);

    constructor(IERC20 _token) {
        token = _token;
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    function createVestingSchedule(
        address beneficiary,
        uint256 startTime,
        uint256 duration,
        uint256 totalAmount
    ) external onlyOwner {
        require(vestingSchedules[beneficiary].startTime == 0, "Vesting schedule already exists");
        require(startTime > block.timestamp, "Start time must be in the future");
        require(duration > 0, "Duration must be greater than 0");
        require(totalAmount > 0, "Total amount must be greater than 0");

        vestingSchedules[beneficiary] = VestingSchedule({
            startTime: startTime,
            duration: duration,
            totalAmount: totalAmount,
            claimedAmount: 0,
            revoked: false
        });

        emit TokensVested(beneficiary, totalAmount);
    }

    function release(address beneficiary) external {
        VestingSchedule storage schedule = vestingSchedules[beneficiary];
        require(schedule.startTime > 0, "No vesting schedule exists");
        require(!schedule.revoked, "Vesting schedule has been revoked");

        uint256 current = block.timestamp;
        require(current >= schedule.startTime, "Vesting has not started");

        uint256 elapsed = current.sub(schedule.startTime);
        uint256 vestedAmount = schedule.totalAmount.mul(elapsed).div(schedule.duration);
        vestedAmount = vestedAmount.sub(schedule.claimedAmount);

        require(vestedAmount > 0, "No tokens are available for release");

        schedule.claimedAmount = schedule.claimedAmount.add(vestedAmount);
        token.transfer(beneficiary, vestedAmount);

        emit TokensReleased(beneficiary, vestedAmount);
    }

    function revoke(address beneficiary) external onlyOwner {
        VestingSchedule storage schedule = vestingSchedules[beneficiary];
        require(schedule.startTime > 0, "No vesting schedule exists");
        require(!schedule.revoked, "Vesting schedule has already been revoked");

        uint256 remainingAmount = schedule.totalAmount.sub(schedule.claimedAmount);
        require(remainingAmount > 0, "All tokens have already been claimed");

        schedule.revoked = true;
        token.transfer(owner, remainingAmount);

        emit TokensRevoked(beneficiary, remainingAmount);
    }

    function getVestedAmount(address beneficiary) external view returns (uint256) {
        VestingSchedule memory schedule = vestingSchedules[beneficiary];
        require(schedule.startTime > 0, "No vesting schedule exists");

        uint256 current = block.timestamp;
        if (current < schedule.startTime) {
            return 0;
        }

        uint256 elapsed = current.sub(schedule.startTime);
        uint256 vestedAmount = schedule.totalAmount.mul(elapsed).div(schedule.duration);
        vestedAmount = vestedAmount.sub(schedule.claimedAmount);

        return vestedAmount;
    }
}
