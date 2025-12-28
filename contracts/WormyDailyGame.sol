// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract WormyDailyGame is ReentrancyGuard {
    error AlreadyDoneToday(address user);
    error InvalidValue();

    event DailyCheckIn(address indexed user, uint64 day);
    event TeamVoted(address indexed user, uint64 day, uint8 team);
    event Cheered(address indexed user, uint64 day, uint8 target);
    event PredictionCommitted(address indexed user, uint64 day, uint8 pType, uint8 value);
    event PresenceMarked(address indexed user, uint64 day);
    event StreakUpdated(address indexed user, uint32 current, uint32 max, uint64 day);

    mapping(address => mapping(uint64 => bool))  public checkedIn;

    // @dev 1:red 2:green 3:blue 4:gray 5:brown
    mapping(address => mapping(uint64 => uint8)) public teamVote;
    
    // @dev enum defined off-chain
    mapping(address => mapping(uint64 => uint8)) public cheerTarget;

    // @dev packed: (type<<8)|value
    mapping(address => mapping(uint64 => uint16)) public prediction;

    mapping(address => mapping(uint64 => bool))  public presence;

    struct Streak {
        uint32 current;
        uint32 max;
        uint64 lastDay;
    }
    mapping(address => Streak) public streaks;

    function _today() internal view returns (uint64) {
        return uint64(block.timestamp / 1 days);
    }

    function _updateStreak(address user, uint64 day) internal {
        Streak storage s = streaks[user];

        if (s.lastDay == day) return;

        if (s.lastDay + 1 == day) {
            s.current += 1;
        } else {
            s.current = 1;
        }

        s.lastDay = day;
        if (s.current > s.max) s.max = s.current;

        emit StreakUpdated(user, s.current, s.max, day);
    }

    function checkIn() external nonReentrant {
        uint64 day = _today();
        if (checkedIn[msg.sender][day]) revert AlreadyDoneToday(msg.sender);

        checkedIn[msg.sender][day] = true;

        _updateStreak(msg.sender, day);

        emit DailyCheckIn(msg.sender, day);
    }

    function voteTeam(uint8 team) external nonReentrant {
        if (team < 1 || team > 5) revert InvalidValue();

        uint64 day = _today();
        if (teamVote[msg.sender][day] != 0) revert AlreadyDoneToday(msg.sender);

        teamVote[msg.sender][day] = team;
        emit TeamVoted(msg.sender, day, team);
    }

    function cheer(uint8 target) external nonReentrant {
        uint64 day = _today();
        if (cheerTarget[msg.sender][day] != 0) revert AlreadyDoneToday(msg.sender);

        cheerTarget[msg.sender][day] = target;
        emit Cheered(msg.sender, day, target);
    }

    /// @dev prediction (on-chain commit, off-chain evaluation)
    function commitPrediction(uint8 predictionType, uint8 value) external nonReentrant {
        uint64 day = _today();
        if (prediction[msg.sender][day] != 0) revert AlreadyDoneToday(msg.sender);

        uint16 packed = (uint16(predictionType) << 8) | uint16(value);
        prediction[msg.sender][day] = packed;

        emit PredictionCommitted(msg.sender, day, predictionType, value);
    }

    function markPresence() external nonReentrant {
        uint64 day = _today();
        if (presence[msg.sender][day]) revert AlreadyDoneToday(msg.sender);

        presence[msg.sender][day] = true;
        emit PresenceMarked(msg.sender, day);
    }

    function hasCompletedAll(address user, uint64 day) external view returns (bool) {
        return
            checkedIn[user][day] &&
            teamVote[user][day] != 0 &&
            cheerTarget[user][day] != 0 &&
            prediction[user][day] != 0 &&
            presence[user][day];
    }

    function getStreak(address user) external view returns (
        uint32 current,
        uint32 max,
        uint64 lastDay
    ) {
        Streak memory s = streaks[user];
        return (s.current, s.max, s.lastDay);
    }

    function getDailyStatus(address user, uint64 day) external view returns (
        bool _checkediN,
        uint8 _teamVote,
        uint8 _cheer,
        uint16 _prediction,
        bool _presence
    ) {
        return (
            checkedIn[user][day],
            teamVote[user][day],
            cheerTarget[user][day],
            prediction[user][day],
            presence[user][day]
        );
    }

    function getTodayStatus(address user) external view returns (
        bool _checkedIn,
        uint8 _teamVote,
        uint8 _cheer,
        uint16 _prediction,
        bool _presence
    ) {
        uint64 day = _today();
        
        return (
            checkedIn[user][day],
            teamVote[user][day],
            cheerTarget[user][day],
            prediction[user][day],
            presence[user][day]
        );
    }

    function getToday() external view returns (uint64) {
        return _today();
    }
}
