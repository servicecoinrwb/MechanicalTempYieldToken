/**
 *Submitted for verification at Arbiscan.io on 2025-10-25
*/

// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/*//////////////////////////////////////////////////////////////
                             INTERFACES
//////////////////////////////////////////////////////////////*/
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address a) external view returns (uint256);
    function allowance(address a, address b) external view returns (uint256);
    function approve(address s, uint256 a) external returns (bool);
    function transfer(address d, uint256 a) external returns (bool);
    function transferFrom(address s, address d, uint256 a) external returns (bool);
    function decimals() external view returns (uint8);
}

interface IMTYLDVault {
    // USD per MTYLD in 1e18
    function pricePerToken() external view returns (uint256);
}

/*//////////////////////////////////////////////////////////////
                             LIBRARIES
//////////////////////////////////////////////////////////////*/
library AddressLib {
    function isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }
}

library SafeERC20 {
    using AddressLib for address;
    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _call(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }
    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _call(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }
    function safeApprove(IERC20 token, address spender, uint256 value) internal {
        _call(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }
    function _call(IERC20 token, bytes memory data) private {
        require(address(token).isContract(), "SafeERC20: non-contract");
        (bool ok, bytes memory ret) = address(token).call(data);
        require(ok, "SafeERC20: call failed");
        if (ret.length > 0) require(abi.decode(ret,(bool)), "SafeERC20: op failed");
    }
}

// Full-precision mulDiv from Uniswap/Remco Bloemen pattern (adapted for 0.8.x)
library FullMath {
    function mulDiv(
        uint256 a,
        uint256 b,
        uint256 denominator
    ) internal pure returns (uint256 result) {
        unchecked {
            uint256 prod0; // Least significant 256 bits
            uint256 prod1; // Most significant 256 bits
            assembly {
                let mm := mulmod(a, b, not(0))
                prod0 := mul(a, b)
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }
            if (prod1 == 0) {
                require(denominator > 0, "div0");
                return prod0 / denominator;
            }
            require(denominator > prod1, "overflow");
            uint256 remainder;
            assembly {
                remainder := mulmod(a, b, denominator)
                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)
            }
            uint256 twos = denominator & (~denominator + 1);
            assembly {
                denominator := div(denominator, twos)
                prod0 := div(prod0, twos)
                twos := add(div(sub(0, twos), twos), 1)
            }
            prod0 |= prod1 * twos;
            uint256 inv = 3 * denominator ^ 2;
            inv *= 2 - denominator * inv;
            inv *= 2 - denominator * inv;
            inv *= 2 - denominator * inv;
            inv *= 2 - denominator * inv;
            inv *= 2 - denominator * inv;
            inv *= 2 - denominator * inv;
            result = prod0 * inv;
            return result;
        }
    }
}

/*//////////////////////////////////////////////////////////////
                  OWNABLE / ROLES / REENTRANCY / PAUSE
//////////////////////////////////////////////////////////////*/
abstract contract Ownable {
    address public owner;
    event OwnershipTransferred(address indexed prev, address indexed next);
    constructor() { owner = msg.sender; emit OwnershipTransferred(address(0), msg.sender); }
    modifier onlyOwner() { require(msg.sender == owner, "not owner"); _; }
    function transferOwnership(address n) external onlyOwner {
        require(n != address(0), "zero addr");
        emit OwnershipTransferred(owner, n);
        owner = n;
    }
}

abstract contract ReentrancyGuard {
    uint256 private _s = 1;
    modifier nonReentrant() { require(_s == 1, "reentrant"); _s = 2; _; _s = 1; }
}

