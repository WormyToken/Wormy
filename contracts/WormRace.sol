// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IPohVerifier {
    function verify(bytes memory signature, address human) external view returns (bool);
}

contract WormRaceVault is Ownable, ReentrancyGuard {
    error PohVerificationFailed(address sender);
    error DailyLimitReached(address sender);
    error VaultEmpty();
    error TokenTransferFailed();

    IPohVerifier public immutable pohVerifier;

    IERC20Metadata public immutable wormToken;

    uint8 public immutable tokenDecimals;
    string public tokenSymbol;
    string public tokenName;
    uint256 public tokensPerRace;
    uint8 public maxRacesPerDay;
    uint256 public totalDistributed;
    uint256 public currentSeasonId;

    struct UserInfo {
        uint64 lastRaceDay;
        uint8  racesToday;
        uint256 totalPoints;
    }

    mapping(address => UserInfo) public users;

    mapping(uint256 => mapping(address => uint256)) public seasonPoints;

    event Raced(
        address indexed user,
        uint256 indexed seasonId,
        uint256 rewardAmount,
        uint64 dayIndex,
        uint8 racesToday,
        uint256 seasonScore,
        uint256 totalPoints
    );

    event SeasonChanged(uint256 indexed previousSeasonId, uint256 indexed newSeasonId);
    event TokensPerRaceUpdated(uint256 oldAmount, uint256 newAmount);
    event MaxRacesPerDayUpdated(uint8 oldMax, uint8 newMax);
    event TokensRecovered(address indexed to, uint256 amount);

    constructor(
        address _pohVerifier,
        address _wormToken,
        uint256 _tokensPerRace,
        uint8 _maxRacesPerDay,
        uint256 _initialSeasonId
    ) Ownable(msg.sender) {
        require(_pohVerifier != address(0), "Vault: pohVerifier is zero");
        require(_wormToken != address(0), "Vault: token is zero");
        require(_tokensPerRace > 0, "Vault: tokensPerRace must be > 0");
        require(_maxRacesPerDay > 0, "Vault: maxRacesPerDay must be > 0");
        require(_initialSeasonId > 0, "Vault: season must be > 0");

        pohVerifier = IPohVerifier(_pohVerifier);

        IERC20Metadata token = IERC20Metadata(_wormToken);
        wormToken = token;

        uint8 decs = token.decimals();
        tokenDecimals = decs;
        tokenSymbol = token.symbol();
        tokenName = token.name();

        tokensPerRace = _tokensPerRace;
        maxRacesPerDay = _maxRacesPerDay;
        currentSeasonId = _initialSeasonId;
    }

    function race(bytes calldata signature) external nonReentrant {
        if (!pohVerifier.verify(signature, msg.sender)) {
            revert PohVerificationFailed(msg.sender);
        }

        UserInfo storage u = users[msg.sender];
        uint64 today = uint64(block.timestamp / 1 days);

        if (u.lastRaceDay < today) {
            u.lastRaceDay = today;
            u.racesToday = 0;
        }

        if (u.racesToday >= maxRacesPerDay) {
            revert DailyLimitReached(msg.sender);
        }

        uint256 amount = tokensPerRace;
        if (amount == 0) {
            revert VaultEmpty();
        }

        uint256 balance = wormToken.balanceOf(address(this));
        if (balance < amount) {
            revert VaultEmpty();
        }

        u.racesToday += 1;
        u.totalPoints += 1;
        seasonPoints[currentSeasonId][msg.sender] += 1;
        totalDistributed += amount;

        bool ok = wormToken.transfer(msg.sender, amount);
        if (!ok) {
            revert TokenTransferFailed();
        }

        emit Raced(
            msg.sender,
            currentSeasonId,
            amount,
            today,
            u.racesToday,
            seasonPoints[currentSeasonId][msg.sender],
            u.totalPoints
        );
    }

    function getUserInfo(address user)
        external
        view
        returns (
            uint64 lastDay,
            uint8 racesToday,
            uint8 maxPerDay,
            uint256 secondsToReset,
            uint256 lifetimePoints,
            uint256 currentSeasonPoints
        )
    {
        UserInfo memory u = users[user];
        lastDay = u.lastRaceDay;
        racesToday = u.racesToday;
        maxPerDay = maxRacesPerDay;
        lifetimePoints = u.totalPoints;
        currentSeasonPoints = seasonPoints[currentSeasonId][user];

        uint64 today = uint64(block.timestamp / 1 days);
        if (u.lastRaceDay < today) {
            secondsToReset = 0;
        } else {
            uint256 nextDayStart = (uint256(u.lastRaceDay) + 1) * 1 days;
            if (block.timestamp >= nextDayStart) {
                secondsToReset = 0;
            } else {
                secondsToReset = nextDayStart - block.timestamp;
            }
        }
    }

    function getSeasonPoints(uint256 seasonId, address user) external view returns (uint256) {
        return seasonPoints[seasonId][user];
    }

    function tokensRemaining() external view returns (uint256) {
        return wormToken.balanceOf(address(this));
    }

    function setTokensPerRace(uint256 newAmount) external onlyOwner {
        require(newAmount > 0, "Vault: tokensPerRace zero");
        uint256 old = tokensPerRace;
        tokensPerRace = newAmount;
        emit TokensPerRaceUpdated(old, newAmount);
    }

    function setMaxRacesPerDay(uint8 newMax) external onlyOwner {
        require(newMax > 0, "Vault: newMax must be > 0");
        uint8 old = maxRacesPerDay;
        maxRacesPerDay = newMax;
        emit MaxRacesPerDayUpdated(old, newMax);
    }

    function setSeason(uint256 newSeasonId) external onlyOwner {
        require(newSeasonId > 0, "Vault: season must be > 0");
        uint256 previous = currentSeasonId;
        currentSeasonId = newSeasonId;
        emit SeasonChanged(previous, newSeasonId);
    }

    function recoverTokens(address to, uint256 amount) external onlyOwner nonReentrant {
        require(to != address(0), "Vault: zero address");
        bool ok = wormToken.transfer(to, amount);
        if (!ok) {
            revert TokenTransferFailed();
        }
        emit TokensRecovered(to, amount);
    }
}
