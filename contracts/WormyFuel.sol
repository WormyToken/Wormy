// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";

interface IERC20 {
    function balanceOf(address user) external view returns (uint256);
}

interface IPohVerifier {
    function verify(bytes calldata signature, address human) external view returns (bool);
}

contract WormyFuel is Ownable, ReentrancyGuard {
    using Address for address payable;

    IPohVerifier public immutable pohVerifier;
    IERC20 public immutable token;

    uint256 public immutable startTime;
    uint256 public baseRequirement;
    uint256 public incrementPerDay;
    uint256 public ethReward;
    uint8 public maxClaimPerDay;

    bool public claimActive;

    struct DailyClaim {
        uint256 day;
        uint256 count;
    }

    mapping(address => DailyClaim) public dailyClaims;

    error PohVerificationFailed(address sender);
    error ClaimNotActive();
    error AlreadyClaimedMaxToday();
    error NotEnoughToken();

    constructor(
        address _initialOwner,
        address _pohVerifier,
        address _tokenAddress,
        uint256 _baseRequirement,
        uint256 _incrementPerDay,
        uint256 _ethReward,
        uint8 _maxClaimPerDay
    ) Ownable(_initialOwner) {
        require(_initialOwner != address(0), "owner=0");
        require(_pohVerifier != address(0), "poh=0");
        require(_tokenAddress != address(0), "token=0");
        require(_maxClaimPerDay > 0, "maxClaim=0");

        pohVerifier = IPohVerifier(_pohVerifier);
        token = IERC20(_tokenAddress);

        baseRequirement = _baseRequirement;
        incrementPerDay = _incrementPerDay;
        ethReward = _ethReward;
        maxClaimPerDay = _maxClaimPerDay;

        startTime = block.timestamp;
        claimActive = false;
    }

    function getCurrentDay() public view returns (uint256) {
        return (block.timestamp - startTime) / 1 days;
    }

    function getRequiredTokenToday() public view returns (uint256) {
        return baseRequirement + (getCurrentDay() * incrementPerDay);
    }

    function claim(bytes calldata signature) external nonReentrant {
        if (!claimActive) revert ClaimNotActive();

        if (!pohVerifier.verify(signature, msg.sender)) {
            revert PohVerificationFailed(msg.sender);
        }

        uint256 today = getCurrentDay();
        DailyClaim storage dc = dailyClaims[msg.sender];

        if (dc.day < today) {
            dc.day = today;
            dc.count = 0;
        }

        if (dc.count >= maxClaimPerDay) {
            revert AlreadyClaimedMaxToday();
        }

        if (token.balanceOf(msg.sender) < getRequiredTokenToday()) {
            revert NotEnoughToken();
        }

        dc.count += 1;

        payable(msg.sender).sendValue(ethReward);
    }

    function setClaimActive(bool active) external onlyOwner {
        claimActive = active;
    }

    function setEthReward(uint256 newReward) external onlyOwner {
        ethReward = newReward;
    }

    function setBaseRequirement(uint256 newBase) external onlyOwner {
        baseRequirement = newBase;
    }

    function setIncrementPerDay(uint256 newIncrement) external onlyOwner {
        incrementPerDay = newIncrement;
    }

    function setMaxClaimPerDay(uint8 newMax) external onlyOwner {
        require(newMax > 0, "maxClaim=0");
        maxClaimPerDay = newMax;
    }

    function withdrawRemaining() external onlyOwner nonReentrant {
        payable(owner()).sendValue(address(this).balance);
    }

    receive() external payable {}
}
