// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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

library MathX {
    function mulDivUp(uint256 a, uint256 b, uint256 d) internal pure returns (uint256) {
        if (a == 0 || b == 0) return 0;
        return (a * b + d - 1) / d;
    }
    function mulDivDown(uint256 a, uint256 b, uint256 d) internal pure returns (uint256) {
        if (a == 0 || b == 0) return 0;
        return (a * b) / d;
    }
}

/*//////////////////////////////////////////////////////////////
                    OWNABLE / PAUSABLE / REENTRANCY
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
abstract contract Pausable is Ownable {
    bool public paused;
    event Paused(address indexed by);
    event Unpaused(address indexed by);
    modifier whenNotPaused(){ require(!paused, "paused"); _; }
    function pause() external onlyOwner { paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner { paused = false; emit Unpaused(msg.sender); }
}
abstract contract ReentrancyGuard {
    uint256 private _s = 1;
    modifier nonReentrant() { require(_s == 1, "reentrant"); _s = 2; _; _s = 1; }
}

/*//////////////////////////////////////////////////////////////
                              ERC20 (18d)
//////////////////////////////////////////////////////////////*/
contract ERC20 {
    string public name; string public symbol;
    uint8 public immutable decimals = 18;
    uint256 public totalSupply;
    mapping(address=>uint256) public balanceOf;
    mapping(address=>mapping(address=>uint256)) public allowance;
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);
    constructor(string memory n, string memory s){ name = n; symbol = s; }
    function _mint(address to, uint256 a) internal { require(to!=address(0),"mint zero"); totalSupply+=a; balanceOf[to]+=a; emit Transfer(address(0),to,a); }
    function _burn(address from, uint256 a) internal { require(from!=address(0),"burn zero"); uint256 b=balanceOf[from]; require(b>=a,"bal"); unchecked{balanceOf[from]=b-a;} totalSupply-=a; emit Transfer(from,address(0),a); }
    function approve(address s, uint256 a) external returns(bool){ allowance[msg.sender][s]=a; emit Approval(msg.sender,s,a); return true; }
    function transfer(address to, uint256 a) external returns(bool){ _xfer(msg.sender,to,a); return true; }
    function transferFrom(address f,address t,uint256 a) external returns(bool){
        uint256 al=allowance[f][msg.sender];
        if(al!=type(uint256).max){ require(al>=a,"allow"); unchecked{allowance[f][msg.sender]=al-a;} emit Approval(f,msg.sender,allowance[f][msg.sender]); }
        _xfer(f,t,a); return true;
    }
    function _xfer(address f,address t,uint256 a) internal { require(t!=address(0),"to zero"); uint256 b=balanceOf[f]; require(b>=a,"bal"); unchecked{balanceOf[f]=b-a;} balanceOf[t]+=a; emit Transfer(f,t,a); }
}