abstract contract Pausable is Ownable {
    bool public paused;
    event Paused(address indexed by);
    event Unpaused(address indexed by);
    modifier whenNotPaused(){ require(!paused, "paused"); _; }
    function pause() external onlyOwner { paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner { paused = false; emit Unpaused(msg.sender); }
}

/*//////////////////////////////////////////////////////////////
                     LENDING VAULT (GATED) V3
//////////////////////////////////////////////////////////////*/
contract LendingVaultGatedV3 is Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*=============================
                CONSTANTS
    =============================*/
    uint256 public constant USD_18 = 1e18;
    uint256 public constant USDC_6 = 1e6;

    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    /*=============================
               CONFIG / ROLES
    =============================*/
    IERC20 public immutable USDC;           // 6 decimals
    IERC20 public immutable MTYLD;          // 18 decimals
    IMTYLDVault public immutable MTYLD_VAULT;

    address public treasury;       // Gnosis Safe (funds borrows / receives repays)
    address public rateGuardian;   // APR/LTV tuning within bounds
    address public riskGuardian;   // liquidation toggles/params

    mapping(address => bool) public isWhitelisted;

    // Rates / thresholds (bps)
    uint16 public aprBps = 800;               // 8% APR
    uint16 public maxLtvBps = 7000;           // 70% max LTV
    uint16 public liqThresholdBps = 8000;     // 80% liquidation threshold
    uint16 public liqBonusBps = 500;          // 5% standard liq bonus

    // Severe liquidation (hard close)
    uint16 public severeLiqThresholdBps = 9000;// 90%
    uint16 public severeLiqBonusBps = 1000;    // 10% (capped)
    bool   public severePublic = false;

    // One-time late fee after maturity (bps of principal)
    uint16 public lateFeeBpsFlat = 200;        // 2%

    // Bounds
    uint16 public constant APR_MAX_BPS = 2000; // <=20%
    uint16 public constant MAX_BPS_U16 = 10_000;

    // Liquidation toggle
    bool public liquidationPaused = false;

    /*=============================
                  CREDIT
    =============================*/
    struct CreditScore {
        uint32 score;       // 0..1000
        uint32 lastUpdated; // unix ts
    }
    mapping(address => CreditScore) public creditScore;

    /*=============================
                 LOANS
    =============================*/
    struct Loan {
        uint256 principalUSDC_6;
        uint256 interestUSDC_6;
        uint256 lateFeesUSDC_6;
        uint64  start;
        uint64  maturity;      // 0 = open ended
        bool    lateFeeApplied;
        bool    active;
    }
    mapping(address => Loan) public loans;

    // Collateral (MTYLD 18d)
    mapping(address => uint256) public collateralMTYLD_18;

    /*=============================
                 EVENTS
    =============================*/
    event RolesUpdated(address treasury, address rateGuardian, address riskGuardian);
    event WhitelistSet(address indexed user, bool allowed);

    event ParamsUpdated(uint16 aprBps, uint16 maxLtvBps, uint16 liqThresholdBps, uint16 liqBonusBps);
    event SevereParamsUpdated(uint16 severeLiqThresholdBps, uint16 severeLiqBonusBps, bool severePublic);
    event LateFeeUpdated(uint16 lateFeeBpsFlat);
    event LiquidationPaused(bool on);

    event CollateralDeposited(address indexed user, uint256 mtyldAmount_18);
    event CollateralWithdrawn(address indexed user, uint256 mtyldAmount_18);
    event Borrowed(address indexed user, uint256 usdcAmount_6, uint64 start, uint64 maturity);
    event Repaid(address indexed user, uint256 repaidUSDC_6, uint256 principalLeft_6);
    event Accrued(address indexed user, uint256 interestAccrued_6, bool lateFeeApplied);

    event Liquidated(
        address indexed liquidator,
        address indexed user,
        uint256 repayUSDC_6,
        uint256 seizeMTYLD_18,
        uint256 price18,
        uint16  bonusBps,
        bool    severe
    );
    event SevereResidualSent(address indexed user, uint256 residualMTYLD_18);

    /*=============================
                 ERRORS
    =============================*/
    error NotWhitelisted();
    error BadAddress();
    error BadAmount();
    error Healthy();
    error NotSevere();
    error Slippage();
    error OverLTV();
    error TooEarly();
    error NotActive();
    error NotOwnerGuardian();

    /*=============================
               CONSTRUCTOR
    =============================*/
    constructor(address usdc, address mtyld, address mtyldVault, address _treasury) {
        if (usdc == address(0) || mtyld == address(0) || mtyldVault == address(0) || _treasury == address(0)) revert BadAddress();
        USDC = IERC20(usdc);
        MTYLD = IERC20(mtyld);
        MTYLD_VAULT = IMTYLDVault(mtyldVault);
        treasury = _treasury;
        creditScore[msg.sender] = CreditScore({score: 600, lastUpdated: uint32(block.timestamp)});
    }

    /*=============================
                 ROLES
    =============================*/
    modifier onlyOwnerOrGuardian() {
        if (msg.sender != owner && msg.sender != rateGuardian && msg.sender != riskGuardian) revert NotOwnerGuardian();
        _;
    }

    function setRoles(address _treasury, address _rate, address _risk) external onlyOwner {
        if (_treasury == address(0)) revert BadAddress();
        treasury = _treasury;
        rateGuardian = _rate;
        riskGuardian = _risk;
        emit RolesUpdated(_treasury, _rate, _risk);
    }

    function setWhitelist(address user, bool allowed) external onlyOwner {
        isWhitelisted[user] = allowed;
        emit WhitelistSet(user, allowed);
    }

    /*=============================
               PARAM TUNING
    =============================*/
    function setParams(uint16 _aprBps, uint16 _maxLtvBps, uint16 _liqThresholdBps, uint16 _liqBonusBps) external onlyOwnerOrGuardian {
        require(_aprBps <= APR_MAX_BPS, "apr too high");
        require(_maxLtvBps <= 9000, "maxLTV too high");
        require(_liqThresholdBps > _maxLtvBps && _liqThresholdBps <= 9500, "bad threshold");
        require(_liqBonusBps <= 2000, "bonus too high");
        aprBps = _aprBps;
        maxLtvBps = _maxLtvBps;
        liqThresholdBps = _liqThresholdBps;
        liqBonusBps = _liqBonusBps;
        emit ParamsUpdated(_aprBps, _maxLtvBps, _liqThresholdBps, _liqBonusBps);
    }

    function setSevereParams(uint16 _sevThreshBps, uint16 _sevBonusBps, bool _public) external onlyOwnerOrGuardian {
        require(_sevThreshBps > liqThresholdBps && _sevThreshBps <= 9900, "bad severe threshold");
        require(_sevBonusBps >= liqBonusBps && _sevBonusBps <= 2000, "severe bonus too high");
        severeLiqThresholdBps = _sevThreshBps;
        severeLiqBonusBps = _sevBonusBps;
        severePublic = _public;
        emit SevereParamsUpdated(_sevThreshBps, _sevBonusBps, _public);
    }

    function setLateFeeBps(uint16 _lateFeeBpsFlat) external onlyOwnerOrGuardian {
        require(_lateFeeBpsFlat <= 2000, "late fee too high");
        lateFeeBpsFlat = _lateFeeBpsFlat;
        emit LateFeeUpdated(_lateFeeBpsFlat);
    }

    function setLiquidationPaused(bool on) external onlyOwnerOrGuardian {
        liquidationPaused = on;
        emit LiquidationPaused(on);
    }

    /*=============================
             PRICE & VALUATION
    =============================*/
    function mtyldUsdPrice_18() public view returns (uint256) {
        uint256 p = MTYLD_VAULT.pricePerToken(); // 1e18 USD per MTYLD
        require(p > 0, "price=0");
        return p;
    }

    function collateralUsd_18(address user) public view returns (uint256) {
        uint256 price18 = MTYLD_VAULT.pricePerToken();
        uint256 c = collateralMTYLD_18[user];
        return FullMath.mulDiv(c, price18, USD_18);
    }

    function debtUsd_18(address user) public view returns (uint256) {
        Loan memory L = loans[user];
        uint256 total6 = L.principalUSDC_6 + L.interestUSDC_6 + L.lateFeesUSDC_6;
        return FullMath.mulDiv(total6, USD_18, USDC_6);
    }

    function ltvBps(address user) public view returns (uint16) {
        uint256 debt18 = debtUsd_18(user);
        if (debt18 == 0) return 0;
        uint256 coll18 = collateralUsd_18(user);
        if (coll18 == 0) return MAX_BPS_U16;
        uint256 bps = FullMath.mulDiv(debt18, BPS_DENOMINATOR, coll18);
        return bps > BPS_DENOMINATOR ? MAX_BPS_U16 : uint16(bps);
    }

    /*=============================
          INTERNAL: ACCRUAL/LATE
    =============================*/
    function _accrue(address user) internal {
        Loan storage L = loans[user];
        if (!L.active) return;

        uint256 principal = L.principalUSDC_6;
        if (principal == 0) { L.start = uint64(block.timestamp); return; }

        uint256 elapsed = block.timestamp - L.start; // seconds
        if (elapsed > 0 && aprBps > 0) {
            uint256 interestPart = FullMath.mulDiv(principal, aprBps, BPS_DENOMINATOR);
            uint256 interest = FullMath.mulDiv(interestPart, elapsed, SECONDS_PER_YEAR);
            L.interestUSDC_6 += interest;
            L.start = uint64(block.timestamp);
            emit Accrued(user, interest, false);
        }

        if (L.maturity != 0 && block.timestamp > L.maturity && !L.lateFeeApplied && lateFeeBpsFlat > 0) {
            uint256 fee = FullMath.mulDiv(L.principalUSDC_6, lateFeeBpsFlat, BPS_DENOMINATOR);
            L.lateFeesUSDC_6 += fee;
            L.lateFeeApplied = true;
            emit Accrued(user, 0, true);
        }
    }

    /*=============================
         USER: COLLATERAL FLOWS
    =============================*/
    function depositCollateral(uint256 amountMTYLD_18) external nonReentrant whenNotPaused {
        if (!isWhitelisted[msg.sender]) revert NotWhitelisted();
        if (amountMTYLD_18 == 0) revert BadAmount();
        collateralMTYLD_18[msg.sender] += amountMTYLD_18;
        MTYLD.safeTransferFrom(msg.sender, address(this), amountMTYLD_18);
        emit CollateralDeposited(msg.sender, amountMTYLD_18);
    }

    function withdrawCollateral(uint256 amountMTYLD_18) external nonReentrant whenNotPaused {
        if (amountMTYLD_18 == 0) revert BadAmount();
        _accrue(msg.sender);

        uint256 old = collateralMTYLD_18[msg.sender];
        require(old >= amountMTYLD_18, "insufficient collat");

        collateralMTYLD_18[msg.sender] = old - amountMTYLD_18;
        uint16 ltv = ltvBps(msg.sender);
        require(ltv <= maxLtvBps, "ltv too high");

        MTYLD.safeTransfer(msg.sender, amountMTYLD_18);
        emit CollateralWithdrawn(msg.sender, amountMTYLD_18);
    }

    /*=============================
             USER: BORROW / REPAY
    =============================*/
    function borrow(uint256 usdcAmount_6, uint64 maturity) external nonReentrant whenNotPaused {
        if (!isWhitelisted[msg.sender]) revert NotWhitelisted();
        if (usdcAmount_6 == 0) revert BadAmount();
        if (maturity != 0) require(maturity > block.timestamp, "bad maturity");

        _accrue(msg.sender);

        Loan storage L = loans[msg.sender];

        // Effects
        L.principalUSDC_6 += usdcAmount_6;
        L.active = true;
        L.start = uint64(block.timestamp);
        L.maturity = maturity;

        // Post-borrow LTV constraint
        uint16 ltv = ltvBps(msg.sender);
        require(ltv <= maxLtvBps, "ltv too high");

        // *** FIX: route USDC from Treasury and surface explicit errors before SafeERC20
        uint256 treBal = USDC.balanceOf(treasury);
        require(treBal >= usdcAmount_6, "treasury balance low");
        uint256 treAllow = USDC.allowance(treasury, address(this));
        require(treAllow >= usdcAmount_6, "treasury allowance low");

        USDC.safeTransferFrom(treasury, msg.sender, usdcAmount_6); // treasury -> borrower
        emit Borrowed(msg.sender, usdcAmount_6, L.start, maturity);
    }

    function repay(uint256 usdcAmount_6) external nonReentrant whenNotPaused {
        if (usdcAmount_6 == 0) revert BadAmount();

        _accrue(msg.sender);

        Loan storage L = loans[msg.sender];
        if (!L.active) revert NotActive();

        uint256 pay = usdcAmount_6;

        uint256 take;
        take = pay > L.lateFeesUSDC_6 ? L.lateFeesUSDC_6 : pay; L.lateFeesUSDC_6 -= take; pay -= take;
        take = pay > L.interestUSDC_6 ? L.interestUSDC_6 : pay; L.interestUSDC_6 -= take; pay -= take;
        take = pay > L.principalUSDC_6 ? L.principalUSDC_6 : pay; L.principalUSDC_6 -= take;

        bool fullyCleared = (L.principalUSDC_6 == 0 && L.interestUSDC_6 == 0 && L.lateFeesUSDC_6 == 0);
        if (fullyCleared) {
            L.active = false;
            L.maturity = 0;
            L.lateFeeApplied = false;
        }

        // *** FIX: send USDC directly to Treasury (borrower -> treasury)
        USDC.safeTransferFrom(msg.sender, treasury, usdcAmount_6);

        if (fullyCleared) _bumpCreditOnGoodRepay(msg.sender);
        emit Repaid(msg.sender, usdcAmount_6, L.principalUSDC_6);
    }

    /*=============================
               CREDIT SCORE
    =============================*/
    function _bumpCreditOnGoodRepay(address user) internal {
        CreditScore storage C = creditScore[user];
        uint32 s = C.score;
        s = s + 10 > 1000 ? 1000 : s + 10;
        C.score = s;
        C.lastUpdated = uint32(block.timestamp);
    }

    function _penalizeOnSevere(address user) internal {
        CreditScore storage C = creditScore[user];
        uint32 s = C.score;
        C.score = s > 50 ? s - 50 : 0;
        C.lastUpdated = uint32(block.timestamp);
    }

    /*=============================
             HEALTH CHECKS
    =============================*/
    function canBeLiquidated(address user) public view returns (bool) {
        return ltvBps(user) >= liqThresholdBps;
    }
    function canBeSeverelyLiquidated(address user) public view returns (bool) {
        return ltvBps(user) >= severeLiqThresholdBps;
    }

    function liquidationAmountUSDC_6(address user) public view returns (uint256) {
        Loan memory L = loans[user];
        return L.principalUSDC_6 + L.interestUSDC_6 + L.lateFeesUSDC_6;
    }

    /*=============================
                LIQUIDATIONS
    =============================*/
    function liquidate(address user, uint256 repayUSDC_6, uint256 minSeizeMTYLD_18) external nonReentrant {
        if (liquidationPaused) revert TooEarly();
        if (repayUSDC_6 == 0) revert BadAmount();
        if (!canBeLiquidated(user)) revert Healthy();

        _accrue(user);

        Loan storage L = loans[user];
        uint256 total = L.principalUSDC_6 + L.interestUSDC_6 + L.lateFeesUSDC_6;
        require(total > 0, "no debt");
        require(repayUSDC_6 <= total, "over repay");

        uint256 price18 = mtyldUsdPrice_18();

        uint256 repayUSD_18 = FullMath.mulDiv(repayUSDC_6, USD_18, USDC_6);
        uint256 usdWithBonus_18 = FullMath.mulDiv(repayUSD_18, BPS_DENOMINATOR + liqBonusBps, BPS_DENOMINATOR);
        uint256 seizeMTYLD_18 = FullMath.mulDiv(usdWithBonus_18, USD_18, price18);

        uint256 userColl = collateralMTYLD_18[user];
        if (seizeMTYLD_18 > userColl) seizeMTYLD_18 = userColl;
        if (seizeMTYLD_18 < minSeizeMTYLD_18) revert Slippage();

        uint256 pay = repayUSDC_6;
        uint256 take;
        take = pay > L.lateFeesUSDC_6 ? L.lateFeesUSDC_6 : pay; L.lateFeesUSDC_6 -= take; pay -= take;
        take = pay > L.interestUSDC_6 ? L.interestUSDC_6 : pay; L.interestUSDC_6 -= take; pay -= take;
        take = pay > L.principalUSDC_6 ? L.principalUSDC_6 : pay; L.principalUSDC_6 -= take;

        collateralMTYLD_18[user] = userColl - seizeMTYLD_18;

        // *** FIX: liquidator pays Treasury (not this contract)
        USDC.safeTransferFrom(msg.sender, treasury, repayUSDC_6);
        MTYLD.safeTransfer(msg.sender, seizeMTYLD_18);

        emit Liquidated(msg.sender, user, repayUSDC_6, seizeMTYLD_18, price18, liqBonusBps, false);
    }

    function severeLiquidate(address user, uint256 minSeizeMTYLD_18) external nonReentrant {
        if (liquidationPaused) revert TooEarly();
        if (!canBeSeverelyLiquidated(user)) revert NotSevere();
        if (!severePublic && msg.sender != owner && msg.sender != riskGuardian) revert NotOwnerGuardian();

        _accrue(user);

        Loan storage L = loans[user];
        uint256 totalDebtUSDC_6 = L.principalUSDC_6 + L.interestUSDC_6 + L.lateFeesUSDC_6;
        require(totalDebtUSDC_6 > 0, "no debt");

        uint256 price18 = mtyldUsdPrice_18();

        uint256 totalDebtUSD_18 = FullMath.mulDiv(totalDebtUSDC_6, USD_18, USDC_6);
        uint256 usdWithBonus_18 = FullMath.mulDiv(totalDebtUSD_18, BPS_DENOMINATOR + severeLiqBonusBps, BPS_DENOMINATOR);
        uint256 seizeMTYLD_18 = FullMath.mulDiv(usdWithBonus_18, USD_18, price18);

        uint256 userColl = collateralMTYLD_18[user];
        if (seizeMTYLD_18 > userColl) seizeMTYLD_18 = userColl;
        if (seizeMTYLD_18 < minSeizeMTYLD_18) revert Slippage();

        L.principalUSDC_6 = 0;
        L.interestUSDC_6  = 0;
        L.lateFeesUSDC_6  = 0;
        L.active          = false;
        L.maturity        = 0;
        L.lateFeeApplied  = false;

        collateralMTYLD_18[user] = userColl - seizeMTYLD_18;

        // *** FIX: liquidator pays Treasury (not this contract)
        USDC.safeTransferFrom(msg.sender, treasury, totalDebtUSDC_6);
        MTYLD.safeTransfer(msg.sender, seizeMTYLD_18);

        uint256 residual = collateralMTYLD_18[user];
        if (residual > 0) {
            collateralMTYLD_18[user] = 0;
            MTYLD.safeTransfer(treasury, residual);
            emit SevereResidualSent(user, residual);
        }

        _penalizeOnSevere(user);
        emit Liquidated(msg.sender, user, totalDebtUSDC_6, seizeMTYLD_18, price18, severeLiqBonusBps, true);
    }

    /*=============================
         ADMIN: CREDIT NUDGES
    =============================*/
    function adminSetCredit(address user, uint32 score) external onlyOwnerOrGuardian {
        require(score <= 1000, "bad score");
        creditScore[user] = CreditScore({score: score, lastUpdated: uint32(block.timestamp)});
    }

    /*=============================
           VIEW: USER SNAPSHOT
    =============================*/
    struct UserView {
        uint256 collateralMTYLD_18;
        uint256 collateralUSD_18;
        uint256 principalUSDC_6;
        uint256 interestUSDC_6;
        uint256 lateFeesUSDC_6;
        uint256 debtUSD_18;
        uint16  ltvBps;
        uint32  creditScore;
        uint64  maturity;
        bool    active;
    }

    function userView(address user) external view returns (UserView memory V) {
        Loan memory L = loans[user];
        V.collateralMTYLD_18 = collateralMTYLD_18[user];
        V.collateralUSD_18   = collateralUsd_18(user);
        V.principalUSDC_6    = L.principalUSDC_6;
        V.interestUSDC_6     = L.interestUSDC_6;
        V.lateFeesUSDC_6     = L.lateFeesUSDC_6;
        V.debtUSD_18         = debtUsd_18(user);
        V.ltvBps             = ltvBps(user);
        V.creditScore        = creditScore[user].score;
        V.maturity           = L.maturity;
        V.active             = L.active;
    }
}
