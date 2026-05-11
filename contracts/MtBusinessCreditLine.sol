// SPDX-License-Identifier: MIT
/**
 * MtBusinessCreditLine v3.0
 *
 * Changes from v2.1:
 *   - MTYLD added as second collateral type (70% LTV, USDC-stable via pricePerToken())
 *   - mtETH-S LTV reduced to 60% (ETH-correlated, higher volatility risk)
 *   - 30% collateral interest split proportional to USD value of each pool at repayment
 *   - Interest precision fix: ceiling division prevents truncation to zero on small/short loans
 *   - Separate reward accumulators for mtETH-S and MTYLD collateral depositors
 *
 * ARCHITECTURE:
 *   SIDE A — USDC Depositors      → fund the pool, earn 70% of interest
 *   SIDE B — mtETH-S Depositors   → collateral (60% LTV), earn share of 30% interest
 *   SIDE C — MTYLD Depositors     → collateral (70% LTV), earn share of 30% interest
 *   BORROWER — Mechanical Temp    → draws USDC, repays principal + interest
 *
 *   The 30% collateral interest is split between SIDE B and SIDE C
 *   proportional to each pool's USD value at the time of repayment.
 */

pragma solidity ^0.8.25;

// ─────────────────────────────────────────────────────────────────────────────
// Interfaces
// ─────────────────────────────────────────────────────────────────────────────

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IChainlink {
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
}

/// @dev MTYLD vault — pricePerToken() returns USDC/MTYLD in 18-decimal fixed point
///      e.g. 1.000001 USDC per MTYLD → 1000001000000000000
interface IMtyldVault {
    function pricePerToken() external view returns (uint256);
}

// ─────────────────────────────────────────────────────────────────────────────
// Base contracts
// ─────────────────────────────────────────────────────────────────────────────

abstract contract ReentrancyGuard {
    uint256 private _status = 1;
    modifier nonReentrant() {
        require(_status == 1, "Reentrant");
        _status = 2;
        _;
        _status = 1;
    }
}

abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(address o) {
        _owner = o;
        emit OwnershipTransferred(address(0), o);
    }

    modifier onlyOwner() { require(msg.sender == _owner, "Not owner"); _; }

    function owner() public view returns (address) { return _owner; }

    function transferOwnership(address n) public onlyOwner {
        require(n != address(0), "Zero address");
        emit OwnershipTransferred(_owner, n);
        _owner = n;
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main contract
// ─────────────────────────────────────────────────────────────────────────────

contract MtBusinessCreditLine is Ownable, ReentrancyGuard {

    // ── LTV per collateral type ───────────────────────────────
    uint256 public constant MTETHS_LTV_BPS       = 6000;  // 60% — ETH-correlated, more volatile
    uint256 public constant MTYLD_LTV_BPS         = 7000;  // 70% — USDC-stable, revenue-backed
    uint256 public constant MAX_TERM_DAYS         = 90;
    uint256 public constant BPS_DENOMINATOR       = 10000;
    uint256 public constant USDC_SHARE_BPS        = 7000;  // 70% of interest → USDC depositors
    uint256 public constant COLLATERAL_SHARE_BPS  = 3000;  // 30% of interest → collateral depositors

    // ── Tokens & oracles ─────────────────────────────────────
    IERC20      public immutable mtETHS;
    IERC20      public immutable mtyld;
    IERC20      public immutable usdc;
    IChainlink  public immutable ethUsdFeed;
    IMtyldVault public immutable mtyldVault;

    // ── Borrower ──────────────────────────────────────────────
    address public borrower;
    uint256 public interestRateBps = 800; // 8% APR

    // ── SIDE A: USDC Depositors ───────────────────────────────
    mapping(address => uint256) public usdcDeposited;
    uint256 public totalUsdcDeposited;
    uint256 public usdcRewardPerTokenStored;
    mapping(address => uint256) public usdcRewardPerTokenPaid;
    mapping(address => uint256) public usdcPendingRewards;
    address[] private _usdcDepositors;
    mapping(address => bool) private _isUsdcDepositor;

    // ── SIDE B: mtETH-S Collateral Depositors ────────────────
    mapping(address => uint256) public collateralDeposited;    // mtETH-S (18 dec)
    uint256 public totalCollateralDeposited;
    uint256 public collateralRewardPerTokenStored;
    mapping(address => uint256) public collateralRewardPerTokenPaid;
    mapping(address => uint256) public collateralPendingRewards;
    address[] private _collateralDepositors;
    mapping(address => bool) private _isCollateralDepositor;

    // ── SIDE C: MTYLD Collateral Depositors ──────────────────
    mapping(address => uint256) public mtyldCollateralDeposited; // MTYLD (18 dec)
    uint256 public totalMtyldCollateral;
    uint256 public mtyldCollateralRewardPerTokenStored;
    mapping(address => uint256) public mtyldCollateralRewardPerTokenPaid;
    mapping(address => uint256) public mtyldCollateralPendingRewards;
    address[] private _mtyldCollateralDepositors;
    mapping(address => bool) private _isMtyldCollateralDepositor;

    // ── Loan ──────────────────────────────────────────────────
    struct Loan {
        uint256 principal;
        uint256 startTime;
        uint256 termSeconds;
        uint256 interestRateBps;
        bool    active;
    }
    Loan    public currentLoan;
    uint256 public totalInterestPaid;
    uint256 public totalLoansOriginated;

    // ── Pause ─────────────────────────────────────────────────
    bool public paused;

    // ── Events ────────────────────────────────────────────────
    event UsdcDeposited(address indexed user, uint256 amount);
    event UsdcWithdrawn(address indexed user, uint256 amount);
    event CollateralDeposited(address indexed user, uint256 amount, string collateralType);
    event CollateralWithdrawn(address indexed user, uint256 amount, string collateralType);
    event LoanOpened(uint256 principal, uint256 termDays, uint256 rateBps);
    event LoanRepaid(uint256 principal, uint256 interest);
    event InterestDistributed(uint256 toUsdcPool, uint256 toMtethsPool, uint256 toMtyldPool);
    event RewardClaimed(address indexed user, uint256 amount, string pool);
    event BorrowerSet(address indexed newBorrower);
    event RateUpdated(uint256 newRateBps);

    // ── Constructor ───────────────────────────────────────────

    constructor(
        address _mtETHS,
        address _mtyld,
        address _mtyldVault,
        address _usdc,
        address _ethUsdFeed,
        address _borrower
    ) Ownable(msg.sender) {
        require(
            _mtETHS != address(0) && _mtyld != address(0) &&
            _mtyldVault != address(0) && _usdc != address(0) &&
            _ethUsdFeed != address(0),
            "Zero address"
        );
        mtETHS     = IERC20(_mtETHS);
        mtyld      = IERC20(_mtyld);
        mtyldVault = IMtyldVault(_mtyldVault);
        usdc       = IERC20(_usdc);
        ethUsdFeed = IChainlink(_ethUsdFeed);
        borrower   = _borrower;
    }

    // ── Modifiers ─────────────────────────────────────────────

    modifier whenNotPaused() { require(!paused, "Paused"); _; }
    modifier onlyBorrower()  { require(msg.sender == borrower, "Not borrower"); _; }
    modifier noActiveLoan()  { require(!currentLoan.active, "Loan active"); _; }

    modifier updateUsdcReward(address user) {
        if (user != address(0)) {
            usdcPendingRewards[user] = earnedUsdc(user);
            usdcRewardPerTokenPaid[user] = usdcRewardPerTokenStored;
        }
        _;
    }

    modifier updateCollateralReward(address user) {
        if (user != address(0)) {
            collateralPendingRewards[user] = earnedCollateral(user);
            collateralRewardPerTokenPaid[user] = collateralRewardPerTokenStored;
        }
        _;
    }

    modifier updateMtyldCollateralReward(address user) {
        if (user != address(0)) {
            mtyldCollateralPendingRewards[user] = earnedMtyldCollateral(user);
            mtyldCollateralRewardPerTokenPaid[user] = mtyldCollateralRewardPerTokenStored;
        }
        _;
    }

    // ── Oracles & pricing ─────────────────────────────────────

    /// @notice ETH/USD price from Chainlink, scaled to 6 decimals (USDC-compatible)
    function ethPriceUsd6() public view returns (uint256) {
        (, int256 price,, uint256 updatedAt,) = ethUsdFeed.latestRoundData();
        require(price > 0, "Invalid price feed");
        require(block.timestamp - updatedAt <= 1 hours, "Stale price feed");
        return uint256(price) / 100; // Chainlink 8 dec → 6 dec
    }

    /// @notice MTYLD/USDC price from vault NAV, scaled to 6 decimals
    ///         pricePerToken() returns 18-decimal fixed point USDC per MTYLD
    function mtyldPriceUsd6() public view returns (uint256) {
        uint256 price18 = mtyldVault.pricePerToken();
        require(price18 > 0, "Invalid MTYLD price");
        return price18 / 1e12; // 18 dec → 6 dec
    }

    // ── Collateral USD values ─────────────────────────────────

    /// @notice USD value (6 dec) of all deposited mtETH-S collateral
    function collateralValueUsdc() public view returns (uint256) {
        if (totalCollateralDeposited == 0) return 0;
        return totalCollateralDeposited * ethPriceUsd6() / 1e18;
    }

    /// @notice USD value (6 dec) of all deposited MTYLD collateral
    function mtyldCollateralValueUsdc() public view returns (uint256) {
        if (totalMtyldCollateral == 0) return 0;
        // MTYLD is 18 dec, price is 6 dec → result is 6 dec
        return totalMtyldCollateral * mtyldPriceUsd6() / 1e18;
    }

    /// @notice Combined collateral value from both collateral types
    function totalCollateralValueUsdc() public view returns (uint256) {
        return collateralValueUsdc() + mtyldCollateralValueUsdc();
    }

    // ── Loan views ────────────────────────────────────────────

    function maxBorrowable() public view returns (uint256) {
        if (currentLoan.active) return 0;
        uint256 mtethsBacked = collateralValueUsdc()      * MTETHS_LTV_BPS / BPS_DENOMINATOR;
        uint256 mtyldBacked  = mtyldCollateralValueUsdc() * MTYLD_LTV_BPS  / BPS_DENOMINATOR;
        uint256 totalBacked  = mtethsBacked + mtyldBacked;
        uint256 usdcAvail    = usdc.balanceOf(address(this));
        return totalBacked < usdcAvail ? totalBacked : usdcAvail;
    }

    /// @notice Accrued interest with ceiling division to prevent truncation on small loans
    function accruedInterest() public view returns (uint256) {
        if (!currentLoan.active) return 0;
        uint256 elapsed     = block.timestamp - currentLoan.startTime;
        uint256 numerator   = currentLoan.principal * currentLoan.interestRateBps * elapsed;
        uint256 denominator = 365 days * BPS_DENOMINATOR;
        // Ceiling division: ensures at least 1 wei is charged to avoid zero-interest free loans
        return (numerator + denominator - 1) / denominator;
    }

    function amountDue() public view returns (uint256) {
        return currentLoan.principal + accruedInterest();
    }

    function isOverdue() public view returns (bool) {
        if (!currentLoan.active) return false;
        return block.timestamp > currentLoan.startTime + currentLoan.termSeconds;
    }

    function daysRemaining() public view returns (uint256) {
        if (!currentLoan.active) return 0;
        uint256 deadline = currentLoan.startTime + currentLoan.termSeconds;
        if (block.timestamp >= deadline) return 0;
        return (deadline - block.timestamp) / 86400;
    }

    // ── Reward views ──────────────────────────────────────────

    function earnedUsdc(address user) public view returns (uint256) {
        uint256 delta = usdcRewardPerTokenStored - usdcRewardPerTokenPaid[user];
        return usdcPendingRewards[user] + (usdcDeposited[user] * delta / 1e18);
    }

    function earnedCollateral(address user) public view returns (uint256) {
        uint256 delta = collateralRewardPerTokenStored - collateralRewardPerTokenPaid[user];
        return collateralPendingRewards[user] + (collateralDeposited[user] * delta / 1e18);
    }

    function earnedMtyldCollateral(address user) public view returns (uint256) {
        uint256 delta = mtyldCollateralRewardPerTokenStored - mtyldCollateralRewardPerTokenPaid[user];
        return mtyldCollateralPendingRewards[user] + (mtyldCollateralDeposited[user] * delta / 1e18);
    }

    function usdcShareOf(address user) external view returns (uint256) {
        if (totalUsdcDeposited == 0) return 0;
        return usdcDeposited[user] * 1e18 / totalUsdcDeposited;
    }

    function collateralShareOf(address user) external view returns (uint256) {
        if (totalCollateralDeposited == 0) return 0;
        return collateralDeposited[user] * 1e18 / totalCollateralDeposited;
    }

    function mtyldCollateralShareOf(address user) external view returns (uint256) {
        if (totalMtyldCollateral == 0) return 0;
        return mtyldCollateralDeposited[user] * 1e18 / totalMtyldCollateral;
    }

    // ── SIDE A: USDC Deposit / Withdraw ───────────────────────

    function depositUsdc(uint256 amount)
        external nonReentrant whenNotPaused updateUsdcReward(msg.sender)
    {
        require(amount > 0, "Amount must be > 0");
        usdc.transferFrom(msg.sender, address(this), amount);
        if (!_isUsdcDepositor[msg.sender]) {
            _usdcDepositors.push(msg.sender);
            _isUsdcDepositor[msg.sender] = true;
        }
        usdcDeposited[msg.sender] += amount;
        totalUsdcDeposited += amount;
        emit UsdcDeposited(msg.sender, amount);
    }

    function withdrawUsdc(uint256 amount)
        external nonReentrant noActiveLoan updateUsdcReward(msg.sender)
    {
        require(amount > 0, "Amount must be > 0");
        require(usdcDeposited[msg.sender] >= amount, "Insufficient balance");
        usdcDeposited[msg.sender] -= amount;
        totalUsdcDeposited -= amount;
        usdc.transfer(msg.sender, amount);
        emit UsdcWithdrawn(msg.sender, amount);
    }

    function exitUsdc()
        external nonReentrant noActiveLoan updateUsdcReward(msg.sender)
    {
        uint256 bal = usdcDeposited[msg.sender];
        if (bal > 0) {
            usdcDeposited[msg.sender] = 0;
            totalUsdcDeposited -= bal;
            usdc.transfer(msg.sender, bal);
            emit UsdcWithdrawn(msg.sender, bal);
        }
        _claimUsdcReward(msg.sender);
    }

    function claimUsdcRewards()
        external nonReentrant updateUsdcReward(msg.sender)
    {
        _claimUsdcReward(msg.sender);
    }

    // ── SIDE B: mtETH-S Collateral Deposit / Withdraw ─────────

    function depositCollateral(uint256 amount)
        external nonReentrant whenNotPaused updateCollateralReward(msg.sender)
    {
        require(amount > 0, "Amount must be > 0");
        mtETHS.transferFrom(msg.sender, address(this), amount);
        if (!_isCollateralDepositor[msg.sender]) {
            _collateralDepositors.push(msg.sender);
            _isCollateralDepositor[msg.sender] = true;
        }
        collateralDeposited[msg.sender] += amount;
        totalCollateralDeposited += amount;
        emit CollateralDeposited(msg.sender, amount, "mtETH-S");
    }

    function withdrawCollateral(uint256 amount)
        external nonReentrant noActiveLoan updateCollateralReward(msg.sender)
    {
        require(amount > 0, "Amount must be > 0");
        require(collateralDeposited[msg.sender] >= amount, "Insufficient balance");
        collateralDeposited[msg.sender] -= amount;
        totalCollateralDeposited -= amount;
        mtETHS.transfer(msg.sender, amount);
        emit CollateralWithdrawn(msg.sender, amount, "mtETH-S");
    }

    function exitCollateral()
        external nonReentrant noActiveLoan updateCollateralReward(msg.sender)
    {
        uint256 bal = collateralDeposited[msg.sender];
        if (bal > 0) {
            collateralDeposited[msg.sender] = 0;
            totalCollateralDeposited -= bal;
            mtETHS.transfer(msg.sender, bal);
            emit CollateralWithdrawn(msg.sender, bal, "mtETH-S");
        }
        _claimCollateralReward(msg.sender);
    }

    function claimCollateralRewards()
        external nonReentrant updateCollateralReward(msg.sender)
    {
        _claimCollateralReward(msg.sender);
    }

    // ── SIDE C: MTYLD Collateral Deposit / Withdraw ───────────

    function depositMtyldCollateral(uint256 amount)
        external nonReentrant whenNotPaused updateMtyldCollateralReward(msg.sender)
    {
        require(amount > 0, "Amount must be > 0");
        mtyld.transferFrom(msg.sender, address(this), amount);
        if (!_isMtyldCollateralDepositor[msg.sender]) {
            _mtyldCollateralDepositors.push(msg.sender);
            _isMtyldCollateralDepositor[msg.sender] = true;
        }
        mtyldCollateralDeposited[msg.sender] += amount;
        totalMtyldCollateral += amount;
        emit CollateralDeposited(msg.sender, amount, "MTYLD");
    }

    function withdrawMtyldCollateral(uint256 amount)
        external nonReentrant noActiveLoan updateMtyldCollateralReward(msg.sender)
    {
        require(amount > 0, "Amount must be > 0");
        require(mtyldCollateralDeposited[msg.sender] >= amount, "Insufficient balance");
        mtyldCollateralDeposited[msg.sender] -= amount;
        totalMtyldCollateral -= amount;
        mtyld.transfer(msg.sender, amount);
        emit CollateralWithdrawn(msg.sender, amount, "MTYLD");
    }

    function exitMtyldCollateral()
        external nonReentrant noActiveLoan updateMtyldCollateralReward(msg.sender)
    {
        uint256 bal = mtyldCollateralDeposited[msg.sender];
        if (bal > 0) {
            mtyldCollateralDeposited[msg.sender] = 0;
            totalMtyldCollateral -= bal;
            mtyld.transfer(msg.sender, bal);
            emit CollateralWithdrawn(msg.sender, bal, "MTYLD");
        }
        _claimMtyldCollateralReward(msg.sender);
    }

    function claimMtyldCollateralRewards()
        external nonReentrant updateMtyldCollateralReward(msg.sender)
    {
        _claimMtyldCollateralReward(msg.sender);
    }

    // ── Internal reward claims ────────────────────────────────

    function _claimUsdcReward(address user) internal {
        uint256 r = usdcPendingRewards[user];
        if (r > 0) {
            usdcPendingRewards[user] = 0;
            usdc.transfer(user, r);
            emit RewardClaimed(user, r, "usdc");
        }
    }

    function _claimCollateralReward(address user) internal {
        uint256 r = collateralPendingRewards[user];
        if (r > 0) {
            collateralPendingRewards[user] = 0;
            usdc.transfer(user, r);
            emit RewardClaimed(user, r, "mteths");
        }
    }

    function _claimMtyldCollateralReward(address user) internal {
        uint256 r = mtyldCollateralPendingRewards[user];
        if (r > 0) {
            mtyldCollateralPendingRewards[user] = 0;
            usdc.transfer(user, r);
            emit RewardClaimed(user, r, "mtyld");
        }
    }

    // ── Loan ──────────────────────────────────────────────────

    function openLoan(uint256 amount, uint256 termDays)
        external onlyBorrower nonReentrant whenNotPaused
    {
        require(!currentLoan.active, "Loan already active");
        require(amount > 0, "Amount must be > 0");
        require(termDays > 0 && termDays <= MAX_TERM_DAYS, "Invalid term: 1-90 days");
        require(totalCollateralDeposited > 0 || totalMtyldCollateral > 0, "No collateral deposited");
        require(totalUsdcDeposited > 0, "No USDC liquidity");
        require(amount <= maxBorrowable(), "Exceeds max borrowable");

        currentLoan = Loan({
            principal:       amount,
            startTime:       block.timestamp,
            termSeconds:     termDays * 86400,
            interestRateBps: interestRateBps,
            active:          true
        });

        totalLoansOriginated++;
        usdc.transfer(borrower, amount);

        emit LoanOpened(amount, termDays, interestRateBps);
    }

    /// @notice Full repayment. Interest split distributed to all three pools.
    function repayLoan() external onlyBorrower nonReentrant {
        require(currentLoan.active, "No active loan");

        uint256 principal = currentLoan.principal;
        uint256 interest  = accruedInterest();
        uint256 total     = principal + interest;

        usdc.transferFrom(msg.sender, address(this), total);

        currentLoan.active = false;
        totalInterestPaid += interest;

        _distributeInterest(interest);

        emit LoanRepaid(principal, interest);
    }

    /// @notice Partial repayment — interest distributed immediately, principal reduced.
    function repayPartial(uint256 amount) external onlyBorrower nonReentrant {
        require(currentLoan.active, "No active loan");
        require(amount > 0, "Amount must be > 0");

        uint256 interest = accruedInterest();
        uint256 due      = currentLoan.principal + interest;
        require(amount <= due, "Exceeds amount due");

        usdc.transferFrom(msg.sender, address(this), amount);

        uint256 interestPaid  = amount >= interest ? interest : amount;
        uint256 principalPaid = amount - interestPaid;

        if (interestPaid > 0) {
            totalInterestPaid += interestPaid;
            currentLoan.startTime = block.timestamp; // reset accrual window
            _distributeInterest(interestPaid);
        }

        currentLoan.principal -= principalPaid;

        if (currentLoan.principal == 0) {
            currentLoan.active = false;
            emit LoanRepaid(0, interestPaid);
        }
    }

    /// @notice Distribute interest:
    ///   70% → USDC depositors (per USDC deposited)
    ///   30% → collateral depositors split by USD collateral value at repayment time
    ///          mtETH-S share = 30% × (mtethsUsd / totalCollateralUsd)
    ///          MTYLD share   = 30% × (mtyldUsd  / totalCollateralUsd)
    function _distributeInterest(uint256 interest) internal {
        if (interest == 0) return;

        uint256 toUsdc       = interest * USDC_SHARE_BPS / BPS_DENOMINATOR;
        uint256 toCollateral = interest - toUsdc; // 30%

        // Distribute to USDC pool
        if (toUsdc > 0 && totalUsdcDeposited > 0) {
            usdcRewardPerTokenStored += toUsdc * 1e18 / totalUsdcDeposited;
        }

        // Split collateral portion by current USD value of each collateral pool
        uint256 mtethsUsd = collateralValueUsdc();
        uint256 mtyldUsd  = mtyldCollateralValueUsdc();
        uint256 totalColUsd = mtethsUsd + mtyldUsd;

        uint256 toMteths = 0;
        uint256 toMtyld  = 0;

        if (totalColUsd > 0 && toCollateral > 0) {
            toMteths = toCollateral * mtethsUsd / totalColUsd;
            toMtyld  = toCollateral - toMteths;
        } else if (toCollateral > 0) {
            // Edge: only one pool has deposits — give it all
            if (totalCollateralDeposited > 0) toMteths = toCollateral;
            else if (totalMtyldCollateral > 0) toMtyld  = toCollateral;
        }

        if (toMteths > 0 && totalCollateralDeposited > 0) {
            collateralRewardPerTokenStored += toMteths * 1e18 / totalCollateralDeposited;
        }

        if (toMtyld > 0 && totalMtyldCollateral > 0) {
            mtyldCollateralRewardPerTokenStored += toMtyld * 1e18 / totalMtyldCollateral;
        }

        emit InterestDistributed(toUsdc, toMteths, toMtyld);
    }

    // ── Admin ─────────────────────────────────────────────────

    function setBorrower(address newBorrower) external onlyOwner {
        require(newBorrower != address(0), "Zero address");
        borrower = newBorrower;
        emit BorrowerSet(newBorrower);
    }

    function setInterestRate(uint256 newRateBps) external onlyOwner {
        require(newRateBps <= 3000, "Max 30% APR");
        interestRateBps = newRateBps;
        emit RateUpdated(newRateBps);
    }

    function pause()   external onlyOwner { paused = true; }
    function unpause() external onlyOwner { paused = false; }

    function emergencySweep(address token, address to) external onlyOwner {
        require(
            token != address(mtETHS) || totalCollateralDeposited == 0,
            "Cannot sweep depositor mtETH-S"
        );
        require(
            token != address(mtyld) || totalMtyldCollateral == 0,
            "Cannot sweep depositor MTYLD"
        );
        uint256 bal = IERC20(token).balanceOf(address(this));
        require(bal > 0, "Nothing to sweep");
        IERC20(token).transfer(to, bal);
    }

    // ── View helpers ──────────────────────────────────────────

    function getUsdcDepositors()
        external view returns (address[] memory addrs, uint256[] memory balances)
    {
        addrs    = _usdcDepositors;
        balances = new uint256[](_usdcDepositors.length);
        for (uint256 i = 0; i < _usdcDepositors.length; i++) {
            balances[i] = usdcDeposited[_usdcDepositors[i]];
        }
    }

    function getCollateralDepositors()
        external view returns (address[] memory addrs, uint256[] memory balances)
    {
        addrs    = _collateralDepositors;
        balances = new uint256[](_collateralDepositors.length);
        for (uint256 i = 0; i < _collateralDepositors.length; i++) {
            balances[i] = collateralDeposited[_collateralDepositors[i]];
        }
    }

    function getMtyldCollateralDepositors()
        external view returns (address[] memory addrs, uint256[] memory balances)
    {
        addrs    = _mtyldCollateralDepositors;
        balances = new uint256[](_mtyldCollateralDepositors.length);
        for (uint256 i = 0; i < _mtyldCollateralDepositors.length; i++) {
            balances[i] = mtyldCollateralDeposited[_mtyldCollateralDepositors[i]];
        }
    }

    /// @notice Convenience: all collateral breakdown for UI
    function collateralSummary() external view returns (
        uint256 mtethsTokens,
        uint256 mtethsUsd,
        uint256 mtethsBorrowPower,
        uint256 mtyldTokens,
        uint256 mtyldUsd,
        uint256 mtyldBorrowPower,
        uint256 totalBorrowPower
    ) {
        mtethsTokens     = totalCollateralDeposited;
        mtethsUsd        = collateralValueUsdc();
        mtethsBorrowPower = mtethsUsd * MTETHS_LTV_BPS / BPS_DENOMINATOR;
        mtyldTokens      = totalMtyldCollateral;
        mtyldUsd         = mtyldCollateralValueUsdc();
        mtyldBorrowPower  = mtyldUsd * MTYLD_LTV_BPS / BPS_DENOMINATOR;
        totalBorrowPower  = mtethsBorrowPower + mtyldBorrowPower;
    }
}