/*//////////////////////////////////////////////////////////////
                MTYLD: Mechanical Temp Yield Vault
//////////////////////////////////////////////////////////////*/
contract MechanicalTempYieldVault is ERC20, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using MathX for uint256;

    // ====== Constants & State ======
    IERC20  public immutable stable;        // USDC (6d on Arbitrum)
    uint8   public immutable stableDecimals; // must be <=18
    uint256 private immutable DEC_OFFSET;    // 10^(18 - stableDecimals)
    uint256 private constant ONE = 1e18;

    // Fees (bps) with rounding mode
    uint16 public mintFeeBps;      // 0..500
    uint16 public redeemFeeBps;    // 0..500
    uint16 public constant MAX_FEE_BPS = 500;
    bool   public feeRoundUp = true;
    address public feeRecipient;

    // Guarded launch & supply cap
    bool   public guardedLaunch = false;
    mapping(address=>bool) public isWhitelistedMinter;
    uint256 public maxSupply; // 0 = no cap

    // Pending revenue anti-front-run
    uint256 public navDelaySec = 3600; // 1h default
    uint256 public pendingRevenueUSDC; // 6d, excluded from NAV until released
    uint64  public pendingReleaseAt;   // timestamp when revenue becomes active

    // Optional epoch close window (hard pause mint/redeem around releases)
    bool public epochClosing;

    // Timelocked rescue
    uint256 public constant RESCUE_DELAY = 24 hours;
    mapping(address=>bool) public rescuable;
    struct RescueReq { address token; uint256 amount; address to; uint64 eta; }
    RescueReq public rescueReq;

    // ====== Events ======
    event Minted(address indexed user, uint256 usdcIn, uint256 mtyldOut, uint256 price);
    event Redeemed(address indexed user, uint256 mtyldIn, uint256 usdcOut, uint256 price);
    event RevenueQueued(address indexed from, uint256 usdcAmount, uint64 releaseAt);
    event RevenueApplied(uint256 appliedUSDC, uint256 newPrice);
    event FeesUpdated(uint16 mintFeeBps, uint16 redeemFeeBps, address feeRecipient, bool feeRoundUp);
    event GuardedLaunchSet(bool enabled);
    event WhitelistSet(address indexed user, bool allowed);
    event MaxSupplySet(uint256 cap);
    event NavDelaySet(uint256 seconds_);
    event EpochCloseSet(bool closing);
    event RescueWhitelisted(address token, bool allowed);
    event RescueAnnounced(address token, uint256 amount, address to, uint64 eta);
    event RescueExecuted(address token, uint256 amount, address to);

    // ====== Errors ======
    error ZeroAmount();
    error InvalidAddress();
    error InvalidFee();
    error BadDecimals();
    error InsufficientTreasury();
    error Guarded();
    error EpochClosing();
    error NotRescuable();
    error TooEarly();

    // ====== Constructor ======
    constructor(address usdc)
        ERC20("Mechanical Temp Yield", "MTYLD")
    {
        if (usdc == address(0)) revert InvalidAddress();
        stable = IERC20(usdc);
        uint8 sd = IERC20(usdc).decimals();
        if (sd > 18) revert BadDecimals();
        stableDecimals = sd;
        DEC_OFFSET = 10 ** (18 - sd);

        feeRecipient = msg.sender;
        mintFeeBps = 0;
        redeemFeeBps = 0;
    }

    // ====== Views ======
    function treasuryUSDC() public view returns (uint256) {
        return stable.balanceOf(address(this));
    }

    function treasuryActiveUSDC() public view returns (uint256) {
        // active treasury excludes pending
        uint256 bal = treasuryUSDC();
        return (pendingRevenueUSDC > bal) ? 0 : (bal - pendingRevenueUSDC);
    }

    function treasury18() public view returns (uint256) {
        return treasuryActiveUSDC() * DEC_OFFSET;
    }

    function pricePerToken() public view returns (uint256) {
        uint256 s = totalSupply;
        if (s == 0) return ONE;
        return (treasury18() * ONE) / s;
    }

    function previewMint(uint256 usdcAmount) external view returns (uint256 mtyldOut, uint256 price) {
        if (usdcAmount == 0) return (0, pricePerToken());
        price = pricePerToken();
        uint256 usdcNet = _postFee(usdcAmount, mintFeeBps);
        uint256 amount18 = usdcNet * DEC_OFFSET;
        mtyldOut = (amount18 * ONE) / price;
    }

    function previewRedeem(uint256 mtyldAmount) external view returns (uint256 usdcOut, uint256 price) {
        if (mtyldAmount == 0) return (0, pricePerToken());
        price = pricePerToken();
        uint256 amount18 = (mtyldAmount * price) / ONE;
        uint256 usdcRaw  = amount18 / DEC_OFFSET;
        usdcOut = _postFee(usdcRaw, redeemFeeBps);
    }

    function pendingReleaseReady() public view returns (bool) {
        return pendingRevenueUSDC > 0 && block.timestamp >= pendingReleaseAt;
    }

    // ====== Core Actions ======
    function mint(uint256 usdcAmount, uint256 minMtyldOut) external whenNotPaused nonReentrant {
        if (epochClosing) revert EpochClosing();
        if (guardedLaunch && !isWhitelistedMinter[msg.sender]) revert Guarded();
        if (usdcAmount == 0) revert ZeroAmount();

        uint256 price = pricePerToken();

        uint256 feeAmt = _fee(usdcAmount, mintFeeBps);
        uint256 usdcNet = usdcAmount - feeAmt;

        stable.safeTransferFrom(msg.sender, address(this), usdcAmount);
        if (feeAmt > 0 && feeRecipient != address(0)) stable.safeTransfer(feeRecipient, feeAmt);

        uint256 amount18 = usdcNet * DEC_OFFSET;
        uint256 mtyldOut = (amount18 * ONE) / price;
        require(mtyldOut >= minMtyldOut, "slippage MTYLD");

        if (maxSupply != 0) require(totalSupply + mtyldOut <= maxSupply, "max supply");

        _mint(msg.sender, mtyldOut);
        emit Minted(msg.sender, usdcAmount, mtyldOut, pricePerToken());
    }

    function redeem(uint256 mtyldAmount, uint256 minUsdcOut) external whenNotPaused nonReentrant {
        if (epochClosing) revert EpochClosing();
        if (mtyldAmount == 0) revert ZeroAmount();

        uint256 price = pricePerToken();

        _burn(msg.sender, mtyldAmount);

        uint256 amount18 = (mtyldAmount * price) / ONE;
        uint256 usdcRaw  = amount18 / DEC_OFFSET;

        uint256 feeAmt = _fee(usdcRaw, redeemFeeBps);
        uint256 usdcNet = usdcRaw - feeAmt;

        uint256 active = treasuryActiveUSDC(); // exclude pending from availability
        if (active < usdcRaw) revert InsufficientTreasury();

        if (feeAmt > 0 && feeRecipient != address(0)) stable.safeTransfer(feeRecipient, feeAmt);
        require(usdcNet >= minUsdcOut, "slippage USDC");
        stable.safeTransfer(msg.sender, usdcNet);

        emit Redeemed(msg.sender, mtyldAmount, usdcNet, pricePerToken());
    }

    /// @notice Queue revenue with delay: funds are transferred now but excluded from NAV until released
    function injectRevenue(uint256 usdcAmount) external onlyOwner nonReentrant {
        if (usdcAmount == 0) revert ZeroAmount();
        stable.safeTransferFrom(msg.sender, address(this), usdcAmount);

        // aggregate pending and push release at least navDelaySec in the future
        pendingRevenueUSDC += usdcAmount;
        uint64 target = uint64(block.timestamp + navDelaySec);
        if (target > pendingReleaseAt) pendingReleaseAt = target;

        emit RevenueQueued(msg.sender, usdcAmount, pendingReleaseAt);
    }

    /// @notice Apply pending revenue into active NAV once delay has elapsed
    function applyPendingRevenue() public nonReentrant {
        if (!pendingReleaseReady()) revert TooEarly();
        uint256 applied = pendingRevenueUSDC;
        pendingRevenueUSDC = 0;
        pendingReleaseAt = 0;
        emit RevenueApplied(applied, pricePerToken());
    }

    // ====== Admin / Ops ======
    function setFees(uint16 _mintFeeBps, uint16 _redeemFeeBps, address _recipient, bool _roundUp) external onlyOwner {
        require(_mintFeeBps <= MAX_FEE_BPS && _redeemFeeBps <= MAX_FEE_BPS, "fee cap");
        require(_recipient != address(0), "fee recv");
        mintFeeBps = _mintFeeBps;
        redeemFeeBps = _redeemFeeBps;
        feeRecipient = _recipient;
        feeRoundUp = _roundUp;
        emit FeesUpdated(_mintFeeBps, _redeemFeeBps, _recipient, _roundUp);
    }

    function setGuardedLaunch(bool on) external onlyOwner { guardedLaunch = on; emit GuardedLaunchSet(on); }
    function setWhitelist(address user, bool allowed) external onlyOwner { isWhitelistedMinter[user]=allowed; emit WhitelistSet(user, allowed); }
    function setMaxSupply(uint256 cap) external onlyOwner { maxSupply = cap; emit MaxSupplySet(cap); }

    function setNavDelay(uint256 seconds_) external onlyOwner { navDelaySec = seconds_; emit NavDelaySet(seconds_); }
    function beginEpochClose() external onlyOwner { epochClosing = true; emit EpochCloseSet(true); }
    function endEpochClose()   external onlyOwner { epochClosing = false; emit EpochCloseSet(false); }

    // Timelocked rescue with whitelist (cannot rescue backing stable)
    function whitelistRescuable(address token, bool allowed) external onlyOwner {
        require(token != address(stable), "backing");
        rescuable[token] = allowed;
        emit RescueWhitelisted(token, allowed);
    }
    function announceRescue(address token, uint256 amount, address to) external onlyOwner {
        if (!rescuable[token]) revert NotRescuable();
        if (to == address(0)) revert InvalidAddress();
        rescueReq = RescueReq({ token: token, amount: amount, to: to, eta: uint64(block.timestamp + RESCUE_DELAY) });
        emit RescueAnnounced(token, amount, to, rescueReq.eta);
    }
    function executeRescue() external onlyOwner {
        RescueReq memory r = rescueReq;
        if (r.token == address(0)) revert InvalidAddress();
        if (block.timestamp < r.eta) revert TooEarly();
        rescueReq = RescueReq(address(0),0,address(0),0);
        IERC20(r.token).transfer(r.to, r.amount);
        emit RescueExecuted(r.token, r.amount, r.to);
    }

    // ====== Internal fee helpers ======
    function _fee(uint256 amount, uint16 bps) internal view returns (uint256) {
        if (bps == 0 || amount == 0) return 0;
        return feeRoundUp ? amount.mulDivUp(bps, 10_000) : amount.mulDivDown(bps, 10_000);
    }
    function _postFee(uint256 amount, uint16 bps) internal view returns (uint256) {
        uint256 f = _fee(amount, bps);
        return amount - f;
    }
}
