// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract WormyClaim is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;
    uint256 public minClaimAmount;
    uint256 public maxClaimAmount;
    uint256 public claimPeriod;
    uint256 public claimStartTime;

    mapping(address => uint256) public lastClaimDay;

    event Claimed(address indexed claimer, uint256 amount, uint256 day);
    event ClaimRangeUpdated(uint256 minAmount, uint256 maxAmount);
    event ClaimPeriodUpdated(uint256 newPeriod);
    event ClaimStartTimeUpdated(uint256 newStartTime);
    event TokensWithdrawn(address to, uint256 amount);

    /**
     * @param _token ERC20 token address (must be already deployed)
     * @param _minClaimAmount minimum amount per claim (18 decimal)
     * @param _maxClaimAmount maximum amount per claim (18 decimal)
     * @param _claimPeriod duration in seconds from deployment/start that claims are allowed
     */
    constructor(
        address _token,
        uint256 _minClaimAmount,
        uint256 _maxClaimAmount,
        uint256 _claimPeriod
    ) Ownable(msg.sender) {
        require(_token != address(0), "token zero address");
        require(_minClaimAmount > 0, "Min must be > 0");
        require(_maxClaimAmount >= _minClaimAmount, "Max < Min");

        token = IERC20(_token);
        minClaimAmount = _minClaimAmount;
        maxClaimAmount = _maxClaimAmount;
        claimPeriod = _claimPeriod;
        claimStartTime = block.timestamp;
    }

    modifier onlyDuringClaimPeriod() {
        require(
            block.timestamp >= claimStartTime &&
            block.timestamp <= claimStartTime + claimPeriod,
            "Claim period inactive"
        );
        _;
    }

    function _randomUint(address user) internal view returns (uint256) {
        return uint256(
            keccak256(
                abi.encodePacked(
                    block.timestamp,
                    user,
                    block.prevrandao,
                    address(this)
                )
            )
        );
    }

    function _randomClaimAmount(address user) internal view returns (uint256) {
        uint256 range = maxClaimAmount - minClaimAmount + 1;
        uint256 rand = _randomUint(user) % range;
        return minClaimAmount + rand;
    }

    function claim() external nonReentrant onlyDuringClaimPeriod {
        uint256 current = block.timestamp / 1 days;
        require(lastClaimDay[msg.sender] < current, "Already claimed today");

        uint256 amount = _randomClaimAmount(msg.sender);
        lastClaimDay[msg.sender] = current;

        token.safeTransfer(msg.sender, amount);

        emit Claimed(msg.sender, amount, current);
    }

    function setClaimAmount(uint256 _min, uint256 _max) external onlyOwner {
        require(_min > 0, "Min must be > 0");
        require(_max >= _min, "Max < Min");
        minClaimAmount = _min;
        maxClaimAmount = _max;
        emit ClaimRangeUpdated(_min, _max);
    }

    function setClaimPeriod(uint256 _newPeriod) external onlyOwner {
        claimPeriod = _newPeriod;
        emit ClaimPeriodUpdated(_newPeriod);
    }

    function setClaimStartTime(uint256 _newStartTime) external onlyOwner {
        claimStartTime = _newStartTime;
        emit ClaimStartTimeUpdated(_newStartTime);
    }

    function withdrawTokens(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "zero address");
        token.safeTransfer(to, amount);
        emit TokensWithdrawn(to, amount);
    }

    function currentDay() public view returns (uint256) {
        return block.timestamp / 1 days;
    }

    function canClaim(address user) external view returns (bool) {
        uint256 current = block.timestamp / 1 days;
        if (block.timestamp < claimStartTime || block.timestamp > claimStartTime + claimPeriod) {
            return false;
        }
        if (lastClaimDay[user] >= current) return false;
        return true;
    }

    receive() external payable {}
}
