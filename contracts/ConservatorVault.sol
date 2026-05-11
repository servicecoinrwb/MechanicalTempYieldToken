// SPDX-License-Identifier: MIT
/**
 * ConservatorVault v5 — Plugin Strategy Architecture
 *
 * ERC-4626 WETH vault with pluggable yield strategies.
 *
 * KEY DESIGN: Strategies PULL funds from vault via transferFrom.
 *             Vault never pushes tokens — no calldata encoding needed ever again.
 *
 * Adding a new strategy (3 steps, no vault redeploy):
 *   1. Deploy StrategyContract(vaultAddress)
 *   2. vault.approveToken(WETH, strategyAddress, maxUint)
 *   3. vault.addStrategy(strategyAddress, "Protocol Name")
 *
 * Removing a strategy:
 *   1. vault.withdrawFromStrategy(strategyAddress, strategyBalance)
 *   2. vault.removeStrategy(strategyAddress)
 */

pragma solidity ^0.8.25;

// ─────────────────────────────────────────────────────────────────────────────
// Interfaces
// ─────────────────────────────────────────────────────────────────────────────

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    function approve(address, uint256) external returns (bool);
}

interface IMTYLD {
    function balanceOf(address) external view returns (uint256);
}

/// @notice Standard interface every strategy must implement
interface IStrategy {
    /// @notice Pull `amount` WETH from vault and deploy to protocol
    function deposit(uint256 amount) external;
    /// @notice Withdraw `amount` WETH from protocol back to vault
    function withdraw(uint256 amount) external;
    /// @notice Withdraw everything from protocol back to vault
    function withdrawAll() external;
    /// @notice Current WETH value held by this strategy (including yield)
    function balance() external view returns (uint256);
    /// @notice Human readable name e.g. "Compound V3"
    function name() external view returns (string memory);
    /// @notice The vault this strategy serves
    function vault() external view returns (address);
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
    constructor(address o) { _owner = o; emit OwnershipTransferred(address(0), o); }
    modifier onlyOwner() { require(msg.sender == _owner, "Not owner"); _; }
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address n) public onlyOwner {
        require(n != address(0), "Zero");
        emit OwnershipTransferred(_owner, n);
        _owner = n;
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// ConservatorVault
// ─────────────────────────────────────────────────────────────────────────────

contract ConservatorVault is Ownable, ReentrancyGuard {

    // ── Constants ─────────────────────────────────────────────
    uint256 public constant MIN_DEPOSIT = 0.01 ether;

    // ── Tokens ────────────────────────────────────────────────
    IERC20  public immutable weth;
    IMTYLD  public immutable mtyld;

    // ── ERC-4626 share token (mtETH-S) ────────────────────────
    string  public name     = "Mechanical Temp ETH Savings";
    string  public symbol   = "mtETH-S";
    uint8   public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    // ── Vault config ──────────────────────────────────────────
    address public aiAgent;
    uint256 public withdrawLockPeriod = 24 hours;
    uint256 public minMtyldRequired   = 1e18; // 1 MTYLD default
    mapping(address => uint256) public lastDepositTime;

    // ── Strategy registry ─────────────────────────────────────
    struct StrategyInfo {
        address addr;
        string  name;
        bool    active;
    }
    address[] public strategyList;
    mapping(address => StrategyInfo) public strategies;
    mapping(address => bool) public isStrategy;

    // ── Events ────────────────────────────────────────────────
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);
    event StrategyAdded(address indexed strategy, string name);
    event StrategyRemoved(address indexed strategy);
    event StrategyDeployed(address indexed strategy, uint256 amount);
    event StrategyWithdrawn(address indexed strategy, uint256 amount);
    event AgentUpdated(address indexed newAgent);

    // ── Constructor ───────────────────────────────────────────
    constructor(address _weth, address _mtyld, address _agent) Ownable(msg.sender) {
        require(_weth != address(0) && _mtyld != address(0), "Zero address");
        weth    = IERC20(_weth);
        mtyld   = IMTYLD(_mtyld);
        aiAgent = _agent;
    }

    // ── Modifiers ─────────────────────────────────────────────
    modifier onlyAgentOrOwner() {
        require(msg.sender == aiAgent || msg.sender == owner(), "Not authorized");
        _;
    }

    // ─────────────────────────────────────────────────────────
    // ERC-20 functions (mtETH-S token)
    // ─────────────────────────────────────────────────────────

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        return _transfer(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(allowance[from][msg.sender] >= amount, "Allowance exceeded");
        allowance[from][msg.sender] -= amount;
        return _transfer(from, to, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        balanceOf[from] -= amount;
        balanceOf[to]   += amount;
        emit Transfer(from, to, amount);
        return true;
    }

    // ─────────────────────────────────────────────────────────
    // ERC-4626 core
    // ─────────────────────────────────────────────────────────

    /// @notice Total WETH managed — idle in vault + all strategy balances
    function totalAssets() public view returns (uint256) {
        uint256 total = weth.balanceOf(address(this));
        for (uint256 i = 0; i < strategyList.length; i++) {
            if (strategies[strategyList[i]].active) {
                try IStrategy(strategyList[i]).balance() returns (uint256 bal) {
                    total += bal;
                } catch {}
            }
        }
        return total;
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        uint256 supply = totalSupply;
        return supply == 0 ? assets : assets * supply / totalAssets();
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        uint256 supply = totalSupply;
        return supply == 0 ? shares : shares * totalAssets() / supply;
    }

    /// @notice NAV per share in WETH (18 decimals)
    function pricePerShare() external view returns (uint256) {
        return totalSupply == 0 ? 1e18 : totalAssets() * 1e18 / totalSupply;
    }

    function maxRedeem(address owner_) external view returns (uint256) {
        uint256 shares = balanceOf[owner_];
        if (block.timestamp < lastDepositTime[owner_] + withdrawLockPeriod) return 0;
        return shares;
    }

    // ─────────────────────────────────────────────────────────
    // Deposit
    // ─────────────────────────────────────────────────────────

    function deposit(uint256 assets, address receiver) external nonReentrant returns (uint256 shares) {
        require(assets >= MIN_DEPOSIT, "Below minimum deposit");
        require(mtyld.balanceOf(msg.sender) >= minMtyldRequired, "Insufficient MTYLD");

        shares = convertToShares(assets);
        require(shares > 0, "Zero shares");

        // First deposit: burn 1000 wei to prevent inflation attacks
        if (totalSupply == 0) {
            shares -= 1000;
            balanceOf[address(0)] += 1000;
            totalSupply += 1000;
            emit Transfer(address(0), address(0), 1000);
        }

        weth.transferFrom(msg.sender, address(this), assets);
        lastDepositTime[receiver] = block.timestamp;

        balanceOf[receiver] += shares;
        totalSupply         += shares;
        emit Transfer(address(0), receiver, shares);
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    // ─────────────────────────────────────────────────────────
    // Redeem / Withdraw
    // ─────────────────────────────────────────────────────────

    function redeem(
        uint256 shares,
        address receiver,
        address owner_
    ) external nonReentrant returns (uint256 assets) {
        require(shares > 0, "Zero shares");
        require(balanceOf[owner_] >= shares, "Insufficient shares");
        require(
            block.timestamp >= lastDepositTime[owner_] + withdrawLockPeriod,
            "Withdraw locked"
        );

        if (msg.sender != owner_) {
            require(allowance[owner_][msg.sender] >= shares, "Allowance exceeded");
            allowance[owner_][msg.sender] -= shares;
        }

        assets = convertToAssets(shares);
        require(assets > 0, "Zero assets");

        balanceOf[owner_] -= shares;
        totalSupply       -= shares;
        emit Transfer(owner_, address(0), shares);

        // Check idle WETH — if not enough the agent must pull from strategies first
        uint256 idle = weth.balanceOf(address(this));
        require(idle >= assets, "Insufficient idle WETH - request agent to pull from strategy first");

        weth.transfer(receiver, assets);
        emit Withdraw(msg.sender, receiver, owner_, assets, shares);
    }

    // ─────────────────────────────────────────────────────────
    // Strategy Management — Owner only
    // ─────────────────────────────────────────────────────────

    /// @notice Register a new strategy. Call approveToken first.
    function addStrategy(address strategy, string calldata stratName) external onlyOwner {
        require(strategy != address(0), "Zero address");
        require(!isStrategy[strategy], "Already registered");
        require(IStrategy(strategy).vault() == address(this), "Wrong vault");

        strategies[strategy] = StrategyInfo({ addr: strategy, name: stratName, active: true });
        strategyList.push(strategy);
        isStrategy[strategy] = true;
        emit StrategyAdded(strategy, stratName);
    }

    /// @notice Deregister a strategy. Withdraw all funds first.
    function removeStrategy(address strategy) external onlyOwner {
        require(isStrategy[strategy], "Not registered");
        try IStrategy(strategy).balance() returns (uint256 bal) {
            require(bal == 0, "Withdraw funds before removing");
        } catch {}
        strategies[strategy].active = false;
        isStrategy[strategy] = false;
        emit StrategyRemoved(strategy);
    }

    /// @notice Give a strategy permission to pull WETH from this vault.
    ///         Call once per strategy after deploying it.
    function approveToken(address token, address spender, uint256 amount) external onlyOwner {
        IERC20(token).approve(spender, amount);
    }

    // ─────────────────────────────────────────────────────────
    // Strategy Deployment — Agent or Owner
    // ─────────────────────────────────────────────────────────

    /// @notice Deploy `amount` WETH to a registered strategy
    function deployToStrategy(address strategy, uint256 amount) external onlyAgentOrOwner nonReentrant {
        require(isStrategy[strategy] && strategies[strategy].active, "Strategy not active");
        require(amount > 0, "Zero amount");
        require(weth.balanceOf(address(this)) >= amount, "Insufficient idle WETH");
        IStrategy(strategy).deposit(amount);
        emit StrategyDeployed(strategy, amount);
    }

    /// @notice Pull `amount` WETH back from a strategy to vault
    function withdrawFromStrategy(address strategy, uint256 amount) external onlyAgentOrOwner nonReentrant {
        require(isStrategy[strategy], "Not registered");
        require(amount > 0, "Zero amount");
        IStrategy(strategy).withdraw(amount);
        emit StrategyWithdrawn(strategy, amount);
    }

    /// @notice Emergency — pull everything from a strategy
    function withdrawAllFromStrategy(address strategy) external onlyAgentOrOwner nonReentrant {
        require(isStrategy[strategy], "Not registered");
        IStrategy(strategy).withdrawAll();
    }

    // ─────────────────────────────────────────────────────────
    // Admin
    // ─────────────────────────────────────────────────────────

    function setAiAgent(address _agent) external onlyOwner {
        require(_agent != address(0), "Zero");
        aiAgent = _agent;
        emit AgentUpdated(_agent);
    }

    function setWithdrawLockPeriod(uint256 seconds_) external onlyOwner {
        withdrawLockPeriod = seconds_;
    }

    function setMinMtyldRequired(uint256 amount) external onlyOwner {
        minMtyldRequired = amount;
    }

    // ─────────────────────────────────────────────────────────
    // Views
    // ─────────────────────────────────────────────────────────

    function getStrategies() external view returns (
        address[] memory addrs,
        string[]  memory names,
        uint256[] memory balances,
        bool[]    memory active
    ) {
        uint256 len = strategyList.length;
        addrs    = new address[](len);
        names    = new string[](len);
        balances = new uint256[](len);
        active   = new bool[](len);
        for (uint256 i = 0; i < len; i++) {
            address s = strategyList[i];
            addrs[i]    = s;
            names[i]    = strategies[s].name;
            active[i]   = strategies[s].active;
            try IStrategy(s).balance() returns (uint256 bal) {
                balances[i] = bal;
            } catch {}
        }
    }

    function idleWeth() external view returns (uint256) {
        return weth.balanceOf(address(this));
    }
}
