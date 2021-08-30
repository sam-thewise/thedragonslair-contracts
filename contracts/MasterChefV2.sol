// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "./libs/IERC20.sol";
import "./libs/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./DragonEggToken.sol";

// MasterChef is the master of the almighty Dragon Eggs. He can make Dragon Eggs and he is a pretty cool guy.
//
// Note that it's ownable and the owner wields tremendous power. 
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChefV2 is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;         // How many LP tokens the user has provided.
        uint256 rewardDebt;     // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of DragonEggs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accDragonEggPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accDragonEggPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. DragonEggs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that DragonEggs distribution occurs.
        uint256 accDragonEggPerShare;   // Accumulated DragonEggs per share, times 1e12. See below.
        uint16 depositFeeBP;      // Deposit fee in basis points
        uint256 lpSupply;
    }

    uint256 public constant dragonEggMaximumSupply = 250 * (10 ** 3) * (10 ** 18);

    uint256 public constant dragonEggPreMint = 1 * (10 ** 3) * (10 ** 18);

    // The DragonEgg TOKEN!
    DragonEggToken public dragonEgg;
    // DragonEgg tokens created per block.
    uint256 public dragonEggPerBlock;
    // Deposit Fee address
    address public feeAddress;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when DragonEgg mining starts.
    uint256 public startBlock;
    // The block number when DragonEgg mining ends.
    uint256 public emmissionEndBlock = type(uint256).max;

    event addPool(uint256 indexed pid, address lpToken, uint256 allocPoint, uint256 depositFeeBP);
    event setPool(uint256 indexed pid, address lpToken, uint256 allocPoint, uint256 depositFeeBP);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetFeeAddress(address indexed user, address indexed newAddress);
    event UpdateStartBlock(uint256 newStartBlock);

    constructor(
        DragonEggToken _dragonEgg,
        address _feeAddress,
        uint256 _dragonEggPerBlock,
        uint256 _startBlock
    ) {
        dragonEgg = _dragonEgg;
        feeAddress = _feeAddress;
        dragonEggPerBlock = _dragonEggPerBlock;
        startBlock = _startBlock;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    mapping(IERC20 => bool) public poolExistence;
    modifier nonDuplicated(IERC20 _lpToken) {
        require(poolExistence[_lpToken] == false, "nonDuplicated: duplicated");
        _;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(uint256 _allocPoint, IERC20 _lpToken, uint16 _depositFeeBP, bool _withUpdate) external onlyOwner nonDuplicated(_lpToken) {
        // Make sure the provided token is ERC20
        _lpToken.balanceOf(address(this));

        require(_depositFeeBP <= 301, "add: invalid deposit fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint + _allocPoint;
        poolExistence[_lpToken] = true;

        poolInfo.push(PoolInfo({
            lpToken : _lpToken,
            allocPoint : _allocPoint,
            lastRewardBlock : lastRewardBlock,
            accDragonEggPerShare : 0,
            depositFeeBP : _depositFeeBP,
            lpSupply: 0
        }));

        emit addPool(poolInfo.length - 1, address(_lpToken), _allocPoint, _depositFeeBP);
    }

    // Update the given pool's DragonEgg allocation point and deposit fee. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP, bool _withUpdate) external onlyOwner {
        require(_depositFeeBP <= 301, "set: invalid deposit fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint - poolInfo[_pid].allocPoint + _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;

        emit setPool(_pid, address(poolInfo[_pid].lpToken), _allocPoint, _depositFeeBP);
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        // As we set the multiplier to 0 here after emmissionEndBlock
        // deposits aren't blocked after farming ends.
        if (_from > emmissionEndBlock)
            return 0;
        if (_to > emmissionEndBlock)
            return emmissionEndBlock - _from;
        else
            return _to - _from;
    }

    // View function to see pending DragonEggs on frontend.
    function pendingDragonEgg(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accDragonEggPerShare = pool.accDragonEggPerShare;
        if (block.number > pool.lastRewardBlock && pool.lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 dragonEggReward = (multiplier * dragonEggPerBlock * pool.allocPoint) / totalAllocPoint;
            accDragonEggPerShare = accDragonEggPerShare + ((dragonEggReward * 1e12) / pool.lpSupply);
        }

        return ((user.amount * accDragonEggPerShare) /  1e12) - user.rewardDebt;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }

        if (pool.lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }

        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 dragonEggReward = (multiplier * dragonEggPerBlock * pool.allocPoint) / totalAllocPoint;

        // This shouldn't happen, but just in case we stop rewards.
        if (dragonEgg.totalSupply() > dragonEggMaximumSupply)
            dragonEggReward = 0;
        else if ((dragonEgg.totalSupply() + dragonEggReward) > dragonEggMaximumSupply)
            dragonEggReward = dragonEggMaximumSupply - dragonEgg.totalSupply();

        if (dragonEggReward > 0)
        {
            dragonEgg.mint(feeAddress, dragonEggReward / 10);
            dragonEgg.mint(address(this), dragonEggReward);
        }


        // The first time we reach the Dragon Eggs max supply we solidify the end of farming.
        if (dragonEgg.totalSupply() >= dragonEggMaximumSupply && emmissionEndBlock == type(uint256).max)
            emmissionEndBlock = block.number;

        pool.accDragonEggPerShare = pool.accDragonEggPerShare + ((dragonEggReward * 1e12) / pool.lpSupply);
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for Dragon Egg allocation.
    function deposit(uint256 _pid, uint256 _amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = ((user.amount * pool.accDragonEggPerShare) / 1e12) - user.rewardDebt;
            if (pending > 0) {
                safeDragonEggTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            uint256 balanceBefore = pool.lpToken.balanceOf(address(this));
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            _amount = pool.lpToken.balanceOf(address(this)) - balanceBefore;
            require(_amount > 0, "we dont accept deposits of 0 size");

            if (pool.depositFeeBP > 0) {
                uint256 depositFee = (_amount * pool.depositFeeBP) / 10000;
                pool.lpToken.safeTransfer(feeAddress, depositFee);
                user.amount = user.amount + _amount - depositFee;
                pool.lpSupply = pool.lpSupply + _amount - depositFee;
            } else {
                user.amount = user.amount + _amount;
                pool.lpSupply = pool.lpSupply + _amount;
            }
        }
        user.rewardDebt = (user.amount * pool.accDragonEggPerShare) / 1e12;

        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = ((user.amount * pool.accDragonEggPerShare) / 1e12) - user.rewardDebt;
        if (pending > 0) {
            safeDragonEggTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount - _amount;
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
            pool.lpSupply = pool.lpSupply - _amount;
        }
        user.rewardDebt = (user.amount * pool.accDragonEggPerShare) / 1e12;
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);

        // In the case of an accounting error, we choose to let the user emergency withdraw anyway
        if (pool.lpSupply >=  amount)
            pool.lpSupply = pool.lpSupply - amount;
        else
            pool.lpSupply = 0;

        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe dragonEgg transfer function, just in case if rounding error causes pool to not have enough DragonEggs.
    function safeDragonEggTransfer(address _to, uint256 _amount) internal {
        uint256 dragonEggBal = dragonEgg.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > dragonEggBal) {
            transferSuccess = dragonEgg.transfer(_to, dragonEggBal);
        } else {
            transferSuccess = dragonEgg.transfer(_to, _amount);
        }
        require(transferSuccess, "safeDragonEggTransfer: transfer failed");
    }

    function setFeeAddress(address _feeAddress) external {
        require(msg.sender == feeAddress, "setFeeAddress: FORBIDDEN");
        require(_feeAddress != address(0), "!nonzero");
        feeAddress = _feeAddress;
        emit SetFeeAddress(msg.sender, _feeAddress);
    }

    function setStartBlock(uint256 _newStartBlock) external onlyOwner {
        require(poolInfo.length == 0, "no changing start block after pools have been added");
        require(block.number < startBlock, "cannot change start block if sale has already commenced");
        require(block.number < _newStartBlock, "cannot set start block in the past");
        startBlock = _newStartBlock;

        emit UpdateStartBlock(startBlock);
    }
}
