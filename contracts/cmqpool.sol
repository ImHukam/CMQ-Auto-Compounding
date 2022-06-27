// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface BusdPrice {
    function price() external view returns (uint256); //price in 18 decimals
}

interface GetDataInterface {
    function returnData()
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        );

    function returnAprData()
        external
        view
        returns (
            uint256,
            uint256,
            bool
        );
        
    function returnMaxStakeUnstake()
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        );
}

interface TreasuryInterface {
    function send(address, uint256) external;
}


contract CMQSTAKEPOOL is ReentrancyGuard, Ownable {
    using SafeMath for uint256;

    address public dataAddress = 0xCEc1D8622A9893CE73428a48F868a20f42E21031;
    GetDataInterface data = GetDataInterface(dataAddress);
    address public busdPriceAddress = 0xd1Aa61B8a09d05e68aDE9c8ccA0dF2192234af43;
    BusdPrice busdPrice = BusdPrice(busdPriceAddress);
    address public TreasuryAddress = 0x02CA4C5e88e125a7f7003fdae697Fa4F2E6da118;
    TreasuryInterface treasury = TreasuryInterface(TreasuryAddress);

    struct stakeInfoData {
        uint256 compoundStart;
        bool isCompoundStartSet;
    }

    struct userInfoData {
        uint256 stakeBalanceWithReward;
        uint256 stakeBalance;
        uint256 lastClaimedReward;
        uint256 lastStakeUnstakeTimestamp;
        uint256 lastClaimTimestamp;
        bool isStaker;
        uint256 totalClaimedReward;
        uint256 autoClaimWithStakeUnstake;
        uint256 pendingRewardAfterFullyUnstake;
        bool isClaimAferUnstake;
        uint256 nextCompoundDuringStakeUnstake;
        uint256 nextCompoundDuringClaim;
        uint256 lastCompoundedRewardWithStakeUnstakeClaim;
    }

    IERC20 public cmq = IERC20(0x074E91c178e4B4c6228357A5A0B6df5aD824f0d8);

    uint256 decimal4 = 1e4;
    uint256 decimal18 = 1e18;
    mapping(address => userInfoData) public userInfo;
    stakeInfoData public stakeInfo;
    uint256 s; // total staking amount
    uint256 u; //total unstaking amount
    bool public isClaim = true; // for all stakers
    bool public fixUnstakeAmount;
    uint256 public stake_fee = 5 * decimal18;
    uint256 public unstake_fee = 5 * decimal18;

    mapping(address => bool) public isBlock; //fpr a user

    event rewardClaim(address indexed user, uint256 rewards);
    event Stake(address account, uint256 stakeAmount);
    event UnStake(address account, uint256 unStakeAmount);
    event DataAddressSet(address newDataAddress);
    event TreasuryAddressSet(address newTreasuryAddresss);
    event SetCompoundStart(uint256 _blocktime);

    constructor() {
        stakeInfo.compoundStart = block.timestamp;
    }

    function set_compoundStart(uint256 _blocktime) public onlyOwner {
        require(stakeInfo.isCompoundStartSet == false, "already set once");
        stakeInfo.compoundStart = _blocktime;
        stakeInfo.isCompoundStartSet = true;
        emit SetCompoundStart(_blocktime);
    }

    function set_data(address _data) public onlyOwner {
        require(
            _data != address(0),
            "can not set zero address for data address"
        );
        dataAddress = _data;
        data = GetDataInterface(_data);
        emit DataAddressSet(_data);
    }

    function set_busdPriceAddress(address _address) public onlyOwner {
        require(
            _address != address(0),
            "can not set zero address for data address"
        );
        busdPriceAddress = _address;
        busdPrice = BusdPrice(_address);
    }

    function set_treasuryAddress(address _treasury) public onlyOwner {
        require(
            _treasury != address(0),
            "can not set zero address for treasury address"
        );
        TreasuryAddress = _treasury;
        treasury = TreasuryInterface(_treasury);
        emit TreasuryAddressSet(_treasury);
    }

    function set_fee(uint256 _stakeFee, uint256 _unstakeFee) public onlyOwner {
        stake_fee = _stakeFee;
        unstake_fee = _unstakeFee;
    }

    // to stop or start claim
    function set_isClaim(bool _isClaim) public onlyOwner {
        isClaim = _isClaim;
    }

    function set_fixUnstakeAmount(bool _fix) public onlyOwner {
        fixUnstakeAmount = _fix;
    }

    function _block(address _address, bool is_Block) public onlyOwner {
        isBlock[_address] = is_Block;
    }

    function nextCompound() public view returns (uint256 _nextCompound) {
        (, uint256 compoundRate, ) = data.returnData();
        uint256 interval = block.timestamp - stakeInfo.compoundStart;
        interval = interval / compoundRate;
        _nextCompound =
            stakeInfo.compoundStart +
            compoundRate +
            interval *
            compoundRate;
    }

    function stake(uint256 amount) external nonReentrant {
        require(isBlock[msg.sender] == false, "blocked");
        //uint256 _price = busdPrice.price();

        (uint256 maxStakePerTx, , uint256 totalStakePerUser) = data
            .returnMaxStakeUnstake();
        require(amount <= maxStakePerTx, "exceed max stake limit for a tx");
        require(
            (userInfo[msg.sender].stakeBalance + amount) <=
                totalStakePerUser,
            "exceed total stake limit"
        );

        //uint256 fee = (stake_fee * decimal4) / _price;
        uint256 fee= stake_fee;
        require(amount > fee, "amount less then stake_fee");
        amount = amount - fee;
        cmq.transferFrom(msg.sender, address(this), amount);
        cmq.transferFrom(msg.sender, TreasuryAddress, fee);

        userInfo[msg.sender]
            .lastCompoundedRewardWithStakeUnstakeClaim = lastCompoundedReward(
            msg.sender
        );

        if (userInfo[msg.sender].isStaker == true) {
            uint256 _pendingReward = compoundedReward(msg.sender);
            uint256 cpending = cPendingReward(msg.sender);
            userInfo[msg.sender].stakeBalanceWithReward =
                userInfo[msg.sender].stakeBalanceWithReward +
                _pendingReward;
            userInfo[msg.sender].autoClaimWithStakeUnstake = _pendingReward;
            userInfo[msg.sender].totalClaimedReward = 0;
            if (
                block.timestamp <
                userInfo[msg.sender].nextCompoundDuringStakeUnstake
            ) {
                userInfo[msg.sender].stakeBalanceWithReward =
                    userInfo[msg.sender].stakeBalanceWithReward +
                    cpending;
                userInfo[msg.sender].autoClaimWithStakeUnstake =
                    userInfo[msg.sender].autoClaimWithStakeUnstake +
                    cpending;
            }
        }

        userInfo[msg.sender].stakeBalanceWithReward =
            userInfo[msg.sender].stakeBalanceWithReward +
            amount;
        userInfo[msg.sender].stakeBalance =
            userInfo[msg.sender].stakeBalance +
            amount;
        userInfo[msg.sender].lastStakeUnstakeTimestamp = block.timestamp;
        userInfo[msg.sender].nextCompoundDuringStakeUnstake = nextCompound();
        userInfo[msg.sender].isStaker = true;
        s = s + amount;
        emit Stake(msg.sender, amount);
    }

    function unStake(uint256 amount) external nonReentrant {
        require(isBlock[msg.sender] == false, "blocked");
        require(
            amount <= userInfo[msg.sender].stakeBalance,
            "invalid staked amount"
        );

        (, uint256 maxUnstakePerTx, ) = data.returnMaxStakeUnstake();
        require(amount <= maxUnstakePerTx, "exceed unstake limit per tx");
        require(amount > unstake_fee, "amount less then unstake_fee");

        uint256 pending = compoundedReward(msg.sender);
        uint256 stakeBalance = userInfo[msg.sender].stakeBalance;
        //uint256 _price = busdPrice.price();
        //uint256 fee = (unstake_fee * decimal4) / _price;
        uint256 fee= unstake_fee;
        cmq.transfer(msg.sender, amount-fee);
        cmq.transfer(TreasuryAddress, fee);
        emit UnStake(msg.sender, amount);

        // reward update
        if (amount < stakeBalance) {
            uint256 _pendingReward = compoundedReward(msg.sender);

            userInfo[msg.sender]
                .lastCompoundedRewardWithStakeUnstakeClaim = lastCompoundedReward(
                msg.sender
            );

            userInfo[msg.sender].autoClaimWithStakeUnstake = _pendingReward;

            // update state

            userInfo[msg.sender].lastStakeUnstakeTimestamp = block.timestamp;
            userInfo[msg.sender]
                .nextCompoundDuringStakeUnstake = nextCompound();
            userInfo[msg.sender].totalClaimedReward = 0;

            userInfo[msg.sender].stakeBalanceWithReward =
                userInfo[msg.sender].stakeBalanceWithReward - amount;
            userInfo[msg.sender].stakeBalance =
                userInfo[msg.sender].stakeBalance - amount;
            u = u + amount;
        }

        if (amount >= stakeBalance) {
            u = u + stakeBalance;
            userInfo[msg.sender].pendingRewardAfterFullyUnstake = pending;
            userInfo[msg.sender].isClaimAferUnstake = true;
            userInfo[msg.sender].stakeBalanceWithReward = 0;
            userInfo[msg.sender].stakeBalance = 0;
            userInfo[msg.sender].isStaker = false;
            userInfo[msg.sender].totalClaimedReward = 0;
            userInfo[msg.sender].autoClaimWithStakeUnstake = 0;
            userInfo[msg.sender].lastCompoundedRewardWithStakeUnstakeClaim = 0;
        }

        if (userInfo[msg.sender].pendingRewardAfterFullyUnstake == 0) {
            userInfo[msg.sender].isClaimAferUnstake = false;
        }
    }

    function cPendingReward(address user)
        internal
        view
        returns (uint256 _compoundedReward)
    {
        uint256 reward;
        if (
            userInfo[user].lastClaimTimestamp <
            userInfo[user].nextCompoundDuringStakeUnstake &&
            userInfo[user].lastStakeUnstakeTimestamp <
            userInfo[user].nextCompoundDuringStakeUnstake
        ) {
            (uint256 a, uint256 compoundRate, ) = data.returnData();
            a = a / compoundRate;
            uint256 tsec = userInfo[user].nextCompoundDuringStakeUnstake -
                userInfo[user].lastStakeUnstakeTimestamp;
            uint256 stakeSec = block.timestamp -
                userInfo[user].lastStakeUnstakeTimestamp;
            uint256 sec = tsec > stakeSec ? stakeSec : tsec;
            uint256 balance = userInfo[user].stakeBalanceWithReward;
            reward = (balance.mul(a)).div(100);
            reward = reward / decimal18;
            _compoundedReward = reward * sec;
        }
    }

    function compoundedReward(address user)
        public
        view
        returns (uint256 _compoundedReward)
    {
        address _user = user;
        uint256 nextcompound = userInfo[user].nextCompoundDuringStakeUnstake;
        (, uint256 compoundRate, ) = data.returnData();
        uint256 compoundTime = block.timestamp > nextcompound
            ? block.timestamp - nextcompound
            : 0;
        uint256 loopRound = compoundTime / compoundRate;
        uint256 reward = 0;
        if (userInfo[user].isStaker == false) {
            loopRound = 0;
        }
        (uint256 a, , ) = data.returnData();
        _compoundedReward = 0;
        uint256 cpending = cPendingReward(user);
        uint256 balance = userInfo[user].stakeBalanceWithReward + cpending;

        for (uint256 i = 1; i <= loopRound; i++) {
            uint256 amount = balance.add(reward);
            reward = (amount.mul(a)).div(100);
            reward = reward / decimal18;
            _compoundedReward = _compoundedReward.add(reward);
            balance = amount;
        }

        if (_compoundedReward != 0) {
            uint256 sum = _compoundedReward +
                userInfo[user].autoClaimWithStakeUnstake;
            _compoundedReward = sum > userInfo[user].totalClaimedReward
                ? sum - userInfo[user].totalClaimedReward
                : 0;
            _compoundedReward = _compoundedReward + cPendingReward(user);
        }

        if (_compoundedReward == 0) {
            _compoundedReward = userInfo[user].autoClaimWithStakeUnstake;

            if (
                block.timestamp > userInfo[user].nextCompoundDuringStakeUnstake
            ) {
                _compoundedReward = _compoundedReward + cPendingReward(user);
            }
        }

        if (userInfo[user].isClaimAferUnstake == true) {
            _compoundedReward =
                _compoundedReward +
                userInfo[user].pendingRewardAfterFullyUnstake;
        }

        (
            uint256 aprChangeTimestamp,
            uint256 aprChangePercentage,
            bool isAprIncrease
        ) = data.returnAprData();

        if (userInfo[_user].lastStakeUnstakeTimestamp < aprChangeTimestamp) {
            if (isAprIncrease == false) {
                _compoundedReward =
                    _compoundedReward -
                    ((userInfo[_user].autoClaimWithStakeUnstake *
                        aprChangePercentage) / 100);
            }

            if (isAprIncrease == true) {
                _compoundedReward =
                    _compoundedReward +
                    ((userInfo[_user].autoClaimWithStakeUnstake *
                        aprChangePercentage) / 100);
            }
        }
    }


    function pendingReward(address user)
        public
        view
        returns (uint256 _pendingReward)
    {
        address _user = user;
        uint256 nextcompound = userInfo[user].nextCompoundDuringStakeUnstake;
        (, uint256 compoundRate, ) = data.returnData();
        uint256 compoundTime = block.timestamp > nextcompound
            ? block.timestamp - nextcompound
            : 0;
        uint256 loopRound = compoundTime / compoundRate;
        uint256 reward = 0;
        (uint256 a, , ) = data.returnData();
        if (userInfo[user].isStaker == false) {
            loopRound = 0;
        }
        _pendingReward = 0;
        uint256 cpending = cPendingReward(user);
        uint256 balance = userInfo[user].stakeBalanceWithReward + cpending;

        for (uint256 i = 1; i <= loopRound + 1; i++) {
            uint256 amount = balance.add(reward);
            reward = (amount.mul(a)).div(100);
            reward = reward / decimal18;
            _pendingReward = _pendingReward.add(reward);
            balance = amount;
        }

        if (_pendingReward != 0) {
            _pendingReward =
                _pendingReward -
                userInfo[user].totalClaimedReward +
                userInfo[user].autoClaimWithStakeUnstake +
                cPendingReward(user);

            if (
                block.timestamp < userInfo[user].nextCompoundDuringStakeUnstake
            ) {
                _pendingReward =
                    userInfo[user].autoClaimWithStakeUnstake +
                    cPendingReward(user);
            }
        }

        if (userInfo[user].isClaimAferUnstake == true) {
            _pendingReward =
                _pendingReward +
                userInfo[user].pendingRewardAfterFullyUnstake;
        }

         (
            uint256 aprChangeTimestamp,
            uint256 aprChangePercentage,
            bool isAprIncrease
        ) = data.returnAprData();

        if (userInfo[_user].lastStakeUnstakeTimestamp < aprChangeTimestamp) {
            if (isAprIncrease == false) {
                _pendingReward =
                    _pendingReward -
                    ((userInfo[_user].autoClaimWithStakeUnstake *
                        aprChangePercentage) / 100);
            }

            if (isAprIncrease == true) {
                _pendingReward =
                    _pendingReward +
                    ((userInfo[_user].autoClaimWithStakeUnstake *
                        aprChangePercentage) / 100);
            }
        }

        _pendingReward = _pendingReward - compoundedReward(user);
    }



    function lastCompoundedReward(address user)
        public
        view
        returns (uint256 _compoundedReward)
    {
        uint256 nextcompound = userInfo[user].nextCompoundDuringStakeUnstake;
        (, uint256 compoundRate, ) = data.returnData();
        uint256 compoundTime = block.timestamp > nextcompound
            ? block.timestamp - nextcompound
            : 0;
        compoundTime = compoundTime > compoundRate
            ? compoundTime - compoundRate
            : 0;
        uint256 loopRound = compoundTime / compoundRate;
        uint256 reward = 0;
        if (userInfo[user].isStaker == false) {
            loopRound = 0;
        }
        (uint256 a, , ) = data.returnData();
        _compoundedReward = 0;
        uint256 cpending = cPendingReward(user);
        uint256 balance = userInfo[user].stakeBalanceWithReward + cpending;

        for (uint256 i = 1; i <= loopRound; i++) {
            uint256 amount = balance.add(reward);
            reward = (amount.mul(a)).div(100);
            reward = reward / decimal18;
            _compoundedReward = _compoundedReward.add(reward);
            balance = amount;
        }

        if (_compoundedReward != 0) {
            uint256 sum = _compoundedReward +
                userInfo[user].autoClaimWithStakeUnstake;
            _compoundedReward = sum > userInfo[user].totalClaimedReward
                ? sum - userInfo[user].totalClaimedReward
                : 0;
            _compoundedReward = _compoundedReward + cPendingReward(user);
        }

        if (_compoundedReward == 0) {
            _compoundedReward = userInfo[user].autoClaimWithStakeUnstake;

            if (
                block.timestamp >
                userInfo[user].nextCompoundDuringStakeUnstake + compoundRate
            ) {
                _compoundedReward = _compoundedReward + cPendingReward(user);
            }
        }

        if (userInfo[user].isClaimAferUnstake == true) {
            _compoundedReward =
                _compoundedReward +
                userInfo[user].pendingRewardAfterFullyUnstake;
        }

        uint256 result = compoundedReward(user) - _compoundedReward;

        if (
            block.timestamp < userInfo[user].nextCompoundDuringStakeUnstake ||
            block.timestamp < userInfo[user].nextCompoundDuringClaim
        ) {
            result =
                result +
                userInfo[user].lastCompoundedRewardWithStakeUnstakeClaim;
        }

        _compoundedReward = result;
    }

    function rewardCalculation(address user) internal {
        (, uint256 compoundRate, ) = data.returnData();
        address _user = user;
        uint256 nextcompound = userInfo[user].nextCompoundDuringStakeUnstake;
        uint256 compoundTime = block.timestamp > nextcompound
            ? block.timestamp - nextcompound
            : 0;
        uint256 loopRound = compoundTime / compoundRate;
        (uint256 a, , ) = data.returnData();
        uint256 reward;
        if (userInfo[user].isStaker == false) {
            loopRound = 0;
        }
        uint256 totalReward;
        uint256 cpending = cPendingReward(user);
        uint256 balance = userInfo[user].stakeBalanceWithReward + cpending;

        for (uint256 i = 1; i <= loopRound; i++) {
            uint256 amount = balance.add(reward);
            reward = (amount.mul(a)).div(100);
            reward = reward / decimal18;
            totalReward = totalReward.add(reward);
            balance = amount;
        }

        if (userInfo[user].isClaimAferUnstake == true) {
            totalReward =
                totalReward +
                userInfo[user].pendingRewardAfterFullyUnstake;
        }
        totalReward = totalReward + cPendingReward(user);
        userInfo[user].lastClaimedReward =
            totalReward -
            userInfo[user].totalClaimedReward;
        userInfo[user].totalClaimedReward =
            userInfo[user].totalClaimedReward +
            userInfo[user].lastClaimedReward -
            cPendingReward(user);

                    (
            uint256 aprChangeTimestamp,
            uint256 aprChangePercentage,
            bool isAprIncrease
        ) = data.returnAprData();

        if (userInfo[_user].lastStakeUnstakeTimestamp < aprChangeTimestamp) {
            if (isAprIncrease == false) {
                userInfo[_user].autoClaimWithStakeUnstake =
                    userInfo[_user].autoClaimWithStakeUnstake -
                    ((userInfo[_user].autoClaimWithStakeUnstake *
                        aprChangePercentage) / 100);
            }

            if (isAprIncrease == true) {
                userInfo[_user].autoClaimWithStakeUnstake =
                    userInfo[_user].autoClaimWithStakeUnstake +
                    (((userInfo[_user].autoClaimWithStakeUnstake) *
                        aprChangePercentage) / 100);
            }
        }
    }

    function claim() public nonReentrant {
        require(isClaim == true, "claim stopped");
        require(isBlock[msg.sender] == false, "blocked");
        require(
            userInfo[msg.sender].isStaker == true ||
                userInfo[msg.sender].isClaimAferUnstake == true,
            "user not staked"
        );
        userInfo[msg.sender]
            .lastCompoundedRewardWithStakeUnstakeClaim = lastCompoundedReward(
            msg.sender
        );

        rewardCalculation(msg.sender);
        uint256 reward = userInfo[msg.sender].lastClaimedReward +
            userInfo[msg.sender].autoClaimWithStakeUnstake;
        require(reward > 0, "can't reap zero reward");

        treasury.send(msg.sender, reward);
        emit rewardClaim(msg.sender, reward);
        userInfo[msg.sender].autoClaimWithStakeUnstake = 0;
        userInfo[msg.sender].lastClaimTimestamp = block.timestamp;
        userInfo[msg.sender].nextCompoundDuringClaim = nextCompound();

        if (
            userInfo[msg.sender].isClaimAferUnstake == true &&
            userInfo[msg.sender].isStaker == false
        ) {
            userInfo[msg.sender].lastStakeUnstakeTimestamp = 0;
            userInfo[msg.sender].lastClaimedReward = 0;
            userInfo[msg.sender].totalClaimedReward = 0;
        }

        if (
            userInfo[msg.sender].isClaimAferUnstake == true &&
            userInfo[msg.sender].isStaker == true
        ) {
            userInfo[msg.sender].totalClaimedReward =
                userInfo[msg.sender].totalClaimedReward -
                userInfo[msg.sender].pendingRewardAfterFullyUnstake;
        }
        bool c = userInfo[msg.sender].isClaimAferUnstake;
        if (c == true) {
            userInfo[msg.sender].pendingRewardAfterFullyUnstake = 0;
            userInfo[msg.sender].isClaimAferUnstake = false;
        }
    }

    function totalStake() external view returns (uint256 stakingAmount) {
        stakingAmount = s;
    }

    function totalUnstake() external view returns (uint256 unstakingAmount) {
        unstakingAmount = u;
    }

    function transferAnyERC20Token(
        address _tokenAddress,
        address _to,
        uint256 _amount
    ) public onlyOwner {
        IERC20(_tokenAddress).transfer(_to, _amount);
    }

    function vyncPrice() public view returns (uint256 _price) {
        _price = busdPrice.price();
    }
}